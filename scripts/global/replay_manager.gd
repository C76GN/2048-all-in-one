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
	ResourceIOManager.ensure_dir(REPLAY_DIR)


# --- 公共方法 ---

## 将一个ReplayData资源保存到文件中。
## @param replay_data: 要保存的ReplayData资源。
func save_replay(replay_data: ReplayData) -> void:
	var file_path := REPLAY_DIR.path_join("replay_%d.tres" % replay_data.timestamp)
	ResourceIOManager.save_resource(replay_data, file_path, &"回放")


## 加载所有已保存的回放文件。
## @return: 一个包含所有ReplayData资源的数组。
func load_replays() -> Array[ReplayData]:
	var loaded_list := ResourceIOManager.load_resources(REPLAY_DIR, &"ReplayData")
	var replays: Array[ReplayData] = []
	
	for res in loaded_list:
		if res is ReplayData:
			replays.append(res as ReplayData)
			
	# 按时间戳降序排序
	replays.sort_custom(func(a: ReplayData, b: ReplayData) -> bool:
		return a.timestamp > b.timestamp
	)
	return replays


## 根据其文件路径删除一个回放文件。
## @param replay_file_path: 要删除的回放文件的文件路径。
func delete_replay(replay_file_path: String) -> void:
	ResourceIOManager.delete_file(replay_file_path, &"回放")
