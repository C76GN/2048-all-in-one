# scripts/ui/replay_list.gd

## ReplayList: 显示所有已保存回放的菜单界面。
##
## 负责从 ReplayManager 加载回放数据，动态创建 ReplayListItem
## 实例，并处理选择回放、删除回放以及返回主菜单的逻辑。
extends Control

const ReplayListItemScene = preload("res://scenes/ui/replay_list_item.tscn")

@onready var replay_items_container: VBoxContainer = %ReplayItemsContainer
@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(GlobalGameManager.return_to_main_menu)
	_populate_replay_list()

## 从 ReplayManager 加载数据并填充列表。
func _populate_replay_list() -> void:
	# 在重新填充前，先清空所有已存在的列表项。
	for child in replay_items_container.get_children():
		child.queue_free()

	var replays = ReplayManager.load_replays()

	print("ReplayList: 加载到 %d 个回放记录。" % replays.size())

	if replays.is_empty():
		var label = Label.new()
		label.text = "没有找到任何回放记录。"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 设置一个最小高度，确保在没有回放时，提示信息有足够的显示空间。
		label.custom_minimum_size.y = 50
		replay_items_container.add_child(label)
		return

	for replay_data in replays:
		print("ReplayList: 正在创建回放项: ", replay_data.timestamp)

		var item: ReplayListItem = ReplayListItemScene.instantiate()

		# 必须先将节点添加到场景树中，这样它的内部节点引用(_onready)才能被正确初始化，
		# 之后才能安全地调用 setup() 函数来配置其内容。
		replay_items_container.add_child(item)
		item.setup(replay_data)

		item.replay_selected.connect(_on_replay_selected)
		item.replay_deleted.connect(_on_replay_deleted)

## 当一个回放被选中时调用。
func _on_replay_selected(replay_data: ReplayData) -> void:
	print("选择了回放: ", replay_data.file_path)
	# 将选择的回放数据传递给全局管理器，然后切换到统一的游戏场景。
	GlobalGameManager.current_replay_data = replay_data
	GlobalGameManager.goto_scene("res://scenes/modes/game_play.tscn")

## 当一个回放被请求删除时调用。
func _on_replay_deleted(replay_data: ReplayData) -> void:
	# 使用 ReplayData 实例中存储的 file_path 属性。
	ReplayManager.delete_replay(replay_data.file_path)
	# 等待一帧，让 Godot 有时间处理 queue_free() 并清理旧的资源引用。
	await get_tree().process_frame
	# 在下一帧，安全地重新加载并刷新整个列表。
	_populate_replay_list()
