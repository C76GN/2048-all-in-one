# scripts/systems/bookmark_system.gd

## BookmarkSystem: 负责处理游戏书签（状态存档）持久化的核心系统。
##
## 负责管理并持久化游戏书签记录。
## 管理所有书签文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `bookmarks` 文件夹来存放所有状态记录。
class_name BookmarkSystem
extends GFSystem

# --- 常量 ---

## 书签存储目录。
const BOOKMARK_DIR: String = "user://bookmarks/"


# --- Godot 生命周期方法 ---

func init() -> void:
	pass

func async_init() -> void:
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		DirAccess.make_dir_recursive_absolute(BOOKMARK_DIR)


# --- 公共方法 ---

## 将一个BookmarkData资源保存到文件中。
## @param bookmark_data: 要保存的BookmarkData资源。
func save_bookmark(bookmark_data: BookmarkData) -> void:
	var file_path := BOOKMARK_DIR.path_join("bookmark_%d_%d.tres" % [bookmark_data.timestamp, Time.get_ticks_msec()])
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		storage.save_resource(file_path, bookmark_data)


## 加载所有已保存的书签文件。
## @return: 一个包含所有BookmarkData资源的数组。
func load_bookmarks() -> Array[BookmarkData]:
	var bookmarks: Array[BookmarkData] = []
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if not storage: return bookmarks
	
	var dir := DirAccess.open(BOOKMARK_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var path := BOOKMARK_DIR.path_join(file_name)
				var res = storage.load_resource(path, "BookmarkData")
				if res is BookmarkData:
					res.file_path = path
					bookmarks.append(res)
			file_name = dir.get_next()
	
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
		
	if FileAccess.file_exists(bookmark_file_path):
		DirAccess.remove_absolute(bookmark_file_path)
