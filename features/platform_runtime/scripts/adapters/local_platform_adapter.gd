## LocalPlatformAdapter: Godot 原生平台能力适配器。
##
## 覆盖桌面、移动端和 Web 的共同能力；微信 SDK 专属能力将在独立适配器中实现。
class_name LocalPlatformAdapter
extends GamePlatformAdapter


# --- 常量 ---

const ADAPTER_ID: StringName = &"platform.adapter.godot_local"
const PLATFORM_WECHAT_MINIGAME: StringName = &"wechat_minigame"
const PLATFORM_WEB: StringName = &"web"
const _FALLBACK_LOCALE: String = "en"


# --- 私有变量 ---

var _detected_platform_id: StringName = &""
var _backgrounded: bool = false
var _last_window_size: Vector2i = Vector2i.ZERO
var _last_safe_area: Rect2i = Rect2i()


# --- Godot 生命周期方法 ---

func _init() -> void:
	adapter_id = ADAPTER_ID
	_detected_platform_id = _detect_platform_id()
	_last_window_size = _get_window_size()
	_last_safe_area = _get_safe_area()


# --- 公共方法 ---

func is_available() -> bool:
	return true


func create_runtime_context() -> GFPlatformRuntimeContext:
	_detected_platform_id = _detect_platform_id()
	_last_window_size = _get_window_size()
	_last_safe_area = _get_safe_area()
	var display_server_name: String = _get_display_server_name()
	var context: GFPlatformRuntimeContext = GFPlatformRuntimeContext.new().configure(
		_detected_platform_id,
		{
			"adapter_id": adapter_id,
			"display_name": _get_platform_display_name(_detected_platform_id),
			"locale": OS.get_locale(),
			"fallback_locale": _FALLBACK_LOCALE,
			"pixel_ratio": _get_pixel_ratio(),
			"window_size": _last_window_size,
			"screen_size": _get_screen_size(),
			"safe_area": _last_safe_area,
			"capability_ids": _get_capability_ids(),
			"storage_roots": {
				"application": "user://",
				"cache": "user://cache",
			},
			"launch_options": {
				"arguments": OS.get_cmdline_user_args(),
			},
			"metadata": {
				"godot_version": Engine.get_version_info(),
				"renderer_method": _get_renderer_method(),
				"display_server_name": display_server_name,
				"headless": display_server_name == "headless",
				"debug_build": OS.is_debug_build(),
			},
		}
	)
	return context


## 接收并转换 Godot 平台通知。
## @param what: Godot 通知标识。
func handle_notification(what: int) -> void:
	match what:
		Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT:
			_set_backgrounded(true)
		Node.NOTIFICATION_APPLICATION_RESUMED, Node.NOTIFICATION_APPLICATION_FOCUS_IN:
			var was_backgrounded: bool = _backgrounded
			_set_backgrounded(false)
			if was_backgrounded:
				var _context_refreshed: bool = refresh_context()
		Node.NOTIFICATION_WM_SIZE_CHANGED:
			_emit_display_changes()


# --- 可重写钩子 / 虚方法 ---

## 通过 Godot DisplayServer 执行 GF runtime 已校验的剪贴板写入。
## @param text: 要写入的非空纯文本。
## @return: 当前平台接受写入请求时返回 true；不依赖受限平台的同步读回能力。
func _write_text_to_clipboard(text: String) -> bool:
	if text.is_empty() or not _has_clipboard_write_support():
		return false
	_set_clipboard_text(text)
	return true


# --- 私有/辅助方法 ---

func _set_backgrounded(value: bool) -> void:
	if _backgrounded == value:
		return
	_backgrounded = value
	var event_type: StringName = (
		GFPlatformLifecycleEvent.TYPE_BACKGROUND
		if value
		else GFPlatformLifecycleEvent.TYPE_FOREGROUND
	)
	var _event_published: bool = emit_lifecycle_event(GFPlatformLifecycleEvent.new().configure(
		event_type,
		_detected_platform_id,
		{"backgrounded": value}
	))


func _emit_display_changes() -> void:
	var display_context_changed: bool = false
	var next_window_size: Vector2i = _get_window_size()
	if next_window_size != _last_window_size:
		_last_window_size = next_window_size
		display_context_changed = true
		var _resize_published: bool = emit_lifecycle_event(GFPlatformLifecycleEvent.new().configure(
			GFPlatformLifecycleEvent.TYPE_WINDOW_RESIZED,
			_detected_platform_id,
			{"window_size": next_window_size}
		))

	var next_safe_area: Rect2i = _get_safe_area()
	if next_safe_area != _last_safe_area:
		_last_safe_area = next_safe_area
		display_context_changed = true
		var _safe_area_published: bool = emit_lifecycle_event(GFPlatformLifecycleEvent.new().configure(
			GFPlatformLifecycleEvent.TYPE_SAFE_AREA_CHANGED,
			_detected_platform_id,
			{"safe_area": next_safe_area}
		))
	if display_context_changed:
		var _context_published: bool = refresh_context()


func _get_capability_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray([
		String(CAPABILITY_STORAGE_LOCAL),
		String(CAPABILITY_HTTP),
		String(CAPABILITY_AUDIO),
		String(CAPABILITY_LIFECYCLE),
		String(CAPABILITY_SAFE_AREA),
		String(CAPABILITY_WINDOW_RESIZE),
		String(CAPABILITY_POINTER),
	])
	if OS.has_feature("web") or OS.has_feature("mobile"):
		var _touch_added: bool = result.append(String(CAPABILITY_TOUCH))
	if _get_renderer_method() == "gl_compatibility":
		var _renderer_added: bool = result.append(String(CAPABILITY_COMPATIBILITY_RENDERER))
	if _has_clipboard_write_support():
		var _clipboard_added: bool = result.append(String(CAPABILITY_CLIPBOARD_WRITE))
	return result


## 返回当前 DisplayServer 是否明确声明剪贴板支持。
##
## Web 与移动端是否暴露该能力完全服从运行时 feature，不按平台名称乐观推断。
func _has_clipboard_write_support() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)


## 提交剪贴板写入；独立 seam 允许测试受限平台的“可写但不可同步读回”语义。
## @param text: 已校验的非空文本。
func _set_clipboard_text(text: String) -> void:
	DisplayServer.clipboard_set(text)


func _detect_platform_id() -> StringName:
	if OS.has_feature("wechat_minigame") or OS.has_feature("wechat_minigame_smoke"):
		return PLATFORM_WECHAT_MINIGAME
	if OS.has_feature("web"):
		return PLATFORM_WEB
	return StringName(OS.get_name().to_snake_case())


func _get_platform_display_name(platform_id: StringName) -> String:
	if platform_id == PLATFORM_WECHAT_MINIGAME:
		return "WeChat Mini Game"
	if platform_id == PLATFORM_WEB:
		return "Web"
	return OS.get_name()


## 返回宿主 DisplayServer 名称；独立 seam 允许验证无渲染帧平台事实。
func _get_display_server_name() -> String:
	return DisplayServer.get_name().to_lower()


func _get_renderer_method() -> String:
	return str(ProjectSettings.get_setting_with_override(
		"rendering/renderer/rendering_method"
	)).strip_edges()


func _get_window_size() -> Vector2i:
	return DisplayServer.window_get_size()


func _get_screen_size() -> Vector2i:
	return DisplayServer.screen_get_size()


func _get_safe_area() -> Rect2i:
	return DisplayServer.get_display_safe_area()


func _get_pixel_ratio() -> float:
	return maxf(DisplayServer.screen_get_scale(), 1.0)
