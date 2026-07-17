## ReplayData: 定义了单个游戏回放所需全部信息的自定义资源。
##
## 该资源封装了复现一局游戏所需的一切：初始状态（种子、模式、拓扑）、
## 玩家的完整操作序列，以及用于导航的快照标记。
class_name ReplayData
extends Resource


# --- 导出变量 ---

## 回放的稳定 UUID v7 标识。
@export var replay_id: String = ""

## 回放保存时的 Unix 时间戳，用于展示与生成 UUID v7 的时间部分。
@export var timestamp: int = 0

## 该局游戏使用的模式配置资源路径。
@export var mode_config_path: String = ""

## 游戏开始时的初始RNG种子。
@export var initial_seed: int = 0

## 游戏开始时的严格 BoardTopology 快照。
@export var initial_board_topology: Dictionary = {}

## 最终得分。
@export var final_score: int = 0

## 玩家的每一步有效操作。存储为Vector2i以代表方向。
@export var actions: Array[Vector2i] = []

## 游戏结束时的棋盘状态快照，用于在列表中预览。
@export var final_board_snapshot: Dictionary = {}


# --- 公共方法 ---

## 转换为 SaveGraph 可持久化字典。
func to_dict() -> Dictionary:
	return {
		"replay_id": replay_id,
		"timestamp": timestamp,
		"mode_config_path": mode_config_path,
		"initial_seed": initial_seed,
		"initial_board_topology": initial_board_topology.duplicate(true),
		"final_score": final_score,
		"actions": actions.duplicate(),
		"final_board_snapshot": final_board_snapshot.duplicate(true),
	}


func get_initial_topology() -> BoardTopology:
	return BoardTopology.from_dict(initial_board_topology)


## 从当前严格 schema 构造回放；任何字段缺失、类型错误或 ID 非法时返回 null。
## @param data: 当前版本的完整回放字典。
static func from_dict(data: Dictionary) -> ReplayData:
	if not _has_valid_persisted_shape(data):
		return null

	var result: ReplayData = ReplayData.new()
	result.replay_id = GFVariantData.get_option_string(data, "replay_id")
	if not GFUuid.is_valid(result.replay_id, 7):
		return null
	result.timestamp = GFVariantData.get_option_int(data, "timestamp")
	result.mode_config_path = GFVariantData.get_option_string(data, "mode_config_path")
	result.initial_seed = GFVariantData.get_option_int(data, "initial_seed")
	result.initial_board_topology = GFVariantData.get_option_dictionary(
		data,
		"initial_board_topology"
	).duplicate(true)
	var initial_topology: BoardTopology = BoardTopology.from_dict(result.initial_board_topology)
	if initial_topology == null:
		return null
	result.final_score = GFVariantData.get_option_int(data, "final_score")
	for action_value: Variant in GFVariantData.get_option_array(data, "actions"):
		if not (action_value is Vector2i):
			return null
		var action: Vector2i = action_value
		result.actions.append(action)
	result.final_board_snapshot = GFVariantData.get_option_dictionary(data, "final_board_snapshot").duplicate(true)
	if not GridModel.is_snapshot_envelope_valid(result.final_board_snapshot):
		return null
	var final_topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(result.final_board_snapshot, &"topology")
	)
	if final_topology == null or final_topology.get_stable_key() != initial_topology.get_stable_key():
		return null
	return result


# --- 私有/辅助方法 ---

static func _has_valid_persisted_shape(data: Dictionary) -> bool:
	if data.size() != 8:
		return false
	return (
		GFVariantData.get_option_value(data, "replay_id") is String
		and GFVariantData.get_option_value(data, "timestamp") is int
		and GFVariantData.get_option_value(data, "mode_config_path") is String
		and GFVariantData.get_option_value(data, "initial_seed") is int
		and GFVariantData.get_option_value(data, "initial_board_topology") is Dictionary
		and GFVariantData.get_option_value(data, "final_score") is int
		and GFVariantData.get_option_value(data, "actions") is Array
		and GFVariantData.get_option_value(data, "final_board_snapshot") is Dictionary
	)
