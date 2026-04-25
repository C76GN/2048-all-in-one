# scripts/menus/bookmark_list.gd

## BookmarkList: 显示所有已保存书签的菜单界面。
##
## 继承自 BaseListMenu，专门负责书签的管理与展示。
class_name BookmarkList
extends BaseListMenu


# --- 常量 ---

const GAME_MODE_CONFIG_CACHE = preload("res://scripts/utilities/game_mode_config_cache.gd")


# --- 导出变量 ---

## 游戏主场景路径。
@export_file("*.tscn") var game_scene_path: String = ""

## 书签列表项场景资源。
@export var item_scene: PackedScene


# --- Godot 生命周期方法 ---

func _ready() -> void:
	assert(not game_scene_path.is_empty(), "BookmarkList: 游戏场景路径 (game_scene_path) 未在编辑器中设置。")
	assert(item_scene != null, "BookmarkList: 列表项场景 (item_scene) 未在编辑器中设置。")

	_item_scene = item_scene
	_primary_button = %LoadButton
	_delete_button = %DeleteButton

	_setup_base_signals()
	_update_ui_text()
	_update_action_buttons()
	_populate_list()

	super._ready()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var bookmark_system := get_system(BookmarkSystem) as BookmarkSystem
	var bookmarks: Array[BookmarkData] = []
	if bookmark_system:
		bookmarks = bookmark_system.load_bookmarks()
	var result: Array = []
	for bookmark_data in bookmarks:
		result.append(bookmark_data)
	return result


func _setup_item(item: Control, data: Resource) -> void:
	if item is BookmarkListItem and data is BookmarkData:
		item.setup(data)


func _connect_item_signals(item: Control, _data: Resource) -> void:
	if item.has_signal("bookmark_selected"):
		if not item.bookmark_selected.is_connected(_on_item_confirmed):
			item.bookmark_selected.connect(_on_item_confirmed)
	if item.has_signal("item_focused"):
		if not item.item_focused.is_connected(_on_item_focused):
			item.item_focused.connect(_on_item_focused)


func _update_preview(data: Resource) -> void:
	var bookmark = data as BookmarkData
	if not is_instance_valid(bookmark):
		_clear_preview()
		return

	var mode_config: GameModeConfig = GAME_MODE_CONFIG_CACHE.get_config(bookmark.mode_config_path)
	if not is_instance_valid(mode_config):
		detail_info_label.text = tr("ERR_LOAD_CONFIG")
		if is_instance_valid(board_preview_node):
			board_preview_node.show_message(tr("ERR_LOAD_CONFIG"))
		return

	var datetime: String = Time.get_datetime_string_from_unix_time(bookmark.timestamp)
	var grid_size: int = bookmark.board_snapshot.get(
		&"grid_size",
		bookmark.board_snapshot.get("grid_size", 0)
	)

	var details: String = ""
	details += "[b]%s[/b] %s\n" % [tr("LABEL_MODE"), tr(mode_config.mode_name)]
	details += "[b]%s[/b] %s\n" % [tr("LABEL_TIME"), datetime.replace("T", " ")]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_SCORE"), bookmark.score]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_MOVES"), bookmark.move_count]
	details += "[b]%s[/b] %d\n" % [tr("LABEL_KILLED"), bookmark.monsters_killed]
	details += "[b]%s[/b] %dx%d\n" % [tr("LABEL_BOARD"), grid_size, grid_size]
	details += "[b]%s[/b] %d" % [tr("LABEL_SEED"), bookmark.initial_seed]

	detail_info_label.text = details

	if is_instance_valid(board_preview_node):
		board_preview_node.show_snapshot(bookmark.board_snapshot, mode_config)


func _update_ui_text() -> void:
	if is_instance_valid(page_title):
		page_title.text = tr("TITLE_LOAD_SAVE")

	var left_column := get_node_or_null("MarginContainer/ColumnsContainer/LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label := left_column.get_child(0) as Label
		if preview_label:
			preview_label.text = tr("TITLE_SAVE_PREVIEW")

	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_LOAD_SAVE")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_SAVE")
	if is_instance_valid(back_button):
		back_button.text = tr("BTN_RETURN_MAIN")

	var right_column := get_node_or_null("MarginContainer/ColumnsContainer/RightColumn")
	if right_column and right_column.get_child_count() > 0:
		var operations_label := right_column.get_child(0) as Label
		if operations_label:
			operations_label.text = tr("CONTROLS_TITLE")


func _do_delete_logic(data: Resource) -> void:
	var bookmark = data as BookmarkData
	var bookmark_system := get_system(BookmarkSystem) as BookmarkSystem
	if bookmark_system:
		bookmark_system.delete_bookmark(bookmark.file_path)


func _on_primary_action_triggered(data: Resource) -> void:
	var bookmark = data as BookmarkData
	var app_config := get_model(AppConfigModel) as AppConfigModel
	if app_config:
		app_config.selected_bookmark_data.set_value(bookmark)
		app_config.selected_mode_config_path.set_value("")
		app_config.selected_grid_size.set_value(0)

	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.goto_scene(game_scene_path)


func _get_empty_message() -> String:
	return tr("MSG_NO_BOOKMARKS")


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_SAVE")
