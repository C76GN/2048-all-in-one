## BookmarkSystem: 负责处理游戏书签（状态存档）持久化的核心系统。
##
## 负责管理并持久化游戏书签记录。
## 书签作为独立 Feature section 参与统一玩家数据 SaveGraph 事务。
class_name BookmarkSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 私有变量 ---

var _save_graph: GameSaveGraphUtility = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameSaveGraphUtility]


func ready() -> void:
	_save_graph = _resolve_save_graph_utility()


func dispose() -> void:
	_save_graph = null


# --- 公共方法 ---

## 将一个 BookmarkData 原子写入统一玩家数据图。
## @param bookmark_data: 要保存的BookmarkData资源。
func save_bookmark(bookmark_data: BookmarkData) -> Error:
	if bookmark_data == null:
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED

	if bookmark_data.bookmark_id.is_empty():
		var timestamp_msec: int = bookmark_data.timestamp * 1000 if bookmark_data.timestamp > 0 else -1
		bookmark_data.bookmark_id = GFUuid.generate_v7(timestamp_msec)
	if not GFUuid.is_valid(bookmark_data.bookmark_id, 7):
		return ERR_INVALID_DATA

	var candidate: BookmarkData = BookmarkData.from_dict(bookmark_data.to_dict())
	if candidate == null:
		return ERR_INVALID_DATA
	var bookmarks: Array[BookmarkData] = load_bookmarks()
	for existing: BookmarkData in bookmarks:
		if existing.bookmark_id == candidate.bookmark_id:
			return ERR_ALREADY_EXISTS
	bookmarks.append(candidate)
	bookmarks.sort_custom(func(left: BookmarkData, right: BookmarkData) -> bool:
		return left.bookmark_id > right.bookmark_id
	)
	return save_graph.replace_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		_serialize_bookmarks(bookmarks)
	)


## 从统一玩家数据图读取全部书签。
## @return: 一个包含所有BookmarkData资源的数组。
func load_bookmarks() -> Array[BookmarkData]:
	var bookmarks: Array[BookmarkData] = []
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return bookmarks

	var section_data: Dictionary = save_graph.get_section_data(GameSaveGraphUtility.BOOKMARKS_SECTION_ID)
	for item_value: Variant in GFVariantData.get_option_array(section_data, "items"):
		if not (item_value is Dictionary):
			continue
		var bookmark: BookmarkData = BookmarkData.from_dict(GFVariantData.as_dictionary(item_value))
		if bookmark != null:
			bookmarks.append(bookmark)
	bookmarks.sort_custom(func(left: BookmarkData, right: BookmarkData) -> bool:
		return left.bookmark_id > right.bookmark_id
	)
	return bookmarks


## 根据稳定 ID 删除一个书签。
## @param bookmark_id: 要删除的 UUID v7 书签标识。
func delete_bookmark(bookmark_id: String) -> Error:
	if not GFUuid.is_valid(bookmark_id, 7):
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED

	var bookmarks: Array[BookmarkData] = load_bookmarks()
	var found: bool = false
	var retained: Array[BookmarkData] = []
	for bookmark: BookmarkData in bookmarks:
		if bookmark.bookmark_id == bookmark_id:
			found = true
			continue
		retained.append(bookmark)
	if not found:
		return ERR_DOES_NOT_EXIST
	return save_graph.replace_section_data(
		GameSaveGraphUtility.BOOKMARKS_SECTION_ID,
		_serialize_bookmarks(retained)
	)


# --- 私有/辅助方法 ---

func _serialize_bookmarks(bookmarks: Array[BookmarkData]) -> Dictionary:
	var items: Array[Dictionary] = []
	for bookmark: BookmarkData in bookmarks:
		if bookmark != null:
			items.append(bookmark.to_dict())
	return {
		"items": items,
	}


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _resolve_save_graph_utility()
	return _save_graph


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = utility_value
		return utility
	return null
