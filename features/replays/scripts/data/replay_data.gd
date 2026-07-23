## ReplayData: 复现并逐回合验证一局游戏的严格回放资源。
class_name ReplayData
extends Resource


# --- 常量 ---

const SCHEMA_VERSION: int = 2


# --- 导出变量 ---

@export var schema_version: int = SCHEMA_VERSION
@export var replay_id: String = ""
@export var timestamp: int = 0
@export var mode_config_path: String = ""
@export var ruleset_id: StringName = &""
@export var ruleset_version: int = 0
@export var ruleset_fingerprint: String = ""
@export var initial_seed: int = 0
@export var initial_board_topology: Dictionary = {}
@export var final_score: int = 0
@export var actions: Array[Vector2i] = []
@export var checkpoints: Array[ReplayCheckpoint] = []
@export var final_board_snapshot: Dictionary = {}


# --- 公共方法 ---

## 从当前模式冻结回放规则集身份。
## @param mode_config: 当前权威模式资源。
## @param determinism: 项目确定性摘要 Utility。
func configure_ruleset(
	mode_config: GameModeConfig,
	determinism: GameDeterminismUtility
) -> bool:
	if not is_instance_valid(mode_config) or not is_instance_valid(determinism):
		return false
	ruleset_id = mode_config.ruleset_id
	ruleset_version = mode_config.ruleset_version
	ruleset_fingerprint = determinism.calculate_ruleset_fingerprint(mode_config)
	return not ruleset_fingerprint.is_empty()


## 判断回放规则集是否与当前模式完全匹配。
## @param mode_config: 待比较的当前模式资源。
## @param determinism: 项目确定性摘要 Utility。
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


func to_dict() -> Dictionary:
	var checkpoint_data: Array[Dictionary] = []
	for checkpoint: ReplayCheckpoint in checkpoints:
		if checkpoint != null:
			checkpoint_data.append(checkpoint.to_dict())
	return {
		&"schema_version": SCHEMA_VERSION,
		&"replay_id": replay_id,
		&"timestamp": timestamp,
		&"mode_config_path": mode_config_path,
		&"ruleset_id": ruleset_id,
		&"ruleset_version": ruleset_version,
		&"ruleset_fingerprint": ruleset_fingerprint,
		&"initial_seed": initial_seed,
		&"initial_board_topology": initial_board_topology.duplicate(true),
		&"final_score": final_score,
		&"actions": actions.duplicate(),
		&"checkpoints": checkpoint_data,
		&"final_board_snapshot": final_board_snapshot.duplicate(true),
	}


func get_initial_topology() -> BoardTopology:
	return BoardTopology.from_dict(initial_board_topology)


## 从当前严格 schema 恢复回放资源。
## @param data: ReplayData schema v2 的完整字典。
static func from_dict(data: Dictionary) -> ReplayData:
	if not _has_valid_persisted_shape(data):
		return null
	var result: ReplayData = ReplayData.new()
	result.schema_version = GFVariantData.get_option_int(data, &"schema_version", 0)
	result.replay_id = GFVariantData.get_option_string(data, &"replay_id")
	if not GFUuid.is_valid(result.replay_id, 7):
		return null
	result.timestamp = GFVariantData.get_option_int(data, &"timestamp")
	result.mode_config_path = GFVariantData.get_option_string(data, &"mode_config_path")
	result.ruleset_id = GFVariantData.get_option_string_name(data, &"ruleset_id")
	result.ruleset_version = GFVariantData.get_option_int(data, &"ruleset_version", 0)
	result.ruleset_fingerprint = GFVariantData.get_option_string(
		data,
		&"ruleset_fingerprint"
	)
	result.initial_seed = GFVariantData.get_option_int(data, &"initial_seed")
	result.initial_board_topology = GFVariantData.get_option_dictionary(
		data,
		&"initial_board_topology"
	).duplicate(true)
	var initial_topology: BoardTopology = BoardTopology.from_dict(result.initial_board_topology)
	if initial_topology == null:
		return null
	result.final_score = GFVariantData.get_option_int(data, &"final_score")
	for action_value: Variant in GFVariantData.get_option_array(data, &"actions"):
		if not action_value is Vector2i:
			return null
		result.actions.append(action_value)
	for checkpoint_value: Variant in GFVariantData.get_option_array(data, &"checkpoints"):
		if not checkpoint_value is Dictionary:
			return null
		var checkpoint_data: Dictionary = checkpoint_value
		var checkpoint: ReplayCheckpoint = ReplayCheckpoint.from_dict(checkpoint_data)
		if checkpoint == null:
			return null
		result.checkpoints.append(checkpoint)
	result.final_board_snapshot = GFVariantData.get_option_dictionary(
		data,
		&"final_board_snapshot"
	).duplicate(true)
	if not result._is_valid_contract(initial_topology):
		return null
	return result


# --- 私有/辅助方法 ---

func _is_valid_contract(initial_topology: BoardTopology) -> bool:
	if (
		schema_version != SCHEMA_VERSION
		or mode_config_path.is_empty()
		or ruleset_id == &""
		or ruleset_version <= 0
		or ruleset_fingerprint.length() != 64
		or checkpoints.size() != actions.size()
		or not GridModel.is_snapshot_envelope_valid(final_board_snapshot)
	):
		return false
	for index: int in range(checkpoints.size()):
		var direction: Vector2i = actions[index]
		if absi(direction.x) + absi(direction.y) != 1:
			return false
		if checkpoints[index] == null or checkpoints[index].step_index != index + 1:
			return false
	if not checkpoints.is_empty() and checkpoints.back().score != final_score:
		return false
	var final_topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(final_board_snapshot, &"topology")
	)
	return (
		final_topology != null
		and final_topology.get_stable_key() == initial_topology.get_stable_key()
	)


static func _has_valid_persisted_shape(data: Dictionary) -> bool:
	if data.size() != 13:
		return false
	return (
		GFVariantData.get_option_value(data, &"schema_version") is int
		and GFVariantData.get_option_value(data, &"replay_id") is String
		and GFVariantData.get_option_value(data, &"timestamp") is int
		and GFVariantData.get_option_value(data, &"mode_config_path") is String
		and GFVariantData.get_option_value(data, &"ruleset_id") is StringName
		and GFVariantData.get_option_value(data, &"ruleset_version") is int
		and GFVariantData.get_option_value(data, &"ruleset_fingerprint") is String
		and GFVariantData.get_option_value(data, &"initial_seed") is int
		and GFVariantData.get_option_value(data, &"initial_board_topology") is Dictionary
		and GFVariantData.get_option_value(data, &"final_score") is int
		and GFVariantData.get_option_value(data, &"actions") is Array
		and GFVariantData.get_option_value(data, &"checkpoints") is Array
		and GFVariantData.get_option_value(data, &"final_board_snapshot") is Dictionary
	)
