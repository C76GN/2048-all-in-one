# scripts/menus/bookmark_list.gd

## BookmarkList: 显示所有已保存书签的菜单界面。
##
## 负责从 BookmarkManager 加载书签数据，动态创建 BookmarkListItem
## 实例，并处理选择书签（加载游戏）、删除书签以及返回主菜单的逻辑。
class_name BookmarkList
extends Control

# --- 常量 ---

## 单个书签列表项的场景资源。
const BOOKMARK_LIST_ITEM_SCENE: PackedScene = preload("res://scenes/ui/bookmark_list_item.tscn")

## 加载书签后要进入的游戏场景。
const GAME_PLAY_SCENE: PackedScene = preload("res://scenes/game/game_play.tscn")


# --- 私有变量 ---

## 当前选中的书签数据。
var _selected_bookmark: BookmarkData = null


# --- @onready 变量 (节点引用) ---

@onready var _items_container: VBoxContainer = %ReplayItemsContainer
@onready var _board_preview: BoardPreview = find_child("BoardPreview", true, false)
@onready var _detail_info_label: RichTextLabel = find_child("DetailInfoLabel", true, false)
@onready var _load_button: Button = %LoadButton
@onready var _delete_button: Button = %DeleteButton
@onready var _back_button: Button = %BackButton
@onready var _page_title: Label = %PageTitle


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_load_button.pressed.connect(_on_load_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)

	_update_ui_text()
	_update_action_buttons()
	_populate_list()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

## 从 BookmarkManager 加载数据并填充列表。
func _populate_list() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	await get_tree().process_frame

	var bookmarks: Array[BookmarkData] = BookmarkManager.load_bookmarks()

	if bookmarks.is_empty():
		var label := Label.new()
		label.text = tr("MSG_NO_BOOKMARKS")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 50
		_items_container.add_child(label)
		_clear_preview()
		_update_focus_neighbors(null)
		return

	var items: Array[BookmarkListItem] = []
	for bookmark_data in bookmarks:
		var item := BOOKMARK_LIST_ITEM_SCENE.instantiate() as BookmarkListItem
		_items_container.add_child(item)
		item.setup(bookmark_data)
		items.append(item)
		item.bookmark_selected.connect(_on_item_confirmed)
		item.item_focused.connect(_on_item_focused)

	# 设置循环导航
	if items.size() > 1:
		var first_item: Control = items[0]
		var last_item: Control = items[-1]
		first_item.focus_neighbor_top = last_item.get_path()
		last_item.focus_neighbor_bottom = first_item.get_path()

	if not items.is_empty():
		items[0].grab_focus()
		_set_selected_item(items[0].get_data())


## 统一选中逻辑：更新数据、预览、按钮状态、列表项视觉和导航路径。
## @param bookmark_data: 选中的书签数据。
func _set_selected_item(bookmark_data: BookmarkData) -> void:
	_selected_bookmark = bookmark_data
	_update_preview(bookmark_data)
	_update_action_buttons()

	var target_node: Control = null
	for child in _items_container.get_children():
		if child is BookmarkListItem:
			var is_target: bool = (child.get_data() == bookmark_data)
			child.set_selected(is_target)
			if is_target:
				target_node = child

	_update_focus_neighbors(target_node)


## 动态更新右侧按钮的“左邻居”，实现焦点记忆恢复。
## @param target_node: 当前选中的列表项节点，用作导航目标。
func _update_focus_neighbors(target_node: Control) -> void:
	var target_path: NodePath = NodePath("")

	if is_instance_valid(target_node):
		target_path = target_node.get_path()
	elif _items_container.get_child_count() > 0:
		var first = _items_container.get_child(0)
		if first is Control: target_path = first.get_path()

	_load_button.focus_neighbor_left = target_path
	_delete_button.focus_neighbor_left = target_path
	_back_button.focus_neighbor_left = target_path


## 更新左侧预览区域。
## @param bookmark: 要显示预览的书签数据。
func _update_preview(bookmark: BookmarkData) -> void:
	if not is_instance_valid(bookmark):
		_clear_preview()
		return

	var mode_config := load(bookmark.mode_config_path) as GameModeConfig
	if not is_instance_valid(mode_config):
		_detail_info_label.text = tr("ERR_LOAD_CONFIG")
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

	_detail_info_label.text = details

	if is_instance_valid(_board_preview):
		_board_preview.show_snapshot(bookmark.board_snapshot, mode_config)


## 清空预览区域。
func _clear_preview() -> void:
	_detail_info_label.text = tr("MSG_SELECT_SAVE")
	if is_instance_valid(_board_preview):
		_board_preview.clear()
	_selected_bookmark = null
	_update_action_buttons()


## 更新右侧按钮状态。
func _update_action_buttons() -> void:
	var has_selection: bool = _selected_bookmark != null
	_load_button.disabled = not has_selection
	_delete_button.disabled = not has_selection


## 更新所有UI元素的文本，用于初始化和语言切换。
func _update_ui_text() -> void:
	if is_instance_valid(_page_title):
		_page_title.text = tr("TITLE_LOAD_SAVE")
	
	var left_column = get_node_or_null("MarginContainer/ColumnsContainer/LeftColumn")
	if left_column and left_column.get_child_count() > 0:
		var preview_label = left_column.get_child(0) as Label
		if preview_label:
			preview_label.text = tr("TITLE_SAVE_PREVIEW")
	
	if is_instance_valid(_load_button):
		_load_button.text = tr("BTN_LOAD_SAVE")
	if is_instance_valid(_delete_button):
		_delete_button.text = tr("BTN_DELETE_SAVE")
	if is_instance_valid(_back_button):
		_back_button.text = tr("BTN_RETURN_MAIN")
	
	var right_column = get_node_or_null("MarginContainer/ColumnsContainer/RightColumn")
	if right_column and right_column.get_child_count() > 0:
		var operations_label = right_column.get_child(0) as Label
		if operations_label:
			operations_label.text = tr("CONTROLS_TITLE")


# --- 信号处理函数 ---

## 当列表项获得焦点时调用
func _on_item_focused(bookmark_data: BookmarkData) -> void:
	if _selected_bookmark != bookmark_data:
		_set_selected_item(bookmark_data)


## 当列表项被“确认”（点击或回车）时调用。
func _on_item_confirmed(bookmark_data: BookmarkData) -> void:
	_set_selected_item(bookmark_data)


## 响应“读取存档”按钮。
func _on_load_button_pressed() -> void:
	if _selected_bookmark:
		GlobalGameManager.load_game_from_bookmark(_selected_bookmark, GAME_PLAY_SCENE)


## 响应“删除存档”按钮。
func _on_delete_button_pressed() -> void:
	if _selected_bookmark:
		BookmarkManager.delete_bookmark(_selected_bookmark.file_path)
		_selected_bookmark = null
		await _populate_list()


## 响应“返回”按钮。
func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()
