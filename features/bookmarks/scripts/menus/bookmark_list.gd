## BookmarkList: 显示所有已保存书签的菜单界面。
##
## 继承自 BaseListMenu，专门负责书签的管理与展示。
class_name BookmarkList
extends BaseListMenu


# --- 常量 ---



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
	await _populate_list()

	super._ready()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	var bookmarks: Array[BookmarkData] = []
	if is_instance_valid(bookmark_system):
		bookmarks = bookmark_system.load_bookmarks()
	var result: Array = []
	for bookmark_data: BookmarkData in bookmarks:
		result.append(bookmark_data)
	return result


func _setup_item(item: Control, data: Resource) -> void:
	if not item is BookmarkListItem or not data is BookmarkData:
		return

	var bookmark_item: BookmarkListItem = item
	var bookmark_data: BookmarkData = data
	bookmark_item.setup(bookmark_data, _get_mode_display_name(bookmark_data.mode_config_path))


func _update_preview(data: Resource) -> void:
	if not data is BookmarkData:
		_clear_preview()
		return

	var bookmark: BookmarkData = data
	var mode_config: GameModeConfig = _get_mode_config(bookmark.mode_config_path)
	if not is_instance_valid(mode_config):
		detail_info_label.text = tr("ERR_LOAD_CONFIG")
		if is_instance_valid(board_preview_node):
			board_preview_node.show_message(tr("ERR_LOAD_CONFIG"))
		return

	var datetime: String = _format_datetime(bookmark.timestamp)
	var grid_size: int = GFVariantData.to_int(
		bookmark.board_snapshot.get(&"grid_size", bookmark.board_snapshot.get("grid_size", 0)),
		0
	)

	var details: String = ""
	details += "[b]%s[/b] %s\n" % [tr("LABEL_MODE"), tr(mode_config.mode_name)]
	details += "[b]%s[/b] %s\n" % [tr("LABEL_TIME"), datetime]
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

	var left_column: Node = get_node_or_null("MarginContainer/ColumnsContainer/LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label: Label = _get_first_label_child(left_column)
		if is_instance_valid(preview_label):
			preview_label.text = tr("TITLE_SAVE_PREVIEW")

	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_LOAD_SAVE")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_SAVE")
	if is_instance_valid(back_button):
		back_button.text = tr("BTN_RETURN_MAIN")

	var right_column: Node = get_node_or_null("MarginContainer/ColumnsContainer/RightColumn")
	if right_column and right_column.get_child_count() > 0:
		var operations_label: Label = _get_first_label_child(right_column)
		if is_instance_valid(operations_label):
			operations_label.text = tr("CONTROLS_TITLE")


func _do_delete_logic(data: Resource) -> void:
	if not data is BookmarkData:
		return

	var bookmark: BookmarkData = data
	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	if is_instance_valid(bookmark_system):
		var delete_error: Error = bookmark_system.delete_bookmark(bookmark.bookmark_id)
		if delete_error != OK:
			push_error("[BookmarkList] 删除书签失败，错误码：%d。" % delete_error)


func _on_primary_action_triggered(data: Resource) -> void:
	if not data is BookmarkData:
		return

	var bookmark: BookmarkData = data
	var app_config: AppConfigModel = _get_app_config_model()
	if is_instance_valid(app_config):
		app_config.current_replay_data.set_value(null)
		app_config.selected_bookmark_data.set_value(bookmark)
		app_config.selected_mode_config_path.set_value("")
		app_config.selected_grid_size.set_value(0)

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.goto_scene(game_scene_path)


func _get_bookmark_system() -> BookmarkSystem:
	var system_value: Object = get_system(BookmarkSystem)
	if system_value is BookmarkSystem:
		var bookmark_system: BookmarkSystem = system_value
		return bookmark_system
	return null


func _get_mode_display_name(mode_config_path: String) -> String:
	if mode_config_path.is_empty():
		return tr("UNKNOWN_MODE")

	var mode_config: GameModeConfig = _get_mode_config(mode_config_path)
	if is_instance_valid(mode_config):
		return tr(mode_config.mode_name)

	return tr("CONFIG_MISSING")


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
	return null


func _get_first_label_child(parent: Node) -> Label:
	if not is_instance_valid(parent) or parent.get_child_count() <= 0:
		return null

	var child: Node = parent.get_child(0)
	if child is Label:
		var label: Label = child
		return label
	return null


func _get_empty_message() -> String:
	return tr("MSG_NO_BOOKMARKS")


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_SAVE")
