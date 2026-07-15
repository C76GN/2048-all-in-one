## BookmarkData: 定义了单个游戏书签所需全部信息的自定义资源。
##
## 该资源封装了恢复一局游戏到特定时间点所需的一切：模式、RNG状态、
## 棋盘布局、分数等。它是一个完整的游戏状态快照。
class_name BookmarkData
extends Resource


# --- 导出变量 ---

## 书签的稳定 UUID v7 标识。
@export var bookmark_id: String = ""

## 书签保存时的 Unix 时间戳，用于展示与生成 UUID v7 的时间部分。
@export var timestamp: int = 0

## 该局游戏使用的模式配置资源路径。
@export var mode_config_path: String = ""

## 游戏状态的游戏种子。
@export var initial_seed: int = 0

## 书签保存时的分数。
@export var score: int = 0

## 书签保存时的移动次数。
@export var move_count: int = 0

## 书签保存时消灭的怪物数。
@export var monsters_killed: int = 0

## 书签保存时的最高玩家方块。
@export var highest_tile: int = 0

## 书签保存时当前模式的目标方块值。
@export var target_tile_value: int = 0

## 书签保存时是否已经达成目标。
@export var target_reached: bool = false

## 书签保存时的状态提示文本。
@export var status_message: String = ""

## 书签保存时的扩展统计数据。
@export var extra_stats: Dictionary = {}

## 完整 RNG 状态，包含 GF 固定随机流与 Godot RNG 分支计数。
@export var rng_full_state: Dictionary = {}

## 完整的棋盘状态快照。
@export var board_snapshot: Dictionary = {}

## 保存生成规则的内部状态。
@export var rules_states: Array = []

## 保存完整的撤回历史记录。
@export var game_state_history: Dictionary = {}


# --- 公共方法 ---

## 转换为 SaveGraph 可持久化字典。
func to_dict() -> Dictionary:
	return {
		"bookmark_id": bookmark_id,
		"timestamp": timestamp,
		"mode_config_path": mode_config_path,
		"initial_seed": initial_seed,
		"score": score,
		"move_count": move_count,
		"monsters_killed": monsters_killed,
		"highest_tile": highest_tile,
		"target_tile_value": target_tile_value,
		"target_reached": target_reached,
		"status_message": status_message,
		"extra_stats": extra_stats.duplicate(true),
		"rng_full_state": rng_full_state.duplicate(true),
		"board_snapshot": board_snapshot.duplicate(true),
		"rules_states": rules_states.duplicate(true),
		"game_state_history": game_state_history.duplicate(true),
	}


## 从当前严格 schema 构造书签；任何字段缺失、类型错误或 ID 非法时返回 null。
## @param data: 当前版本的完整书签字典。
static func from_dict(data: Dictionary) -> BookmarkData:
	if not _has_valid_persisted_shape(data):
		return null

	var result: BookmarkData = BookmarkData.new()
	result.bookmark_id = GFVariantData.get_option_string(data, "bookmark_id")
	if not GFUuid.is_valid(result.bookmark_id, 7):
		return null
	result.timestamp = GFVariantData.get_option_int(data, "timestamp")
	result.mode_config_path = GFVariantData.get_option_string(data, "mode_config_path")
	result.initial_seed = GFVariantData.get_option_int(data, "initial_seed")
	result.score = GFVariantData.get_option_int(data, "score")
	result.move_count = GFVariantData.get_option_int(data, "move_count")
	result.monsters_killed = GFVariantData.get_option_int(data, "monsters_killed")
	result.highest_tile = GFVariantData.get_option_int(data, "highest_tile")
	result.target_tile_value = GFVariantData.get_option_int(data, "target_tile_value")
	result.target_reached = GFVariantData.get_option_bool(data, "target_reached")
	result.status_message = GFVariantData.get_option_string(data, "status_message")
	result.extra_stats = GFVariantData.get_option_dictionary(data, "extra_stats").duplicate(true)
	result.rng_full_state = GFVariantData.get_option_dictionary(data, "rng_full_state").duplicate(true)
	result.board_snapshot = GFVariantData.get_option_dictionary(data, "board_snapshot").duplicate(true)
	result.rules_states = GFVariantData.get_option_array(data, "rules_states").duplicate(true)
	result.game_state_history = GFVariantData.get_option_dictionary(data, "game_state_history").duplicate(true)
	return result


# --- 私有/辅助方法 ---

static func _has_valid_persisted_shape(data: Dictionary) -> bool:
	if data.size() != 16:
		return false
	return (
		GFVariantData.get_option_value(data, "bookmark_id") is String
		and GFVariantData.get_option_value(data, "timestamp") is int
		and GFVariantData.get_option_value(data, "mode_config_path") is String
		and GFVariantData.get_option_value(data, "initial_seed") is int
		and GFVariantData.get_option_value(data, "score") is int
		and GFVariantData.get_option_value(data, "move_count") is int
		and GFVariantData.get_option_value(data, "monsters_killed") is int
		and GFVariantData.get_option_value(data, "highest_tile") is int
		and GFVariantData.get_option_value(data, "target_tile_value") is int
		and GFVariantData.get_option_value(data, "target_reached") is bool
		and GFVariantData.get_option_value(data, "status_message") is String
		and GFVariantData.get_option_value(data, "extra_stats") is Dictionary
		and GFVariantData.get_option_value(data, "rng_full_state") is Dictionary
		and GFVariantData.get_option_value(data, "board_snapshot") is Dictionary
		and GFVariantData.get_option_value(data, "rules_states") is Array
		and GFVariantData.get_option_value(data, "game_state_history") is Dictionary
	)
