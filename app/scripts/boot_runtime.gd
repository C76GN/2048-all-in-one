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
const _GAMEPLAY_VISUAL_WARMUP_SCRIPT: GDScript = preload("res://features/gameplay/scripts/ui/gameplay_visual_warmup.gd")
const _STARTUP_RENDER_WARMUP_MANIFEST: GFRenderWarmupManifest = preload(
	"res://features/themes/resources/themes/boot/startup_render_warmup_manifest.tres"
)
const _STARTUP_RENDER_CACHE_GROUP: StringName = &"startup.gameplay_visuals"
const _MIN_SPLASH_SECONDS: float = 0.30
const _PRELOAD_TIMEOUT_SECONDS: float = 8.0
const _FINISH_DELAY_SECONDS: float = 0.04
const _OUTRO_DURATION_SECONDS: float = 0.18


# --- 私有变量 ---

var _startup_progress: GFAsyncProgress
var _preload_failed: bool = false
var _visual_warmup: GameplayVisualWarmup


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)
	_setup_progress()
	await _run_startup_sequence()


# --- 私有/辅助方法 ---

func _run_startup_sequence() -> void:
	var started_msec: int = Time.get_ticks_msec()
	_publish_progress(0.10, "准备启动")
	await _await_startup_frame(true)

	_publish_progress(0.18, "初始化 GF 架构")
	await _await_startup_frame(true)
	var architecture: GFArchitecture = Gf.create_architecture()
	architecture.strict_dependency_lookup = true
	architecture.fail_on_missing_declared_dependencies = true
	var architecture_ready: bool = await Gf.init()
	if not architecture_ready:
		push_error("[Boot] GF 架构严格初始化失败。")
		_publish_progress(1.0, "架构初始化失败")
		return

	_publish_progress(0.42, "加载主题资源")
	var themes_ready: bool = await _prepare_initial_themes()
	if not themes_ready:
		push_error("[Boot] 初始视觉或声音主题激活失败。")
		_publish_progress(1.0, "主题资源初始化失败")
		return

	_publish_progress(0.58, "准备视觉资源")
	await _prime_gameplay_visuals()

	var scene_utility: GFSceneUtility = _get_scene_utility()
	if is_instance_valid(scene_utility):
		await _preload_startup_scene(scene_utility)
	else:
		_publish_progress(0.88, "读取入口场景")
		await get_tree().process_frame

	_publish_progress(0.96, "整理入口场景")
	await _wait_for_minimum_duration(started_msec)
	var _complete_result: bool = _startup_progress.complete("启动完成")
	var finish_wait: Dictionary = await GFAsyncWaitUtility.delay_seconds(
		_FINISH_DELAY_SECONDS,
		_get_boot_wait_options()
	)
	if not GFVariantData.get_option_bool(finish_wait, "completed"):
		return
	await _play_startup_outro()
	_goto_startup_scene()


func _prepare_initial_themes() -> bool:
	var theme_utility: GameThemeUtility = _get_theme_utility()
	if not is_instance_valid(theme_utility):
		return false
	var activated: bool = await theme_utility.ensure_initial_themes_ready()
	return activated and is_inside_tree()


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
	_visual_warmup = warmup
	_visual_warmup.name = "GameplayVisualWarmup"
	add_child(_visual_warmup)
	_visual_warmup.prime()
	_prime_render_resources(_visual_warmup)
	await RenderingServer.frame_post_draw
	_release_visual_warmup()


func _preload_startup_scene(scene_utility: GFSceneUtility) -> void:
	_preload_failed = false
	_connect_preload_signals(scene_utility)
	var startup_scene_path: String = _get_startup_scene_path()
	if DisplayServer.get_name() != "headless":
		scene_utility.configure_scene_preload_map(_SCENE_PRELOAD_MAP, 1, true)
		var _preload_plan: Dictionary = scene_utility.preload_scene_map_for(
			startup_scene_path,
			1,
			true
		)
	var error: Error = scene_utility.preload_scene(startup_scene_path, true)
	if error == OK:
		await _wait_for_startup_scene_preload(scene_utility)
	else:
		_publish_progress(0.86, "入口场景将直接载入")
		await get_tree().process_frame
	_disconnect_preload_signals(scene_utility)


func _wait_for_startup_scene_preload(scene_utility: GFSceneUtility) -> void:
	var startup_scene_path: String = _get_startup_scene_path()
	if scene_utility.is_scene_preloaded(startup_scene_path):
		_publish_progress(0.92, "入口场景已预热")
		return
	var _preload_wait: Dictionary = await GFAsyncWaitUtility.wait_until(
		_is_startup_scene_preload_finished.bind(scene_utility),
		_get_boot_wait_options(_PRELOAD_TIMEOUT_SECONDS)
	)
	if is_instance_valid(scene_utility) and scene_utility.is_scene_preloaded(startup_scene_path):
		_publish_progress(0.92, "入口场景已预热")
	else:
		_publish_progress(0.86, "入口场景将直接载入")


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
	_startup_progress = GFAsyncProgress.new(0.0, "准备启动")
	_startup_progress.min_delta = 0.0
	_startup_progress.min_interval_msec = 0
	var _connect_result: int = _startup_progress.progressed.connect(_on_startup_progressed)
	var _emit_result: bool = _startup_progress.force_emit()


func _publish_progress(value: float, message: String) -> void:
	if _startup_progress == null:
		return
	var _update_result: bool = _startup_progress.update(value, message)


func _on_startup_progressed(value: float, message: String, _metadata: Dictionary) -> void:
	var boot_shell: Boot = _get_boot_shell()
	if is_instance_valid(boot_shell):
		boot_shell.set_runtime_progress(clampf(value, 0.0, 1.0), message)


func _connect_preload_signals(scene_utility: GFSceneUtility) -> void:
	if not scene_utility.scene_preload_progress.is_connected(_on_scene_preload_progress):
		var _progress_connect: int = scene_utility.scene_preload_progress.connect(_on_scene_preload_progress)
	if not scene_utility.scene_preload_failed.is_connected(_on_scene_preload_failed):
		var _failed_connect: int = scene_utility.scene_preload_failed.connect(_on_scene_preload_failed)


func _disconnect_preload_signals(scene_utility: GFSceneUtility) -> void:
	if scene_utility.scene_preload_progress.is_connected(_on_scene_preload_progress):
		scene_utility.scene_preload_progress.disconnect(_on_scene_preload_progress)
	if scene_utility.scene_preload_failed.is_connected(_on_scene_preload_failed):
		scene_utility.scene_preload_failed.disconnect(_on_scene_preload_failed)


func _on_scene_preload_progress(path: String, progress: float) -> void:
	if path == _get_startup_scene_path():
		_publish_progress(lerpf(0.58, 0.92, clampf(progress, 0.0, 1.0)), "预热入口场景")


func _on_scene_preload_failed(path: String) -> void:
	if path == _get_startup_scene_path():
		_preload_failed = true
		_publish_progress(0.84, "入口场景将直接载入")


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
