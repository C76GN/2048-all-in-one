# scripts/global/bookmark_manager.gd

## BookmarkManager: 负责处理游戏书签（状态存档）持久化的全局单例。
##
## 管理所有书签文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `bookmarks` 文件夹来存放所有状态记录。
extends Node


# --- 常量 ---

## 书签存储目录。
const BOOKMARK_DIR: String = "user://bookmarks/"


# --- Godot 生命周期方法 ---

func _ready() -> void:
	ResourceIOManager.ensure_dir(BOOKMARK_DIR)


# --- 公共方法 ---

## 将一个BookmarkData资源保存到文件中。
## @param bookmark_data: 要保存的BookmarkData资源。
func save_bookmark(bookmark_data: BookmarkData) -> void:
	var file_path := BOOKMARK_DIR.path_join("bookmark_%d.tres" % bookmark_data.timestamp)
	ResourceIOManager.save_resource(bookmark_data, file_path, &"书签")


## 加载所有已保存的书签文件。
## @return: 一个包含所有BookmarkData资源的数组。
func load_bookmarks() -> Array[BookmarkData]:
	var loaded_list := ResourceIOManager.load_resources(BOOKMARK_DIR, &"BookmarkData")
	var bookmarks: Array[BookmarkData] = []
	
	for res in loaded_list:
		if res is BookmarkData:
			bookmarks.append(res as BookmarkData)
	
	# 按时间戳降序排序
	bookmarks.sort_custom(func(a: BookmarkData, b: BookmarkData) -> bool:
		return a.timestamp > b.timestamp
	)
	return bookmarks


## 根据其文件路径删除一个书签文件。
## @param bookmark_file_path: 要删除的书签文件的文件路径。
func delete_bookmark(bookmark_file_path: String) -> void:
	ResourceIOManager.delete_file(bookmark_file_path, &"书签")
