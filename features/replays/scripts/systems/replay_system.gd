## ReplaySystem: 负责处理游戏回放数据持久化的核心系统。
##
## 取代了原本的 ReplayManager 全局单例。
## 管理所有回放文件的保存、加载和删除。它在用户数据目录中
## 创建一个专用的 `replays` 文件夹来存放所有回放记录。
class_name ReplaySystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 信号 ---

## 当回放进度发生变化时发出。
signal playback_progress_changed(current_step: int, total_steps: int)

## 当回放开始或停止时发出。
signal playback_status_changed(is_playing: bool)


# --- 常量 ---

## 回放文件存储目录。
const REPLAY_DIR_NAME: String = "replays"
const _SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT: Script = preload("res://shared/scripts/utilities/saved_resource_collection_utility.gd")


# --- 私有变量 ---

var _current_replay: ReplayData = null
var _is_replay_active: bool = false
var _command_history: GFCommandHistoryUtility = null
var _saved_resources: SavedResourceCollectionUtility = null


# --- Godot 生命周期方法 ---

func ready() -> void:
	_command_history = _get_command_history_utility()
	_saved_resources = _resolve_saved_resource_collection()
	if is_instance_valid(_saved_resources):
		var _ensure_result: Error = _saved_resources.ensure_collection_directory(REPLAY_DIR_NAME)


func dispose() -> void:
	_command_history = null
	_saved_resources = null
	_current_replay = null
	_is_replay_active = false


# --- 公共方法 ---

## 将一个ReplayData资源保存到文件中。
## @param replay_data: 要保存的ReplayData资源。
func save_replay(replay_data: ReplayData) -> void:
	if is_instance_valid(_saved_resources):
		var _saved_path: String = _saved_resources.save_timestamped_resource(REPLAY_DIR_NAME, "replay", replay_data)


## 加载所有已保存的回放文件。
## @return: 一个包含所有ReplayData资源的数组。
func load_replays() -> Array[ReplayData]:
	var replays: Array[ReplayData] = []
	if not is_instance_valid(_saved_resources):
		return replays

	for resource: Resource in _saved_resources.load_timestamped_resources(REPLAY_DIR_NAME, "ReplayData", ReplayData):
		if resource is ReplayData:
			var replay_data: ReplayData = resource
			replays.append(replay_data)
	return replays


## 根据其文件路径删除一个回放文件。
## @param replay_file_path: 要删除的回放文件的文件路径。
func delete_replay(replay_file_path: String) -> void:
	if replay_file_path.is_empty():
		return

	if is_instance_valid(_saved_resources):
		var _delete_result: Error = _saved_resources.delete_resource_file(replay_file_path)


## 激活回放模式。
## @param data: 要播放的回放资源。
func activate_replay_mode(data: ReplayData) -> void:
	_current_replay = data
	_is_replay_active = (data != null)
	playback_status_changed.emit(_is_replay_active)
	_emit_progress()


## 清理当前激活的回放数据。
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

	var current_step: int = get_current_step()
	var actions_prefix: Array[Vector2i] = _get_actions_prefix(current_step)
	var payload: ReplayContinueData = ReplayContinueData.new(
		_current_replay,
		current_step,
		get_total_steps(),
		actions_prefix
	)

	if is_instance_valid(_command_history):
		_clear_command_history_redo_stack()

	send_simple_event(EventNames.REPLAY_CONTINUE_REQUESTED, payload)
	deactivate_replay_mode()


## 获取当前步数。
func get_current_step() -> int:
	if not is_instance_valid(_command_history):
		return 0
	return maxi(_command_history.undo_count - 1, 0)


## 获取总步数。
func get_total_steps() -> int:
	return _current_replay.actions.size() if is_instance_valid(_current_replay) else 0


## 是否处于回放模式。
func is_replay_active() -> bool:
	return _is_replay_active


## 当前回放位置是否可以恢复为可游玩的普通对局。
func can_continue_from_current_step() -> bool:
	if not _is_replay_active or not is_instance_valid(_current_replay):
		return false
	return get_total_steps() > 0 and get_current_step() < get_total_steps()


# --- 私有/辅助方法 ---


func _clear_command_history_redo_stack() -> void:
	if not is_instance_valid(_command_history):
		return

	var history_data: Dictionary = _command_history.serialize_full_history()
	history_data["redo"] = []
	_command_history.deserialize_full_history(history_data, Callable(MoveCommand, "deserialize"))


func _emit_progress() -> void:
	playback_progress_changed.emit(get_current_step(), get_total_steps())


func _get_actions_prefix(step_count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_instance_valid(_current_replay):
		return result

	var safe_count: int = clampi(step_count, 0, _current_replay.actions.size())
	for i: int in range(safe_count):
		var action_value: Variant = _current_replay.actions[i]
		if action_value is Vector2i:
			var direction: Vector2i = action_value
			result.append(direction)

	return result


func _get_command_history_utility() -> GFCommandHistoryUtility:
	var utility_value: Object = get_utility(GFCommandHistoryUtility)
	if utility_value is GFCommandHistoryUtility:
		var command_history: GFCommandHistoryUtility = utility_value
		return command_history
	return null


func _resolve_saved_resource_collection() -> SavedResourceCollectionUtility:
	var utility_value: Object = get_utility(_SAVED_RESOURCE_COLLECTION_UTILITY_SCRIPT)
	if utility_value is SavedResourceCollectionUtility:
		var collection: SavedResourceCollectionUtility = utility_value
		return collection
	return null
