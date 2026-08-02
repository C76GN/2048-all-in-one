## BookmarkData: 定义了单个游戏书签所需全部信息的自定义资源。
##
## 该资源封装了恢复一局游戏到特定时间点所需的一切：模式、RNG状态、
## 棋盘布局、分数等。它是一个完整的游戏状态快照。
class_name BookmarkData
extends Resource


# --- 常量 ---

## v6 以 GFStorageCodec 二进制信封保存命令历史，避免 Profile gather
## 在主线程递归复制每一步完整快照。读取时兼容 v5 的字典历史并在下次保存时
## 原子升级；所在 bookmarks section 无需失效，也不会重置玩家 Profile。
const SCHEMA_VERSION: int = 6
## 新建书签的 undo/redo 合计只保留最近 64 条；运行中 GFCommandHistory 的
## 1024 条上限不变。读取仍接受当前 schema 的历史条目，但必须满足下方统一载荷预算。
const PERSISTED_HISTORY_TOTAL_LIMIT: int = 64
## v5 迁移输入的绝对命令数边界；只用于复制前防御，不改变 v6 新书签的 64 条窗口。
const LEGACY_HISTORY_ABSOLUTE_COMMAND_LIMIT: int = 1024
## 玩家可达棋盘当前不超过 8x8；为未来 16x16 布局预留到 256 格，
## 同时阻止通用 BoardTopology 的工具级极限进入每步命令快照。
const PERSISTED_BOARD_CELL_LIMIT: int = 256
## 回放轨迹属于书签恢复证据而不是无界日志。
const PERSISTED_REPLAY_TRACE_LIMIT: int = 8192
const _LEGACY_DICTIONARY_HISTORY_SCHEMA_VERSION: int = 5
const _HISTORY_CODEC_ID: String = "gf_storage_binary_v1"
## 256 格状态、64 条命令的防御预算；为字段和 codec 开销留出余量，
## 但不再允许单个书签独占 GFStorage 64 MiB 文档预算的一半。
const MAX_HISTORY_PAYLOAD_BYTES: int = 2 * 1024 * 1024


# --- 导出变量 ---

@export var schema_version: int = SCHEMA_VERSION

## 书签的稳定 UUID v7 标识。
@export var bookmark_id: String = ""

## 书签保存时的 Unix 时间戳，用于展示与生成 UUID v7 的时间部分。
@export var timestamp: int = 0

## 该局游戏使用的模式配置资源路径。
@export var mode_config_path: String = ""

## 保存时冻结的稳定玩法规则集 ID。
@export var ruleset_id: StringName = &""

## 保存时冻结的玩法规则集版本。
@export var ruleset_version: int = 0

## 保存时冻结的完整玩法内容指纹。
@export var ruleset_fingerprint: String = ""

## 游戏状态的游戏种子。
@export var initial_seed: int = 0

## 保存时冻结的 seed 来源和比赛资格上下文。
@export var session_metadata: Dictionary = GameSessionMetadata.make_default_dict()

## 书签保存时的分数。
@export var score: int = 0

## 书签保存时的移动次数。
@export var move_count: int = 0

## 书签保存时完成的跨定义求商次数。
@export var ratio_resolutions: int = 0

## 书签保存时的最高方块值。
@export var highest_tile: int = 0

## 书签保存时当前模式的目标方块值。
@export var target_tile_value: int = 0

## 书签保存时是否已经达成目标。
@export var target_reached: bool = false

## 书签保存时的扩展统计数据。
@export var extra_stats: Dictionary = {}

## 完整 RNG 状态，包含 GF 固定随机流与 Godot RNG 分支计数。
@export var rng_full_state: Dictionary = {}

## 完整的棋盘状态快照。
@export var board_snapshot: Dictionary = {}

## 保存生成规则的内部状态。
@export var rules_states: Dictionary = {}

## 运行时完整 undo/redo 历史；新书签持久化时合计保留最近 64 条
## （双栈非空时各 32 条，单栈可使用全部容量）。
@export var game_state_history: Dictionary = {}

## 从初始种子到当前书签位置的有效玩家操作。
@export var replay_actions: Array[Vector2i] = []

## 与 replay_actions 一一对应的确定性回放检查点。
@export var replay_checkpoints: Array[ReplayCheckpoint] = []


# --- 公共方法 ---

## 从当前模式冻结书签规则集身份。
## @param mode_config: 当前权威模式配置。
## @param determinism: 负责生成规则集身份的确定性工具。
func configure_ruleset(
	mode_config: GameModeConfig,
	determinism: GameDeterminismUtility
) -> bool:
	if not is_instance_valid(mode_config) or not is_instance_valid(determinism):
		return false
	ruleset_id = mode_config.ruleset_id
	ruleset_version = mode_config.ruleset_version
	ruleset_fingerprint = determinism.calculate_ruleset_fingerprint(mode_config)
	return _is_valid_fingerprint(ruleset_fingerprint)


## 判断书签规则集是否与当前模式完全匹配。
## @param mode_config: 要比较的当前权威模式配置。
## @param determinism: 负责生成规则集身份的确定性工具。
func matches_ruleset(
	mode_config: GameModeConfig,
	determinism: GameDeterminismUtility
) -> bool:
	return (
		is_instance_valid(mode_config)
		and is_instance_valid(determinism)
		and ruleset_id == mode_config.ruleset_id
		and ruleset_version == mode_config.ruleset_version
		and ruleset_fingerprint == determinism.calculate_ruleset_fingerprint(mode_config)
	)


## 转换为 GFSaveProfile 可持久化字典。
func to_dict() -> Dictionary:
	return _to_persisted_dict(true, false)


## 构造仅供 BookmarkCatalogSaveData 严格候选应用的持久化信封。
##
## 此入口把 undo/redo 合计裁剪为最近 64 条，并跳过编码前对命令历史的重复
## 语义遍历；双栈都非空时各预留一半，空余容量由另一栈使用。provider 对所有
## 新增或变化 payload 仍必须通过 from_dict() 完整解码校验后才可进入权威状态。
func to_persisted_candidate_envelope() -> Dictionary:
	return _to_persisted_dict(false, true)


## 轻量校验持久化书签信封，不解码可能很大的二进制命令历史。
##
## 此入口用于 section 内的稳定 ID 查询、过滤与排序。v6 历史只校验 codec、
## 类型和大小边界；GameSaveGraph 的 BookmarkCatalogSaveData provider 在应用
## 候选 section 时仍会通过 from_dict() 完整解码并执行最终语义校验。
## @param data: to_dict()、to_persisted_candidate_envelope() 或 provider
## 当前持有的书签信封。
static func is_persisted_envelope_lightweight_valid(data: Dictionary) -> bool:
	if not _has_valid_persisted_shape(data):
		return false
	var persisted_schema_version: int = GFVariantData.get_option_int(
		data,
		"schema_version",
		0
	)
	if not _is_persisted_history_envelope_valid(
		GFVariantData.as_dictionary(
			GFVariantData.get_option_value(data, "game_state_history")
		),
		persisted_schema_version
	):
		return false

	# 复用完整字段与业务身份校验，但以规范空历史代替大二进制载荷；
	# 真正 payload 的解码与命令语义仍由 provider 的 from_dict() 承担一次。
	# 这里只替换顶层 history 信封；浅复制避免为校验再次复制大 payload。
	var validation_data: Dictionary = data.duplicate(false)
	var empty_history: Dictionary = {
		"undo": [],
		"redo": [],
	}
	validation_data["game_state_history"] = (
		empty_history
		if persisted_schema_version == _LEGACY_DICTIONARY_HISTORY_SCHEMA_VERSION
		else _encode_history(empty_history)
	)
	return from_dict(validation_data) != null


## 在取得候选所有权前执行不会复制大型容器的防御校验。
##
## 此入口只确认根 schema、二进制历史字节数、旧历史命令数、棋盘格数与回放数；
## provider 取得隔离或唯一所有权后仍须调用 from_dict() 完成语义校验。
## @param data: 尚未复制或接管的持久化书签 envelope。
static func is_persisted_envelope_copy_boundary_valid(
	data: Dictionary
) -> bool:
	if not _has_valid_persisted_shape(data):
		return false
	var persisted_schema_version: int = GFVariantData.get_option_int(
		data,
		"schema_version",
		0
	)
	var history: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(data, "game_state_history")
	)
	if persisted_schema_version == _LEGACY_DICTIONARY_HISTORY_SCHEMA_VERSION:
		if not _has_valid_history_root_shape(history):
			return false
		var legacy_command_count: int = (
			GFVariantData.as_array(
				GFVariantData.get_option_value(history, "undo")
			).size()
			+ GFVariantData.as_array(
				GFVariantData.get_option_value(history, "redo")
			).size()
		)
		if legacy_command_count > LEGACY_HISTORY_ABSOLUTE_COMMAND_LIMIT:
			return false
	elif not _is_persisted_history_envelope_valid(
		history,
		persisted_schema_version
	):
		return false
	if not _is_board_snapshot_within_persisted_bounds(
		GFVariantData.as_dictionary(
			GFVariantData.get_option_value(data, "board_snapshot")
		)
	):
		return false
	var action_values: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(data, "replay_actions")
	)
	var checkpoint_values: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(data, "replay_checkpoints")
	)
	return (
		action_values.size() <= PERSISTED_REPLAY_TRACE_LIMIT
		and checkpoint_values.size() == action_values.size()
	)


func get_session_metadata() -> GameSessionMetadata:
	return GameSessionMetadata.from_dict(session_metadata)


## 从当前严格 schema 构造书签；任何字段缺失、类型错误或 ID 非法时返回 null。
## @param data: 当前版本的完整书签字典。
static func from_dict(data: Dictionary) -> BookmarkData:
	if not is_persisted_envelope_copy_boundary_valid(data):
		return null

	var result: BookmarkData = BookmarkData.new()
	var persisted_schema_version: int = GFVariantData.get_option_int(
		data,
		"schema_version",
		0
	)
	result.schema_version = SCHEMA_VERSION
	result.bookmark_id = GFVariantData.get_option_string(data, "bookmark_id")
	if not GFUuid.is_valid(result.bookmark_id, 7):
		return null
	result.timestamp = GFVariantData.get_option_int(data, "timestamp")
	result.mode_config_path = GFVariantData.get_option_string(data, "mode_config_path")
	result.ruleset_id = GFVariantData.get_option_string_name(data, "ruleset_id")
	result.ruleset_version = GFVariantData.get_option_int(data, "ruleset_version", 0)
	result.ruleset_fingerprint = GFVariantData.get_option_string(data, "ruleset_fingerprint")
	result.initial_seed = GFVariantData.get_option_int(data, "initial_seed")
	result.session_metadata = GFVariantData.get_option_dictionary(
		data,
		"session_metadata"
	).duplicate(true)
	if result.get_session_metadata() == null:
		return null
	result.score = GFVariantData.get_option_int(data, "score")
	result.move_count = GFVariantData.get_option_int(data, "move_count")
	result.ratio_resolutions = GFVariantData.get_option_int(data, "ratio_resolutions")
	result.highest_tile = GFVariantData.get_option_int(data, "highest_tile")
	result.target_tile_value = GFVariantData.get_option_int(data, "target_tile_value")
	result.target_reached = GFVariantData.get_option_bool(data, "target_reached")
	result.extra_stats = GFVariantData.get_option_dictionary(data, "extra_stats").duplicate(true)
	result.rng_full_state = GFVariantData.get_option_dictionary(data, "rng_full_state").duplicate(true)
	var board_snapshot_value: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(data, "board_snapshot")
	)
	# active_cells/tiles 数量可从候选根直接读取；必须在获取独立所有权前
	# 拒绝超限棋盘，避免恶意存档触发一次无意义的大型递归复制。
	if not _is_board_snapshot_within_persisted_bounds(board_snapshot_value):
		return null
	result.board_snapshot = board_snapshot_value.duplicate(true)
	if not GridModel.is_snapshot_envelope_valid(result.board_snapshot):
		return null
	result.rules_states = GFVariantData.get_option_dictionary(data, "rules_states").duplicate(true)
	result.game_state_history = _decode_history(
		GFVariantData.get_option_dictionary(data, "game_state_history"),
		persisted_schema_version
	)
	var action_values: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(data, "replay_actions")
	)
	var checkpoint_values: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(data, "replay_checkpoints")
	)
	if (
		action_values.size() > PERSISTED_REPLAY_TRACE_LIMIT
		or checkpoint_values.size() != action_values.size()
	):
		return null
	for action_value: Variant in action_values:
		if not action_value is Vector2i:
			return null
		result.replay_actions.append(action_value)
	for checkpoint_value: Variant in checkpoint_values:
		if not checkpoint_value is Dictionary:
			return null
		var checkpoint_data: Dictionary = checkpoint_value
		var checkpoint: ReplayCheckpoint = ReplayCheckpoint.from_dict(checkpoint_data)
		if checkpoint == null:
			return null
		result.replay_checkpoints.append(checkpoint)
	if not result._has_valid_replay_trace():
		return null
	# _decode_history() 只返回已完成命令语义校验的历史；空字典代表解码失败。
	if (
		not result._has_valid_game_state_payload()
		or result.game_state_history.is_empty()
	):
		return null
	return result


# --- 私有/辅助方法 ---

func _to_persisted_dict(
	should_validate_history: bool,
	should_bound_history: bool
) -> Dictionary:
	var checkpoint_data: Array[Dictionary] = []
	for checkpoint: ReplayCheckpoint in replay_checkpoints:
		if checkpoint != null:
			checkpoint_data.append(checkpoint.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"bookmark_id": bookmark_id,
		"timestamp": timestamp,
		"mode_config_path": mode_config_path,
		"ruleset_id": ruleset_id,
		"ruleset_version": ruleset_version,
		"ruleset_fingerprint": ruleset_fingerprint,
		"initial_seed": initial_seed,
		"session_metadata": session_metadata.duplicate(true),
		"score": score,
		"move_count": move_count,
		"ratio_resolutions": ratio_resolutions,
		"highest_tile": highest_tile,
		"target_tile_value": target_tile_value,
		"target_reached": target_reached,
		"extra_stats": extra_stats.duplicate(true),
		"rng_full_state": rng_full_state.duplicate(true),
		"board_snapshot": board_snapshot.duplicate(true),
		"rules_states": rules_states.duplicate(true),
		"game_state_history": _encode_history(
			_bound_history_for_new_bookmark(game_state_history)
			if should_bound_history
			else game_state_history,
			should_validate_history
		),
		"replay_actions": replay_actions.duplicate(),
		"replay_checkpoints": checkpoint_data,
	}


static func _bound_history_for_new_bookmark(history: Dictionary) -> Dictionary:
	if not _has_valid_history_root_shape(history):
		return {}
	var undo_stack: Array = GFVariantData.get_option_array(history, "undo")
	var redo_stack: Array = GFVariantData.get_option_array(history, "redo")
	var half_limit: int = PERSISTED_HISTORY_TOTAL_LIMIT >> 1
	var undo_limit: int = mini(undo_stack.size(), half_limit)
	var redo_limit: int = mini(redo_stack.size(), half_limit)
	var remaining: int = (
		PERSISTED_HISTORY_TOTAL_LIMIT - undo_limit - redo_limit
	)
	var undo_overflow: int = undo_stack.size() - undo_limit
	var undo_extra: int = mini(undo_overflow, remaining)
	undo_limit += undo_extra
	remaining -= undo_extra
	var redo_overflow: int = redo_stack.size() - redo_limit
	redo_limit += mini(redo_overflow, remaining)
	return {
		"undo": undo_stack.slice(undo_stack.size() - undo_limit),
		"redo": redo_stack.slice(redo_stack.size() - redo_limit),
	}


static func _has_valid_persisted_shape(data: Dictionary) -> bool:
	if data.size() != 22:
		return false
	var has_expected_types: bool = (
		GFVariantData.get_option_value(data, "schema_version") is int
		and GFVariantData.get_option_value(data, "bookmark_id") is String
		and GFVariantData.get_option_value(data, "timestamp") is int
		and GFVariantData.get_option_value(data, "mode_config_path") is String
		and GFVariantData.get_option_value(data, "ruleset_id") is StringName
		and GFVariantData.get_option_value(data, "ruleset_version") is int
		and GFVariantData.get_option_value(data, "ruleset_fingerprint") is String
		and GFVariantData.get_option_value(data, "initial_seed") is int
		and GFVariantData.get_option_value(data, "session_metadata") is Dictionary
		and GFVariantData.get_option_value(data, "score") is int
		and GFVariantData.get_option_value(data, "move_count") is int
		and GFVariantData.get_option_value(data, "ratio_resolutions") is int
		and GFVariantData.get_option_value(data, "highest_tile") is int
		and GFVariantData.get_option_value(data, "target_tile_value") is int
		and GFVariantData.get_option_value(data, "target_reached") is bool
		and GFVariantData.get_option_value(data, "extra_stats") is Dictionary
		and GFVariantData.get_option_value(data, "rng_full_state") is Dictionary
		and GFVariantData.get_option_value(data, "board_snapshot") is Dictionary
		and GFVariantData.get_option_value(data, "rules_states") is Dictionary
		and GFVariantData.get_option_value(data, "game_state_history") is Dictionary
		and GFVariantData.get_option_value(data, "replay_actions") is Array
		and GFVariantData.get_option_value(data, "replay_checkpoints") is Array
	)
	if not has_expected_types:
		return false
	var persisted_schema_version: int = GFVariantData.get_option_int(
		data,
		"schema_version",
		0
	)
	return (
		persisted_schema_version in [
			_LEGACY_DICTIONARY_HISTORY_SCHEMA_VERSION,
			SCHEMA_VERSION,
		]
		and GFVariantData.get_option_int(data, "timestamp", -1) >= 0
		and not GFVariantData.get_option_string(data, "mode_config_path").is_empty()
		and GFVariantData.get_option_string_name(data, "ruleset_id") != &""
		and GFVariantData.get_option_int(data, "ruleset_version", 0) > 0
		and _is_valid_fingerprint(
			GFVariantData.get_option_string(data, "ruleset_fingerprint")
		)
		and GFVariantData.get_option_int(data, "score", -1) >= 0
		and GFVariantData.get_option_int(data, "move_count", -1) >= 0
		and GFVariantData.get_option_int(data, "ratio_resolutions", -1) >= 0
		and _has_valid_target_state(data)
	)


static func _has_valid_target_state(data: Dictionary) -> bool:
	var highest_tile_value: int = GFVariantData.get_option_int(data, "highest_tile")
	var target_value: int = GFVariantData.get_option_int(data, "target_tile_value")
	var reached: bool = GFVariantData.get_option_bool(data, "target_reached")
	if highest_tile_value < 0 or target_value < 0:
		return false
	if target_value == 0:
		return not reached
	return reached or highest_tile_value < target_value


func _has_valid_replay_trace() -> bool:
	if replay_actions.size() != replay_checkpoints.size():
		return false
	for index: int in range(replay_actions.size()):
		var direction: Vector2i = replay_actions[index]
		if absi(direction.x) + absi(direction.y) != 1:
			return false
		var checkpoint: ReplayCheckpoint = replay_checkpoints[index]
		if checkpoint == null or checkpoint.step_index != index + 1:
			return false
	if not replay_checkpoints.is_empty() and replay_checkpoints.back().score != score:
		return false
	return true


func _has_valid_game_state_payload() -> bool:
	var topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(board_snapshot, &"topology")
	)
	if topology == null:
		return false
	var metadata: GameSessionMetadata = get_session_metadata()
	if metadata == null:
		return false
	return GameStateSystem.is_state_envelope_valid({
		&"schema_version": GameStateSystem.STATE_SCHEMA_VERSION,
		&"board_key": topology.get_stable_key(),
		&"board_snapshot": board_snapshot,
		&"rng_full_state": rng_full_state,
		&"score": score,
		&"move_count": move_count,
		&"highest_tile": highest_tile,
		&"ratio_resolutions": ratio_resolutions,
		&"target_tile_value": target_tile_value,
		&"target_reached": target_reached,
		&"extra_stats": extra_stats,
		&"rules_states": rules_states,
	})


static func _has_valid_history_root_shape(history: Dictionary) -> bool:
	return (
		history.size() == 2
		and GFVariantData.get_option_value(history, "undo") is Array
		and GFVariantData.get_option_value(history, "redo") is Array
	)


static func _is_valid_history(history: Dictionary) -> bool:
	if not _has_valid_history_root_shape(history):
		return false
	for stack_key: String in ["undo", "redo"]:
		for command_value: Variant in GFVariantData.get_option_array(history, stack_key):
			if not command_value is Dictionary:
				return false
			var command_data: Dictionary = command_value
			if not MoveCommand.is_serialized_data_valid(command_data):
				return false
	return true


static func _encode_history(
	history: Dictionary,
	should_validate: bool = true
) -> Dictionary:
	if not _has_valid_history_root_shape(history):
		return {}
	if should_validate and not _is_valid_history(history):
		return {}
	var codec: GFStorageCodec = GFStorageCodec.new()
	var payload: PackedByteArray = codec.serialize_dictionary(
		history,
		GFStorageCodec.Format.BINARY
	)
	if (
		payload.is_empty()
		or payload.size() > MAX_HISTORY_PAYLOAD_BYTES
	):
		return {}
	return {
		"codec": _HISTORY_CODEC_ID,
		"payload": payload,
	}


static func _decode_history(
	envelope: Dictionary,
	persisted_schema_version: int
) -> Dictionary:
	if persisted_schema_version == _LEGACY_DICTIONARY_HISTORY_SCHEMA_VERSION:
		return envelope.duplicate(true) if _is_valid_history(envelope) else {}
	if persisted_schema_version != SCHEMA_VERSION:
		return {}
	if not (
		envelope.size() == 2
		and GFVariantData.get_option_value(envelope, "codec") is String
		and GFVariantData.get_option_value(envelope, "payload")
		is PackedByteArray
		and GFVariantData.get_option_string(envelope, "codec")
		== _HISTORY_CODEC_ID
	):
		return {}
	var payload_value: Variant = GFVariantData.get_option_value(
		envelope,
		"payload"
	)
	var payload: PackedByteArray = payload_value
	if (
		payload.is_empty()
		or payload.size() > MAX_HISTORY_PAYLOAD_BYTES
	):
		return {}
	var codec: GFStorageCodec = GFStorageCodec.new()
	var history: Dictionary = codec.deserialize_dictionary(
		payload,
		GFStorageCodec.Format.BINARY
	)
	return history if _is_valid_history(history) else {}


static func _is_persisted_history_envelope_valid(
	envelope: Dictionary,
	persisted_schema_version: int
) -> bool:
	if persisted_schema_version == _LEGACY_DICTIONARY_HISTORY_SCHEMA_VERSION:
		return _is_valid_history(envelope)
	if persisted_schema_version != SCHEMA_VERSION:
		return false
	if not (
		envelope.size() == 2
		and GFVariantData.get_option_value(envelope, "codec") is String
		and GFVariantData.get_option_value(envelope, "payload")
		is PackedByteArray
		and GFVariantData.get_option_string(envelope, "codec")
		== _HISTORY_CODEC_ID
	):
		return false
	var payload_value: Variant = GFVariantData.get_option_value(
		envelope,
		"payload"
	)
	var payload: PackedByteArray = payload_value
	return not payload.is_empty() and payload.size() <= MAX_HISTORY_PAYLOAD_BYTES


static func _is_board_snapshot_within_persisted_bounds(
	snapshot: Dictionary
) -> bool:
	if not (
		GFVariantData.get_option_value(snapshot, &"topology") is Dictionary
		and GFVariantData.get_option_value(snapshot, &"tiles") is Array
	):
		return false
	var topology_data: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(snapshot, &"topology")
	)
	if not GFVariantData.get_option_value(
		topology_data,
		&"active_cells"
	) is Array:
		return false
	return (
		GFVariantData.as_array(
			GFVariantData.get_option_value(topology_data, &"active_cells")
		).size() <= PERSISTED_BOARD_CELL_LIMIT
		and GFVariantData.as_array(
			GFVariantData.get_option_value(snapshot, &"tiles")
		).size() <= PERSISTED_BOARD_CELL_LIMIT
	)


static func _is_valid_fingerprint(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1).to_lower()
		if not (
			(character >= "0" and character <= "9")
			or (character >= "a" and character <= "f")
		):
			return false
	return true
