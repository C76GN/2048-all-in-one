# scripts/global/replay_manager.gd

## ReplayManager: 负责处理游戏回放数据持久化的全局单例。
##
## 管理所有回放文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `replays` 文件夹来存放所有回放记录。
extends Node


# --- 常量 ---

## 回放文件存储目录。
const REPLAY_DIR: String = "user://replays/"


# --- Godot 生命周期方法 ---

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(REPLAY_DIR):
		DirAccess.make_dir_absolute(REPLAY_DIR)
		print("已创建回放存储目录: %s" % REPLAY_DIR)


# --- 公共方法 ---

## 将一个ReplayData资源保存到文件中。
## @param replay_data: 要保存的ReplayData资源。
func save_replay(replay_data: ReplayData) -> void:
	if not is_instance_valid(replay_data):
		push_error("保存回放失败: 无效的ReplayData对象。")
		return

	var file_path: String = REPLAY_DIR.path_join("replay_%d.tres" % replay_data.timestamp)
	var error: Error = ResourceSaver.save(replay_data, file_path)

	if error != OK:
		push_error("保存回放文件失败: %s (错误码: %d)" % [file_path, error])
	else:
		print("回放已成功保存到: %s" % file_path)


## 加载所有已保存的回放文件。
## @return: 一个包含所有ReplayData资源的数组。
func load_replays() -> Array[ReplayData]:
	var replays: Array[ReplayData] = []
	var dir: DirAccess = DirAccess.open(REPLAY_DIR)

	if not dir:
		push_error("无法打开回放目录: %s" % REPLAY_DIR)
		return replays

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var file_path: String = REPLAY_DIR.path_join(file_name)
			var loaded_resource: Resource = ResourceLoader.load(file_path, "ReplayData", ResourceLoader.CACHE_MODE_IGNORE)

			if is_instance_valid(loaded_resource) and loaded_resource is ReplayData:
				var unique_replay_instance: ReplayData = loaded_resource.duplicate()
				unique_replay_instance.file_path = file_path
				replays.append(unique_replay_instance)
			else:
				push_error("加载回放资源失败或类型不匹配: %s" % file_path)

		file_name = dir.get_next()

	dir.list_dir_end()
	replays.sort_custom(func(a: ReplayData, b: ReplayData): return a.timestamp > b.timestamp)
	return replays


## 根据其文件路径删除一个回放文件。
## @param replay_file_path: 要删除的回放文件的文件路径。
func delete_replay(replay_file_path: String) -> void:
	if not FileAccess.file_exists(replay_file_path):
		push_error("删除回放失败: 文件不存在 - %s" % replay_file_path)
		return

	var error: Error = DirAccess.remove_absolute(replay_file_path)

	if error != OK:
		push_error("删除回放文件时出错: %s (错误码: %d)" % [replay_file_path, error])
	else:
		print("已删除回放文件: %s" % replay_file_path)
