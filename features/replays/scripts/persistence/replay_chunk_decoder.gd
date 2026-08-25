## Replay 分块流的严格可推进解码器。
##
## 每个 advance work unit 至多读取一个不超过 128 KiB 的结构化 frame；
## topology/tile 通过固定小批恢复，step 逐条恢复。解码永不允许对象，
## 并在把 payload 移交业务 Provider 前完成顺序、计数与业务形状早验。
class_name ReplayChunkDecoder
extends RefCounted


# --- 常量 ---

const STREAM_SCHEMA_ID: StringName = &"replay_record_stream"
const STREAM_SCHEMA_VERSION: int = 2
const BUSINESS_SCHEMA_VERSION: int = ReplayCatalogSaveData.SCHEMA_VERSION
const CHUNK_BYTES: int = ChunkFrameStreamReader.CHUNK_BYTES
const MAX_TOTAL_BYTES: int = ChunkFrameStreamReader.MAX_TOTAL_BYTES
const MAX_FRAME_BYTES: int = ChunkFrameStreamReader.CHUNK_BYTES
const MAX_FRAME_PAYLOAD_BYTES: int = (
	ChunkFrameStreamReader.MAX_FRAME_PAYLOAD_BYTES
)

const TOPOLOGY_CELL_BATCH_SIZE: int = (
	ReplayChunkSourceSnapshot.TOPOLOGY_CELL_BATCH_SIZE
)
const FINAL_TILE_BATCH_SIZE: int = (
	ReplayChunkSourceSnapshot.FINAL_TILE_BATCH_SIZE
)

const RECORD_CATALOG: StringName = &"catalog"
const RECORD_REPLAY_METADATA: StringName = &"replay_metadata"
const RECORD_TOPOLOGY_CELLS: StringName = &"topology_cells"
const RECORD_FINAL_TILES: StringName = &"final_tiles"
const RECORD_STEP: StringName = &"step"

const _PHASE_HEADER: int = 0
const _PHASE_METADATA: int = 1
const _PHASE_CELLS: int = 2
const _PHASE_TILES: int = 3
const _PHASE_STEPS: int = 4

const _HEADER_FIELDS: Array[StringName] = [
	&"record_type",
	&"schema_id",
	&"schema_version",
	&"business_schema_version",
	&"replay_count",
]
const _METADATA_FIELDS: Array[StringName] = [
	&"record_type",
	&"replay_index",
	&"schema_version",
	&"replay_id",
	&"timestamp",
	&"mode_config_path",
	&"ruleset_id",
	&"ruleset_version",
	&"ruleset_fingerprint",
	&"initial_seed",
	&"session_metadata",
	&"final_score",
	&"topology_schema_version",
	&"topology_id",
	&"active_cell_count",
	&"snapshot_schema_version",
	&"tile_count",
	&"step_count",
]
const _CELL_BATCH_FIELDS: Array[StringName] = [
	&"record_type",
	&"replay_index",
	&"start_index",
	&"cells",
]
const _TILE_BATCH_FIELDS: Array[StringName] = [
	&"record_type",
	&"replay_index",
	&"start_index",
	&"tiles",
]
const _STEP_FIELDS: Array[StringName] = [
	&"record_type",
	&"replay_index",
	&"step_index",
	&"action",
	&"checkpoint",
]
const _TILE_FIELDS: Array[StringName] = [
	&"schema_version",
	&"tile_id",
	&"definition_id",
	&"value",
	&"capability_recipe_ids",
	&"capability_state",
	&"pos",
]


# --- 私有变量 ---

var _reader: ChunkFrameStreamReader = null
var _phase: int = _PHASE_HEADER
var _replay_count: int = -1
var _next_replay_index: int = 0
var _current_metadata: Dictionary = {}
var _current_cell_count: int = 0
var _current_tile_count: int = 0
var _current_step_count: int = 0
var _current_cell_index: int = 0
var _current_tile_index: int = 0
var _current_step_index: int = 0
var _current_cells: Array[Vector2i] = []
var _current_tiles: Array[Dictionary] = []
var _current_actions: Array[Vector2i] = []
var _current_checkpoints: Array[ReplayCheckpoint] = []
var _cell_lookup: Dictionary = {}
var _seen_tile_cells: Dictionary = {}
var _seen_tile_ids: Dictionary = {}
var _has_previous_cell: bool = false
var _previous_cell: Vector2i = Vector2i.ZERO
var _minimum_cell: Vector2i = Vector2i.ZERO
var _last_checkpoint_score: int = 0
var _items: Array[ReplayData] = []
var _seen_replay_ids: Dictionary = {}
var _prepared_state: ReplayCatalogPreparedState = null
var _complete: bool = false
var _prepared_state_claimed: bool = false
var _error_code: Error = OK
var _error: String = ""


# --- 公共方法 ---

## 接管 chunks 的只读元素别名；调用方返回后必须放弃原数组及其元素。
## @param chunks: 移交所有权的规范 replay stream 分块。
static func begin_decode(
	chunks: Array[PackedByteArray]
) -> ReplayChunkDecoder:
	var reader: ChunkFrameStreamReader = (
		ChunkFrameStreamReader.begin_reading_taking_ownership(chunks)
	)
	if reader == null:
		return null
	var decoder: ReplayChunkDecoder = ReplayChunkDecoder.new()
	decoder._reader = reader
	return decoder


## 在 frame 预算内推进解码；每个 unit 只消费一个有界 frame。
## @param frame_budget: 本次调用最多解码的有界 frame 数。
func advance(frame_budget: int) -> int:
	if frame_budget <= 0 or _complete or is_failed() or _reader == null:
		return 0
	var consumed_units: int = 0
	while consumed_units < frame_budget and not _complete and not is_failed():
		var frame_result: Dictionary = _reader.read_variant_frame()
		if not GFVariantData.get_option_bool(frame_result, &"ok", false):
			_fail(ERR_FILE_CORRUPT, "Replay stream frame is invalid.")
			break
		var frame_value: Variant = frame_result.get(&"value")
		if not frame_value is Dictionary:
			_fail(ERR_FILE_CORRUPT, "Replay stream frame must be a Dictionary.")
			break
		var frame: Dictionary = frame_value
		var accepted: bool = false
		match _phase:
			_PHASE_HEADER:
				accepted = _consume_header(frame)
			_PHASE_METADATA:
				accepted = _consume_metadata(frame)
			_PHASE_CELLS:
				accepted = _consume_cell_batch(frame)
			_PHASE_TILES:
				accepted = _consume_tile_batch(frame)
			_PHASE_STEPS:
				accepted = _consume_step(frame)
			_:
				accepted = false
		consumed_units += 1
		if not accepted and not is_failed():
			_fail(ERR_FILE_CORRUPT, "Replay stream record violates its phase schema.")
	return consumed_units


func is_complete() -> bool:
	return _complete and not is_failed()


func is_failed() -> bool:
	return _error_code != OK


func get_error_code() -> Error:
	return _error_code


func get_error() -> String:
	return _error


func get_decoded_replay_count() -> int:
	return (
		_prepared_state.get_item_count()
		if _prepared_state != null
		else _items.size()
	)


## 一次性移出已经逐 frame 验证并构造的业务根。
func take_prepared_state_taking_ownership() -> ReplayCatalogPreparedState:
	if (
		not is_complete()
		or _prepared_state_claimed
		or _prepared_state == null
	):
		return null
	_prepared_state_claimed = true
	var owned_state: ReplayCatalogPreparedState = _prepared_state
	_prepared_state = null
	return owned_state


# --- 私有/辅助方法 ---

func _consume_header(frame: Dictionary) -> bool:
	if not _has_exact_fields(frame, _HEADER_FIELDS):
		return false
	if not _has_record_type(frame, RECORD_CATALOG):
		return false
	var schema_id_value: Variant = frame.get(&"schema_id")
	var schema_version_value: Variant = frame.get(&"schema_version")
	var business_version_value: Variant = frame.get(
		&"business_schema_version"
	)
	var replay_count_value: Variant = frame.get(&"replay_count")
	if (
		not schema_id_value is StringName
		or not schema_version_value is int
		or not business_version_value is int
		or not replay_count_value is int
	):
		return false
	var replay_count: int = replay_count_value
	if (
		schema_id_value != STREAM_SCHEMA_ID
		or schema_version_value != STREAM_SCHEMA_VERSION
		or business_version_value != BUSINESS_SCHEMA_VERSION
		or replay_count < 0
		or replay_count > ReplayCatalogSaveData.MAX_REPLAY_COUNT
	):
		return false
	_replay_count = replay_count
	if replay_count == 0:
		return _complete_stream()
	_phase = _PHASE_METADATA
	return true


func _consume_metadata(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _METADATA_FIELDS)
		or not _has_record_type(frame, RECORD_REPLAY_METADATA)
		or not _has_expected_index(frame, &"replay_index", _next_replay_index)
		or not _is_valid_scalar_metadata(frame)
	):
		return false
	var replay_id: String = GFVariantData.get_option_string(frame, &"replay_id")
	if _seen_replay_ids.has(replay_id):
		return false
	_seen_replay_ids[replay_id] = true
	_current_cell_count = GFVariantData.get_option_int(
		frame,
		&"active_cell_count",
		-1
	)
	_current_tile_count = GFVariantData.get_option_int(
		frame,
		&"tile_count",
		-1
	)
	_current_step_count = GFVariantData.get_option_int(
		frame,
		&"step_count",
		-1
	)
	_current_metadata = {
		&"schema_version": frame.get(&"schema_version"),
		&"replay_id": frame.get(&"replay_id"),
		&"timestamp": frame.get(&"timestamp"),
		&"mode_config_path": frame.get(&"mode_config_path"),
		&"ruleset_id": frame.get(&"ruleset_id"),
		&"ruleset_version": frame.get(&"ruleset_version"),
		&"ruleset_fingerprint": frame.get(&"ruleset_fingerprint"),
		&"initial_seed": frame.get(&"initial_seed"),
		&"session_metadata": frame.get(&"session_metadata"),
		&"final_score": frame.get(&"final_score"),
		&"topology_schema_version": frame.get(&"topology_schema_version"),
		&"topology_id": frame.get(&"topology_id"),
		&"snapshot_schema_version": frame.get(&"snapshot_schema_version"),
	}
	_current_cell_index = 0
	_current_tile_index = 0
	_current_step_index = 0
	_current_cells = []
	_current_tiles = []
	_current_actions = []
	_current_checkpoints = []
	_cell_lookup = {}
	_seen_tile_cells = {}
	_seen_tile_ids = {}
	_has_previous_cell = false
	_previous_cell = Vector2i.ZERO
	_minimum_cell = Vector2i.ZERO
	_last_checkpoint_score = 0
	_phase = _PHASE_CELLS
	return true


func _consume_cell_batch(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _CELL_BATCH_FIELDS)
		or not _has_record_type(frame, RECORD_TOPOLOGY_CELLS)
		or not _has_expected_index(frame, &"replay_index", _next_replay_index)
		or not _has_expected_index(frame, &"start_index", _current_cell_index)
	):
		return false
	var cells_value: Variant = frame.get(&"cells")
	if not cells_value is Array:
		return false
	var cells: Array = cells_value
	var expected_count: int = mini(
		TOPOLOGY_CELL_BATCH_SIZE,
		_current_cell_count - _current_cell_index
	)
	if expected_count <= 0 or cells.size() != expected_count:
		return false
	for cell_value: Variant in cells:
		if not cell_value is Vector2i:
			return false
		var cell: Vector2i = cell_value
		if cell.x < 0 or cell.y < 0 or _cell_lookup.has(cell):
			return false
		if _has_previous_cell and not _is_row_major_before(
			_previous_cell,
			cell
		):
			return false
		if not _has_previous_cell:
			_minimum_cell = cell
			_has_previous_cell = true
		else:
			_minimum_cell.x = mini(_minimum_cell.x, cell.x)
			_minimum_cell.y = mini(_minimum_cell.y, cell.y)
		_previous_cell = cell
		_cell_lookup[cell] = true
		_current_cells.append(cell)
	_current_cell_index += cells.size()
	if _current_cell_index == _current_cell_count:
		if _minimum_cell != Vector2i.ZERO:
			return false
		if _current_tile_count > 0:
			_phase = _PHASE_TILES
		elif _current_step_count > 0:
			_phase = _PHASE_STEPS
		else:
			return _finish_current_replay()
	return true


func _consume_tile_batch(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _TILE_BATCH_FIELDS)
		or not _has_record_type(frame, RECORD_FINAL_TILES)
		or not _has_expected_index(frame, &"replay_index", _next_replay_index)
		or not _has_expected_index(frame, &"start_index", _current_tile_index)
	):
		return false
	var tiles_value: Variant = frame.get(&"tiles")
	if not tiles_value is Array:
		return false
	var tiles: Array = tiles_value
	var expected_count: int = mini(
		FINAL_TILE_BATCH_SIZE,
		_current_tile_count - _current_tile_index
	)
	if expected_count <= 0 or tiles.size() != expected_count:
		return false
	for tile_value: Variant in tiles:
		if not tile_value is Dictionary:
			return false
		var tile: Dictionary = tile_value
		if not _validate_and_remember_tile(tile):
			return false
		_current_tiles.append(tile)
	_current_tile_index += tiles.size()
	if _current_tile_index == _current_tile_count:
		if _current_step_count > 0:
			_phase = _PHASE_STEPS
		else:
			return _finish_current_replay()
	return true


func _consume_step(frame: Dictionary) -> bool:
	if (
		not _has_exact_fields(frame, _STEP_FIELDS)
		or not _has_record_type(frame, RECORD_STEP)
		or not _has_expected_index(frame, &"replay_index", _next_replay_index)
		or not _has_expected_index(frame, &"step_index", _current_step_index)
	):
		return false
	var action_value: Variant = frame.get(&"action")
	var checkpoint_value: Variant = frame.get(&"checkpoint")
	if not action_value is Vector2i or not checkpoint_value is Dictionary:
		return false
	var action: Vector2i = action_value
	if not _is_cardinal_direction(action):
		return false
	var checkpoint_payload: Dictionary = checkpoint_value
	var checkpoint: ReplayCheckpoint = ReplayCheckpoint.from_dict(
		checkpoint_payload
	)
	if (
		checkpoint == null
		or checkpoint.step_index != _current_step_index + 1
	):
		return false
	_last_checkpoint_score = checkpoint.score
	_current_actions.append(action)
	_current_checkpoints.append(checkpoint)
	_current_step_index += 1
	if _current_step_index == _current_step_count:
		return _finish_current_replay()
	return true


func _finish_current_replay() -> bool:
	if (
		_current_cell_index != _current_cell_count
		or _current_tile_index != _current_tile_count
		or _current_step_index != _current_step_count
		or (
			_current_step_count > 0
			and _last_checkpoint_score
			!= GFVariantData.get_option_int(
				_current_metadata,
				&"final_score"
			)
		)
	):
		return false
	var topology: Dictionary = {
		&"schema_version": _current_metadata.get(
			&"topology_schema_version"
		),
		&"topology_id": _current_metadata.get(&"topology_id"),
		&"active_cells": _current_cells,
	}
	var topology_value: BoardTopology = BoardTopology.from_dict(topology)
	if (
		topology_value == null
		or not topology_value.get_playable_validation_report().is_ok()
	):
		return false
	var replay: ReplayData = ReplayData.new()
	replay.schema_version = ReplayData.SCHEMA_VERSION
	replay.replay_id = GFVariantData.get_option_string(
		_current_metadata,
		&"replay_id"
	)
	replay.timestamp = GFVariantData.get_option_int(
		_current_metadata,
		&"timestamp"
	)
	replay.mode_config_path = GFVariantData.get_option_string(
		_current_metadata,
		&"mode_config_path"
	)
	replay.ruleset_id = GFVariantData.get_option_string_name(
		_current_metadata,
		&"ruleset_id"
	)
	replay.ruleset_version = GFVariantData.get_option_int(
		_current_metadata,
		&"ruleset_version"
	)
	replay.ruleset_fingerprint = GFVariantData.get_option_string(
		_current_metadata,
		&"ruleset_fingerprint"
	)
	replay.initial_seed = GFVariantData.get_option_int(
		_current_metadata,
		&"initial_seed"
	)
	replay.session_metadata = GFVariantData.get_option_dictionary(
		_current_metadata,
		&"session_metadata"
	)
	replay.initial_board_topology = topology
	replay.final_score = GFVariantData.get_option_int(
		_current_metadata,
		&"final_score"
	)
	replay.actions = _current_actions
	replay.checkpoints = _current_checkpoints
	replay.final_board_snapshot = {
		&"schema_version": _current_metadata.get(
			&"snapshot_schema_version"
		),
		&"topology": topology,
		&"tiles": _current_tiles,
	}
	if not GridModel.is_snapshot_envelope_valid(replay.final_board_snapshot):
		return false
	_items.append(replay)
	_next_replay_index += 1
	_clear_current_replay()
	if _next_replay_index == _replay_count:
		return _complete_stream()
	_phase = _PHASE_METADATA
	return true


func _complete_stream() -> bool:
	if (
		_reader == null
		or _reader.get_remaining_bytes() != 0
		or _items.size() != _replay_count
	):
		return false
	var prepared_state: ReplayCatalogPreparedState = (
		ReplayCatalogPreparedState.take_ownership_of_validated_items(_items)
	)
	if prepared_state == null:
		return false
	_items = []
	_prepared_state = prepared_state
	_complete = true
	_reader.release()
	_reader = null
	return true


func _clear_current_replay() -> void:
	_current_metadata = {}
	_current_cell_count = 0
	_current_tile_count = 0
	_current_step_count = 0
	_current_cell_index = 0
	_current_tile_index = 0
	_current_step_index = 0
	_current_cells = []
	_current_tiles = []
	_current_actions = []
	_current_checkpoints = []
	_cell_lookup = {}
	_seen_tile_cells = {}
	_seen_tile_ids = {}
	_has_previous_cell = false
	_previous_cell = Vector2i.ZERO
	_minimum_cell = Vector2i.ZERO
	_last_checkpoint_score = 0


func _fail(error_code: Error, error: String) -> void:
	_error_code = error_code if error_code != OK else ERR_FILE_CORRUPT
	_error = error
	_items.clear()
	_seen_replay_ids.clear()
	_prepared_state = null
	_clear_current_replay()
	if _reader != null:
		_reader.release()
	_reader = null


func _validate_and_remember_tile(tile: Dictionary) -> bool:
	if not _has_exact_fields(tile, _TILE_FIELDS):
		return false
	var schema_value: Variant = tile.get(&"schema_version")
	var tile_id_value: Variant = tile.get(&"tile_id")
	var definition_value: Variant = tile.get(&"definition_id")
	var value_value: Variant = tile.get(&"value")
	var recipes_value: Variant = tile.get(&"capability_recipe_ids")
	var state_value: Variant = tile.get(&"capability_state")
	var position_value: Variant = tile.get(&"pos")
	if (
		not schema_value is int
		or not tile_id_value is String
		or not definition_value is StringName
		or not value_value is int
		or not recipes_value is Array
		or not state_value is Dictionary
		or not position_value is Vector2i
	):
		return false
	var tile_id: String = tile_id_value
	var definition_id: StringName = definition_value
	var position: Vector2i = position_value
	if (
		schema_value != TileState.SERIALIZATION_SCHEMA_VERSION
		or not GFUuid.is_valid(tile_id, 7)
		or _seen_tile_ids.has(tile_id)
		or definition_id == &""
		or value_value <= 0
		or not _cell_lookup.has(position)
		or _seen_tile_cells.has(position)
	):
		return false
	var recipe_values: Array = recipes_value
	if recipe_values.is_empty():
		return false
	var seen_recipes: Dictionary = {}
	for recipe_value: Variant in recipe_values:
		if not recipe_value is StringName:
			return false
		var recipe_id: StringName = recipe_value
		if recipe_id == &"" or seen_recipes.has(recipe_id):
			return false
		seen_recipes[recipe_id] = true
	var capability_state: Dictionary = state_value
	for state_key: Variant in capability_state.keys():
		if not state_key is StringName or not seen_recipes.has(state_key):
			return false
	_seen_tile_ids[tile_id] = true
	_seen_tile_cells[position] = true
	return true


static func _is_valid_scalar_metadata(frame: Dictionary) -> bool:
	var session_value: Variant = frame.get(&"session_metadata")
	var cell_count_value: Variant = frame.get(&"active_cell_count")
	var tile_count_value: Variant = frame.get(&"tile_count")
	var step_count_value: Variant = frame.get(&"step_count")
	if (
		not frame.get(&"schema_version") is int
		or not frame.get(&"replay_id") is String
		or not frame.get(&"timestamp") is int
		or not frame.get(&"mode_config_path") is String
		or not frame.get(&"ruleset_id") is StringName
		or not frame.get(&"ruleset_version") is int
		or not frame.get(&"ruleset_fingerprint") is String
		or not frame.get(&"initial_seed") is int
		or not session_value is Dictionary
		or not frame.get(&"final_score") is int
		or not frame.get(&"topology_schema_version") is int
		or not frame.get(&"topology_id") is String
		or not cell_count_value is int
		or not frame.get(&"snapshot_schema_version") is int
		or not tile_count_value is int
		or not step_count_value is int
	):
		return false
	var replay_id: String = frame.get(&"replay_id")
	var timestamp: int = frame.get(&"timestamp")
	var mode_config_path: String = frame.get(&"mode_config_path")
	var ruleset_id: StringName = frame.get(&"ruleset_id")
	var fingerprint: String = frame.get(&"ruleset_fingerprint")
	var final_score: int = frame.get(&"final_score")
	var topology_id: String = frame.get(&"topology_id")
	var cell_count: int = cell_count_value
	var tile_count: int = tile_count_value
	var step_count: int = step_count_value
	return (
		frame.get(&"schema_version") == ReplayData.SCHEMA_VERSION
		and GFUuid.is_valid(replay_id, 7)
		and timestamp >= 0
		and not mode_config_path.is_empty()
		and ruleset_id != &""
		and frame.get(&"ruleset_version") > 0
		and ReplayData.is_canonical_ruleset_fingerprint(fingerprint)
		and final_score >= 0
		and GameSessionMetadata.from_dict(
			GFVariantData.as_dictionary(session_value)
		) != null
		and frame.get(&"topology_schema_version")
		== BoardTopology.SERIALIZATION_SCHEMA_VERSION
		and not topology_id.is_empty()
		and cell_count > 0
		and cell_count <= BoardTopology.MAX_PLAYABLE_CELL_COUNT
		and frame.get(&"snapshot_schema_version")
		== GridModel.SNAPSHOT_SCHEMA_VERSION
		and tile_count >= 0
		and tile_count <= cell_count
		and step_count >= 0
		and step_count <= ReplayData.MAX_STEP_COUNT
	)


static func _has_record_type(
	frame: Dictionary,
	expected: StringName
) -> bool:
	var value: Variant = frame.get(&"record_type")
	return value is StringName and value == expected


static func _has_expected_index(
	frame: Dictionary,
	key: StringName,
	expected: int
) -> bool:
	var value: Variant = frame.get(key)
	return value is int and value == expected


static func _has_exact_fields(
	payload: Dictionary,
	fields: Array[StringName]
) -> bool:
	if payload.size() != fields.size():
		return false
	var keys: Array = payload.keys()
	for index: int in range(fields.size()):
		var key_value: Variant = keys[index]
		if not key_value is StringName or key_value != fields[index]:
			return false
	return true


static func _is_row_major_before(
	left: Vector2i,
	right: Vector2i
) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)


static func _is_cardinal_direction(direction: Vector2i) -> bool:
	return (
		direction == Vector2i.LEFT
		or direction == Vector2i.RIGHT
		or direction == Vector2i.UP
		or direction == Vector2i.DOWN
	)
