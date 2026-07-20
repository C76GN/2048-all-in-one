## PlatformSmokeController: 跨平台 Compatibility 冒烟场景控制器。
##
## 该场景验证平台上下文、安全区域、指针手势、本地存储、HTTP、音频和代表性
## Shader；通过 platform_smoke 导出 feature 从 Boot 进入。
class_name PlatformSmokeController
extends GFController


# --- 常量 ---

const _STORAGE_FILE: String = "diagnostics/platform_smoke.save"
const _AUDIO_ASSET_KEY: StringName = &"asset.audio.ui.printworks.confirm_soft_01"
const _BACKGROUND_SHADER_KEY: StringName = &"asset.shader.background.halftone_paper"
const _HTTP_DEFAULT_URL: String = "https://httpbin.org/get"
const _HTTP_MAX_RESPONSE_BYTES: int = 64 * 1024

const _PAPER_COLOR: Color = Color("f4f0e6")
const _INK_COLOR: Color = Color("303238")
const _MUTED_COLOR: Color = Color("68625c")
const _ACCENT_COLOR: Color = Color("6ca9a5")
const _WARM_COLOR: Color = Color("b77a75")
const _OK_COLOR: Color = Color("3d7a62")
const _ERROR_COLOR: Color = Color("a5483f")


# --- 私有变量 ---

var _platform: GamePlatformUtility = null
var _viewport_utility: GFViewportUtility = null
var _gestures: GFPointerGestureUtility = null
var _storage: GFStorageUtility = null
var _http: GFHttpClientUtility = null
var _audio: GFAudioUtility = null
var _assets: GameAssetLibraryUtility = null

var _safe_margin: MarginContainer = null
var _platform_label: Label = null
var _renderer_label: Label = null
var _capabilities_label: Label = null
var _lifecycle_label: Label = null
var _gesture_label: Label = null
var _storage_label: Label = null
var _http_label: Label = null
var _http_url: LineEdit = null
var _active_response: GFHttpResponse = null


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_utilities()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_interface()
	_bind_runtime_signals()
	_refresh_platform_display()
	_apply_safe_area()


func _input(event: InputEvent) -> void:
	if _gestures != null:
		var _handled: bool = _gestures.handle_input_event(event)


func _exit_tree() -> void:
	_unbind_runtime_signals()
	if _active_response != null and _active_response.is_pending():
		_active_response.cancel("scene_exited")
	_active_response = null


# --- 私有/辅助方法：依赖 ---

func _resolve_utilities() -> void:
	_platform = _get_platform_utility()
	_viewport_utility = _get_viewport_utility()
	_gestures = _get_gesture_utility()
	_storage = _get_storage_utility()
	_http = _get_http_utility()
	_audio = _get_audio_utility()
	_assets = _get_asset_library_utility()


func _get_platform_utility() -> GamePlatformUtility:
	var utility_value: Object = get_utility(GamePlatformUtility, true)
	if utility_value is GamePlatformUtility:
		var platform_utility: GamePlatformUtility = utility_value
		return platform_utility
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility, true)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _get_gesture_utility() -> GFPointerGestureUtility:
	var utility_value: Object = get_utility(GFPointerGestureUtility, true)
	if utility_value is GFPointerGestureUtility:
		var gesture_utility: GFPointerGestureUtility = utility_value
		return gesture_utility
	return null


func _get_storage_utility() -> GFStorageUtility:
	var utility_value: Object = get_utility(GFStorageUtility, true)
	if utility_value is GFStorageUtility:
		var storage_utility: GFStorageUtility = utility_value
		return storage_utility
	return null


func _get_http_utility() -> GFHttpClientUtility:
	var utility_value: Object = get_utility(GFHttpClientUtility, true)
	if utility_value is GFHttpClientUtility:
		var http_utility: GFHttpClientUtility = utility_value
		return http_utility
	return null


func _get_audio_utility() -> GFAudioUtility:
	var utility_value: Object = get_utility(GFAudioUtility, true)
	if utility_value is GFAudioUtility:
		var audio_utility: GFAudioUtility = utility_value
		return audio_utility
	return null


func _get_asset_library_utility() -> GameAssetLibraryUtility:
	var utility_value: Object = get_utility(GameAssetLibraryUtility, true)
	if utility_value is GameAssetLibraryUtility:
		var asset_library_utility: GameAssetLibraryUtility = utility_value
		return asset_library_utility
	return null


func _get_host_control() -> Control:
	var host_value: Variant = get_host_as(Control)
	if host_value is Control:
		var host_control: Control = host_value
		return host_control
	return null


func _bind_runtime_signals() -> void:
	if _platform != null:
		if not _platform.context_changed.is_connected(_on_platform_context_changed):
			var _context_connect: int = _platform.context_changed.connect(
				_on_platform_context_changed
			)
		if not _platform.lifecycle_event_received.is_connected(_on_lifecycle_event_received):
			var _lifecycle_connect: int = _platform.lifecycle_event_received.connect(
				_on_lifecycle_event_received
			)
	if _gestures != null:
		if not _gestures.gesture_updated.is_connected(_on_gesture_updated):
			var _gesture_connect: int = _gestures.gesture_updated.connect(_on_gesture_updated)
		if not _gestures.gesture_ended.is_connected(_on_gesture_ended):
			var _ended_connect: int = _gestures.gesture_ended.connect(_on_gesture_ended)
	var root: Control = _get_host_control()
	if root != null and not root.resized.is_connected(_apply_safe_area):
		var _resize_connect: int = root.resized.connect(_apply_safe_area)


func _unbind_runtime_signals() -> void:
	if _platform != null:
		if _platform.context_changed.is_connected(_on_platform_context_changed):
			_platform.context_changed.disconnect(_on_platform_context_changed)
		if _platform.lifecycle_event_received.is_connected(_on_lifecycle_event_received):
			_platform.lifecycle_event_received.disconnect(_on_lifecycle_event_received)
	if _gestures != null:
		if _gestures.gesture_updated.is_connected(_on_gesture_updated):
			_gestures.gesture_updated.disconnect(_on_gesture_updated)
		if _gestures.gesture_ended.is_connected(_on_gesture_ended):
			_gestures.gesture_ended.disconnect(_on_gesture_ended)
	var root: Control = _get_host_control()
	if root != null and root.resized.is_connected(_apply_safe_area):
		root.resized.disconnect(_apply_safe_area)


# --- 私有/辅助方法：界面 ---

func _build_interface() -> void:
	var root: Control = _get_host_control()
	if root == null:
		push_error("[PlatformSmokeController] 缺少 Control 宿主节点。")
		return

	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.color = _PAPER_COLOR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_full_rect(background)
	_apply_background_shader(background)
	root.add_child(background)

	_safe_margin = MarginContainer.new()
	_safe_margin.name = "SafeArea"
	_set_full_rect(_safe_margin)
	root.add_child(_safe_margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_safe_margin.add_child(scroll)

	var page_margin: MarginContainer = MarginContainer.new()
	page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_margin.add_theme_constant_override("margin_left", 24)
	page_margin.add_theme_constant_override("margin_top", 20)
	page_margin.add_theme_constant_override("margin_right", 24)
	page_margin.add_theme_constant_override("margin_bottom", 28)
	scroll.add_child(page_margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(300.0, 0.0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	page_margin.add_child(content)

	content.add_child(_make_label("跨平台兼容性冒烟", 34, _INK_COLOR))
	content.add_child(_make_label(
		"用于 Web / 微信小游戏适配前验证，不代表微信 SDK 已接入。",
		16,
		_MUTED_COLOR
	))

	_platform_label = _make_status_label()
	content.add_child(_make_section("运行平台", _platform_label))
	_renderer_label = _make_status_label()
	content.add_child(_make_section("Compatibility 渲染器", _renderer_label))
	_capabilities_label = _make_status_label()
	_capabilities_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_make_section("能力契约", _capabilities_label))

	_lifecycle_label = _make_status_label("等待后台 / 前台 / 窗口事件")
	content.add_child(_make_section("生命周期", _lifecycle_label))
	_gesture_label = _make_status_label("拖动、滚轮缩放或双指缩放以验证输入")
	content.add_child(_make_section("指针与触摸", _gesture_label))

	var storage_content: VBoxContainer = VBoxContainer.new()
	storage_content.add_theme_constant_override("separation", 8)
	_storage_label = _make_status_label("尚未执行持久化测试")
	storage_content.add_child(_storage_label)
	storage_content.add_child(_make_button("写入并回读", _on_storage_test_pressed))
	storage_content.add_child(_make_button("清除冒烟数据", _on_storage_clear_pressed))
	content.add_child(_make_section("GFStorageUtility", storage_content))

	var http_content: VBoxContainer = VBoxContainer.new()
	http_content.add_theme_constant_override("separation", 8)
	_http_url = LineEdit.new()
	_http_url.text = _HTTP_DEFAULT_URL
	_http_url.placeholder_text = "HTTPS endpoint（微信真机必须加入合法域名）"
	_http_url.add_theme_color_override("font_color", _INK_COLOR)
	_http_url.add_theme_color_override("font_placeholder_color", _MUTED_COLOR)
	http_content.add_child(_http_url)
	_http_label = _make_status_label("尚未发起请求")
	http_content.add_child(_http_label)
	http_content.add_child(_make_button("发起 GET 请求", _on_http_test_pressed))
	content.add_child(_make_section("GFHttpClientUtility", http_content))

	var media_content: VBoxContainer = VBoxContainer.new()
	media_content.add_theme_constant_override("separation", 8)
	media_content.add_child(_make_label(
		"背景正在运行已审批的半色调 Shader；音频必须由用户操作触发。",
		15,
		_MUTED_COLOR
	))
	media_content.add_child(_make_button("播放已审批 UI 音效", _on_audio_test_pressed))
	content.add_child(_make_section("素材与音频", media_content))


func _make_section(title: String, body: Control) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 13)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	column.add_child(_make_label(title, 18, _INK_COLOR))
	column.add_child(body)
	return panel


func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.99, 0.96, 0.94)
	style.border_color = Color(_INK_COLOR, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _make_label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_status_label(text: String = "") -> Label:
	var label: Label = _make_label(text, 15, _INK_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.add_theme_color_override("font_color", _INK_COLOR)
	button.add_theme_color_override("font_hover_color", _INK_COLOR)
	button.add_theme_color_override("font_pressed_color", _PAPER_COLOR)
	var normal: StyleBoxFlat = _make_panel_style()
	normal.bg_color = Color("ead8a8")
	normal.border_color = _WARM_COLOR
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = _duplicate_flat_style(normal)
	hover.bg_color = Color("f0d696")
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = _duplicate_flat_style(normal)
	pressed.bg_color = _WARM_COLOR
	button.add_theme_stylebox_override("pressed", pressed)
	var _connect_result: int = button.pressed.connect(callback)
	return button


func _apply_background_shader(background: ColorRect) -> void:
	if _assets == null:
		return
	var resource: Resource = _assets.load_asset(_BACKGROUND_SHADER_KEY, "Shader")
	if resource is Shader:
		var shader: Shader = resource
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		background.material = material


func _duplicate_flat_style(source: StyleBoxFlat) -> StyleBoxFlat:
	var duplicate_value: Resource = source.duplicate()
	if duplicate_value is StyleBoxFlat:
		var duplicate_style: StyleBoxFlat = duplicate_value
		return duplicate_style
	return _make_panel_style()


func _set_full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- 私有/辅助方法：状态显示 ---

func _refresh_platform_display() -> void:
	if _platform == null:
		_set_status(_platform_label, "GamePlatformUtility 未注册", false)
		return
	var context: GFPlatformRuntimeContext = _platform.get_runtime_context()
	if context == null:
		_set_status(_platform_label, "平台上下文不可用", false)
		return
	_set_status(
		_platform_label,
		"%s / %s · %dx%d · safe %s" % [
			String(context.platform_id),
			String(context.adapter_id),
			context.window_size.x,
			context.window_size.y,
			str(context.safe_area),
		],
		true
	)
	var renderer_method: String = GFVariantData.get_option_string(
		context.metadata,
		"renderer_method"
	)
	var requires_compatibility: bool = (
		context.platform_id == LocalPlatformAdapter.PLATFORM_WEB
		or context.platform_id == LocalPlatformAdapter.PLATFORM_WECHAT_MINIGAME
	)
	var renderer_ok: bool = not requires_compatibility or renderer_method == "gl_compatibility"
	_set_status(
		_renderer_label,
		"%s%s" % [
			renderer_method,
			"（目标平台要求 gl_compatibility）" if requires_compatibility else "",
		],
		renderer_ok
	)
	var capability_text: String = "\n".join(context.capabilities.capabilities)
	_set_status(_capabilities_label, capability_text, not capability_text.is_empty())


func _set_status(label: Label, text: String, ok: bool) -> void:
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", _OK_COLOR if ok else _ERROR_COLOR)


func _apply_safe_area() -> void:
	if _viewport_utility == null or _safe_margin == null:
		return
	var _report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
		_safe_margin,
		_safe_margin.get_viewport(),
		{"left": 8, "top": 8, "right": 8, "bottom": 8}
	)


# --- 信号处理函数 ---

func _on_platform_context_changed(_context: GFPlatformRuntimeContext) -> void:
	_refresh_platform_display()
	_apply_safe_area()


func _on_lifecycle_event_received(event: GFPlatformLifecycleEvent) -> void:
	_set_status(
		_lifecycle_label,
		"#%d %s · %s" % [event.sequence, String(event.event_type), str(event.payload)],
		true
	)


func _on_gesture_updated(snapshot: Dictionary, _event: InputEvent) -> void:
	_set_status(
		_gesture_label,
		"%s · pointers=%d · pan=%s · scale=%.3f" % [
			GFVariantData.get_option_string(snapshot, "source"),
			GFVariantData.get_option_int(snapshot, "pointer_count"),
			str(GFVariantData.get_option_value(snapshot, "pan_delta", Vector2.ZERO)),
			GFVariantData.get_option_float(snapshot, "scale", 1.0),
		],
		true
	)


func _on_gesture_ended(snapshot: Dictionary) -> void:
	_set_status(
		_gesture_label,
		"手势结束 · center=%s" % str(GFVariantData.get_option_value(snapshot, "center", Vector2.ZERO)),
		true
	)


func _on_storage_test_pressed() -> void:
	if _storage == null:
		_set_status(_storage_label, "GFStorageUtility 未注册", false)
		return
	var previous_result: GFStorageReadResult = _storage.load_data(_STORAGE_FILE)
	var previous_data: Dictionary = previous_result.payload if previous_result.ok else {}
	var run_count: int = GFVariantData.get_option_int(previous_data, "run_count") + 1
	var save_error: Error = _storage.save_data(_STORAGE_FILE, {
		"run_count": run_count,
		"platform_id": String(_platform.get_runtime_context().platform_id) if _platform != null else "unknown",
	})
	if save_error != OK:
		_set_status(_storage_label, "写入失败：%s" % error_string(save_error), false)
		return
	var verify_result: GFStorageReadResult = _storage.load_data(_STORAGE_FILE)
	var verify_data: Dictionary = verify_result.payload if verify_result.ok else {}
	var verified: bool = (
		verify_result.ok
		and GFVariantData.get_option_int(verify_data, "run_count") == run_count
	)
	_set_status(
		_storage_label,
		"持久化往返%s；跨启动计数=%d" % ["通过" if verified else "失败", run_count],
		verified
	)


func _on_storage_clear_pressed() -> void:
	if _storage == null:
		_set_status(_storage_label, "GFStorageUtility 未注册", false)
		return
	var delete_error: Error = _storage.delete_file(_STORAGE_FILE)
	var cleared: bool = delete_error == OK or delete_error == ERR_FILE_NOT_FOUND
	_set_status(
		_storage_label,
		"冒烟数据已清除" if cleared else "清除失败：%s" % error_string(delete_error),
		cleared
	)


func _on_http_test_pressed() -> void:
	if _http == null:
		_set_status(_http_label, "GFHttpClientUtility 未注册", false)
		return
	var url: String = _http_url.text.strip_edges()
	if not url.begins_with("https://"):
		_set_status(_http_label, "仅允许 HTTPS endpoint", false)
		return
	if _active_response != null and _active_response.is_pending():
		_active_response.cancel("replaced")
	var builder: GFHttpRequestBuilder = GFHttpRequestBuilder.new()
	var _configured_builder: GFHttpRequestBuilder = builder.set_url(url).set_method(
		GFHttpRequestBuilder.Method.GET
	).set_parse_mode(GFHttpRequestBuilder.ParseMode.TEXT).set_timeout(10.0).set_max_response_bytes(
		_HTTP_MAX_RESPONSE_BYTES
	)
	_active_response = _http.execute(builder)
	if _active_response == null:
		_set_status(_http_label, "请求未能入队", false)
		return
	_set_status(_http_label, "请求中…", true)
	var _connect_result: int = _active_response.completed.connect(_on_http_completed)


func _on_http_completed(response: GFHttpResponse) -> void:
	var succeeded: bool = response != null and response.is_successful()
	var text: String = (
		"HTTP %d · %d bytes" % [response.status_code, response.body.size()]
		if response != null
		else "响应对象为空"
	)
	if response != null and not response.error.is_empty():
		text += " · %s" % response.error
	_set_status(_http_label, text, succeeded)
	if response == _active_response:
		_active_response = null


func _on_audio_test_pressed() -> void:
	if _audio == null or _assets == null:
		_set_status(_lifecycle_label, "音频或素材库 Utility 未注册", false)
		return
	var path: String = _assets.resolve_asset_path(_AUDIO_ASSET_KEY, "AudioStreamOggVorbis")
	if path.is_empty():
		_set_status(_lifecycle_label, "已审批音频资源键解析失败", false)
		return
	_audio.play_sfx(path)
