## GameDiagnosticsUtility: 把项目业务工具接入 GF 诊断与支持报告能力。
class_name GameDiagnosticsUtility
extends GFUtility


# --- 常量 ---

const _CMD_SUPPORT_REPORT: String = "support_report"
const _LOG_TAG: String = "GameDiagnosticsUtility"
const _REPORT_DIRECTORY: String = "user://diagnostics"
# --- 私有变量 ---

var _registered_tool_ids: Array[StringName] = []
var _support_report_command_registered: bool = false
var _last_report_path: String = ""
var _diagnostics_utility: GFDiagnosticsUtility
var _support_report_utility: GFSupportReportUtility
var _console_utility: GFConsoleUtility
var _log_utility: GFLogUtility


# --- GF 生命周期方法 ---

## 注册项目诊断 provider 和支持报告命令。
func ready() -> void:
	_diagnostics_utility = _get_diagnostics_utility()
	_support_report_utility = _get_support_report_utility()
	_console_utility = _get_console_utility()
	_log_utility = _get_log_utility()
	_register_project_tool_snapshots()
	_register_support_report_command()


## 注销项目贡献，避免运行时重装 Architecture 时残留回调。
func dispose() -> void:
	if _diagnostics_utility != null:
		for tool_id: StringName in _registered_tool_ids:
			_diagnostics_utility.unregister_tool_snapshot_provider(tool_id)
	_registered_tool_ids.clear()

	if _support_report_command_registered and _console_utility != null:
		if _console_utility.has_command(_CMD_SUPPORT_REPORT):
			_console_utility.unregister_command(_CMD_SUPPORT_REPORT)
	_support_report_command_registered = false
	_last_report_path = ""
	_diagnostics_utility = null
	_support_report_utility = null
	_console_utility = null
	_log_utility = null


# --- 公共方法 ---

## 获取项目诊断接入状态。
func get_debug_snapshot() -> Dictionary:
	return {
		"registered_tool_ids": _registered_tool_ids.duplicate(),
		"support_report_command_registered": _support_report_command_registered,
		"last_report_path": _last_report_path,
	}


# --- 私有/辅助方法 ---

func _register_project_tool_snapshots() -> void:
	if _diagnostics_utility == null:
		return

	_register_tool_snapshot(&"resource_catalog", Callable(self, &"_collect_resource_catalog_snapshot"))
	_register_tool_snapshot(&"save_slots", Callable(self, &"_collect_save_slots_snapshot"))
	_register_tool_snapshot(&"asset_library", Callable(self, &"_collect_asset_library_snapshot"))
	_register_tool_snapshot(&"theme_catalog", Callable(self, &"_collect_theme_catalog_snapshot"))
	_register_tool_snapshot(&"themes", Callable(self, &"_collect_themes_snapshot"))
	_register_tool_snapshot(&"game_modes", Callable(self, &"_collect_game_modes_snapshot"))
	_register_tool_snapshot(&"ui_routes", Callable(self, &"_collect_ui_routes_snapshot"))
	_register_tool_snapshot(&"project_diagnostics", Callable(self, &"get_debug_snapshot"))


func _register_support_report_command() -> void:
	if _console_utility == null:
		return
	_console_utility.register_command(
		_CMD_SUPPORT_REPORT,
		Callable(self, &"_on_support_report_command"),
		"Build and save a GF support report. Optional arguments become the description."
	)
	_support_report_command_registered = true


func _register_tool_snapshot(tool_id: StringName, provider: Callable) -> void:
	if _diagnostics_utility.register_tool_snapshot_provider(tool_id, provider):
		_registered_tool_ids.append(tool_id)


func _collect_resource_catalog_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var utility: ProjectResourceCatalogUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_save_slots_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameSaveSlotWorkflowUtility)
	if utility_value is GameSaveSlotWorkflowUtility:
		var utility: GameSaveSlotWorkflowUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_asset_library_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameAssetLibraryUtility)
	if utility_value is GameAssetLibraryUtility:
		var utility: GameAssetLibraryUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_theme_catalog_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameThemeCatalogUtility)
	if utility_value is GameThemeCatalogUtility:
		var utility: GameThemeCatalogUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_themes_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameThemeUtility)
	if utility_value is GameThemeUtility:
		var utility: GameThemeUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_game_modes_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameModeConfigCacheUtility)
	if utility_value is GameModeConfigCacheUtility:
		var utility: GameModeConfigCacheUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_ui_routes_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameUiRouterUtility)
	if utility_value is GameUiRouterUtility:
		var utility: GameUiRouterUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _on_support_report_command(args: PackedStringArray) -> void:
	if _support_report_utility == null:
		if _log_utility != null:
			_log_utility.error(_LOG_TAG, "GFSupportReportUtility is unavailable.")
		return

	_last_report_path = "%s/support_report_%d.json" % [
		_REPORT_DIRECTORY,
		int(Time.get_unix_time_from_system()),
	]
	var description: String = " ".join(args)
	var error: Error = _support_report_utility.build_and_save_report(_last_report_path, description, {
		"tags": PackedStringArray(["runtime", "manual"]),
		"diagnostics_options": {
			"include_scene_tree": true,
			"include_signal_graph": true,
		},
	})
	if _log_utility == null:
		return
	if error == OK:
		_log_utility.info(_LOG_TAG, "Support report saved: %s" % ProjectSettings.globalize_path(_last_report_path))
	else:
		_log_utility.error(_LOG_TAG, "Failed to save support report: %s (error=%d)" % [_last_report_path, error])


func _get_diagnostics_utility() -> GFDiagnosticsUtility:
	var utility: Object = get_utility(GFDiagnosticsUtility)
	if utility is GFDiagnosticsUtility:
		var diagnostics: GFDiagnosticsUtility = utility
		return diagnostics
	return null


func _get_support_report_utility() -> GFSupportReportUtility:
	var utility: Object = get_utility(GFSupportReportUtility)
	if utility is GFSupportReportUtility:
		var support_reports: GFSupportReportUtility = utility
		return support_reports
	return null


func _get_console_utility() -> GFConsoleUtility:
	var utility: Object = get_utility(GFConsoleUtility)
	if utility is GFConsoleUtility:
		var console: GFConsoleUtility = utility
		return console
	return null


func _get_log_utility() -> GFLogUtility:
	var utility: Object = get_utility(GFLogUtility)
	if utility is GFLogUtility:
		var log_utility: GFLogUtility = utility
		return log_utility
	return null
