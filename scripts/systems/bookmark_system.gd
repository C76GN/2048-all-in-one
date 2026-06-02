## BookmarkSystem: 负责处理游戏书签（状态存档）持久化的核心系统。
##
## 负责管理并持久化游戏书签记录。
## 管理所有书签文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `bookmarks` 文件夹来存放所有状态记录。
class_name BookmarkSystem
extends GFSystem


# --- 常量 ---

## 书签存储目录。
const BOOKMARK_DIR_NAME: String = "bookmarks"


# --- Godot 生命周期方法 ---

func async_init() -> void:
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		storage.ensure_directory(BOOKMARK_DIR_NAME)


# --- 公共方法 ---

## 将一个BookmarkData资源保存到文件中。
## @param bookmark_data: 要保存的BookmarkData资源。
func save_bookmark(bookmark_data: BookmarkData) -> void:
	var file_path := BOOKMARK_DIR_NAME.path_join(
		"bookmark_%d_%d.tres" % [bookmark_data.timestamp, Time.get_ticks_msec()]
	)
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		storage.save_resource(file_path, bookmark_data)


## 加载所有已保存的书签文件。
## @return: 一个包含所有BookmarkData资源的数组。
func load_bookmarks() -> Array[BookmarkData]:
	var bookmarks: Array[BookmarkData] = []
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if not storage:
		return bookmarks

	for path: String in storage.list_files(BOOKMARK_DIR_NAME, "tres"):
		var resource := storage.load_resource(path, "BookmarkData")
		if resource is BookmarkData:
			var bookmark := resource as BookmarkData
			bookmark.file_path = path
			bookmarks.append(bookmark)

	# 按时间戳降序排序
	bookmarks.sort_custom(func(a: BookmarkData, b: BookmarkData) -> bool:
		return a.timestamp > b.timestamp
	)
	return bookmarks


## 根据其文件路径删除一个书签文件。
## @param bookmark_file_path: 要删除的书签文件的文件路径。
func delete_bookmark(bookmark_file_path: String) -> void:
	if bookmark_file_path.is_empty():
		return

	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		storage.delete_file(bookmark_file_path)
