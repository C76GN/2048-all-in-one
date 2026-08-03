## SceneRouterSystem: 负责全局场景路由并编排 GF 场景加载与屏幕转场。
##
## 业务模块只提交路由意图；GFSceneUtility 管理加载事务，
## GFScreenTransitionUtility 管理覆盖层生命周期和效果推进。
class_name SceneRouterSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _LOG_TAG: String = "SceneRouterSystem"
const _TRANSITION_MINIMUM_SECONDS: float = 0.30
const _DEFAULT_TRANSITION_TIMEOUT_SECONDS: float = 5.0
const _QUIT_SHUTDOWN_TIMEOUT_SECONDS: float = 10.0


# --- 私有变量 ---

## 缓存当前主菜单场景的路径，用于快速返回。
var _main_menu_scene_path: String = "res://features/navigation/scenes/menus/main_menu.tscn"
var _log: GFLogUtility
var _scene_utility: GFSceneUtility
var _screen_transition: GFScreenTransitionUtility
var _shader_parameters: GFShaderParameterUtility
var _theme_utility: GameThemeUtility
var _accessibility: GameAccessibilityUtility
var _platform_utility: GamePlatformUtility
var _signal_utility: GFSignalUtility
var _operation_diagnostics: GFOperationDiagnosticsUtility
var _scene_switch_started_connection: GFSignalConnection
var _scene_switch_completed_connection: GFSignalConnection
var _scene_switch_failed_connection: GFSignalConnection
var _scene_change_operation_id: StringName = &""
var _active_scene_request: _SceneChangeRequest = null
var _next_scene_request_id: int = 1
var _transition_timeout_seconds: float = _DEFAULT_TRANSITION_TIMEOUT_SECONDS
var _quit_requested: bool = false
var _quit_completion: GFAsyncCompletion = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameThemeUtility,
		GameAccessibilityUtility,
		GamePlatformUtility,
		GFLogUtility,
		GFOperationDiagnosticsUtility,
		GFSceneUtility,
		GFScreenTransitionUtility,
		GFShaderParameterUtility,
		GFSignalUtility,
	]


func ready() -> void:
	_quit_requested = false
	_quit_completion = null
	_log = _get_log_utility()
	_scene_utility = _get_scene_utility()
	_screen_transition = _get_screen_transition_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_theme_utility = _get_theme_utility()
	_accessibility = _get_accessibility_utility()
	_platform_utility = _get_platform_utility()
	_signal_utility = _get_signal_utility()
	_operation_diagnostics = _get_operation_diagnostics_utility()
	if not _has_required_dependencies():
		return
	_connect_scene_utility_signals()

	register_simple_event(EventNames.SCENE_CHANGE_REQUESTED, GFEventListener.from_method(self, &"_on_scene_change_requested", 1))
	register_simple_event(EventNames.RETURN_TO_MAIN_MENU_REQUESTED, GFEventListener.from_method(self, &"_on_return_to_main_menu_requested", 1))


func dispose() -> void:
	var _cancelled_request: bool = _cancel_active_scene_request(
		&"system_disposed",
		{"reason": "system_disposed"}
	)
	_cancel_screen_transition_and_hide()
	_disconnect_scene_utility_signals()
	_scene_utility = null
	_screen_transition = null
	_shader_parameters = null
	_theme_utility = null
	_accessibility = null
	_platform_utility = null
	_signal_utility = null
	_operation_diagnostics = null
	_log = null
	_scene_switch_started_connection = null
	_scene_switch_completed_connection = null
	_scene_switch_failed_connection = null


# --- 公共方法 ---

## 切换到指定的场景资源。
## @param scene: 待切换的场景资源 (PackedScene)。
func goto_scene_packed(scene: PackedScene) -> void:
	var _scene_change: GFAsyncCompletion = request_scene_change_packed(scene)


## 提交可观测的 PackedScene 场景切换请求。
## @param scene: 待切换的场景资源。
## @param owner: 可选请求 owner；Node 在 GF 接管前退出场景树时取消请求。
## @return 本次路由的一次性成功、失败或取消终态。
func request_scene_change_packed(
	scene: PackedScene,
	owner: Object = null
) -> GFAsyncCompletion:
	if not _is_scene_resource_ready(scene):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "传入的场景资源为空或不可实例化。")
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, _get_scene_resource_path(scene))
		return _make_failed_scene_completion(
			_get_scene_resource_path(scene),
			&"invalid_scene_resource",
			ERR_INVALID_DATA
		)

	if scene.resource_path.is_empty():
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "PackedScene 缺少稳定资源路径，无法交给 GFSceneUtility。")
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, scene.resource_path)
		return _make_failed_scene_completion(
			scene.resource_path,
			&"unstable_scene_path",
			ERR_INVALID_PARAMETER
		)
	return request_scene_change(scene.resource_path, owner)


## 使用 GFSceneTransitionConfig 切换到指定场景路径。
## @param path: 待切换的场景资源路径。
func goto_scene(path: String) -> void:
	var _scene_change: GFAsyncCompletion = request_scene_change(path)


## 提交可观测的场景路径切换请求。
## @param path: 待切换的绝对 .tscn 资源路径。
## @param owner: 可选请求 owner；Node 在 GF 接管前退出场景树时取消请求。
## @return 本次路由的一次性成功、失败或取消终态。
func request_scene_change(
	path: String,
	owner: Object = null
) -> GFAsyncCompletion:
	if not _is_valid_scene_path(path):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "场景路径必须是绝对的 .tscn 资源路径: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return _make_failed_scene_completion(
			path,
			&"invalid_scene_path",
			ERR_INVALID_PARAMETER
		)

	if not is_instance_valid(_scene_utility):
		if is_instance_valid(_log):
			_log.error(_LOG_TAG, "GFSceneUtility 未注册，无法执行场景切换: %s" % path)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, path)
		return _make_failed_scene_completion(
			path,
			&"scene_utility_unavailable",
			ERR_UNCONFIGURED
		)

	var active_request: _SceneChangeRequest = _get_active_scene_request()
	if active_request != null:
		if (
			active_request.accepted_by_scene_utility
			or active_request.completion_queued
		):
			push_warning(
				"[SceneRouterSystem] 场景切换已由 GF 接管或正在收敛终态，拒绝并发请求：%s。"
				% path
			)
			return _make_failed_scene_completion(
				path,
				&"scene_change_busy",
				ERR_BUSY,
				{"active_path": active_request.path}
			)
		var _cancelled_request: bool = _cancel_active_scene_request(
			&"superseded",
			{
				"reason": "superseded",
				"replacement_path": path,
			}
		)
		_cancel_screen_transition_and_hide()

	var preload_error: Error = prime_scene(path)
	if preload_error != OK and is_instance_valid(_log):
		_log.warn(
			_LOG_TAG,
			"GF 场景预加载未能提前启动，将由正式切换继续尝试。错误码: %d，路径: %s"
			% [preload_error, path]
		)
	var request: _SceneChangeRequest = _create_scene_request(path, owner)
	_active_scene_request = request
	_begin_scene_change_operation(path)
	call_deferred(&"_run_scene_change", request.request_id)
	return request.completion


## 提前把场景交给 GFSceneUtility 的线程化缓存。
##
## 可由焦点/悬停等导航意图调用；重复请求由 GF 按资源身份去重。场景只进入
## 临时 LRU，不使用 fixed 缓存，避免低频页面永久驻留。
## @param path: 待准备的绝对 .tscn 资源路径。
## @return GFSceneUtility 发起或复用请求的错误码。
func prime_scene(path: String) -> Error:
	if not _is_valid_scene_path(path):
		return ERR_INVALID_PARAMETER
	if not is_instance_valid(_scene_utility):
		return ERR_UNCONFIGURED
	return _scene_utility.preload_scene(path, false)


## 快速返回到主菜单。
func return_to_main_menu() -> void:
	goto_scene(_main_menu_scene_path)


## 静默并关闭当前 GF 架构后退出整个游戏；重复调用共享同一终态。
## @return 架构关闭完成或失败后抵达终态的一次性完成源。
func quit_game() -> GFAsyncCompletion:
	if _quit_requested and _quit_completion != null:
		return _quit_completion
	_quit_requested = true
	_quit_completion = GFAsyncCompletion.new()
	if is_instance_valid(_log):
		_log.info(_LOG_TAG, "正在退出游戏。")
	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree):
		var _failed_tree: bool = _quit_completion.fail(
			"SceneTree is unavailable for application quit."
		)
		return _quit_completion
	var architecture: GFArchitecture = _get_architecture_or_null()
	call_deferred(
		&"_shutdown_architecture_then_quit",
		architecture,
		tree,
		_quit_completion
	)
	return _quit_completion


## 返回场景路由与 GF 转场服务的诊断快照。
func get_debug_snapshot() -> Dictionary:
	var active_request: _SceneChangeRequest = _get_active_scene_request()
	return {
		"main_menu_scene_path": _main_menu_scene_path,
		"scene_change_active": active_request != null,
		"pending_scene_path": active_request.path if active_request != null else "",
		"scene_change_request_id": (
			active_request.request_id
			if active_request != null
			else 0
		),
		"scene_change_accepted_by_gf": (
			active_request.accepted_by_scene_utility
			if active_request != null
			else false
		),
		"scene_change_completion": (
			active_request.completion.get_debug_snapshot()
			if active_request != null
			else {}
		),
		"scene_change_started_usec": _get_scene_change_started_usec(),
		"screen_transition": (
			_screen_transition.get_debug_snapshot()
			if is_instance_valid(_screen_transition)
			else {}
		),
		"quit_requested": _quit_requested,
	}


# --- 私有/辅助方法 ---

func _shutdown_architecture_then_quit(
	architecture: GFArchitecture,
	tree: SceneTree,
	completion: GFAsyncCompletion
) -> void:
	# 关闭流程会 dispose 当前 System；await 后只使用捕获的局部引用，
	# 不再读取任何已释放的依赖或成员状态。
	# coroutine 栈显式强持有路由 owner；架构 registry 在 await 期间会释放它，
	# 不能依赖 Callable 对 RefCounted target 的保留语义。
	var quit_owner: SceneRouterSystem = self
	var shutdown_result: GFArchitectureShutdownResult = null
	if architecture != null:
		shutdown_result = await architecture.shutdown_async(
			null,
			_QUIT_SHUTDOWN_TIMEOUT_SECONDS
		)
	# completion 的语义覆盖“架构已关闭且退出请求已交给 SceneTree”；先发出
	# quit 再 settle，避免 await 调用方恢复时观察到尚未执行的退出动作。
	if is_instance_valid(tree) and is_instance_valid(quit_owner):
		quit_owner._quit_scene_tree(tree)
	if completion != null and completion.is_pending():
		if shutdown_result == null or shutdown_result.is_successful():
			var _succeeded: bool = completion.succeed({
				&"shutdown": (
					shutdown_result.to_dict()
					if shutdown_result != null
					else {&"skipped": true}
				),
			})
		else:
			var _failed_shutdown: bool = completion.fail(
				"GF architecture shutdown required forced or failed disposal.",
				{&"shutdown": shutdown_result.to_dict()}
			)


func _quit_scene_tree(tree: SceneTree) -> void:
	tree.quit()


func _run_scene_change(request_id: int) -> void:
	var request: _SceneChangeRequest = _get_scene_request(request_id)
	if request == null:
		return
	var cover_error: Error = _play_scene_transition_cover()
	if cover_error == OK:
		await _await_screen_transition()
	request = _get_scene_request(request_id)
	if request == null:
		return

	send_simple_event(EventNames.SCENE_WILL_CHANGE)
	var config: GFSceneTransitionConfig = _make_scene_transition_config(request.path)
	request.accepted_by_scene_utility = true
	var error: Error = _scene_utility.load_scene_with_transition(config)
	if error == OK:
		return

	request.accepted_by_scene_utility = false
	if is_instance_valid(_log):
		_log.error(
			_LOG_TAG,
			"GFSceneUtility 拒绝场景切换，错误码: %d，路径: %s"
			% [error, request.path]
		)
	_queue_scene_change_completion(
		request.request_id,
		false,
		error,
		"GFSceneUtility rejected the scene change."
	)

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


func _get_accessibility_utility() -> GameAccessibilityUtility:
	var utility_value: Object = get_utility(GameAccessibilityUtility)
	if utility_value is GameAccessibilityUtility:
		var accessibility: GameAccessibilityUtility = utility_value
		return accessibility
	return null


func _get_platform_utility() -> GamePlatformUtility:
	var utility_value: Object = get_utility(GamePlatformUtility)
	if utility_value is GamePlatformUtility:
		var platform_utility: GamePlatformUtility = utility_value
		return platform_utility
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


func _has_required_dependencies() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not is_instance_valid(_scene_utility):
		var _scene_appended: bool = missing.append("GFSceneUtility")
	if not is_instance_valid(_screen_transition):
		var _transition_appended: bool = missing.append("GFScreenTransitionUtility")
	if not is_instance_valid(_shader_parameters):
		var _shader_appended: bool = missing.append("GFShaderParameterUtility")
	if not is_instance_valid(_theme_utility):
		var _theme_appended: bool = missing.append("GameThemeUtility")
	if not is_instance_valid(_accessibility):
		var _accessibility_appended: bool = missing.append("GameAccessibilityUtility")
	if not is_instance_valid(_platform_utility):
		var _platform_appended: bool = missing.append("GamePlatformUtility")
	if not is_instance_valid(_signal_utility):
		var _signal_appended: bool = missing.append("GFSignalUtility")
	if not is_instance_valid(_operation_diagnostics):
		var _diagnostics_appended: bool = missing.append(
			"GFOperationDiagnosticsUtility"
		)
	if missing.is_empty():
		return true
	push_error("[SceneRouterSystem] 缺少必需架构依赖：%s。" % ", ".join(missing))
	return false


func _get_scene_tree() -> SceneTree:
	var loop_value: MainLoop = Engine.get_main_loop()
	if loop_value is SceneTree:
		var tree: SceneTree = loop_value
		return tree
	return null


func _is_valid_scene_path(path: String) -> bool:
	return path.begins_with("res://") and path.ends_with(".tscn")


func _connect_scene_utility_signals() -> void:
	if not is_instance_valid(_scene_utility) or not is_instance_valid(_signal_utility):
		return

	_scene_switch_started_connection = _signal_utility.connect_signal(
		_scene_utility.scene_switch_started,
		_on_scene_switch_started,
		self
	)
	_scene_switch_completed_connection = _signal_utility.connect_signal(
		_scene_utility.scene_switch_completed,
		_on_scene_switch_completed,
		self
	)
	_scene_switch_failed_connection = _signal_utility.connect_signal(
		_scene_utility.scene_switch_failed,
		_on_scene_switch_failed,
		self
	)


func _disconnect_scene_utility_signals() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


func _is_scene_resource_ready(scene: PackedScene) -> bool:
	return scene != null and scene.can_instantiate()


func _get_scene_resource_path(scene: PackedScene) -> String:
	return scene.resource_path if scene != null else ""


func _create_scene_request(path: String, owner: Object) -> _SceneChangeRequest:
	var request: _SceneChangeRequest = _SceneChangeRequest.new(
		_next_scene_request_id,
		path
	)
	_next_scene_request_id += 1
	var cleanup_registered: bool = request.scope.register_cleanup(
		Callable(self, &"_on_scene_request_scope_cancelled").bind(
			request.request_id
		)
	)
	if not cleanup_registered:
		push_error("[SceneRouterSystem] 无法注册场景请求取消清理：%s。" % path)
	if is_instance_valid(owner):
		request.owner_lifetime = GFLifetimeSubscription.new(
			owner,
			Callable(self, &"_on_scene_request_owner_released").bind(
				request.request_id
			),
			"scene_route:%d" % request.request_id
		)
	return request


func _get_active_scene_request() -> _SceneChangeRequest:
	if _active_scene_request == null:
		return null
	if not _active_scene_request.completion.is_pending():
		return null
	return _active_scene_request


func _get_scene_request(request_id: int) -> _SceneChangeRequest:
	var request: _SceneChangeRequest = _get_active_scene_request()
	if request == null or request.request_id != request_id:
		return null
	return request


func _get_scene_request_for_path(path: String) -> _SceneChangeRequest:
	var request: _SceneChangeRequest = _get_active_scene_request()
	if request == null or request.path != path:
		return null
	return request


func _make_failed_scene_completion(
	path: String,
	reason: StringName,
	error: Error,
	extra_metadata: Dictionary = {}
) -> GFAsyncCompletion:
	var completion: GFAsyncCompletion = GFAsyncCompletion.new()
	var metadata: Dictionary = extra_metadata.duplicate(true)
	metadata["path"] = path
	metadata["reason"] = reason
	metadata["error"] = error
	var _failed: bool = completion.fail(String(reason), metadata)
	return completion


func _cancel_active_scene_request(
	reason: StringName,
	metadata: Dictionary = {}
) -> bool:
	var request: _SceneChangeRequest = _get_active_scene_request()
	if request == null or not request.scope.is_active():
		return false
	return request.scope.cancel(String(reason), metadata)


func _on_scene_request_scope_cancelled(request_id: int) -> void:
	var request: _SceneChangeRequest = _get_scene_request(request_id)
	if request == null:
		return
	_active_scene_request = null
	_finish_scene_change_operation(false, {
		"path": request.path,
		"reason": request.scope.get_cancel_reason(),
		"cancelled": true,
	})
	_release_scene_request_owner_lifetime(request)
	var completion_metadata: Dictionary = (
		request.scope.get_cancel_metadata()
	)
	completion_metadata["path"] = request.path
	completion_metadata["reason"] = request.scope.get_cancel_reason()
	var _cancelled: bool = request.completion.cancel(
		request.scope.get_cancel_reason(),
		completion_metadata,
		{"path": request.path}
	)


func _on_scene_request_owner_released(request_id: int) -> void:
	var request: _SceneChangeRequest = _get_scene_request(request_id)
	if (
		request == null
		or request.accepted_by_scene_utility
		or request.completion_queued
	):
		return
	var _cancelled: bool = request.scope.cancel(
		"owner_released",
		{
			"path": request.path,
			"reason": "owner_released",
		}
	)


func _finish_scene_request_success(request: _SceneChangeRequest) -> void:
	if request == null or _get_scene_request(request.request_id) == null:
		return
	request.scope.complete()
	_active_scene_request = null
	_finish_scene_change_operation(true, {"path": request.path})
	_release_scene_request_owner_lifetime(request)
	var _succeeded: bool = request.completion.succeed(
		{"path": request.path},
		{
			"path": request.path,
			"reason": &"scene_switch_completed",
		}
	)


func _finish_scene_request_failure(
	request: _SceneChangeRequest,
	reason: StringName,
	error: Error,
	error_message: String = ""
) -> void:
	if request == null or _get_scene_request(request.request_id) == null:
		return
	request.scope.complete()
	_active_scene_request = null
	var metadata: Dictionary = {
		"path": request.path,
		"reason": reason,
		"error": error,
	}
	if not error_message.is_empty():
		metadata["message"] = error_message
	_finish_scene_change_operation(false, metadata)
	_release_scene_request_owner_lifetime(request)
	var _failed: bool = request.completion.fail(String(reason), metadata)


func _release_scene_request_owner_lifetime(
	request: _SceneChangeRequest
) -> void:
	if request == null or request.owner_lifetime == null:
		return
	if request.owner_lifetime.is_active():
		var _cancelled: bool = request.owner_lifetime.cancel()
	request.owner_lifetime = null


func _cancel_screen_transition_and_hide() -> void:
	if not is_instance_valid(_screen_transition):
		return
	if _screen_transition.is_transition_active():
		var _cancelled: bool = _screen_transition.cancel_transition()
	_screen_transition.hide_overlay()


func _make_scene_transition_config(path: String) -> GFSceneTransitionConfig:
	var config: GFSceneTransitionConfig = GFSceneTransitionConfig.new()
	config.target_scene_path = path
	# goto_scene() 已在覆盖转场开始前显式 prime；GFSceneUtility.load_scene_async()
	# 会直接复用该缓存或 in-flight 请求。这里再次要求 preload 会产生第二次
	# admission/查找，因此只保留正式切换阶段的复用语义。
	config.preload_before_change = false
	config.preload_as_fixed_cache = false
	config.cache_loaded_scene = true
	config.minimum_duration_seconds = (
		0.0 if _is_reduced_motion() else _TRANSITION_MINIMUM_SECONDS
	)
	config.metadata = {
		"source": &"scene_router",
		"path": path,
	}
	return config


func _play_scene_transition_cover() -> Error:
	return _play_scene_transition(&"cover")


func _play_scene_transition_reveal() -> Error:
	return _play_scene_transition(&"reveal")


func _play_scene_transition(phase: StringName) -> Error:
	if not is_instance_valid(_screen_transition):
		_log_transition_error("GFScreenTransitionUtility 未注册，无法播放 %s 转场。" % phase)
		return ERR_UNCONFIGURED

	var effect: GFScreenTransitionEffect = _resolve_scene_transition_effect(phase)
	if effect == null:
		_log_transition_error("当前主题未配置 %s 场景转场。" % phase)
		return ERR_DOES_NOT_EXIST

	var on_finished: Callable = Callable()
	if phase == &"reveal":
		on_finished = Callable(_screen_transition, &"hide_overlay")
	var error: Error = _screen_transition.play(effect, on_finished)
	if error != OK:
		_log_transition_error("GFScreenTransitionUtility 启动 %s 转场失败，错误码: %d。" % [phase, error])
	return error


func _await_screen_transition() -> bool:
	if not is_instance_valid(_screen_transition):
		return false
	if not _screen_transition.is_transition_active():
		return true
	var tree: SceneTree = _get_scene_tree()
	var wait_result: Dictionary = await GFAsyncWaitUtility.wait_while(
		Callable(_screen_transition, &"is_transition_active"),
		{
			"tree": tree,
			"timeout_seconds": _transition_timeout_seconds,
			"respect_time_scale": false,
			"timeout_warning": "[SceneRouterSystem] 屏幕转场等待超时。",
		}
	)
	if GFVariantData.get_option_bool(wait_result, "completed", false):
		return true
	if is_instance_valid(_screen_transition):
		var _cancelled: bool = _screen_transition.cancel_transition()
		_screen_transition.hide_overlay()
	_log_transition_warning(
		"屏幕转场未进入终态，已解除覆盖层。status=%s"
		% String(GFVariantData.get_option_string_name(wait_result, "status"))
	)
	return false


func _queue_scene_change_completion(
	request_id: int,
	success: bool,
	error: Error = OK,
	error_message: String = ""
) -> void:
	var request: _SceneChangeRequest = _get_scene_request(request_id)
	if request == null or request.completion_queued:
		return
	request.completion_queued = true
	call_deferred(
		&"_complete_scene_change",
		request.request_id,
		success,
		error,
		error_message
	)


func _complete_scene_change(
	request_id: int,
	success: bool,
	error: Error,
	error_message: String
) -> void:
	var request: _SceneChangeRequest = _get_scene_request(request_id)
	if request == null:
		return
	var tree: SceneTree = _get_scene_tree()
	if success and is_instance_valid(tree):
		await tree.process_frame
		request = _get_scene_request(request_id)
		if request == null:
			return
		if (
			is_instance_valid(_platform_utility)
			and not _platform_utility.is_headless_runtime()
		):
			await RenderingServer.frame_post_draw
			request = _get_scene_request(request_id)
			if request == null:
				return

	var reveal_error: Error = _play_scene_transition_reveal()
	if reveal_error == OK:
		await _await_screen_transition()
	request = _get_scene_request(request_id)
	if request == null:
		return

	if success:
		if is_instance_valid(_log):
			_log.debug(_LOG_TAG, "已完成异步场景加载与揭示: %s" % request.path)
		_finish_scene_request_success(request)
	else:
		_finish_scene_request_failure(
			request,
			&"scene_switch_failed",
			error,
			error_message
		)
		send_simple_event(EventNames.SCENE_CHANGE_FAILED, request.path)


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
	if _is_reduced_motion():
		effect.duration_seconds = 0.0
		effect.shader_material = null
		return effect
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


func _is_reduced_motion() -> bool:
	if not is_instance_valid(_accessibility):
		_accessibility = _get_accessibility_utility()
	return (
		is_instance_valid(_accessibility)
		and _accessibility.get_state().reduced_motion
	)


func _log_transition_error(message: String) -> void:
	if is_instance_valid(_log):
		_log.error(_LOG_TAG, message)
		return
	push_error("[%s] %s" % [_LOG_TAG, message])


func _log_transition_warning(message: String) -> void:
	if is_instance_valid(_log):
		_log.warn(_LOG_TAG, message)
		return
	push_warning("[%s] %s" % [_LOG_TAG, message])


func _begin_scene_change_operation(path: String) -> void:
	_finish_scene_change_operation(false, {"reason": "superseded"})
	if not is_instance_valid(_operation_diagnostics):
		return
	_scene_change_operation_id = _operation_diagnostics.begin_operation(&"game.scene_change", {
		"component": &"scene_router",
		"label": "Load scene",
		"metadata": {"path": path},
	})


func _get_scene_change_started_usec() -> int:
	if _scene_change_operation_id == &"" or not is_instance_valid(_operation_diagnostics):
		return 0
	var operation: Dictionary = _operation_diagnostics.get_operation(_scene_change_operation_id)
	return GFVariantData.get_option_int(operation, "started_ticks_usec", 0)


func _finish_scene_change_operation(success: bool, metadata: Dictionary = {}) -> void:
	if _scene_change_operation_id != &"" and is_instance_valid(_operation_diagnostics):
		var _operation: Dictionary = _operation_diagnostics.finish_operation(
			_scene_change_operation_id,
			success,
			{"metadata": metadata}
		)
	_scene_change_operation_id = &""


# --- 信号处理函数 ---

func _on_scene_change_requested(scene: PackedScene) -> void:
	goto_scene_packed(scene)


func _on_return_to_main_menu_requested(_payload: Variant = null) -> void:
	return_to_main_menu()


func _on_scene_switch_started(path: String, previous_path: String) -> void:
	var request: _SceneChangeRequest = _get_scene_request_for_path(path)
	if request == null:
		return
	if _scene_change_operation_id != &"" and is_instance_valid(_operation_diagnostics):
		var _state: Dictionary = _operation_diagnostics.record_state_snapshot(
			_scene_change_operation_id,
			&"loading",
			GFOperationDiagnosticsUtility.STATE_RUNNING,
			{"progress": 0.1, "metadata": {"path": path, "previous_path": previous_path}}
		)


func _on_scene_switch_completed(path: String, _previous_path: String) -> void:
	var request: _SceneChangeRequest = _get_scene_request_for_path(path)
	if request == null:
		return
	var started_ticks_usec: int = _get_scene_change_started_usec()
	if started_ticks_usec > 0:
		var _phase: Dictionary = _operation_diagnostics.record_phase_from_ticks(
			_scene_change_operation_id,
			&"load",
			started_ticks_usec,
			{"metadata": {"path": path}}
		)
	_queue_scene_change_completion(request.request_id, true)


func _on_scene_switch_failed(
	path: String,
	_previous_path: String,
	message: String
) -> void:
	var request: _SceneChangeRequest = _get_scene_request_for_path(path)
	if request == null:
		return
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
	_queue_scene_change_completion(
		request.request_id,
		false,
		ERR_CANT_OPEN,
		message
	)


# --- 子类（Subclasses） ---

## 单次场景切换请求。
##
## 把路径、一次性终态、生命周期作用域和 GF 接管状态约束在同一个身份中，
## 避免跨 await 与全局 Signal 仅依赖可变路径/布尔值关联不同请求。
class _SceneChangeRequest extends RefCounted:
	var request_id: int = 0
	var path: String = ""
	var completion: GFAsyncCompletion = GFAsyncCompletion.new()
	var scope: GFAsyncScope = GFAsyncScope.new()
	var owner_lifetime: GFLifetimeSubscription = null
	var accepted_by_scene_utility: bool = false
	var completion_queued: bool = false

	func _init(next_request_id: int, target_path: String) -> void:
		request_id = next_request_id
		path = target_path
