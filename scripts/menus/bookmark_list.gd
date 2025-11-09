# scripts/bookmark_list.gd

## BookmarkList: 显示所有已保存书签的菜单界面。
##
## 负责从 BookmarkManager 加载书签数据，动态创建 BookmarkListItem
## 实例，并处理选择书签（加载游戏）、删除书签以及返回主菜单的逻辑。
extends Control

const BookmarkListItemScene = preload("res://scenes/ui/bookmark_list_item.tscn")
# 注意：加载书签后，仍然是进入游戏主场景
const GamePlayScene = preload("res://scenes/game/game_play.tscn")

@onready var items_container: VBoxContainer = %ReplayItemsContainer
@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(GlobalGameManager.return_to_main_menu)
	_populate_bookmark_list()

## 从 BookmarkManager 加载数据并填充列表。
func _populate_bookmark_list() -> void:
	for child in items_container.get_children():
		child.queue_free()

	var bookmarks = BookmarkManager.load_bookmarks()

	if bookmarks.is_empty():
		var label = Label.new()
		label.text = "没有找到任何书签记录。"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 50
		items_container.add_child(label)
		return

	for bookmark_data in bookmarks:
		var item: BookmarkListItem = BookmarkListItemScene.instantiate()
		items_container.add_child(item)
		item.setup(bookmark_data)

		item.bookmark_selected.connect(_on_bookmark_selected)
		item.bookmark_deleted.connect(_on_bookmark_deleted)

## 当一个书签被选中时调用。
func _on_bookmark_selected(bookmark_data: BookmarkData) -> void:
	GlobalGameManager.load_game_from_bookmark(bookmark_data, GamePlayScene)

## 当一个书签被请求删除时调用。
func _on_bookmark_deleted(bookmark_data: BookmarkData) -> void:
	BookmarkManager.delete_bookmark(bookmark_data.file_path)
	await get_tree().process_frame
	_populate_bookmark_list()
