## BookmarkList: 显示所有已保存书签的菜单界面。
##
## 继承自 BaseListMenu，专门负责书签的管理与展示。
class_name BookmarkList
extends BaseListMenu


# --- 常量 ---



# --- 导出变量 ---

## 书签列表项场景资源。
@export var item_scene: PackedScene


# --- 节点引用 ---

@onready var _capacity_label: Label = %CapacityLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	assert(item_scene != null, "BookmarkList: 列表项场景 (item_scene) 未在编辑器中设置。")

	_item_scene = item_scene
	_primary_button = %LoadButton
	_delete_button = %DeleteButton

	super._ready()
	_setup_base_signals()
	_update_ui_text()
	_update_action_buttons()
	await _populate_list()


# --- 虚方法覆写 ---

func _get_data_list() -> Array:
	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	var bookmarks: Array[BookmarkData] = []
	if is_instance_valid(bookmark_system):
		bookmarks = bookmark_system.load_bookmarks()
	_update_capacity_text(bookmarks.size())
	var result: Array = []
	for bookmark_data: BookmarkData in bookmarks:
		result.append(bookmark_data)
	return result


func _get_data_identity(data: Resource) -> String:
	if data is BookmarkData:
		var bookmark: BookmarkData = data
		return bookmark.bookmark_id
	return ""


func _setup_item(item: Control, data: Resource) -> void:
	if not item is BookmarkListItem or not data is BookmarkData:
		return

	var bookmark_item: BookmarkListItem = item
	var bookmark_data: BookmarkData = data
	bookmark_item.setup(
		bookmark_data,
		_get_mode_display_name(bookmark_data.mode_config_path),
		_get_mode_config(bookmark_data.mode_config_path),
		_get_theme_utility()
	)


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
	var topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(bookmark.board_snapshot, &"topology")
	)
	var board_label: String = topology.get_size_label() if topology != null else tr("UI_NONE")

	var details: String = ""
	details += "[b]%s[/b] %s   [b]%s[/b] %s\n" % [
		tr("LABEL_MODE"),
		tr(mode_config.mode_name),
		tr("LABEL_BOARD"),
		board_label,
	]
	details += "[b]%s[/b] %s\n" % [tr("LABEL_TIME"), datetime]
	details += "[b]%s[/b] %d   [b]%s[/b] %d\n" % [
		tr("LABEL_SCORE"),
		bookmark.score,
		tr("LABEL_MOVES"),
		bookmark.move_count,
	]
	details += "[b]%s[/b] %d   [b]%s[/b] %d" % [
		tr("LABEL_RATIO_RESOLUTIONS"),
		bookmark.ratio_resolutions,
		tr("LABEL_SEED"),
		bookmark.initial_seed,
	]

	detail_info_label.text = details

	if is_instance_valid(board_preview_node):
		board_preview_node.show_snapshot(bookmark.board_snapshot, mode_config)


func _update_ui_text() -> void:
	if is_instance_valid(page_title):
		page_title.text = _translate_with_fallback(
			"TITLE_BOOKMARK_DRAWER",
			"样张抽屉"
		)
	var drawer_guide_node: Node = get_node_or_null("%DrawerGuideLabel")
	if drawer_guide_node is Label:
		var drawer_guide: Label = drawer_guide_node
		drawer_guide.text = _translate_with_fallback(
			"BOOKMARK_DRAWER_GUIDE",
			"冻结样张 · 棋盘状态是主要辨识对象"
		)

	var left_column: Node = get_node_or_null("%LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label: Label = _get_first_label_child(left_column)
		if is_instance_valid(preview_label):
			preview_label.text = _translate_with_fallback(
				"TITLE_BOOKMARK_PROOF",
				"冻结样张"
			)

	if is_instance_valid(_primary_button):
		_primary_button.text = tr("BTN_LOAD_SAVE")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_SAVE")
	if is_instance_valid(back_button):
		back_button.text = tr("BTN_RETURN_MAIN")

func _do_delete_logic(data: Resource) -> GameSaveSectionOperation:
	if not data is BookmarkData:
		return null

	var bookmark: BookmarkData = data
	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	if not is_instance_valid(bookmark_system):
		return null
	return bookmark_system.request_delete_bookmark(bookmark.bookmark_id)


func _on_primary_action_triggered(data: Resource) -> void:
	if not data is BookmarkData:
		return

	var bookmark: BookmarkData = data
	var launch_port: GameSessionLaunchPort = _get_session_launch_port()
	if not is_instance_valid(launch_port):
		push_error("[BookmarkList] 缺少 GameSessionLaunchPort，无法启动书签。")
		return
	var _launched: bool = launch_port.launch_bookmark(bookmark.bookmark_id)


func _get_bookmark_system() -> BookmarkSystem:
	var system_value: Object = get_system(BookmarkSystem)
	if system_value is BookmarkSystem:
		var bookmark_system: BookmarkSystem = system_value
		return bookmark_system
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = get_utility(GameThemeUtility)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _update_capacity_text(count: int) -> void:
	if not is_instance_valid(_capacity_label):
		return
	_capacity_label.text = tr("BOOKMARK_CAPACITY_STATUS") % [
		mini(count, BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT),
		BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT,
	]
	_capacity_label.tooltip_text = (
		tr("BOOKMARK_CAPACITY_FULL_HINT")
		if count >= BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT
		else ""
	)


func _apply_list_focus_order(items: Array[Control]) -> void:
	if items.is_empty():
		return
	var compact: bool = (
		_layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	)
	var grid_columns: int = 1 if compact else 2
	for item_index: int in range(items.size()):
		var item: Control = items[item_index]
		var column_index: int = item_index % grid_columns
		var top_index: int = item_index - grid_columns
		if top_index < 0:
			top_index = column_index
			while top_index + grid_columns < items.size():
				top_index += grid_columns
		var bottom_index: int = item_index + grid_columns
		if bottom_index >= items.size():
			bottom_index = column_index
		item.focus_neighbor_left = item.get_path_to(
			items[item_index - 1]
			if column_index > 0
			else (_primary_button if is_instance_valid(_primary_button) else item)
		)
		item.focus_neighbor_right = item.get_path_to(
			items[item_index + 1]
			if column_index < grid_columns - 1 and item_index + 1 < items.size()
			else (_primary_button if is_instance_valid(_primary_button) else item)
		)
		item.focus_neighbor_top = item.get_path_to(items[top_index])
		item.focus_neighbor_bottom = item.get_path_to(items[bottom_index])
	var focus_order: Array[Control] = items.duplicate()
	if compact:
		for action_control: Control in [_primary_button, _delete_button, back_button]:
			if is_instance_valid(action_control):
				focus_order.append(action_control)
	var focus_report: Dictionary = GFControlFocusUtility.apply_focus_order(
		focus_order,
		{
			"axis": GFControlFocusUtility.AXIS_NONE,
			"wrap": true,
			"wire_tab_order": true,
			"preserve_unwired_directional_neighbors": true,
		}
	)
	if not GFVariantData.get_option_bool(focus_report, "ok", false):
		push_error("[BookmarkList] GF 样张抽屉焦点顺序应用失败。")


func _apply_responsive_layout() -> void:
	super._apply_responsive_layout()
	if items_container is GridContainer:
		var grid: GridContainer = items_container
		grid.columns = (
			1
			if _layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
			else 2
		)
	_apply_list_focus_order(_get_list_item_controls())


func _get_mode_display_name(mode_config_path: String) -> String:
	if mode_config_path.is_empty():
		return tr("UNKNOWN_MODE")

	var mode_config: GameModeConfig = _get_mode_config(mode_config_path)
	if is_instance_valid(mode_config):
		return tr(mode_config.mode_name)

	return tr("CONFIG_MISSING")


func _translate_with_fallback(key: String, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == key or translated.is_empty() else translated


func _get_session_launch_port() -> GameSessionLaunchPort:
	var system_value: Object = get_system(GameSessionLaunchPort)
	if system_value is GameSessionLaunchPort:
		var launch_port: GameSessionLaunchPort = system_value
		return launch_port
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
	return "%s\n%s" % [
		tr("MSG_NO_SAVES"),
		tr("MSG_EMPTY_SAVE_GUIDANCE"),
	]


func _get_select_hint_message() -> String:
	return tr("MSG_SELECT_SAVE")


func _get_empty_detail_message() -> String:
	return tr("MSG_EMPTY_SAVE_GUIDANCE")


func _on_empty_state_changed(is_empty: bool) -> void:
	var preview_heading: Label = _get_first_label_child(_left_column)
	if is_instance_valid(preview_heading):
		preview_heading.visible = not is_empty
	if is_instance_valid(_preview_container):
		_preview_container.visible = not is_empty
	var preview_separator_node: Node = _left_column.get_node_or_null("HSeparator")
	if preview_separator_node is HSeparator:
		var preview_separator: HSeparator = preview_separator_node
		preview_separator.visible = not is_empty
	if is_instance_valid(detail_info_label):
		detail_info_label.visible = not is_empty
		detail_info_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if is_instance_valid(_primary_button):
		_primary_button.visible = not is_empty
	if is_instance_valid(_delete_button):
		_delete_button.visible = not is_empty


func _get_delete_confirmation_message(_data: Resource) -> String:
	return tr("DELETE_SAVE_CONFIRMATION")


func _get_delete_failure_message(error: Error) -> String:
	return tr("DELETE_SAVE_FAILED") % int(error)
