## SceneRouterSystem: 负责全局场景路由并编排 GF 场景加载与屏幕转场。
##
## 业务模块只提交路由意图；GFSceneUtility 管理加载事务，
## GFScreenTransitionUtility 管理覆盖层生命周期和效果推进。
class_name SceneRouterSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "SceneRouterSystem"
const _TRANSITION_MINIMUM_SECONDS: float = 0.30


# --- 私有变量 ---

## 缓存当前主菜单场景的路径，用于快速返回。
var _main_menu_scene_path: String = "res://scenes/menus/main_menu.tscn"
var _log: GFLogUtility
var _scene_utility: GFSceneUtility
var _screen_transition: GFScreenTransitionUtility
var _shader_parameters: GFShaderParameterUtility
var _theme_utility: GameThemeUtility
var _signal_utility: GFSignalUtility
var _operation_diagnostics: GFOperationDiagnosticsUtility
var _scene_switch_started_connection: GFSignalConnection
var _scene_load_completed_connection: GFSignalConnection
var _scene_load_failed_connection: GFSignalConnection
var _scene_change_operation_id: StringName = &""
var _scene_change_started_usec: int = 0


# --- GF 生命周期方法 ---

func ready() -> void:
	_log = _get_log_utility()
	_scene_utility = _get_scene_utility()
	_screen_transition = _get_screen_transition_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_theme_utility = _get_theme_utility()
	_signal_utility = _get_signal_utility()
	_operation_diagnostics = _get_operation_diagnostics_utility()
	_connect_scene_utility_signals()

	register_simple_event(EventNames.SCENE_CHANGE_REQUESTED, GFEventListener.from_method(self, &"_on_scene_change_requested", 1))
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, GFEventListener.from_method(self, &"_on_return_to_main_menu_requested", 1))


func dispose() -> void:
	_finish_scene_change_operation(false, {"reason": "system_disposed"})
	_disconnect_scene_utility_signals()
	_scene_utility = null
	_screen_transition = null
	_shader_parameters = null
	_theme_utility = null
	_signal_utility = null
	_operation_diagnostics = null
	_log = null
	_scene_switch_started_connection = null
	_scene_load_completed_connection = null
	_scene_load_failed_connection = null


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

	var error: Error = tree.change_scene_to_packed(scene)
	if error != OK:
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "切换到场景失败，错误码: %d" % error)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return
	if is_instance_valid(_log):
		_log.debug(_LOG_TAG, "已请求切换到场景: %s" % scene.resource_path)


## 使用 GFSceneTransitionConfig 切换到指定场景路径。
## @param path: 待切换的场景资源路径。
func goto_scene(path: String) -> void:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "场景路径必须是绝对的 .tscn 资源路径: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	if not is_instance_valid(_scene_utility):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GFSceneUtility 未注册，无法执行场景切换: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return

	_begin_scene_change_operation(path)
	var config: GFSceneTransitionConfig = _make_scene_transition_config(path)
	var error: Error = _scene_utility.load_scene_with_transition(config)
	if error == OK:
		return

	_finish_scene_change_operation(false, {"path": path, "error": error})
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, "GFSceneUtility 拒绝场景切换，错误码: %d，路径: %s" % [error, path])
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


## 返回场景路由与 GF 转场服务的诊断快照。
func get_debug_snapshot() -> Dictionary:
	return {
		"main_menu_scene_path": _main_menu_scene_path,
		"scene_change_active": _scene_change_operation_id != &"",
		"scene_change_started_usec": _scene_change_started_usec,
		"screen_transition": (
			_screen_transition.get_debug_snapshot()
			if is_instance_valid(_screen_transition)
			else {}
		),
	}


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


func _get_screen_transition_utility() -> GFScreenTransitionUtility:
	var utility_value: Object = get_utility(GFScreenTransitionUtility)
	if utility_value is GFScreenTransitionUtility:
		var transition_utility: GFScreenTransitionUtility = utility_value
		return transition_utility
	return null


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		var shader_utility: GFShaderParameterUtility = utility_value
		return shader_utility
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = get_utility(GameThemeUtility)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
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
		var _connect_started_result: int = _scene_utility.scene_switch_started.connect(_on_scene_switch_started)
	if not _scene_utility.scene_load_completed.is_connected(_on_scene_load_completed):
		var _connect_completed_result: int = _scene_utility.scene_load_completed.connect(_on_scene_load_completed)
	if not _scene_utility.scene_load_failed.is_connected(_on_scene_load_failed):
		var _connect_failed_result: int = _scene_utility.scene_load_failed.connect(_on_scene_load_failed)


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


func _make_scene_transition_config(path: String) -> GFSceneTransitionConfig:
	var config: GFSceneTransitionConfig = GFSceneTransitionConfig.new()
	config.target_scene_path = path
	config.cache_loaded_scene = true
	config.minimum_duration_seconds = _TRANSITION_MINIMUM_SECONDS
	config.metadata = {
		"source": &"scene_router",
		"path": path,
	}
	return config


func _play_scene_transition_cover() -> void:
	_play_scene_transition(&"cover")


func _play_scene_transition_reveal() -> void:
	_play_scene_transition(&"reveal")


func _play_scene_transition(phase: StringName) -> void:
	if not is_instance_valid(_screen_transition):
		_log_transition_error("GFScreenTransitionUtility 未注册，无法播放 %s 转场。" % phase)
		return

	var effect: GFScreenTransitionEffect = _resolve_scene_transition_effect(phase)
	if effect == null:
		_log_transition_error("当前主题未配置 %s 场景转场。" % phase)
		return

	var on_finished: Callable = Callable()
	if phase == &"reveal":
		on_finished = Callable(_screen_transition, &"hide_overlay")
	var error: Error = _screen_transition.play(effect, on_finished)
	if error != OK:
		_log_transition_error("GFScreenTransitionUtility 启动 %s 转场失败，错误码: %d。" % [phase, error])


func _resolve_scene_transition_effect(phase: StringName) -> GFScreenTransitionEffect:
	if not is_instance_valid(_theme_utility):
		return null
	var theme: GameTheme = _theme_utility.get_current_visual_theme()
	if theme == null:
		return null
	var configured_effect: GFScreenTransitionEffect = theme.get_scene_transition_effect(phase)
	if configured_effect == null:
		return null

	var effect: GFScreenTransitionEffect = configured_effect.duplicate_effect()
	effect.metadata["phase"] = phase
	effect.metadata["theme_id"] = theme.theme_id
	if effect.shader_material != null:
		if not is_instance_valid(_shader_parameters):
			_shader_parameters = _get_shader_parameter_utility()
		if not is_instance_valid(_shader_parameters):
			_log_transition_error("GFShaderParameterUtility 未注册，无法同步转场分辨率。")
			return null
		var applied_count: int = _shader_parameters.apply_parameters(
			effect.shader_material,
			{&"node_resolution": _get_transition_resolution()},
			{
				"require_declared_parameters": true,
				"warn_on_invalid_target": true,
				"warn_on_missing_parameters": true,
				"copy_values": true,
			}
		)
		if applied_count != 1:
			_log_transition_error("主题转场 shader 缺少 node_resolution 参数。")
			return null
	return effect


func _get_transition_resolution() -> Vector2:
	var tree: SceneTree = _get_scene_tree()
	if is_instance_valid(tree) and is_instance_valid(tree.root):
		var viewport_size: Vector2 = tree.root.get_visible_rect().size
		if viewport_size.x > 0.0 and viewport_size.y > 0.0:
			return viewport_size
	return Vector2(1280.0, 720.0)


func _log_transition_error(message: String) -> void:
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, message)
		return
	push_error("[%s] %s" % [_LOG_TAG, message])


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
