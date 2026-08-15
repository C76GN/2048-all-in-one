## GameDiagnosticsInstaller: 按显式构建 feature 装配开发诊断能力。
##
## 普通玩家运行不会加载本脚本，避免 Console、Inspector、Screenshot 和独立测试窗口
## 进入首屏依赖链。需要诊断能力的构建必须声明 `with_dev_tools`。
class_name GameDiagnosticsInstaller
extends GFInstaller


# --- 常量 ---

const _VERBOSE_LOGGING_FEATURE: String = "verbose_logging"
const _GAME_DIAGNOSTICS_UTILITY_SCRIPT: Script = preload(
	"res://features/diagnostics/scripts/utilities/game_diagnostics_utility.gd"
)


# --- 私有变量 ---

var _architecture: GFArchitecture = null


# --- 公共方法 ---

## 捕获当前尚未发布的候选架构，供必需绑定失败时设置终态。
## @param architecture: GF 尚未发布的候选架构。
## @param scope: 当前 Installer 的协作取消作用域。
func install(architecture: GFArchitecture, scope: GFAsyncScope) -> void:
	if architecture == null or scope == null:
		var invalid_reason: String = (
			"[GameDiagnosticsInstaller] install 失败：候选架构或 scope 为空。"
		)
		if architecture != null:
			architecture.fail_initialization(invalid_reason)
		else:
			push_error(invalid_reason)
		if scope != null:
			var _cancelled_invalid_install: bool = scope.cancel(invalid_reason)
		return
	if scope.is_cancel_requested():
		return
	_architecture = architecture


## 注册只在显式开发构建中启用的诊断模块。
## @param binder: GF 传入的声明式绑定器。
## @param scope: 当前 Installer 的可取消异步作用域。
func install_bindings(binder: Variant, scope: GFAsyncScope) -> void:
	if not binder is GFBinder:
		push_error("[GameDiagnosticsInstaller] install_bindings 收到无效 Binder。")
		return
	if scope == null:
		push_error("[GameDiagnosticsInstaller] install_bindings 收到无效 Scope。")
		return
	if scope.is_cancel_requested():
		return
	if _architecture == null:
		var missing_architecture_reason: String = (
			"[GameDiagnosticsInstaller] install_bindings 失败：未配置候选架构。"
		)
		push_error(missing_architecture_reason)
		var _cancelled_missing_architecture: bool = scope.cancel(
			missing_architecture_reason
		)
		return
	var gf_binder: GFBinder = binder

	if not await _bind_required(
		gf_binder.bind_utility(GFConsoleUtility), scope, GFConsoleUtility
	):
		return
	var tracker_binding: GFBindBuilder = gf_binder.bind_utility(
		GFAsyncTrackerUtility
	).from_instance(_create_async_tracker_utility())
	if not await _bind_required(tracker_binding, scope, GFAsyncTrackerUtility):
		return
	if not await _bind_required(
		gf_binder.bind_utility(GFSupportReportUtility), scope, GFSupportReportUtility
	):
		return
	var overlay_binding: GFBindBuilder = gf_binder.bind_utility(GFDebugOverlayUtility)
	overlay_binding = overlay_binding.from_instance(_create_debug_overlay_utility())
	if not await _bind_required(overlay_binding, scope, GFDebugOverlayUtility):
		return
	var inspector_binding: GFBindBuilder = gf_binder.bind_utility(GFRuntimeInspectorUtility)
	inspector_binding = inspector_binding.from_instance(_create_runtime_inspector_utility())
	if not await _bind_required(inspector_binding, scope, GFRuntimeInspectorUtility):
		return
	var screenshot_binding: GFBindBuilder = gf_binder.bind_utility(GFScreenshotUtility)
	screenshot_binding = screenshot_binding.from_instance(_create_screenshot_utility())
	if not await _bind_required(screenshot_binding, scope, GFScreenshotUtility):
		return
	if not await _bind_required(
		gf_binder.bind_utility(_GAME_DIAGNOSTICS_UTILITY_SCRIPT),
		scope,
		_GAME_DIAGNOSTICS_UTILITY_SCRIPT
	):
		return
	if not await _bind_required(
		gf_binder.bind_utility(TestToolUtility), scope, TestToolUtility
	):
		return


# --- 私有/辅助方法 ---

func _bind_required(
	binding: GFBindBuilder,
	scope: GFAsyncScope,
	target_script: Script
) -> bool:
	return await ProjectRequiredBinding.bind_singleton(
		binding,
		_architecture,
		scope,
		&"utility",
		target_script
	)


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
