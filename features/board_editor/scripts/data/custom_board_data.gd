## CustomBoardData: 玩家保存的一张自定义棋盘模板。
class_name CustomBoardData
extends Resource


# --- 常量 ---

const MAX_DISPLAY_NAME_LENGTH: int = 64
## 自定义棋盘持久化上限；当前编辑器最大 8x8，向后预留到 16x16。
const MAX_PERSISTED_CELL_COUNT: int = 256
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
	if not is_persisted_envelope_copy_boundary_valid(data):
		return null

	var result: CustomBoardData = CustomBoardData.new()
	result.custom_board_id = GFVariantData.get_option_string(data, "custom_board_id")
	result.display_name = GFVariantData.get_option_string(data, "display_name")
	result.created_at = GFVariantData.get_option_int(data, "created_at")
	result.updated_at = GFVariantData.get_option_int(data, "updated_at")
	var topology_data: Dictionary = GFVariantData.get_option_dictionary(
		data,
		"topology"
	)
	result.topology = BoardTopology.from_dict(topology_data)
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


## 在 provider 深复制调用方候选前执行有界结构与容量校验。
##
## 该入口只遍历最多 256 个 Vector2i；完整拓扑语义仍由 from_dict() 校验。
## @param data: 尚未复制或接管的自定义棋盘 envelope。
static func is_persisted_envelope_copy_boundary_valid(
	data: Dictionary
) -> bool:
	if not _has_valid_persisted_shape(data):
		return false
	var board_id: String = GFVariantData.get_option_string(
		data,
		&"custom_board_id"
	)
	var display_name_value: String = GFVariantData.get_option_string(
		data,
		&"display_name"
	)
	var created_at_value: int = GFVariantData.get_option_int(
		data,
		&"created_at"
	)
	var updated_at_value: int = GFVariantData.get_option_int(
		data,
		&"updated_at"
	)
	if (
		not GFUuid.is_valid(board_id, 7)
		or not _is_valid_display_name(display_name_value)
		or created_at_value <= 0
		or updated_at_value < created_at_value
	):
		return false
	var topology_data: Dictionary = GFVariantData.as_dictionary(
		GFVariantData.get_option_value(data, &"topology")
	)
	if not (
		topology_data.size() == 3
		and GFVariantData.get_option_value(
			topology_data,
			&"schema_version"
		) is int
		and GFVariantData.get_option_value(
			topology_data,
			&"topology_id"
		) is String
		and GFVariantData.get_option_value(
			topology_data,
			&"active_cells"
		) is Array
		and GFVariantData.get_option_int(
			topology_data,
			&"schema_version"
		) == BoardTopology.SERIALIZATION_SCHEMA_VERSION
		and GFVariantData.get_option_string(
			topology_data,
			&"topology_id"
		) == String(get_topology_id(board_id))
	):
		return false
	var active_cells: Array = GFVariantData.as_array(
		GFVariantData.get_option_value(topology_data, &"active_cells")
	)
	if active_cells.is_empty() or active_cells.size() > MAX_PERSISTED_CELL_COUNT:
		return false
	for cell_value: Variant in active_cells:
		if not cell_value is Vector2i:
			return false
	return true


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
