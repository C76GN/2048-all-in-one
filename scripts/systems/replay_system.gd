# scripts/systems/replay_system.gd

## ReplaySystem: 负责处理游戏回放数据持久化的核心系统。
##
## 取代了原本的 ReplayManager 全局单例。
## 管理所有回放文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `replays` 文件夹来存放所有回放记录。
class_name ReplaySystem
extends GFSystem

# --- 常量 ---

## 回放文件存储目录。
const REPLAY_DIR: String = "user://replays/"


# --- 信号 ---

## 当回放进度发生变化时发出。
signal playback_progress_changed(current_step: int, total_steps: int)

## 当回放开始或停止时发出。
signal playback_status_changed(is_playing: bool)


# --- 私有变量 ---

var _current_replay: ReplayData = null
var _is_replay_active: bool = false
var _command_history: GFCommandHistoryUtility


# --- Godot 生命周期方法 ---

func init() -> void:
	_command_history = get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility

func async_init() -> void:
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		DirAccess.make_dir_recursive_absolute(REPLAY_DIR)


# --- 公共方法 ---

## 将一个ReplayData资源保存到文件中。
## @param replay_data: 要保存的ReplayData资源。
func save_replay(replay_data: ReplayData) -> void:
	var file_path := REPLAY_DIR.path_join("replay_%d.tres" % replay_data.timestamp)
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		storage.save_resource(file_path, replay_data)


## 加载所有已保存的回放文件。
## @return: 一个包含所有ReplayData资源的数组。
func load_replays() -> Array[ReplayData]:
	var replays: Array[ReplayData] = []
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if not storage: return replays
	
	var dir := DirAccess.open(REPLAY_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var path := REPLAY_DIR.path_join(file_name)
				var res = storage.load_resource(path, "ReplayData")
				if res is ReplayData:
					res.file_path = path
					replays.append(res)
			file_name = dir.get_next()
			
	# 按时间戳降序排序
	replays.sort_custom(func(a: ReplayData, b: ReplayData) -> bool:
		return a.timestamp > b.timestamp
	)
	return replays


## 根据其文件路径删除一个回放文件。
## @param replay_file_path: 要删除的回放文件的文件路径。
func delete_replay(replay_file_path: String) -> void:
	if replay_file_path.is_empty():
		return
		
	if FileAccess.file_exists(replay_file_path):
		DirAccess.remove_absolute(replay_file_path)


## 激活回放模式。
func activate_replay_mode(data: ReplayData) -> void:
	_current_replay = data
	_is_replay_active = (data != null)
	playback_status_changed.emit(_is_replay_active)
	_emit_progress()


## 回放下一步。
func step_forward() -> void:
	if not _is_replay_active or _current_replay == null:
		return
		
	var step_index: int = get_current_step()
	if step_index < _current_replay.actions.size():
		Gf.send_simple_event(&"replay_next_step")
		# 进度更新通常由 ReplayInputSystem 处理后的事件触发，或者在这里手动触发
		call_deferred("_emit_progress")


## 回放上一步。
func step_backward() -> void:
	if not _is_replay_active:
		return
	
	Gf.send_simple_event(&"replay_prev_step")
	call_deferred("_emit_progress")


## 获取当前步数。
func get_current_step() -> int:
	return _command_history.undo_count - 1 if is_instance_valid(_command_history) else 0


## 获取总步数。
func get_total_steps() -> int:
	return _current_replay.actions.size() if _current_replay else 0


## 是否处于回放模式。
func is_replay_active() -> bool:
	return _is_replay_active


func _emit_progress() -> void:
	playback_progress_changed.emit(get_current_step(), get_total_steps())
