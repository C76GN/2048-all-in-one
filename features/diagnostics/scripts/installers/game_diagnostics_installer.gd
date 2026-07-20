## GameDiagnosticsInstaller: 按显式构建 feature 装配开发诊断能力。
##
## 普通玩家运行不会加载本脚本，避免 Console、Inspector、Screenshot 和独立测试窗口
## 进入首屏依赖链。需要诊断能力的构建必须声明 `with_dev_tools`。
class_name GameDiagnosticsInstaller
extends "res://addons/gf/kernel/core/gf_installer.gd"


# --- 常量 ---

const _VERBOSE_LOGGING_FEATURE: String = "verbose_logging"
const _GAME_DIAGNOSTICS_UTILITY_SCRIPT: Script = preload(
	"res://features/diagnostics/scripts/utilities/game_diagnostics_utility.gd"
)


# --- 公共方法 ---

## 注册只在显式开发构建中启用的诊断模块。
## @param binder: GF 传入的声明式绑定器。
## @param _scope: 当前 Installer 的可取消异步作用域。
func install_bindings(binder: Variant, _scope: GFAsyncScope) -> void:
	if not binder is GFBinder:
		push_error("[GameDiagnosticsInstaller] install_bindings 收到无效 Binder。")
		return
	var gf_binder: GFBinder = binder

	await gf_binder.bind_utility(GFConsoleUtility).as_singleton()
	var tracker_binding: GFBindBuilder = gf_binder.bind_utility(
		GFAsyncTrackerUtility
	).from_instance(_create_async_tracker_utility())
	await tracker_binding.as_singleton()
	await gf_binder.bind_utility(GFOperationDiagnosticsUtility).as_singleton()
	await gf_binder.bind_utility(GFSupportReportUtility).as_singleton()
	var overlay_binding: GFBindBuilder = gf_binder.bind_utility(GFDebugOverlayUtility)
	overlay_binding = overlay_binding.from_instance(_create_debug_overlay_utility())
	await overlay_binding.as_singleton()
	var inspector_binding: GFBindBuilder = gf_binder.bind_utility(GFRuntimeInspectorUtility)
	inspector_binding = inspector_binding.from_instance(_create_runtime_inspector_utility())
	await inspector_binding.as_singleton()
	var screenshot_binding: GFBindBuilder = gf_binder.bind_utility(GFScreenshotUtility)
	screenshot_binding = screenshot_binding.from_instance(_create_screenshot_utility())
	await screenshot_binding.as_singleton()
	await gf_binder.bind_utility(_GAME_DIAGNOSTICS_UTILITY_SCRIPT).as_singleton()
	await gf_binder.bind_utility(TestToolUtility).as_singleton()


# --- 私有/辅助方法 ---

func _create_async_tracker_utility() -> GFAsyncTrackerUtility:
	var tracker: GFAsyncTrackerUtility = GFAsyncTrackerUtility.new()
	tracker.tracking_enabled = true
	tracker.stack_trace_enabled = OS.has_feature(_VERBOSE_LOGGING_FEATURE)
	return tracker


func _create_debug_overlay_utility() -> GFDebugOverlayUtility:
	var overlay: GFDebugOverlayUtility = GFDebugOverlayUtility.new()
	overlay.toggle_key = KEY_F3
	overlay.refresh_interval_seconds = 0.25
	overlay.include_diagnostics_monitors = true
	overlay.include_recent_logs = true
	return overlay


func _create_runtime_inspector_utility() -> GFRuntimeInspectorUtility:
	var inspector: GFRuntimeInspectorUtility = GFRuntimeInspectorUtility.new()
	inspector.allow_writes = true
	inspector.debug_build_writes_only = true
	return inspector


func _create_screenshot_utility() -> GFScreenshotUtility:
	var screenshots: GFScreenshotUtility = GFScreenshotUtility.new()
	screenshots.default_save_dir = "user://diagnostics/screenshots"
	screenshots.default_prefix = "2048"
	screenshots.default_format = GFScreenshotUtility.FORMAT_PNG
	return screenshots
