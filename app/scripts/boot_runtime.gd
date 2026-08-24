## BootRuntime: GF、视觉预热与入口场景的正式启动编排器。
##
## 该脚本不创建第二套加载 UI，只把进度推送给父级 Boot 静态壳，保证原生启动图、
## 项目首帧和 GF 初始化阶段保持同一构图。
class_name BootRuntime
extends Control


# --- 常量 ---

const MAIN_MENU_SCENE_PATH: String = "res://features/navigation/scenes/menus/main_menu.tscn"
const PLATFORM_SMOKE_SCENE_PATH: String = "res://features/platform_runtime/scenes/smoke_test/platform_smoke_test.tscn"
const _PLATFORM_SMOKE_FEATURE: String = "platform_smoke"
const _SCENE_PRELOAD_MAP: GFScenePreloadMap = preload("res://features/navigation/resources/scene_preload_map.tres")
const _GAMEPLAY_VISUAL_WARMUP_SCRIPT: GDScript = preload("res://features/game_session/scripts/ui/gameplay_visual_warmup.gd")
const _STARTUP_RENDER_WARMUP_MANIFEST: GFRenderWarmupManifest = preload(
	"res://features/themes/resources/themes/boot/startup_render_warmup_manifest.tres"
)
const _STARTUP_RENDER_CACHE_GROUP: StringName = &"startup.gameplay_visuals"
const _ARCHITECTURE_INSTALLER_TIMING_META: StringName = (
	&"game_architecture_installer_timing"
)
const _MIN_SPLASH_SECONDS: float = 0.30
const _PRELOAD_TIMEOUT_SECONDS: float = 8.0
const _ENTRY_SCENE_FINAL_WAIT_SECONDS: float = 0.20
const _FINISH_DELAY_SECONDS: float = 0.04
const _OUTRO_DURATION_SECONDS: float = 0.18
const _PROGRESS_TASK_PREPARE: StringName = &"prepare"
const _PROGRESS_TASK_ARCHITECTURE: StringName = &"architecture"
const _PROGRESS_TASK_THEMES: StringName = &"themes"
const _PROGRESS_TASK_VISUALS: StringName = &"visuals"
const _PROGRESS_TASK_ENTRY_SCENE: StringName = &"entry_scene"
const _PROGRESS_TASK_FINISH: StringName = &"finish"
const _PROGRESS_WEIGHT_PREPARE: float = 0.10
const _PROGRESS_WEIGHT_ARCHITECTURE: float = 0.32
const _PROGRESS_WEIGHT_THEMES: float = 0.16
const _PROGRESS_WEIGHT_VISUALS: float = 0.10
const _PROGRESS_WEIGHT_ENTRY_SCENE: float = 0.24
const _PROGRESS_WEIGHT_FINISH: float = 0.08


# --- 私有变量 ---

var _startup_progress: GFAsyncProgressAggregator
var _preload_failed: bool = false
var _visual_warmup: GameplayVisualWarmup
var _operation_diagnostics: GFOperationDiagnosticsUtility
var _startup_operation_id: StringName = &""
var _startup_scene_preload_error: Error = ERR_UNCONFIGURED
var _startup_scene_utility: GFSceneUtility
var _architecture_installers_finished_usec: int = -1


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_setup_progress()
	await _run_startup_sequence()


func _exit_tree() -> void:
	_stop_startup_scene_preload_observation()
	_finish_startup_diagnostics(false, &"owner_exited")


# --- 私有/辅助方法 ---

func _run_startup_sequence() -> void:
	var started_msec: int = Time.get_ticks_msec()
	var started_usec: int = Time.get_ticks_usec()
	_complete_startup_task(_PROGRESS_TASK_PREPARE, "准备启动")
	await _await_startup_frame(true)

	_set_startup_task_progress(_PROGRESS_TASK_ARCHITECTURE, 0.25, "初始化 GF 架构")
	await _await_startup_frame(true)
	var architecture_started_usec: int = Time.get_ticks_usec()
	var architecture: GFArchitecture = Gf.create_architecture()
	architecture.strict_dependency_lookup = true
	_architecture_installers_finished_usec = -1
	@warning_ignore("int_as_enum_without_cast")
	var installers_finished_connect_error: Error = architecture.project_installers_finished.connect(
			_on_project_installers_finished,
			CONNECT_ONE_SHOT
		)
	var architecture_ready: bool = await Gf.init()
	if architecture.project_installers_finished.is_connected(
		_on_project_installers_finished
	):
		architecture.project_installers_finished.disconnect(
			_on_project_installers_finished
		)
	if not architecture_ready:
		push_error("[Boot] GF 架构严格初始化失败。")
		_complete_startup_failure("架构初始化失败")
		return
	_begin_startup_diagnostics(started_usec)
	var architecture_finished_usec: int = Time.get_ticks_usec()
	_record_startup_phase(
		&"architecture",
		architecture_started_usec,
		_get_architecture_phase_metadata(
			architecture,
			architecture_started_usec,
			architecture_finished_usec,
			installers_finished_connect_error
		)
	)

	# 入口场景首先取得共享 Broker admission，并与模式、主题及渲染预热并行。
	# 最终路由会复用同一个 in-flight/cache 身份，因此这里不需要阻塞整个启动链。
	var scene_utility: GFSceneUtility = _get_scene_utility()
	if is_instance_valid(scene_utility):
		_start_startup_scene_preload(scene_utility)

	var mode_catalog_started_usec: int = Time.get_ticks_usec()
	var mode_catalog_ready: bool = await _prepare_mode_catalog()
	_record_startup_phase(&"mode_catalog", mode_catalog_started_usec)
	if not mode_catalog_ready:
		push_error("[Boot] 模式配置异步预载未成功完成。")
		_complete_startup_failure("模式配置初始化失败")
		_stop_startup_scene_preload_observation()
		_finish_startup_diagnostics(false, &"mode_catalog_failed")
		return

	_complete_startup_task(_PROGRESS_TASK_ARCHITECTURE, "加载主题资源")
	var themes_started_usec: int = Time.get_ticks_usec()
	var themes_ready: bool = await _prepare_initial_themes()
	_record_startup_phase(&"themes", themes_started_usec)
	if not themes_ready:
		push_error("[Boot] 初始视觉或声音主题激活失败。")
		_complete_startup_failure("主题资源初始化失败")
		_stop_startup_scene_preload_observation()
		_finish_startup_diagnostics(false, &"themes_failed")
		return

	_complete_startup_task(_PROGRESS_TASK_THEMES, "准备视觉资源")
	var visuals_started_usec: int = Time.get_ticks_usec()
	await _prime_gameplay_visuals()
	_record_startup_phase(&"render_warmup", visuals_started_usec)
	_complete_startup_task(_PROGRESS_TASK_VISUALS, "预热入口场景")

	var entry_scene_started_usec: int = Time.get_ticks_usec()
	if is_instance_valid(scene_utility):
		await _settle_startup_scene_preload(scene_utility)
	else:
		_set_startup_task_progress(_PROGRESS_TASK_ENTRY_SCENE, 0.0, "读取入口场景")
		await get_tree().process_frame
		_complete_startup_task(_PROGRESS_TASK_ENTRY_SCENE, "读取入口场景")
	_record_startup_phase(&"entry_scene", entry_scene_started_usec, {
		"preloaded": (
			is_instance_valid(scene_utility)
			and scene_utility.is_scene_preloaded(_get_startup_scene_path())
		),
	})

	_set_startup_task_progress(_PROGRESS_TASK_FINISH, 0.5, "整理入口场景")
	var finish_started_usec: int = Time.get_ticks_usec()
	await _wait_for_minimum_duration(started_msec)
	var _complete_result: bool = _startup_progress.complete_all("启动完成")
	var finish_wait: Dictionary = await GFAsyncWaitUtility.delay_seconds(
		_FINISH_DELAY_SECONDS,
		_get_boot_wait_options()
	)
	if not GFVariantData.get_option_bool(finish_wait, "completed"):
		_stop_startup_scene_preload_observation()
		_finish_startup_diagnostics(false, &"finish_wait_cancelled")
		return
	await _play_startup_outro()
	_record_startup_phase(&"finish", finish_started_usec)
	_finish_startup_diagnostics(true, &"route_handoff")
	_goto_startup_scene()


func _prepare_initial_themes() -> bool:
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if not is_instance_valid(theme_utility):
		return false
	var activated: bool = await theme_utility.ensure_initial_themes_ready()
	return activated and is_inside_tree()


func _prepare_mode_catalog() -> bool:
	var utility_value: Object = Gf.get_utility(GameModeCatalogUtility)
	if not utility_value is GameModeCatalogUtility:
		return false
	var mode_catalog: GameModeCatalogUtility = utility_value
	var session: GFAssetLoadSession = mode_catalog.get_preload_session()
	if not is_instance_valid(session):
		return false
	if not session.is_completed():
		var wait_result: Dictionary = await GFAsyncWaitUtility.wait_until(
			session.is_completed,
			_get_boot_wait_options(_PRELOAD_TIMEOUT_SECONDS)
		)
		if (
			not GFVariantData.get_option_bool(wait_result, "completed", false)
			and not session.is_completed()
		):
			var _rollback_started: bool = mode_catalog.rollback_preload_session(
				&"boot_preload_timeout"
			)
			return false
	var result: GFAssetLoadSessionResult = session.get_result()
	if result == null or not result.is_successful():
		push_error(
			"[Boot] 模式配置 GFAssetLoadSession 未提交：%s。"
			% str(result.to_dict() if result != null else {})
		)
		return false
	return is_inside_tree()


func _prime_gameplay_visuals() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	var warmup_value: Object = _GAMEPLAY_VISUAL_WARMUP_SCRIPT.new()
	if not warmup_value is Node2D:
		push_error("[Boot] 游戏视觉预热脚本必须实例化为 Node2D。")
		return
	if not warmup_value is GameplayVisualWarmup:
		push_error("[Boot] 游戏视觉预热脚本类型与 GameplayVisualWarmup 不一致。")
		return
	var warmup: GameplayVisualWarmup = warmup_value
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if (
		not is_instance_valid(theme_utility)
		or not warmup.configure(theme_utility.get_current_visual_theme())
	):
		push_error("[Boot] 游戏视觉预热无法绑定当前已激活主题。")
		return
	_visual_warmup = warmup
	_visual_warmup.name = "GameplayVisualWarmup"
	add_child(_visual_warmup)
	_visual_warmup.prime()
	_prime_render_resources(_visual_warmup)
	await RenderingServer.frame_post_draw
	_release_visual_warmup()


func _start_startup_scene_preload(scene_utility: GFSceneUtility) -> void:
	_preload_failed = false
	_startup_scene_preload_error = ERR_UNCONFIGURED
	_startup_scene_utility = scene_utility
	_connect_preload_signals(scene_utility)
	_set_startup_task_progress(_PROGRESS_TASK_ENTRY_SCENE, 0.0, "后台预热入口场景")
	var startup_scene_path: String = _get_startup_scene_path()
	# 固定入口先取得 admission；邻居使用临时缓存且排除 fixed 路径，避免重复提交入口。
	_startup_scene_preload_error = scene_utility.preload_scene(startup_scene_path, true)
	if DisplayServer.get_name() != "headless":
		scene_utility.configure_scene_preload_map(_SCENE_PRELOAD_MAP, 1, true)
		# 自动策略负责后续切换；启动期仅并行准备非 fixed 的直接邻居。
		var _preload_plan: Dictionary = scene_utility.preload_scene_map_for(
			startup_scene_path,
			1,
			false
		)
	if _startup_scene_preload_error != OK:
		_set_startup_task_progress(_PROGRESS_TASK_ENTRY_SCENE, 0.0, "入口场景将直接载入")


func _settle_startup_scene_preload(scene_utility: GFSceneUtility) -> void:
	var startup_scene_path: String = _get_startup_scene_path()
	if scene_utility.is_scene_preloaded(startup_scene_path):
		_complete_startup_task(_PROGRESS_TASK_ENTRY_SCENE, "入口场景已预热")
		_disconnect_preload_signals(scene_utility)
		return
	if _startup_scene_preload_error != OK:
		_complete_startup_task(_PROGRESS_TASK_ENTRY_SCENE, "入口场景将直接载入")
		_disconnect_preload_signals(scene_utility)
		return
	var preload_wait: Dictionary = await GFAsyncWaitUtility.wait_until(
		_is_startup_scene_preload_finished.bind(scene_utility),
		_get_boot_wait_options(_ENTRY_SCENE_FINAL_WAIT_SECONDS)
	)
	if is_instance_valid(scene_utility) and scene_utility.is_scene_preloaded(startup_scene_path):
		_complete_startup_task(_PROGRESS_TASK_ENTRY_SCENE, "入口场景已预热")
	else:
		if is_instance_valid(scene_utility):
			var still_preloading: bool = scene_utility.is_scene_preloading(
				startup_scene_path
			)
			var wait_completed: bool = GFVariantData.get_option_bool(
				preload_wait,
				"completed"
			)
			if not wait_completed and still_preloading:
				_record_startup_preload_incomplete(
					&"deferred",
					preload_wait,
					scene_utility
				)
			elif _preload_failed:
				_record_startup_preload_incomplete(
					&"failed",
					preload_wait,
					scene_utility
				)
			elif not still_preloading:
				_record_startup_preload_incomplete(
					&"settled_without_cache",
					preload_wait,
					scene_utility
				)
		_complete_startup_task(_PROGRESS_TASK_ENTRY_SCENE, "入口场景将直接载入")
	_disconnect_preload_signals(scene_utility)


func _wait_for_minimum_duration(started_msec: int) -> void:
	var elapsed_seconds: float = float(Time.get_ticks_msec() - started_msec) / 1000.0
	var remaining_seconds: float = _MIN_SPLASH_SECONDS - elapsed_seconds
	if remaining_seconds <= 0.0:
		await get_tree().process_frame
		return
	var _duration_wait: Dictionary = await GFAsyncWaitUtility.delay_seconds(
		remaining_seconds,
		_get_boot_wait_options()
	)


func _await_startup_frame(wait_for_draw: bool = false) -> void:
	await get_tree().process_frame
	if wait_for_draw and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _is_startup_scene_preload_finished(scene_utility: GFSceneUtility) -> bool:
	var startup_scene_path: String = _get_startup_scene_path()
	return (
		not is_instance_valid(scene_utility)
		or scene_utility.is_scene_preloaded(startup_scene_path)
		or not scene_utility.is_scene_preloading(startup_scene_path)
		or _preload_failed
	)


func _get_boot_wait_options(timeout_seconds: float = 0.0) -> Dictionary:
	var options: Dictionary = {
		"guard_node": self,
		"respect_time_scale": false,
	}
	if timeout_seconds > 0.0:
		options["timeout_seconds"] = timeout_seconds
	return options


func _setup_progress() -> void:
	_startup_progress = GFAsyncProgressAggregator.new()
	_startup_progress.min_delta = 0.0
	_startup_progress.min_interval_msec = 0
	var _prepare_task_index: int = _startup_progress.add_task(
		_PROGRESS_TASK_PREPARE,
		_PROGRESS_WEIGHT_PREPARE
	)
	var _architecture_task_index: int = _startup_progress.add_task(
		_PROGRESS_TASK_ARCHITECTURE,
		_PROGRESS_WEIGHT_ARCHITECTURE
	)
	var _themes_task_index: int = _startup_progress.add_task(
		_PROGRESS_TASK_THEMES,
		_PROGRESS_WEIGHT_THEMES
	)
	var _visuals_task_index: int = _startup_progress.add_task(
		_PROGRESS_TASK_VISUALS,
		_PROGRESS_WEIGHT_VISUALS
	)
	var _entry_scene_task_index: int = _startup_progress.add_task(
		_PROGRESS_TASK_ENTRY_SCENE,
		_PROGRESS_WEIGHT_ENTRY_SCENE
	)
	var _finish_task_index: int = _startup_progress.add_task(
		_PROGRESS_TASK_FINISH,
		_PROGRESS_WEIGHT_FINISH
	)
	_startup_progress.reset()
	var _connect_result: int = _startup_progress.progressed.connect(_on_startup_progressed)
	_set_startup_task_progress(_PROGRESS_TASK_PREPARE, 0.0, "准备启动")


func _set_startup_task_progress(task_key: StringName, value: float, message: String) -> void:
	if _startup_progress == null:
		return
	var _update_result: bool = _startup_progress.set_task_progress_by_key(
		task_key,
		value,
		message
	)


func _complete_startup_task(task_key: StringName, message: String) -> void:
	if _startup_progress == null:
		return
	var _complete_result: bool = _startup_progress.complete_task_by_key(task_key, message)


func _complete_startup_failure(message: String) -> void:
	if _startup_progress == null:
		return
	var _complete_result: bool = _startup_progress.complete_all(message, {
		"failed": true,
	})


func _on_startup_progressed(value: float, message: String, _metadata: Dictionary) -> void:
	var boot_shell: Boot = _get_boot_shell()
	if is_instance_valid(boot_shell):
		boot_shell.set_runtime_progress(clampf(value, 0.0, 1.0), message)


func _on_project_installers_finished() -> void:
	_architecture_installers_finished_usec = Time.get_ticks_usec()


func _get_architecture_phase_metadata(
	architecture: GFArchitecture,
	architecture_started_usec: int,
	architecture_finished_usec: int,
	connect_error: Error
) -> Dictionary:
	var metadata: Dictionary = {
		"installers_signal_connected": connect_error == OK,
	}
	if (
		connect_error != OK
		or _architecture_installers_finished_usec < architecture_started_usec
		or _architecture_installers_finished_usec > architecture_finished_usec
	):
		return metadata
	metadata["installers_duration_ms"] = (
		float(_architecture_installers_finished_usec - architecture_started_usec)
		/ 1000.0
	)
	metadata["lifecycle_duration_ms"] = (
		float(architecture_finished_usec - _architecture_installers_finished_usec)
		/ 1000.0
	)
	var installer_timing_value: Variant = architecture.get_meta(
		_ARCHITECTURE_INSTALLER_TIMING_META,
		{}
	)
	if installer_timing_value is Dictionary:
		var installer_timing: Dictionary = installer_timing_value
		metadata["project_installer"] = installer_timing.duplicate(true)
		var project_started_usec: int = GFVariantData.get_option_int(
			installer_timing,
			"project_install_started_usec",
			-1
		)
		var project_finished_usec: int = GFVariantData.get_option_int(
			installer_timing,
			"project_install_finished_usec",
			-1
		)
		if project_started_usec >= architecture_started_usec:
			metadata["installers_before_project_ms"] = (
				float(project_started_usec - architecture_started_usec) / 1000.0
			)
		if (
			project_finished_usec >= project_started_usec
			and project_finished_usec <= _architecture_installers_finished_usec
		):
			metadata["installers_after_project_ms"] = (
				float(
					_architecture_installers_finished_usec - project_finished_usec
				) / 1000.0
			)
	return metadata


func _connect_preload_signals(scene_utility: GFSceneUtility) -> void:
	if not scene_utility.scene_preload_progress.is_connected(_on_scene_preload_progress):
		var _progress_connect: int = scene_utility.scene_preload_progress.connect(_on_scene_preload_progress)
	if not scene_utility.scene_preload_failed.is_connected(_on_scene_preload_failed):
		var _failed_connect: int = scene_utility.scene_preload_failed.connect(_on_scene_preload_failed)


func _disconnect_preload_signals(scene_utility: GFSceneUtility) -> void:
	if not is_instance_valid(scene_utility):
		if _startup_scene_utility == scene_utility:
			_startup_scene_utility = null
		return
	if scene_utility.scene_preload_progress.is_connected(_on_scene_preload_progress):
		scene_utility.scene_preload_progress.disconnect(_on_scene_preload_progress)
	if scene_utility.scene_preload_failed.is_connected(_on_scene_preload_failed):
		scene_utility.scene_preload_failed.disconnect(_on_scene_preload_failed)
	if _startup_scene_utility == scene_utility:
		_startup_scene_utility = null


func _stop_startup_scene_preload_observation() -> void:
	var scene_utility: GFSceneUtility = _startup_scene_utility
	_startup_scene_utility = null
	if is_instance_valid(scene_utility):
		_disconnect_preload_signals(scene_utility)


func _on_scene_preload_progress(path: String, progress: float) -> void:
	if path == _get_startup_scene_path():
		_set_startup_task_progress(
			_PROGRESS_TASK_ENTRY_SCENE,
			clampf(progress, 0.0, 1.0),
			"预热入口场景"
		)


func _on_scene_preload_failed(path: String) -> void:
	if path == _get_startup_scene_path():
		_preload_failed = true
		var task_index: int = _startup_progress.get_task_index(_PROGRESS_TASK_ENTRY_SCENE)
		var task_snapshot: Dictionary = _startup_progress.get_task_snapshot(task_index)
		_set_startup_task_progress(
			_PROGRESS_TASK_ENTRY_SCENE,
			GFVariantData.get_option_float(task_snapshot, "progress"),
			"入口场景将直接载入"
		)


func _release_visual_warmup() -> void:
	var render_warmup: GFRenderWarmupUtility = _get_render_warmup_utility()
	if is_instance_valid(render_warmup):
		render_warmup.release_cached_resources(_STARTUP_RENDER_CACHE_GROUP)
		render_warmup.release_temporary_render_nodes()
	if is_instance_valid(_visual_warmup):
		_visual_warmup.queue_free()
	_visual_warmup = null


func _prime_render_resources(warmup_root: Node) -> void:
	var render_warmup: GFRenderWarmupUtility = _get_render_warmup_utility()
	if not is_instance_valid(render_warmup):
		push_error("[Boot] 缺少 GFRenderWarmupUtility，无法执行启动渲染预热。")
		return

	var manifest: GFRenderWarmupManifest = render_warmup.build_manifest_from_tree(
		warmup_root,
		{
			"manifest_id": _STARTUP_RENDER_WARMUP_MANIFEST.manifest_id,
			"include_materials": true,
			"include_meshes": true,
			"include_textures": true,
		}
	)
	var _appended_entries: int = manifest.append_manifest(_STARTUP_RENDER_WARMUP_MANIFEST)
	var summary: Dictionary = render_warmup.warmup_manifest_now(
		manifest,
		{
			"touch_mode": GFRenderWarmupUtility.TouchMode.RID_ONLY,
			"keep_cached": true,
			"cache_group": _STARTUP_RENDER_CACHE_GROUP,
			"max_cached_resources": 32,
		}
	)
	if not GFVariantData.get_option_bool(summary, "ok", false):
		push_error("[Boot] 启动渲染预热存在失败条目：%s" % summary)


func _play_startup_outro() -> void:
	var boot_shell: Boot = _get_boot_shell()
	if not is_instance_valid(boot_shell):
		await get_tree().process_frame
		return
	var tween: Tween = boot_shell.create_runtime_outro(_OUTRO_DURATION_SECONDS)
	await tween.finished


func _goto_startup_scene() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if not is_instance_valid(router):
		push_error("[Boot] 缺少 SceneRouterSystem，无法进入入口场景。")
		return
	router.call_deferred("goto_scene", _get_startup_scene_path())


func _get_startup_scene_path() -> String:
	return PLATFORM_SMOKE_SCENE_PATH if OS.has_feature(_PLATFORM_SMOKE_FEATURE) else MAIN_MENU_SCENE_PATH


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = Gf.get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var system: SceneRouterSystem = system_value
		return system
	return null


func _get_scene_utility() -> GFSceneUtility:
	var utility_value: Object = Gf.get_utility(GFSceneUtility)
	if utility_value is GFSceneUtility:
		var utility: GFSceneUtility = utility_value
		return utility
	return null


func _get_render_warmup_utility() -> GFRenderWarmupUtility:
	var utility_value: Object = Gf.get_utility(GFRenderWarmupUtility)
	if utility_value is GFRenderWarmupUtility:
		var utility: GFRenderWarmupUtility = utility_value
		return utility
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = Gf.get_utility(GameThemeUtility)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null


func _get_operation_diagnostics_utility() -> GFOperationDiagnosticsUtility:
	var utility_value: Object = Gf.get_utility(GFOperationDiagnosticsUtility)
	if utility_value is GFOperationDiagnosticsUtility:
		var diagnostics: GFOperationDiagnosticsUtility = utility_value
		return diagnostics
	return null


func _begin_startup_diagnostics(started_usec: int) -> void:
	_operation_diagnostics = _get_operation_diagnostics_utility()
	if not is_instance_valid(_operation_diagnostics):
		return
	_startup_operation_id = _operation_diagnostics.begin_operation(
		&"game.boot_startup",
		{
			"component": &"boot_runtime",
			"label": "Boot to route handoff",
			"started_ticks_usec": started_usec,
			"metadata": {
				"startup_scene": (
					&"platform_smoke"
					if OS.has_feature(_PLATFORM_SMOKE_FEATURE)
					else &"main_menu"
				),
			},
		}
	)


func _record_startup_phase(
	phase_id: StringName,
	started_usec: int,
	metadata: Dictionary = {}
) -> void:
	if not is_instance_valid(_operation_diagnostics):
		return
	var options: Dictionary = {
		"component": &"boot_runtime",
		"label": String(phase_id),
		"metadata": metadata,
	}
	if _startup_operation_id != &"":
		var _phase: Dictionary = _operation_diagnostics.record_phase_from_ticks(
			_startup_operation_id,
			phase_id,
			started_usec,
			options
		)
	var _sample: Dictionary = _operation_diagnostics.record_sample_from_ticks(
		StringName("game.boot.%s" % phase_id),
		started_usec,
		options
	)


func _finish_startup_diagnostics(success: bool, reason: StringName) -> void:
	if (
		_startup_operation_id != &""
		and is_instance_valid(_operation_diagnostics)
	):
		var _operation: Dictionary = _operation_diagnostics.finish_operation(
			_startup_operation_id,
			success,
			{"metadata": {"reason": reason}}
		)
	_startup_operation_id = &""


func _record_startup_preload_incomplete(
	outcome: StringName,
	wait_result: Dictionary,
	scene_utility: GFSceneUtility
) -> void:
	if not is_instance_valid(_operation_diagnostics):
		return
	var scene_snapshot: Dictionary = scene_utility.get_scene_cache_debug_snapshot()
	var preload_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		scene_snapshot,
		"preloading"
	)
	var cache_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		scene_snapshot,
		"preload_cache"
	)
	var broker_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		scene_snapshot,
		"resource_broker"
	)
	var message: String = (
		"Entry scene preload did not settle inside the non-blocking startup grace period."
		if outcome == &"deferred"
		else "Entry scene preload ended without a reusable cached scene."
	)
	var _incident: Dictionary = _operation_diagnostics.record_incident(
		GFOperationDiagnosticsUtility.SEVERITY_WARNING,
		StringName("boot_entry_scene_preload_%s" % outcome),
		message,
		{
			"category": &"performance",
			"component": &"boot_runtime",
			"phase": &"entry_scene",
			"recoverable": true,
			"suggested_action": "Inspect SceneUtility and ResourceBroker admission snapshots.",
			"metadata": {
				"outcome": outcome,
				"preload_failed": _preload_failed,
				"still_preloading": scene_utility.is_scene_preloading(
					_get_startup_scene_path()
				),
				"wait_status": GFVariantData.get_option_string_name(
					wait_result,
					"status"
				),
				"preloading_count": GFVariantData.get_option_int(
					preload_snapshot,
					"size"
				),
				"cache_size": GFVariantData.get_option_int(
					cache_snapshot,
					"size"
				),
				"broker_active_count": GFVariantData.get_option_int(
					broker_snapshot,
					"active_count"
				),
				"broker_pending_count": GFVariantData.get_option_int(
					broker_snapshot,
					"pending_count"
				),
				"broker_draining_count": GFVariantData.get_option_int(
					broker_snapshot,
					"draining_count"
				),
			},
		}
	)


func _get_boot_shell() -> Boot:
	var parent_node: Node = get_parent()
	if parent_node is Boot:
		var boot_shell: Boot = parent_node
		return boot_shell
	return null


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
