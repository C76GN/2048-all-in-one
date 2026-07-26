## BookmarkData: 定义了单个游戏书签所需全部信息的自定义资源。
##
## 该资源封装了恢复一局游戏到特定时间点所需的一切：模式、RNG状态、
## 棋盘布局、分数等。它是一个完整的游戏状态快照。
class_name BookmarkData
extends Resource


# --- 常量 ---

const SCHEMA_VERSION: int = 4


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

## 保存完整的撤回历史记录。
@export var game_state_history: Dictionary = {}

## 从初始种子到当前书签位置的有效玩家操作。
@export var replay_actions: Array[Vector2i] = []

## 与 replay_actions 一一对应的确定性回放检查点。
@export var replay_checkpoints: Array[ReplayCheckpoint] = []


# --- 公共方法 ---

## 从当前模式冻结书签规则集身份。
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


## 转换为 SaveGraph 可持久化字典。
func to_dict() -> Dictionary:
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
		"game_state_history": game_state_history.duplicate(true),
		"replay_actions": replay_actions.duplicate(),
		"replay_checkpoints": checkpoint_data,
	}


## 从当前严格 schema 构造书签；任何字段缺失、类型错误或 ID 非法时返回 null。
## @param data: 当前版本的完整书签字典。
static func from_dict(data: Dictionary) -> BookmarkData:
	if not _has_valid_persisted_shape(data):
		return null

	var result: BookmarkData = BookmarkData.new()
	result.schema_version = GFVariantData.get_option_int(data, "schema_version", 0)
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
	result.board_snapshot = GFVariantData.get_option_dictionary(data, "board_snapshot").duplicate(true)
	if not GridModel.is_snapshot_envelope_valid(result.board_snapshot):
		return null
	result.rules_states = GFVariantData.get_option_dictionary(data, "rules_states").duplicate(true)
	result.game_state_history = GFVariantData.get_option_dictionary(data, "game_state_history").duplicate(true)
	for action_value: Variant in GFVariantData.get_option_array(data, "replay_actions"):
		if not action_value is Vector2i:
			return null
		result.replay_actions.append(action_value)
	for checkpoint_value: Variant in GFVariantData.get_option_array(data, "replay_checkpoints"):
		if not checkpoint_value is Dictionary:
			return null
		var checkpoint_data: Dictionary = checkpoint_value
		var checkpoint: ReplayCheckpoint = ReplayCheckpoint.from_dict(checkpoint_data)
		if checkpoint == null:
			return null
		result.replay_checkpoints.append(checkpoint)
	if not result._has_valid_replay_trace():
		return null
	if not result._has_valid_game_state_payload() or not _is_valid_history(
		result.game_state_history
	):
		return null
	return result


func get_session_metadata() -> GameSessionMetadata:
	return GameSessionMetadata.from_dict(session_metadata)


# --- 私有/辅助方法 ---

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
	return (
		GFVariantData.get_option_int(data, "schema_version", 0) == SCHEMA_VERSION
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


static func _is_valid_history(history: Dictionary) -> bool:
	if not (
		history.size() == 2
		and GFVariantData.get_option_value(history, "undo") is Array
		and GFVariantData.get_option_value(history, "redo") is Array
	):
		return false
	for stack_key: String in ["undo", "redo"]:
		for command_value: Variant in GFVariantData.get_option_array(history, stack_key):
			if not command_value is Dictionary:
				return false
			var command_data: Dictionary = command_value
			if not MoveCommand.is_serialized_data_valid(command_data):
				return false
	return true


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
