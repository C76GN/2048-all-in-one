# global/bookmark_manager.gd

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
	if not DirAccess.dir_exists_absolute(BOOKMARK_DIR):
		DirAccess.make_dir_absolute(BOOKMARK_DIR)
		print("已创建书签存储目录: %s" % BOOKMARK_DIR)


# --- 公共方法 ---

## 将一个BookmarkData资源保存到文件中。
## @param bookmark_data: 要保存的BookmarkData资源。
func save_bookmark(bookmark_data: BookmarkData) -> void:
	if not is_instance_valid(bookmark_data):
		push_error("保存书签失败: 无效的BookmarkData对象。")
		return

	var file_path: String = BOOKMARK_DIR.path_join("bookmark_%d.tres" % bookmark_data.timestamp)
	var error: Error = ResourceSaver.save(bookmark_data, file_path)

	if error != OK:
		push_error("保存书签文件失败: %s (错误码: %d)" % [file_path, error])
	else:
		print("书签已成功保存到: %s" % file_path)


## 加载所有已保存的书签文件。
## @return: 一个包含所有BookmarkData资源的数组。
func load_bookmarks() -> Array[BookmarkData]:
	var bookmarks: Array[BookmarkData] = []
	var dir: DirAccess = DirAccess.open(BOOKMARK_DIR)

	if not dir:
		push_error("无法打开书签目录: %s" % BOOKMARK_DIR)
		return bookmarks

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var file_path: String = BOOKMARK_DIR.path_join(file_name)
			var loaded_resource: Resource = ResourceLoader.load(file_path, "BookmarkData", ResourceLoader.CACHE_MODE_IGNORE)

			if is_instance_valid(loaded_resource) and loaded_resource is BookmarkData:
				var unique_bookmark_instance: BookmarkData = loaded_resource.duplicate()
				unique_bookmark_instance.file_path = file_path
				bookmarks.append(unique_bookmark_instance)
			else:
				push_error("加载书签资源失败或类型不匹配: %s" % file_path)

		file_name = dir.get_next()

	dir.list_dir_end()
	bookmarks.sort_custom(func(a: BookmarkData, b: BookmarkData): return a.timestamp > b.timestamp)
	return bookmarks


## 根据其文件路径删除一个书签文件。
## @param bookmark_file_path: 要删除的书签文件的文件路径。
func delete_bookmark(bookmark_file_path: String) -> void:
	if not FileAccess.file_exists(bookmark_file_path):
		push_error("删除书签失败: 文件不存在 - %s" % bookmark_file_path)
		return

	var error: Error = DirAccess.remove_absolute(bookmark_file_path)

	if error != OK:
		push_error("删除书签文件时出错: %s (错误码: %d)" % [bookmark_file_path, error])
	else:
		print("已删除书签文件: %s" % bookmark_file_path)
