## Boot: 游戏启动入口。
class_name Boot
extends Control


# --- 常量 ---

const MAIN_MENU_SCENE_PATH: String = "res://features/navigation/scenes/menus/main_menu.tscn"
const PLATFORM_SMOKE_SCENE_PATH: String = "res://features/platform_runtime/scenes/smoke_test/platform_smoke_test.tscn"
const _PLATFORM_SMOKE_FEATURE: String = "platform_smoke"
const _BACKGROUND_SHADER: Shader = preload("res://features/asset_library/resources/shaders/background/halftone_paper_background.gdshader")
const _PROGRESS_SHADER: Shader = preload("res://features/asset_library/resources/shaders/ui/startup_progress_bar.gdshader")
const _BACKGROUND_SHADER_PROFILE: GFShaderParameterProfile = preload("res://features/themes/resources/themes/boot/startup_background_profile.tres")
const _PROGRESS_SHADER_PROFILE: GFShaderParameterProfile = preload("res://features/themes/resources/themes/boot/startup_progress_profile.tres")

const _MIN_SPLASH_SECONDS: float = 1.05
const _PRELOAD_TIMEOUT_SECONDS: float = 8.0
const _FINISH_DELAY_SECONDS: float = 0.14
const _PROGRESS_BAR_ASPECT_FALLBACK: float = 8.0
const _PAPER_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.94)
const _INK_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _MUTED_INK_COLOR: Color = Color(0.4, 0.35686275, 0.32156864, 0.92)
const _ACCENT_COLOR: Color = Color(0.61960787, 0.8235294, 0.80784315, 1.0)
const _WARM_COLOR: Color = Color(0.7176471, 0.47843137, 0.45882353, 1.0)


# --- 私有变量 ---

var _startup_progress: GFAsyncProgress
var _progress_bar: ColorRect
var _progress_bar_material: ShaderMaterial
var _status_label: Label
var _percent_label: Label
var _preload_failed: bool = false
var _shader_parameters: GFShaderParameterUtility = GFShaderParameterUtility.new()


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_setup_startup_screen()
	_setup_progress()
	await _run_startup_sequence()


# --- 公共方法 ---

static func are_dev_tools_enabled() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build() or OS.has_feature("with_test_panel")


# --- 私有/辅助方法 ---

func _run_startup_sequence() -> void:
	var started_msec: int = Time.get_ticks_msec()
	_publish_progress(0.04, "准备纸面")
	await get_tree().process_frame

	_publish_progress(0.18, "初始化 GF 架构")
	var architecture: GFArchitecture = Gf.create_architecture()
	architecture.strict_dependency_lookup = true
	architecture.fail_on_missing_declared_dependencies = true
	var architecture_ready: bool = await Gf.init()
	if not architecture_ready:
		push_error("[Boot] GF 架构严格初始化失败。")
		_publish_progress(1.0, "架构初始化失败")
		return
	_publish_progress(0.54, "注册系统与素材")
	await get_tree().process_frame

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
	_goto_startup_scene()


func _preload_startup_scene(scene_utility: GFSceneUtility) -> void:
	_preload_failed = false
	_connect_preload_signals(scene_utility)
	var startup_scene_path: String = _get_startup_scene_path()
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
	var safe_value: float = clampf(value, 0.0, 1.0)
	if is_instance_valid(_progress_bar_material):
		var _parameter_count: int = _shader_parameters.apply_parameters(
			_progress_bar_material,
			{&"progress": safe_value},
			_get_shader_apply_options()
		)
	if is_instance_valid(_status_label):
		_status_label.text = message
	if is_instance_valid(_percent_label):
		var percent_value: float = round(safe_value * 100.0)
		_percent_label.text = "%d%%" % int(percent_value)
	_sync_progress_bar_aspect()


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
	if path != _get_startup_scene_path():
		return
	var mapped_progress: float = lerpf(0.56, 0.92, clampf(progress, 0.0, 1.0))
	_publish_progress(mapped_progress, "预热入口场景")


func _on_scene_preload_failed(path: String) -> void:
	if path != _get_startup_scene_path():
		return
	_preload_failed = true
	_publish_progress(0.84, "入口场景将直接载入")


func _goto_startup_scene() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if not is_instance_valid(router):
		push_error("[Boot] 缺少 SceneRouterSystem，无法进入入口场景。")
		return
	router.call_deferred("goto_scene", _get_startup_scene_path())


func _get_startup_scene_path() -> String:
	if OS.has_feature(_PLATFORM_SMOKE_FEATURE):
		return PLATFORM_SMOKE_SCENE_PATH
	return MAIN_MENU_SCENE_PATH


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = Gf.get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


func _get_scene_utility() -> GFSceneUtility:
	var utility_value: Object = Gf.get_utility(GFSceneUtility)
	if utility_value is GFSceneUtility:
		var scene_utility: GFSceneUtility = utility_value
		return scene_utility
	return null


func _setup_startup_screen() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(self)

	var background: ColorRect = ColorRect.new()
	background.name = "StartupBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.color = Color.WHITE
	_set_full_rect(background)
	var background_material: ShaderMaterial = ShaderMaterial.new()
	background_material.shader = _BACKGROUND_SHADER
	background.material = background_material
	var _background_parameter_count: int = _shader_parameters.apply_profile(
		background,
		_BACKGROUND_SHADER_PROFILE,
		_get_shader_apply_options()
	)
	add_child(background)

	var center: CenterContainer = CenterContainer.new()
	center.name = "StartupCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(center)
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "StartupPanel"
	panel.custom_minimum_size = Vector2(560.0, 360.0)
	panel.add_theme_stylebox_override("panel", _create_panel_style())
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "PanelMargin"
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.name = "StartupContent"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	content.add_child(_create_title_label("2048"))
	content.add_child(_create_subtitle_label("PRINTWORKS ATLAS"))
	content.add_child(_create_micro_board())
	content.add_child(_create_progress_row())
	_progress_bar = _create_progress_bar()
	content.add_child(_progress_bar)
	content.add_child(_create_footer_label("GF Framework / Scene Preload"))


func _create_title_label(text: String) -> Label:
	var label: Label = Label.new()
	label.name = "TitleLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _INK_COLOR)
	label.add_theme_color_override("font_shadow_color", _ACCENT_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", 74)
	return label


func _create_subtitle_label(text: String) -> Label:
	var label: Label = Label.new()
	label.name = "SubtitleLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _MUTED_INK_COLOR)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _create_footer_label(text: String) -> Label:
	var label: Label = Label.new()
	label.name = "FooterLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _MUTED_INK_COLOR)
	label.add_theme_font_size_override("font_size", 14)
	return label


func _create_progress_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ProgressStatusRow"
	row.add_theme_constant_override("separation", 12)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "准备启动"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_color_override("font_color", _INK_COLOR)
	_status_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_status_label)

	_percent_label = Label.new()
	_percent_label.name = "PercentLabel"
	_percent_label.text = "0%"
	_percent_label.custom_minimum_size = Vector2(72.0, 0.0)
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_percent_label.add_theme_color_override("font_color", _WARM_COLOR)
	_percent_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_percent_label)
	return row


func _create_progress_bar() -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.name = "StartupProgressBar"
	bar.custom_minimum_size = Vector2(460.0, 34.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color.WHITE

	_progress_bar_material = ShaderMaterial.new()
	_progress_bar_material.shader = _PROGRESS_SHADER
	bar.material = _progress_bar_material
	var _progress_parameter_count: int = _shader_parameters.apply_profile(
		bar,
		_PROGRESS_SHADER_PROFILE,
		_get_shader_apply_options()
	)

	var _resize_connect: int = bar.resized.connect(_on_progress_bar_resized)
	return bar


func _create_micro_board() -> GridContainer:
	var board: GridContainer = GridContainer.new()
	board.name = "StartupBoardPreview"
	board.columns = 4
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board.add_theme_constant_override("h_separation", 5)
	board.add_theme_constant_override("v_separation", 5)

	var values: PackedStringArray = PackedStringArray([
		"2", "", "4", "",
		"", "8", "", "16",
		"32", "", "64", "",
		"", "128", "", "2048",
	])
	for index: int in range(values.size()):
		var cell: PanelContainer = PanelContainer.new()
		cell.custom_minimum_size = Vector2(44.0, 44.0)
		cell.add_theme_stylebox_override("panel", _create_board_cell_style(index))
		var label: Label = Label.new()
		label.text = values[index]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", _INK_COLOR)
		label.add_theme_font_size_override("font_size", 18)
		cell.add_child(label)
		board.add_child(cell)
	return board


func _create_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = _PAPER_COLOR
	style.border_color = _INK_COLOR
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	return style


func _create_board_cell_style(index: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var palette: Array[Color] = [
		Color(0.95686275, 0.92941177, 0.8666667, 1.0),
		Color(0.61960787, 0.8235294, 0.80784315, 1.0),
		Color(0.9411765, 0.8392157, 0.5882353, 1.0),
		Color(0.7176471, 0.47843137, 0.45882353, 1.0),
	]
	style.bg_color = palette[index % palette.size()]
	style.border_color = _INK_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	return style


func _on_progress_bar_resized() -> void:
	_sync_progress_bar_aspect()


func _sync_progress_bar_aspect() -> void:
	if not is_instance_valid(_progress_bar_material) or not is_instance_valid(_progress_bar):
		return
	var height: float = maxf(_progress_bar.size.y, 1.0)
	var bar_aspect: float = maxf(_progress_bar.size.x / height, _PROGRESS_BAR_ASPECT_FALLBACK)
	var _parameter_count: int = _shader_parameters.apply_parameters(
		_progress_bar_material,
		{&"aspect": bar_aspect},
		_get_shader_apply_options()
	)


func _get_shader_apply_options() -> Dictionary:
	return {
		"duplicate_material": false,
		"require_declared_parameters": true,
		"warn_on_invalid_target": true,
		"warn_on_missing_parameters": true,
		"copy_values": true,
	}


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
