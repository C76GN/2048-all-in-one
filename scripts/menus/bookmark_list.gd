# scripts/menus/bookmark_list.gd

## BookmarkList: 显示所有已保存书签的菜单界面。
##
## 继承自 BaseListMenu，专门负责书签的管理与展示。
class_name BookmarkList
extends BaseListMenu


# --- 常量 ---

## 加载书签后要进入的游戏场景。
const GAME_PLAY_SCENE: PackedScene = preload("res://scenes/game/game_play.tscn")


# --- Godot 生命周期方法 ---

func _ready() -> void:
	# 初始化工厂资源和节点引用
	_item_scene = preload("res://scenes/ui/bookmark_list_item.tscn")
	_primary_button = %LoadButton
	_delete_button = %DeleteButton
	
	# 连接基类基础信号
	_setup_base_signals()
	
	# 初始化 UI
	_update_ui_text()
	_update_action_buttons()
	_populate_list()
	
	# 确保父类连接了 back_button
	super._ready()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var bookmarks: Array[BookmarkData] = BookmarkManager.load_bookmarks()
	# 显式转换为普通 Array 以适配基类
	var result: Array = []
	for b in bookmarks: result.append(b)
	return result


func _setup_item(item: Control, data: Resource) -> void:
	if item is BookmarkListItem and data is BookmarkData:
		item.setup(data)


func _connect_item_signals(item: Control, _data: Resource) -> void:
	if item.has_signal("bookmark_selected"):
		item.bookmark_selected.connect(_on_item_confirmed)
	if item.has_signal("item_focused"):
		item.item_focused.connect(_on_item_focused)


func _update_preview(data: Resource) -> void:
	var bookmark = data as BookmarkData
	if not is_instance_valid(bookmark):
		_clear_preview()
		return

	var mode_config := load(bookmark.mode_config_path) as GameModeConfig
	if not is_instance_valid(mode_config):
		DetailInfoLabel.text = tr("ERR_LOAD_CONFIG")
		return

	var datetime: String = Time.get_datetime_string_from_unix_time(bookmark.timestamp)
	var grid_size: int = bookmark.board_snapshot.get("grid_size", 0)

	var details: String = ""
	details += "[b]%s[/b] %s\n" % [tr("LABEL_MODE"), tr(mode_config.mode_name)]
	details += "[b]%s[/b] %s\n" % [tr("LABEL_TIME"), datetime.replace("T", " ")]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_SCORE"), bookmark.score]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_MOVES"), bookmark.move_count]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_KILLED"), bookmark.monsters_killed]
	details += "[b]%s[/b] %dx%d\n" % [tr("LABEL_BOARD"), grid_size, grid_size]
	details += "[b]%s[/b] %d" % [tr("LABEL_SEED"), bookmark.initial_seed]

	DetailInfoLabel.text = details

	if is_instance_valid(BoardPreviewNode):
		BoardPreviewNode.show_snapshot(bookmark.board_snapshot, mode_config)


func _update_ui_text() -> void:
	if is_instance_valid(PageTitle):
		PageTitle.text = tr("TITLE_LOAD_SAVE")
	
	var left_column = get_node_or_null("MarginContainer/ColumnsContainer/LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label = left_column.get_child(0) as Label
		if preview_label:
			preview_label.text = tr("TITLE_SAVE_PREVIEW")
	
	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_LOAD_SAVE")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_SAVE")
	if is_instance_valid(BackButton):
		BackButton.text = tr("BTN_RETURN_MAIN")
	
	var right_column = get_node_or_null("MarginContainer/ColumnsContainer/RightColumn")
	if right_column and right_column.get_child_count() > 0:
		var operations_label = right_column.get_child(0) as Label
		if operations_label:
			operations_label.text = tr("CONTROLS_TITLE")


func _do_delete_logic(data: Resource) -> void:
	var bookmark = data as BookmarkData
	BookmarkManager.delete_bookmark(bookmark.file_path)


func _on_primary_action_triggered(data: Resource) -> void:
	var bookmark = data as BookmarkData
	GlobalGameManager.load_game_from_bookmark(bookmark, GAME_PLAY_SCENE)


func _get_empty_message() -> String:
	return tr("MSG_NO_BOOKMARKS")


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_SAVE")
