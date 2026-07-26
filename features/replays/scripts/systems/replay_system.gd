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

## 首次检测到回放越界同步时发出；后续差异不会覆盖首个根因。
signal playback_desynchronized(report: Dictionary)

## 标记目录发生变化时发出；只读数组元素为 ReplayMarker。
signal playback_markers_changed(markers: Array)

## 确定性跳转开始或结束时发出。
signal playback_jump_status_changed(is_jumping: bool, target_step: int)


# --- 私有变量 ---

var _current_replay: ReplayData = null
var _is_replay_active: bool = false
var _command_history: GFCommandHistoryUtility = null
var _save_graph: GameSaveGraphUtility = null
var _oos_report: Dictionary = {}
var _markers: Array[ReplayMarker] = []
var _is_jump_active: bool = false
var _jump_target_step: int = 0
var _jump_request_id: int = 0


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
	_oos_report.clear()
	_markers.clear()
	_is_jump_active = false
	_jump_target_step = 0
	_jump_request_id = 0


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
	replays = _retain_newest_replays(replays)
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
	var item_values: Array = GFVariantData.get_option_array(section_data, "items")
	if item_values.size() > ReplayCatalogSaveData.MAX_REPLAY_COUNT:
		return replays
	for item_value: Variant in item_values:
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
	_oos_report.clear()
	_current_replay = data
	_is_replay_active = (data != null)
	_is_jump_active = false
	_jump_target_step = 0
	_rebuild_markers()
	playback_status_changed.emit(_is_replay_active)
	_emit_progress()


## 清理当前激活的回放数据。
func deactivate_replay_mode() -> void:
	_current_replay = null
	_is_replay_active = false
	_oos_report.clear()
	_markers.clear()
	_cancel_active_jump()
	playback_markers_changed.emit([])
	playback_status_changed.emit(false)
	_emit_progress()


## 回放下一步。
func step_forward() -> void:
	if (
		not _is_replay_active
		or _current_replay == null
		or is_playback_desynchronized()
		or _is_jump_active
	):
		return
		
	var step_index: int = get_current_step()
	if step_index < _current_replay.actions.size():
		send_simple_event(EventNames.REPLAY_NEXT_STEP)


## 回放上一步。
func step_backward() -> void:
	if not _is_replay_active or is_playback_desynchronized() or _is_jump_active:
		return

	if get_current_step() <= 0:
		_emit_progress()
		return
	
	send_simple_event(EventNames.REPLAY_PREV_STEP)


## 在回放命令完成执行或撤销后发布准确进度。
func notify_playback_step_settled() -> void:
	if _is_replay_active:
		_emit_progress()


## 请求通过现有 MoveCommand/GFCommandHistoryUtility 重建到目标步。
##
## 本 System 只验证并发布请求；实际命令执行由 ReplayInputSystem 单一拥有。
## @param target_step: 要重建到的 0-based 回放进度步。
func jump_to_step(target_step: int) -> bool:
	if (
		not _is_replay_active
		or not is_instance_valid(_current_replay)
		or is_playback_desynchronized()
		or _is_jump_active
		or target_step < 0
		or target_step > get_total_steps()
	):
		return false
	if target_step == get_current_step():
		_emit_progress()
		return true

	_jump_request_id += 1
	_is_jump_active = true
	_jump_target_step = target_step
	playback_jump_status_changed.emit(true, target_step)
	send_simple_event(
		EventNames.REPLAY_JUMP_TO_STEP,
		ReplayJumpRequestData.new(_jump_request_id, target_step)
	)
	return true


## 跳转到标记目录中的指定条目。
## @param marker_index: 标记目录中的 0-based 索引。
func jump_to_marker(marker_index: int) -> bool:
	var marker: ReplayMarker = get_marker(marker_index)
	return jump_to_step(marker.step_index) if is_instance_valid(marker) else false


func jump_to_previous_marker() -> bool:
	var marker_index: int = find_previous_marker_index(get_current_step())
	return jump_to_marker(marker_index) if marker_index >= 0 else false


func jump_to_next_marker() -> bool:
	var marker_index: int = find_next_marker_index(get_current_step())
	return jump_to_marker(marker_index) if marker_index >= 0 else false


## ReplayInputSystem 在命令历史达到目标或首次失败后关闭请求。
## @param request_id: 当前跳转请求的稳定序号。
## @param target_step: 请求期望达到的回放步数。
## @param succeeded: 命令历史是否成功重建到目标步。
func notify_jump_completed(request_id: int, target_step: int, succeeded: bool) -> bool:
	if (
		not _is_jump_active
		or request_id != _jump_request_id
		or target_step != _jump_target_step
	):
		return false
	var final_success: bool = (
		succeeded
		and not is_playback_desynchronized()
		and get_current_step() == target_step
	)
	_is_jump_active = false
	_jump_target_step = get_current_step()
	playback_jump_status_changed.emit(false, _jump_target_step)
	_emit_progress()
	return final_success


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


func get_current_replay() -> ReplayData:
	return _current_replay


func is_playback_desynchronized() -> bool:
	return not _oos_report.is_empty()


func get_oos_report() -> Dictionary:
	return _oos_report.duplicate(true)


func get_markers() -> Array[ReplayMarker]:
	return _markers.duplicate()


## 获取标记目录中的指定条目。
## @param marker_index: 标记目录中的 0-based 索引。
func get_marker(marker_index: int) -> ReplayMarker:
	if marker_index < 0 or marker_index >= _markers.size():
		return null
	return _markers[marker_index]


func get_marker_count() -> int:
	return _markers.size()


## 查找严格早于指定步数的最近标记。
## @param from_step: 搜索起点的回放步数。
func find_previous_marker_index(from_step: int) -> int:
	for index: int in range(_markers.size() - 1, -1, -1):
		var marker: ReplayMarker = _markers[index]
		if is_instance_valid(marker) and marker.step_index < from_step:
			return index
	return -1


## 查找严格晚于指定步数的最近标记。
## @param from_step: 搜索起点的回放步数。
func find_next_marker_index(from_step: int) -> int:
	for index: int in range(_markers.size()):
		var marker: ReplayMarker = _markers[index]
		if is_instance_valid(marker) and marker.step_index > from_step:
			return index
	return -1


func is_jump_in_progress() -> bool:
	return _is_jump_active


## 判断标识与目标是否仍对应当前有效跳转请求。
## @param request_id: 要比对的跳转请求序号。
## @param target_step: 要比对的目标回放步数。
func is_jump_request_current(request_id: int, target_step: int) -> bool:
	return (
		_is_jump_active
		and request_id == _jump_request_id
		and target_step == _jump_target_step
	)


## 记录首个回放 OOS 并阻止后续前进。
## @param report: 包含首个偏离回合与 expected/actual 摘要的诊断字典。
func report_oos(report: Dictionary) -> bool:
	if not _is_replay_active or report.is_empty() or is_playback_desynchronized():
		return false
	_oos_report = report.duplicate(true)
	_rebuild_markers()
	_cancel_active_jump()
	playback_desynchronized.emit(get_oos_report())
	return true


## 将预期有效但未产生 TurnResult 的回放动作记录为首个 OOS。
## @param direction: 当前回放步骤声明的四向动作。
func report_ineffective_action(direction: Vector2i) -> bool:
	if not _is_replay_active or not is_instance_valid(_current_replay):
		return false
	var step_index: int = get_current_step() + 1
	var report: Dictionary = {
		&"kind": &"ineffective_action",
		&"step_index": step_index,
		&"direction": direction,
	}
	if step_index > 0 and step_index <= _current_replay.checkpoints.size():
		var expected: ReplayCheckpoint = _current_replay.checkpoints[step_index - 1]
		report[&"expected_state_checksum"] = expected.state_checksum
		report[&"expected_board_checksum"] = expected.board_checksum
		report[&"expected_rng_checksum"] = expected.rng_checksum
		report[&"expected_score"] = expected.score
	return report_oos(report)


## 当前回放位置是否可以恢复为可游玩的普通对局。
func can_continue_from_current_step() -> bool:
	if (
		not _is_replay_active
		or not is_instance_valid(_current_replay)
		or is_playback_desynchronized()
		or _is_jump_active
	):
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


func _rebuild_markers() -> void:
	_markers = ReplayMarker.build_catalog(_current_replay, _oos_report)
	playback_markers_changed.emit(get_markers())


func _cancel_active_jump() -> void:
	if not _is_jump_active:
		return
	_is_jump_active = false
	_jump_target_step = get_current_step()
	playback_jump_status_changed.emit(false, _jump_target_step)


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
	for replay: ReplayData in _retain_newest_replays(replays):
		if replay != null:
			items.append(replay.to_dict())
	return {
		"items": items,
	}


## 按 UUID v7 的时间有序身份确定性保留最新目录，避免依赖数组插入顺序。
func _retain_newest_replays(replays: Array[ReplayData]) -> Array[ReplayData]:
	var retained: Array[ReplayData] = replays.duplicate()
	retained.sort_custom(func(left: ReplayData, right: ReplayData) -> bool:
		return left.replay_id > right.replay_id
	)
	if retained.size() > ReplayCatalogSaveData.MAX_REPLAY_COUNT:
		var _resize_error_code: int = retained.resize(
			ReplayCatalogSaveData.MAX_REPLAY_COUNT
		)
	return retained


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
