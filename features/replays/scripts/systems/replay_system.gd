## ReplaySystem: 负责处理游戏回放数据持久化的核心系统。
##
## 取代了原本的 ReplayManager 全局单例。
## 回放作为独立 Feature section 参与统一玩家数据 SaveGraph 事务。
class_name ReplaySystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 信号 ---

## 当回放进度发生变化时发出。
signal playback_progress_changed(current_step: int, total_steps: int)

## 当回放开始或停止时发出。
signal playback_status_changed(is_playing: bool)


# --- 私有变量 ---

var _current_replay: ReplayData = null
var _is_replay_active: bool = false
var _command_history: GFCommandHistoryUtility = null
var _save_graph: GameSaveGraphUtility = null


# --- Godot 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameSaveGraphUtility, GFCommandHistoryUtility]


func ready() -> void:
	_command_history = _get_command_history_utility()
	_save_graph = _resolve_save_graph_utility()


func dispose() -> void:
	_command_history = null
	_save_graph = null
	_current_replay = null
	_is_replay_active = false


# --- 公共方法 ---

## 将一个 ReplayData 原子写入统一玩家数据图。
## @param replay_data: 要保存的ReplayData资源。
func save_replay(replay_data: ReplayData) -> Error:
	if replay_data == null:
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED

	if replay_data.replay_id.is_empty():
		var timestamp_msec: int = replay_data.timestamp * 1000 if replay_data.timestamp > 0 else -1
		replay_data.replay_id = GFUuid.generate_v7(timestamp_msec)
	if not GFUuid.is_valid(replay_data.replay_id, 7):
		return ERR_INVALID_DATA

	var candidate: ReplayData = ReplayData.from_dict(replay_data.to_dict())
	if candidate == null:
		return ERR_INVALID_DATA
	var replays: Array[ReplayData] = load_replays()
	for existing: ReplayData in replays:
		if existing.replay_id == candidate.replay_id:
			return ERR_ALREADY_EXISTS
	replays.append(candidate)
	replays.sort_custom(func(left: ReplayData, right: ReplayData) -> bool:
		return left.replay_id > right.replay_id
	)
	return save_graph.replace_section_data(
		GameSaveGraphUtility.REPLAYS_SECTION_ID,
		_serialize_replays(replays)
	)


## 从统一玩家数据图读取全部回放。
## @return: 一个包含所有ReplayData资源的数组。
func load_replays() -> Array[ReplayData]:
	var replays: Array[ReplayData] = []
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return replays

	var section_data: Dictionary = save_graph.get_section_data(GameSaveGraphUtility.REPLAYS_SECTION_ID)
	for item_value: Variant in GFVariantData.get_option_array(section_data, "items"):
		if not (item_value is Dictionary):
			continue
		var replay: ReplayData = ReplayData.from_dict(GFVariantData.as_dictionary(item_value))
		if replay != null:
			replays.append(replay)
	replays.sort_custom(func(left: ReplayData, right: ReplayData) -> bool:
		return left.replay_id > right.replay_id
	)
	return replays


## 根据稳定 ID 删除一个回放。
## @param replay_id: 要删除的 UUID v7 回放标识。
func delete_replay(replay_id: String) -> Error:
	if not GFUuid.is_valid(replay_id, 7):
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED

	var replays: Array[ReplayData] = load_replays()
	var found: bool = false
	var retained: Array[ReplayData] = []
	for replay: ReplayData in replays:
		if replay.replay_id == replay_id:
			found = true
			continue
		retained.append(replay)
	if not found:
		return ERR_DOES_NOT_EXIST
	return save_graph.replace_section_data(
		GameSaveGraphUtility.REPLAYS_SECTION_ID,
		_serialize_replays(retained)
	)


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


## 回放上一步。
func step_backward() -> void:
	if not _is_replay_active:
		return

	if get_current_step() <= 0:
		_emit_progress()
		return
	
	send_simple_event(EventNames.REPLAY_PREV_STEP)


## 在回放命令完成执行或撤销后发布准确进度。
func notify_playback_step_settled() -> void:
	if _is_replay_active:
		_emit_progress()


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


func _serialize_replays(replays: Array[ReplayData]) -> Dictionary:
	var items: Array[Dictionary] = []
	for replay: ReplayData in replays:
		if replay != null:
			items.append(replay.to_dict())
	return {
		"items": items,
	}


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _resolve_save_graph_utility()
	return _save_graph


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = utility_value
		return utility
	return null
