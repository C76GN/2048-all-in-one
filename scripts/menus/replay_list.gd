# scripts/menus/replay_list.gd

## ReplayList: 显示所有已保存回放的菜单界面。
##
## 负责从 ReplayManager 加载回放数据，动态创建 ReplayListItem
## 实例，并处理选择回放、删除回放以及返回主菜单的逻辑。
class_name ReplayList
extends Control

# --- 常量 ---

## 单个回放列表项的场景资源。
const REPLAY_LIST_ITEM_SCENE: PackedScene = preload("res://scenes/ui/replay_list_item.tscn")

## 游戏场景路径。
const GAME_SCENE_PATH: String = "res://scenes/game/game_play.tscn"


# --- 私有变量 ---

## 当前选中的回放数据。
var _selected_replay: ReplayData = null


# --- @onready 变量 (节点引用) ---

@onready var _items_container: VBoxContainer = %ReplayItemsContainer
@onready var _board_preview: BoardPreview = find_child("BoardPreview", true, false)
@onready var _detail_info_label: RichTextLabel = find_child("DetailInfoLabel", true, false)
@onready var _play_button: Button = %PlayButton
@onready var _delete_button: Button = %DeleteButton
@onready var _back_button: Button = %BackButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_play_button.pressed.connect(_on_play_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)

	_update_action_buttons()
	_populate_replay_list()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

## 从 ReplayManager 加载数据并填充列表。
func _populate_replay_list() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	await get_tree().process_frame

	var replays: Array[ReplayData] = ReplayManager.load_replays()

	if replays.is_empty():
		var label := Label.new()
		label.text = tr("MSG_NO_REPLAYS")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 50
		_items_container.add_child(label)
		_clear_preview()
		_update_focus_neighbors(null)
		return

	var items: Array[ReplayListItem] = []
	for replay_data in replays:
		var item := REPLAY_LIST_ITEM_SCENE.instantiate() as ReplayListItem
		_items_container.add_child(item)
		item.setup(replay_data)
		items.append(item)

		item.replay_selected.connect(_on_item_confirmed)
		item.item_focused.connect(_on_item_focused)

	if items.size() > 1:
		var first_item: Control = items[0]
		var last_item: Control = items[-1]
		first_item.focus_neighbor_top = last_item.get_path()
		last_item.focus_neighbor_bottom = first_item.get_path()

	if not items.is_empty():
		items[0].grab_focus()
		_set_selected_item(items[0].get_data())


## 统一选中逻辑。
func _set_selected_item(replay_data: ReplayData) -> void:
	_selected_replay = replay_data
	_update_preview(replay_data)
	_update_action_buttons()

	var target_node: Control = null
	for child in _items_container.get_children():
		if child is ReplayListItem:
			var is_target: bool = (child.get_data() == replay_data)
			child.set_selected(is_target)
			if is_target:
				target_node = child

	_update_focus_neighbors(target_node)


## 动态更新右侧按钮的导航目标，以修复焦点路径。
## 确保从右侧按钮向左移动时，能回到当前选中的列表项。
func _update_focus_neighbors(target_node: Control) -> void:
	var target_path: NodePath = NodePath("")

	if is_instance_valid(target_node):
		target_path = target_node.get_path()
	elif _items_container.get_child_count() > 0:
		var first = _items_container.get_child(0)
		if first is Control: target_path = first.get_path()

	_play_button.focus_neighbor_left = target_path
	_delete_button.focus_neighbor_left = target_path
	_back_button.focus_neighbor_left = target_path


## 更新左侧预览区域。
func _update_preview(replay: ReplayData) -> void:
	if not is_instance_valid(replay):
		_clear_preview()
		return

	var mode_config := load(replay.mode_config_path) as GameModeConfig
	if not is_instance_valid(mode_config):
		_detail_info_label.text = tr("ERR_LOAD_CONFIG")
		return

	var datetime: String = Time.get_datetime_string_from_unix_time(replay.timestamp)
	var grid_size: int = replay.grid_size

	var details: String = ""
	details += "[b]模式:[/b] %s\n" % mode_config.mode_name
	details += "[b]时间:[/b] %s\n" % datetime.replace("T", " ")
	details += "[b]最终分数:[/b] %d\n" % replay.final_score
	details += "[b]总步数:[/b] %d\n" % replay.actions.size()
	details += "[b]棋盘:[/b] %dx%d\n" % [grid_size, grid_size]
	details += "[b]种子:[/b] %d" % replay.initial_seed

	_detail_info_label.text = details

	if is_instance_valid(_board_preview):
		if "final_board_snapshot" in replay and not replay.final_board_snapshot.is_empty():
			_board_preview.show_snapshot(replay.final_board_snapshot, mode_config)
		else:
			_board_preview.show_message(tr("MSG_NO_PREVIEW_REPLAY"))


## 清空预览区域。
func _clear_preview() -> void:
	_detail_info_label.text = tr("MSG_SELECT_REPLAY")
	if is_instance_valid(_board_preview):
		_board_preview.show_message(tr("MSG_SELECT_REPLAY").replace("...", ""))
	_selected_replay = null
	_update_action_buttons()


## 更新右侧按钮状态。
func _update_action_buttons() -> void:
	var has_selection: bool = _selected_replay != null
	_play_button.disabled = not has_selection
	_delete_button.disabled = not has_selection


# --- 信号处理函数 ---

func _on_item_focused(replay_data: ReplayData) -> void:
	if _selected_replay != replay_data:
		_set_selected_item(replay_data)


func _on_item_confirmed(replay_data: ReplayData) -> void:
	_set_selected_item(replay_data)


## 响应“播放回放”按钮。
func _on_play_button_pressed() -> void:
	if _selected_replay:
		GlobalGameManager.current_replay_data = _selected_replay
		GlobalGameManager.goto_scene(GAME_SCENE_PATH)


## 响应“删除回放”按钮。
func _on_delete_button_pressed() -> void:
	if _selected_replay:
		ReplayManager.delete_replay(_selected_replay.file_path)
		_selected_replay = null
		await _populate_replay_list()


## 响应“返回”按钮。
func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()
