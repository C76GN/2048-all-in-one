## BoardTweenBatchAction: 将棋盘已有 Tween 适配为 GF 可等待视觉动作。
class_name BoardTweenBatchAction
extends "res://addons/gf/extensions/action_queue/actions/gf_visual_action.gd"


# --- 私有变量 ---

var _active_tweens: Array[Tween] = []
var _wait_guard_node: Node


# --- 公共方法 ---

func cancel() -> void:
	_clear_tracked_tweens(true)
	_emit_completed_once()


func pause() -> void:
	for tween: Tween in _active_tweens:
		if _is_active_tween(tween):
			tween.pause()


func resume() -> void:
	for tween: Tween in _active_tweens:
		if _is_active_tween(tween):
			tween.play()


func finish() -> void:
	var tween_snapshot: Array[Tween] = _active_tweens.duplicate()
	for tween: Tween in tween_snapshot:
		if _is_active_tween(tween):
			var _still_running: bool = tween.custom_step(1_000_000.0)
	_clear_tracked_tweens(true)
	_emit_completed_once()


func get_wait_guard_node() -> Node:
	return _wait_guard_node if is_instance_valid(_wait_guard_node) else null


# --- 受保护的辅助方法 ---

func _wait_for_tweens(tweens: Array[Tween], guard_node: Node) -> Variant:
	_clear_tracked_tweens(true)
	_reset_completion_state()
	_wait_guard_node = guard_node

	for tween: Tween in tweens:
		if not _is_active_tween(tween) or _active_tweens.has(tween):
			continue
		_active_tweens.append(tween)
		var finished_callback: Callable = _on_tracked_tween_finished.bind(tween)
		var _finished_connected: int = tween.finished.connect(finished_callback)

	if _active_tweens.is_empty():
		_wait_guard_node = null
		return null
	return _action_completed


# --- 私有/辅助方法 ---

func _clear_tracked_tweens(kill_tweens: bool) -> void:
	var tween_snapshot: Array[Tween] = _active_tweens.duplicate()
	_active_tweens.clear()
	for tween: Tween in tween_snapshot:
		if not is_instance_valid(tween):
			continue
		var finished_callback: Callable = _on_tracked_tween_finished.bind(tween)
		if tween.finished.is_connected(finished_callback):
			tween.finished.disconnect(finished_callback)
		if kill_tweens and tween.is_valid():
			tween.kill()
	_wait_guard_node = null


func _is_active_tween(tween: Tween) -> bool:
	return is_instance_valid(tween) and tween.is_valid()


func _on_tracked_tween_finished(tween: Tween) -> void:
	_active_tweens.erase(tween)
	if not _active_tweens.is_empty():
		return
	_wait_guard_node = null
	_emit_completed_once()
