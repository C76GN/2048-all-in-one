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


# --- @onready 变量 (节点引用) ---

@onready var _items_container: VBoxContainer = %ReplayItemsContainer
@onready var _back_button: Button = %BackButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_back_button.pressed.connect(_on_back_button_pressed)
	_populate_list()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

## 从 BookmarkManager 加载数据并填充列表。
func _populate_list() -> void:
	for child in _items_container.get_children():
		child.queue_free()

	var bookmarks: Array[BookmarkData] = BookmarkManager.load_bookmarks()

	if bookmarks.is_empty():
		var label := Label.new()
		label.text = "没有找到任何书签记录。"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 50
		_items_container.add_child(label)
		return

	for bookmark_data in bookmarks:
		var item := BOOKMARK_LIST_ITEM_SCENE.instantiate() as BookmarkListItem
		_items_container.add_child(item)
		item.setup(bookmark_data)

		item.bookmark_selected.connect(_on_bookmark_selected)
		item.bookmark_deleted.connect(_on_bookmark_deleted)

		if _items_container.get_child_count() > 0:
			var first_item: Control = _items_container.get_child(0)
			if first_item is BookmarkListItem:
				first_item.grab_focus()


# --- 信号处理函数 ---

## 当一个书签列表项被选中时调用。
func _on_bookmark_selected(bookmark_data: BookmarkData) -> void:
	GlobalGameManager.load_game_from_bookmark(bookmark_data, GAME_PLAY_SCENE)


## 当一个书签列表项被请求删除时调用。
func _on_bookmark_deleted(bookmark_data: BookmarkData) -> void:
	BookmarkManager.delete_bookmark(bookmark_data.file_path)
	await get_tree().process_frame
	_populate_list()


## 响应“返回主菜单”按钮的点击事件。
func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()
