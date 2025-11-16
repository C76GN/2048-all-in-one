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


# --- @onready 变量 (节点引用) ---

@onready var _replay_items_container: VBoxContainer = %ReplayItemsContainer
@onready var _back_button: Button = %BackButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_back_button.pressed.connect(_on_back_button_pressed)
	_populate_replay_list()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

## 从 ReplayManager 加载数据并填充列表。
func _populate_replay_list() -> void:
	for child in _replay_items_container.get_children():
		child.queue_free()

	var replays: Array[ReplayData] = ReplayManager.load_replays()

	if replays.is_empty():
		var label := Label.new()
		label.text = "没有找到任何回放记录。"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 50
		_replay_items_container.add_child(label)
		return

	for replay_data in replays:
		var item := REPLAY_LIST_ITEM_SCENE.instantiate() as ReplayListItem
		_replay_items_container.add_child(item)
		item.setup(replay_data)

		item.replay_selected.connect(_on_replay_selected)
		item.replay_deleted.connect(_on_replay_deleted)

		if _replay_items_container.get_child_count() > 0:
			var first_item: Control = _replay_items_container.get_child(0)
			if first_item is ReplayListItem:
				first_item.grab_focus()


# --- 信号处理函数 ---

## 当一个回放列表项被选中时调用。
func _on_replay_selected(replay_data: ReplayData) -> void:
	GlobalGameManager.current_replay_data = replay_data
	GlobalGameManager.goto_scene("res://scenes/game/game_play.tscn")


## 当一个回放列表项被请求删除时调用。
func _on_replay_deleted(replay_data: ReplayData) -> void:
	ReplayManager.delete_replay(replay_data.file_path)
	await get_tree().process_frame
	_populate_replay_list()


## 响应“返回主菜单”按钮的点击事件。
func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()
