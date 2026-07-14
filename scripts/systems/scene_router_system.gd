## SceneRouterSystem: 负责全局的场景切换与路由控制。
##
## 负责管理并执行全局的场景跳转功能。
## 任何需要切换场景的模块，通过调用此系统的公共方法或发送事件来实现。
class_name SceneRouterSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "SceneRouterSystem"
const _TRANSITION_SHADER: Shader = preload("res://asset_library/shaders/transition/halftone_wipe_transition.gdshader")
const _TRANSITION_LAYER_NAME: String = "SceneTransitionOverlay"
const _TRANSITION_RECT_NAME: String = "SceneTransitionRect"
const _TRANSITION_LAYER_INDEX: int = 1024
const _TRANSITION_MINIMUM_SECONDS: float = 0.30
const _TRANSITION_COVER_DURATION: float = 0.24
const _TRANSITION_HOLD_DURATION: float = 0.04
const _TRANSITION_REVEAL_DURATION: float = 0.26


# --- 私有变量 ---

## 缓存当前主菜单场景的路径，用于快速返回。
var _main_menu_scene_path: String = "res://scenes/menus/main_menu.tscn"
var _log: GFLogUtility
var _scene_utility: GFSceneUtility
var _signal_utility: GFSignalUtility
var _async_tracker: GFAsyncTrackerUtility
var _operation_diagnostics: GFOperationDiagnosticsUtility
var _scene_switch_started_connection: GFSignalConnection
var _scene_load_completed_connection: GFSignalConnection
var _scene_load_failed_connection: GFSignalConnection
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect
var _transition_tween: Tween
var _transition_factor: float = 0.0
var _transition_tracking_id: int = 0
var _scene_change_operation_id: StringName = &""
var _scene_change_started_usec: int = 0


# --- Godot 生命周期方法 ---

func ready() -> void:
	_log = _get_log_utility()
	_scene_utility = _get_scene_utility()
	_signal_utility = _get_signal_utility()
	_async_tracker = _get_async_tracker_utility()
	_operation_diagnostics = _get_operation_diagnostics_utility()
	_connect_scene_utility_signals()

	# 可选：监听全局事件 `scene_change_requested` 以解耦调用
	register_simple_event(EventNames.SCENE_CHANGE_REQUESTED, GFEventListener.from_method(self, &"_on_scene_change_requested", 1))
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, GFEventListener.from_method(self, &"_on_return_to_main_menu_requested", 1))


func dispose() -> void:
	_finish_scene_change_operation(false, {"reason": "system_disposed"})
	_disconnect_scene_utility_signals()
	_scene_utility = null
	_signal_utility = null
	_async_tracker = null
	_operation_diagnostics = null
	_log = null
	_scene_switch_started_connection = null
	_scene_load_completed_connection = null
	_scene_load_failed_connection = null
	_cleanup_transition_overlay()


# --- 公共方法 ---

## 切换到指定的场景资源。
## @param scene: 待切换的场景资源 (PackedScene)。
func goto_scene_packed(scene: PackedScene) -> void:
	if not _is_scene_resource_ready(scene):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "传入的场景资源为空或不可实例化。")
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, _get_scene_resource_path(scene))
		return

	if is_instance_valid(_scene_utility) and not scene.resource_path.is_empty():
		goto_scene(scene.resource_path)
		return

	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree):
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return

	if is_instance_valid(tree.current_scene):
		send_simple_event(EventNames.SCENE_WILL_CHANGE)

	var error: int = tree.change_scene_to_packed(scene)
	if error != OK:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "切换到场景失败，错误码: %d" % error)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已请求切换到场景: %s" % scene.resource_path)


## 切换到指定的场景路径。
## @param path: 待切换的场景资源路径。
func goto_scene(path: String) -> void:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "场景路径必须是绝对的 .tscn 资源路径: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	if is_instance_valid(_scene_utility):
		_begin_scene_change_operation(path)
		_scene_utility.load_scene_async(path, "", {}, _TRANSITION_MINIMUM_SECONDS)
		return

	if is_instance_valid(_log):
		_log.error(_LOG_TAG, "GFSceneUtility 未注册，无法执行场景切换: %s" % path)
	send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)


## 快速返回到主菜单。
func return_to_main_menu() -> void:
	goto_scene(_main_menu_scene_path)


## 安全地退出整个游戏。
func quit_game() -> void:
	if is_instance_valid(_log):
		_log.info(_LOG_TAG, "正在退出游戏。")
	var tree: SceneTree = _get_scene_tree()
	if is_instance_valid(tree):
		tree.quit()


# --- 私有/辅助方法 ---

func _get_log_utility() -> GFLogUtility:
	var utility_value: Object = get_utility(GFLogUtility)
	if utility_value is GFLogUtility:
		var log_utility: GFLogUtility = utility_value
		return log_utility
	return null


func _get_scene_utility() -> GFSceneUtility:
	var utility_value: Object = get_utility(GFSceneUtility)
	if utility_value is GFSceneUtility:
		var scene_utility: GFSceneUtility = utility_value
		return scene_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_async_tracker_utility() -> GFAsyncTrackerUtility:
	var utility_value: Object = get_utility(GFAsyncTrackerUtility)
	if utility_value is GFAsyncTrackerUtility:
		var tracker: GFAsyncTrackerUtility = utility_value
		return tracker
	return null


func _get_operation_diagnostics_utility() -> GFOperationDiagnosticsUtility:
	var utility_value: Object = get_utility(GFOperationDiagnosticsUtility)
	if utility_value is GFOperationDiagnosticsUtility:
		var diagnostics: GFOperationDiagnosticsUtility = utility_value
		return diagnostics
	return null


func _get_scene_tree() -> SceneTree:
	var loop_value: MainLoop = Engine.get_main_loop()
	if loop_value is SceneTree:
		var tree: SceneTree = loop_value
		return tree
	return null


func _connect_scene_utility_signals() -> void:
	if not is_instance_valid(_scene_utility):
		return

	if is_instance_valid(_signal_utility):
		_scene_switch_started_connection = _signal_utility.connect_signal(_scene_utility.scene_switch_started, _on_scene_switch_started, self)
		_scene_load_completed_connection = _signal_utility.connect_signal(_scene_utility.scene_load_completed, _on_scene_load_completed, self)
		_scene_load_failed_connection = _signal_utility.connect_signal(_scene_utility.scene_load_failed, _on_scene_load_failed, self)
		return

	if not _scene_utility.scene_switch_started.is_connected(_on_scene_switch_started):
		var _connect_result_134: int = _scene_utility.scene_switch_started.connect(_on_scene_switch_started)
	if not _scene_utility.scene_load_completed.is_connected(_on_scene_load_completed):
		var _connect_result_136: int = _scene_utility.scene_load_completed.connect(_on_scene_load_completed)
	if not _scene_utility.scene_load_failed.is_connected(_on_scene_load_failed):
		var _connect_result_138: int = _scene_utility.scene_load_failed.connect(_on_scene_load_failed)


func _disconnect_scene_utility_signals() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
		return

	if not is_instance_valid(_scene_utility):
		return

	if _scene_utility.scene_switch_started.is_connected(_on_scene_switch_started):
		_scene_utility.scene_switch_started.disconnect(_on_scene_switch_started)
	if _scene_utility.scene_load_completed.is_connected(_on_scene_load_completed):
		_scene_utility.scene_load_completed.disconnect(_on_scene_load_completed)
	if _scene_utility.scene_load_failed.is_connected(_on_scene_load_failed):
		_scene_utility.scene_load_failed.disconnect(_on_scene_load_failed)


func _is_scene_resource_ready(scene: PackedScene) -> bool:
	return scene != null and scene.can_instantiate()


func _get_scene_resource_path(scene: PackedScene) -> String:
	return scene.resource_path if scene != null else ""


func _play_scene_transition_cover() -> void:
	var rect: ColorRect = _ensure_transition_overlay()
	if not is_instance_valid(rect):
		return

	rect.visible = true
	_sync_transition_resolution()
	_set_transition_factor(0.0)
	_kill_transition_tween()
	_transition_tween = rect.create_tween()
	var _transition_result: Tween = _transition_tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = _transition_tween.set_ease(Tween.EASE_OUT)
	var _factor_tweener: MethodTweener = _transition_tween.tween_method(
		_set_transition_factor,
		_transition_factor,
		1.0,
		_TRANSITION_COVER_DURATION
	)
	_track_transition_tween(_transition_tween, &"cover")


func _play_scene_transition_reveal() -> void:
	var rect: ColorRect = _ensure_transition_overlay()
	if not is_instance_valid(rect):
		return

	rect.visible = true
	_sync_transition_resolution()
	_set_transition_factor(1.0)
	_kill_transition_tween()
	_transition_tween = rect.create_tween()
	var _transition_result: Tween = _transition_tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = _transition_tween.set_ease(Tween.EASE_IN_OUT)
	var _hold_tweener: IntervalTweener = _transition_tween.tween_interval(_TRANSITION_HOLD_DURATION)
	var _factor_tweener: MethodTweener = _transition_tween.tween_method(
		_set_transition_factor,
		_transition_factor,
		0.0,
		_TRANSITION_REVEAL_DURATION
	)
	var _callback_tweener: CallbackTweener = _transition_tween.tween_callback(_hide_transition_overlay)
	_track_transition_tween(_transition_tween, &"reveal")


func _ensure_transition_overlay() -> ColorRect:
	if is_instance_valid(_transition_rect):
		return _transition_rect

	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return null

	var root: Window = tree.root
	var existing_layer: Node = root.get_node_or_null(_TRANSITION_LAYER_NAME)
	if existing_layer is CanvasLayer:
		_transition_layer = existing_layer
	else:
		_transition_layer = CanvasLayer.new()
		_transition_layer.name = _TRANSITION_LAYER_NAME
		_transition_layer.layer = _TRANSITION_LAYER_INDEX
		_transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child(_transition_layer)

	var existing_rect: Node = _transition_layer.get_node_or_null(_TRANSITION_RECT_NAME)
	if existing_rect is ColorRect:
		_transition_rect = existing_rect
	else:
		_transition_rect = ColorRect.new()
		_transition_rect.name = _TRANSITION_RECT_NAME
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transition_rect.process_mode = Node.PROCESS_MODE_ALWAYS
		_transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_transition_rect.offset_left = 0.0
		_transition_rect.offset_top = 0.0
		_transition_rect.offset_right = 0.0
		_transition_rect.offset_bottom = 0.0
		_transition_rect.color = Color.WHITE
		_transition_layer.add_child(_transition_rect)

	if not (_transition_rect.material is ShaderMaterial):
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = _TRANSITION_SHADER
		_transition_rect.material = shader_material

	_set_transition_factor(_transition_factor)
	_hide_transition_overlay()
	return _transition_rect


func _sync_transition_resolution() -> void:
	if not is_instance_valid(_transition_rect):
		return

	var viewport_rect: Rect2 = _transition_rect.get_viewport_rect()
	var shader_material: ShaderMaterial = _get_transition_material()
	if is_instance_valid(shader_material):
		shader_material.set_shader_parameter("node_resolution", viewport_rect.size)


func _set_transition_factor(value: float) -> void:
	_transition_factor = clampf(value, 0.0, 1.0)
	var shader_material: ShaderMaterial = _get_transition_material()
	if is_instance_valid(shader_material):
		shader_material.set_shader_parameter("factor", _transition_factor)


func _get_transition_material() -> ShaderMaterial:
	if not is_instance_valid(_transition_rect):
		return null
	var material_value: Material = _transition_rect.material
	if material_value is ShaderMaterial:
		var shader_material: ShaderMaterial = material_value
		return shader_material
	return null


func _hide_transition_overlay() -> void:
	if is_instance_valid(_transition_rect) and _transition_factor <= 0.001:
		_transition_rect.visible = false


func _kill_transition_tween() -> void:
	_untrack_transition_tween()
	if is_instance_valid(_transition_tween):
		_transition_tween.kill()
	_transition_tween = null


func _track_transition_tween(tween: Tween, phase: StringName) -> void:
	if not is_instance_valid(tween) or not is_instance_valid(_async_tracker):
		return
	_transition_tracking_id = _async_tracker.track_handle(
		tween,
		&"scene_transition_tween",
		{"phase": phase},
		Callable(self, &"_get_transition_tracking_snapshot").bind(phase)
	)
	if _transition_tracking_id > 0:
		var _connect_result: int = tween.finished.connect(
			Callable(self, &"_on_transition_tween_finished").bind(tween, _transition_tracking_id)
		)


func _untrack_transition_tween() -> void:
	if _transition_tracking_id > 0 and is_instance_valid(_async_tracker):
		var _untracked: bool = _async_tracker.untrack_id(_transition_tracking_id)
	_transition_tracking_id = 0


func _get_transition_tracking_snapshot(phase: StringName) -> Dictionary:
	return {
		"phase": phase,
		"factor": _transition_factor,
		"overlay_visible": is_instance_valid(_transition_rect) and _transition_rect.visible,
	}


func _begin_scene_change_operation(path: String) -> void:
	_finish_scene_change_operation(false, {"reason": "superseded"})
	_scene_change_started_usec = Time.get_ticks_usec()
	if not is_instance_valid(_operation_diagnostics):
		return
	_scene_change_operation_id = _operation_diagnostics.begin_operation(&"game.scene_change", {
		"component": &"scene_router",
		"label": "Load scene",
		"started_ticks_usec": _scene_change_started_usec,
		"metadata": {"path": path},
	})


func _finish_scene_change_operation(success: bool, metadata: Dictionary = {}) -> void:
	if _scene_change_operation_id != &"" and is_instance_valid(_operation_diagnostics):
		var _operation: Dictionary = _operation_diagnostics.finish_operation(
			_scene_change_operation_id,
			success,
			{"metadata": metadata}
		)
	_scene_change_operation_id = &""
	_scene_change_started_usec = 0


func _cleanup_transition_overlay() -> void:
	_kill_transition_tween()
	if is_instance_valid(_transition_layer):
		_transition_layer.queue_free()
	_transition_layer = null
	_transition_rect = null
	_transition_factor = 0.0


# --- 信号处理函数 ---

func _on_scene_change_requested(scene: PackedScene) -> void:
	goto_scene_packed(scene)


func _on_return_to_main_menu_requested(_payload: Variant = null) -> void:
	return_to_main_menu()


func _on_scene_switch_started(path: String, previous_path: String) -> void:
	if _scene_change_operation_id != &"" and is_instance_valid(_operation_diagnostics):
		var _state: Dictionary = _operation_diagnostics.record_state_snapshot(
			_scene_change_operation_id,
			&"loading",
			GFOperationDiagnosticsUtility.STATE_RUNNING,
			{"progress": 0.1, "metadata": {"path": path, "previous_path": previous_path}}
		)
	_play_scene_transition_cover()
	send_simple_event(EventNames.SCENE_WILL_CHANGE)


func _on_scene_load_completed(path: String, _scene: PackedScene) -> void:
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已完成异步场景加载: %s" % path)
	if _scene_change_operation_id != &"" and is_instance_valid(_operation_diagnostics):
		var _phase: Dictionary = _operation_diagnostics.record_phase_from_ticks(
			_scene_change_operation_id,
			&"load",
			_scene_change_started_usec,
			{"metadata": {"path": path}}
		)
	_finish_scene_change_operation(true, {"path": path})
	_play_scene_transition_reveal()


func _on_scene_load_failed(path: String) -> void:
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, "异步场景加载失败: %s" % path)
	if is_instance_valid(_operation_diagnostics):
		var _incident: Dictionary = _operation_diagnostics.record_incident(
			GFOperationDiagnosticsUtility.SEVERITY_ERROR,
			&"scene_load_failed",
			"GFSceneUtility failed to load a scene.",
			{
				"category": &"scene",
				"component": &"scene_router",
				"recoverable": true,
				"metadata": {"path": path},
			}
		)
	_finish_scene_change_operation(false, {"path": path, "reason": "load_failed"})
	_play_scene_transition_reveal()
	send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)


func _on_transition_tween_finished(tween: Tween, tracking_id: int) -> void:
	if tracking_id > 0 and is_instance_valid(_async_tracker):
		var _untracked: bool = _async_tracker.untrack_id(tracking_id)
	if _transition_tracking_id == tracking_id:
		_transition_tracking_id = 0
	if _transition_tween == tween:
		_transition_tween = null
