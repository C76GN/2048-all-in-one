## ReplaySystem: 负责处理游戏回放数据持久化的核心系统。
##
## 取代了原本的 ReplayManager 全局单例。
## 管理所有回放文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `replays` 文件夹来存放所有回放记录。
class_name ReplaySystem
extends GFSystem

# --- 常量 ---

## 回放文件存储目录。
const REPLAY_DIR_NAME: String = "replays"
const _REPLAY_CONTINUE_DATA_SCRIPT = preload("res://scripts/events/replay_continue_data.gd")


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

func async_init() -> void:
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		DirAccess.make_dir_recursive_absolute(_get_storage_dir_path(storage, REPLAY_DIR_NAME))


func ready() -> void:
	_command_history = get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility


# --- 公共方法 ---

## 将一个ReplayData资源保存到文件中。
## @param replay_data: 要保存的ReplayData资源。
func save_replay(replay_data: ReplayData) -> void:
	var file_path := REPLAY_DIR_NAME.path_join(
		"replay_%d_%d.tres" % [replay_data.timestamp, Time.get_ticks_msec()]
	)
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if storage:
		storage.save_resource(file_path, replay_data)


## 加载所有已保存的回放文件。
## @return: 一个包含所有ReplayData资源的数组。
func load_replays() -> Array[ReplayData]:
	var replays: Array[ReplayData] = []
	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	if not storage:
		return replays
	
	var dir := DirAccess.open(_get_storage_dir_path(storage, REPLAY_DIR_NAME))
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var path := REPLAY_DIR_NAME.path_join(file_name)
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

	var storage := get_utility(GFStorageUtility) as GFStorageUtility
	var absolute_path := _get_storage_file_path(storage, REPLAY_DIR_NAME, replay_file_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


## 激活回放模式。
func activate_replay_mode(data: ReplayData) -> void:
	_current_replay = data
	_is_replay_active = (data != null)
	playback_status_changed.emit(_is_replay_active)
	_emit_progress()


## Clears active replay data.
func deactivate_replay_mode() -> void:
	_current_replay = null
	_is_replay_active = false
	playback_status_changed.emit(false)
	_emit_progress()


## 回放下一步。
func step_forward() -> void:
	if not _is_replay_active or _current_replay == null:
		return
		
	var step_index: int = get_current_step()
	if step_index < _current_replay.actions.size():
		send_simple_event(EventNames.REPLAY_NEXT_STEP)
		# 进度更新通常由 ReplayInputSystem 处理后的事件触发，或者在这里手动触发
		call_deferred("_emit_progress")


## 回放上一步。
func step_backward() -> void:
	if not _is_replay_active:
		return

	if get_current_step() <= 0:
		_emit_progress()
		return
	
	send_simple_event(EventNames.REPLAY_PREV_STEP)
	call_deferred("_emit_progress")


## 从当前回放步数恢复成普通对局继续游玩。
func continue_from_current_step() -> void:
	if not can_continue_from_current_step():
		return

	var current_step := get_current_step()
	var actions_prefix := _get_actions_prefix(current_step)
	var payload := _REPLAY_CONTINUE_DATA_SCRIPT.new(
		_current_replay,
		current_step,
		get_total_steps(),
		actions_prefix
	)

	if is_instance_valid(_command_history):
		_command_history.clear_redo()

	send_simple_event(EventNames.REPLAY_CONTINUE_REQUESTED, payload)
	deactivate_replay_mode()


## 获取当前步数。
func get_current_step() -> int:
	if not is_instance_valid(_command_history):
		return 0
	return maxi(_command_history.undo_count - 1, 0)


## 获取总步数。
func get_total_steps() -> int:
	return _current_replay.actions.size() if _current_replay else 0


## 是否处于回放模式。
func is_replay_active() -> bool:
	return _is_replay_active


## 当前回放位置是否可以恢复为可游玩的普通对局。
func can_continue_from_current_step() -> bool:
	if not _is_replay_active or not is_instance_valid(_current_replay):
		return false
	return get_total_steps() > 0 and get_current_step() < get_total_steps()


func _get_storage_dir_path(storage: GFStorageUtility, directory_name: String) -> String:
	return _get_storage_base_path(storage).path_join(directory_name)


func _get_storage_file_path(
	storage: GFStorageUtility,
	directory_name: String,
	file_path: String
) -> String:
	return _get_storage_dir_path(storage, directory_name).path_join(file_path.get_file())


func _get_storage_base_path(storage: GFStorageUtility) -> String:
	if is_instance_valid(storage) and not storage.save_dir_name.is_empty():
		return "user://".path_join(storage.save_dir_name)
	return "user://"


func _emit_progress() -> void:
	playback_progress_changed.emit(get_current_step(), get_total_steps())


func _get_actions_prefix(step_count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_instance_valid(_current_replay):
		return result

	var safe_count := clampi(step_count, 0, _current_replay.actions.size())
	for i in range(safe_count):
		result.append(_current_replay.actions[i])

	return result
