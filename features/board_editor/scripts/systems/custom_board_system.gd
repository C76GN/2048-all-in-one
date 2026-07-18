## CustomBoardSystem: 管理玩家自定义棋盘模板及其统一 SaveGraph 事务。
class_name CustomBoardSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 私有变量 ---

var _save_graph: GameSaveGraphUtility
var _clock: GameClockUtility


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameClockUtility, GameSaveGraphUtility]


func ready() -> void:
	_save_graph = _resolve_save_graph_utility()
	_clock = _resolve_clock_utility()


func dispose() -> void:
	_save_graph = null
	_clock = null


# --- 公共方法 ---

## 新建或更新玩家棋盘。空 ID 表示新建；非空 ID 必须已存在。
## @param custom_board: 待保存并回填稳定身份的数据对象。
func save_custom_board(custom_board: CustomBoardData) -> Error:
	if custom_board == null or not is_instance_valid(custom_board.topology):
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var clock: GameClockUtility = _get_clock()
	if save_graph == null or clock == null:
		return ERR_UNCONFIGURED

	var display_name: String = CustomBoardData.normalize_display_name(custom_board.display_name)
	if display_name.is_empty():
		return ERR_INVALID_DATA
	if not custom_board.topology.get_validation_report().is_ok():
		return ERR_INVALID_DATA

	var boards: Array[CustomBoardData] = load_custom_boards()
	var now: int = maxi(clock.get_unix_timestamp(), 1)
	var board_id: String = custom_board.custom_board_id
	var created_at: int = now
	var replacing_index: int = -1
	if board_id.is_empty():
		board_id = _generate_unique_id(boards, now)
		if board_id.is_empty():
			return FAILED
	else:
		if not GFUuid.is_valid(board_id, 7):
			return ERR_INVALID_DATA
		replacing_index = _find_board_index(boards, board_id)
		if replacing_index < 0:
			return ERR_DOES_NOT_EXIST
		created_at = boards[replacing_index].created_at

	var topology: BoardTopology = BoardTopology.from_dict(custom_board.topology.to_dict())
	if topology == null:
		return ERR_INVALID_DATA
	topology.topology_id = CustomBoardData.get_topology_id(board_id)

	var candidate: CustomBoardData = CustomBoardData.new()
	candidate.custom_board_id = board_id
	candidate.display_name = display_name
	candidate.created_at = created_at
	candidate.updated_at = maxi(now, created_at)
	candidate.topology = topology
	var strict_candidate: CustomBoardData = CustomBoardData.from_dict(candidate.to_dict())
	if strict_candidate == null:
		return ERR_INVALID_DATA

	if replacing_index >= 0:
		boards[replacing_index] = strict_candidate
	else:
		boards.append(strict_candidate)
	boards.sort_custom(_is_newer_board)
	var save_error: Error = save_graph.replace_section_data(
		GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID,
		_serialize_custom_boards(boards)
	)
	if save_error != OK:
		return save_error

	custom_board.custom_board_id = strict_candidate.custom_board_id
	custom_board.display_name = strict_candidate.display_name
	custom_board.created_at = strict_candidate.created_at
	custom_board.updated_at = strict_candidate.updated_at
	custom_board.topology = BoardTopology.from_dict(strict_candidate.topology.to_dict())
	return OK


func load_custom_boards() -> Array[CustomBoardData]:
	var boards: Array[CustomBoardData] = []
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return boards

	var section_data: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID
	)
	for item_value: Variant in GFVariantData.get_option_array(section_data, "items"):
		if not item_value is Dictionary:
			continue
		var custom_board: CustomBoardData = CustomBoardData.from_dict(
			GFVariantData.as_dictionary(item_value)
		)
		if custom_board != null:
			boards.append(custom_board)
	boards.sort_custom(_is_newer_board)
	return boards


## @param custom_board_id: 玩家棋盘 UUID v7。
func get_custom_board(custom_board_id: String) -> CustomBoardData:
	if not GFUuid.is_valid(custom_board_id, 7):
		return null
	for custom_board: CustomBoardData in load_custom_boards():
		if custom_board.custom_board_id == custom_board_id:
			return custom_board
	return null


## @param custom_board_id: 待删除的玩家棋盘 UUID v7。
func delete_custom_board(custom_board_id: String) -> Error:
	if not GFUuid.is_valid(custom_board_id, 7):
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED

	var boards: Array[CustomBoardData] = load_custom_boards()
	var board_index: int = _find_board_index(boards, custom_board_id)
	if board_index < 0:
		return ERR_DOES_NOT_EXIST
	boards.remove_at(board_index)
	return save_graph.replace_section_data(
		GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID,
		_serialize_custom_boards(boards)
	)


# --- 私有/辅助方法 ---

func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _resolve_save_graph_utility()
	return _save_graph


func _get_clock() -> GameClockUtility:
	if is_instance_valid(_clock):
		return _clock
	_clock = _resolve_clock_utility()
	return _clock


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = utility_value
		return utility
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var utility: GameClockUtility = utility_value
		return utility
	return null


static func _serialize_custom_boards(boards: Array[CustomBoardData]) -> Dictionary:
	var items: Array[Dictionary] = []
	for custom_board: CustomBoardData in boards:
		if custom_board != null:
			items.append(custom_board.to_dict())
	return {
		"items": items,
	}


static func _find_board_index(boards: Array[CustomBoardData], custom_board_id: String) -> int:
	for index: int in range(boards.size()):
		if boards[index].custom_board_id == custom_board_id:
			return index
	return -1


static func _generate_unique_id(boards: Array[CustomBoardData], timestamp: int) -> String:
	var known_ids: Dictionary = {}
	for custom_board: CustomBoardData in boards:
		known_ids[custom_board.custom_board_id] = true
	for offset: int in range(4):
		var candidate: String = GFUuid.generate_v7((timestamp * 1000) + offset)
		if GFUuid.is_valid(candidate, 7) and not known_ids.has(candidate):
			return candidate
	return ""


static func _is_newer_board(left: CustomBoardData, right: CustomBoardData) -> bool:
	if left.updated_at != right.updated_at:
		return left.updated_at > right.updated_at
	return left.custom_board_id > right.custom_board_id
