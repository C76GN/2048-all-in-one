## CustomBoardData: 玩家保存的一张自定义棋盘模板。
class_name CustomBoardData
extends Resource


# --- 常量 ---

const MAX_DISPLAY_NAME_LENGTH: int = 64
const TOPOLOGY_ID_PREFIX: String = "board.player."


# --- 导出变量 ---

@export var custom_board_id: String = ""
@export var display_name: String = ""
@export var created_at: int = 0
@export var updated_at: int = 0
@export var topology: BoardTopology


# --- 公共方法 ---

func to_dict() -> Dictionary:
	return {
		"custom_board_id": custom_board_id,
		"display_name": display_name,
		"created_at": created_at,
		"updated_at": updated_at,
		"topology": topology.to_dict() if is_instance_valid(topology) else {},
	}


## 从当前严格 schema 恢复玩家棋盘；任何额外字段或非法拓扑都会被拒绝。
## @param data: 当前版本的完整持久化字典。
static func from_dict(data: Dictionary) -> CustomBoardData:
	if not _has_valid_persisted_shape(data):
		return null

	var result: CustomBoardData = CustomBoardData.new()
	result.custom_board_id = GFVariantData.get_option_string(data, "custom_board_id")
	result.display_name = GFVariantData.get_option_string(data, "display_name")
	result.created_at = GFVariantData.get_option_int(data, "created_at")
	result.updated_at = GFVariantData.get_option_int(data, "updated_at")
	result.topology = BoardTopology.from_dict(GFVariantData.get_option_dictionary(data, "topology"))
	if not GFUuid.is_valid(result.custom_board_id, 7):
		return null
	if not _is_valid_display_name(result.display_name):
		return null
	if result.created_at <= 0 or result.updated_at < result.created_at:
		return null
	if not is_instance_valid(result.topology):
		return null
	if result.topology.topology_id != get_topology_id(result.custom_board_id):
		return null
	return result


## @param board_id: 玩家棋盘 UUID v7。
static func get_topology_id(board_id: String) -> StringName:
	return StringName(TOPOLOGY_ID_PREFIX + board_id)


## @param value: 用户输入的显示名称。
static func normalize_display_name(value: String) -> String:
	return value.strip_edges().substr(0, MAX_DISPLAY_NAME_LENGTH)


# --- 私有/辅助方法 ---

static func _has_valid_persisted_shape(data: Dictionary) -> bool:
	return (
		data.size() == 5
		and GFVariantData.get_option_value(data, "custom_board_id") is String
		and GFVariantData.get_option_value(data, "display_name") is String
		and GFVariantData.get_option_value(data, "created_at") is int
		and GFVariantData.get_option_value(data, "updated_at") is int
		and GFVariantData.get_option_value(data, "topology") is Dictionary
	)


static func _is_valid_display_name(value: String) -> bool:
	return (
		not value.is_empty()
		and value == value.strip_edges()
		and value.length() <= MAX_DISPLAY_NAME_LENGTH
	)
