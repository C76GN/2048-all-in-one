## GameDiagnosticsUtility: 把项目业务工具接入 GF 诊断与支持报告能力。
class_name GameDiagnosticsUtility
extends GFUtility


# --- 常量 ---

const _CMD_SUPPORT_REPORT: String = "support_report"
const _CMD_SCREENSHOT: String = "screenshot"
const _LOG_TAG: String = "GameDiagnosticsUtility"
const _REPORT_DIRECTORY: String = "user://diagnostics"
const _SCREENSHOT_DIRECTORY: String = "user://diagnostics/screenshots"
const _PROJECT_OVERLAY_PANEL_ID: StringName = &"game.project_diagnostics"
const _RUNTIME_OVERLAY_TARGET_ID: StringName = &"game.debug_overlay"
const _RUNTIME_SCREENSHOT_TARGET_ID: StringName = &"game.screenshots"
const _MAX_SCENE_METADATA_NODES: int = 4096


# --- 私有变量 ---

var _registered_tool_ids: Array[StringName] = []
var _last_report_path: String = ""
var _last_screenshot_record: Dictionary = {}
var _diagnostics_utility: GFDiagnosticsUtility
var _support_report_utility: GFSupportReportUtility
var _console_utility: GFConsoleUtility
var _log_utility: GFLogUtility
var _clock_utility: GameClockUtility
var _asset_metadata_utility: GFAssetMetadataUtility
var _debug_overlay_utility: GFDebugOverlayUtility
var _runtime_inspector_utility: GFRuntimeInspectorUtility
var _screenshot_utility: GFScreenshotUtility
var _command_subscriptions: Array[GFLifetimeSubscription] = []


# --- GF 生命周期方法 ---

## 注册项目诊断 provider 和支持报告命令。
func get_required_utilities() -> Array[Script]:
	return [
		AchievementCatalogUtility,
		GameAssetLibraryUtility,
		GameClockUtility,
		GameModeCatalogUtility,
		GameSaveGraphUtility,
		GameThemeCatalogUtility,
		GameThemeUtility,
		GameUiRouterUtility,
		TileCatalogUtility,
		GFConsoleUtility,
		GFAssetMetadataUtility,
		GFDebugOverlayUtility,
		GFDiagnosticsUtility,
		GFLogUtility,
		GFRuntimeInspectorUtility,
		GFScreenshotUtility,
		GFSupportReportUtility,
		ProjectResourceCatalogUtility,
	]


func get_required_systems() -> Array[Script]:
	return [AchievementSystem, TileDiscoverySystem]


func ready() -> void:
	_diagnostics_utility = _get_diagnostics_utility()
	_support_report_utility = _get_support_report_utility()
	_console_utility = _get_console_utility()
	_log_utility = _get_log_utility()
	_clock_utility = _get_clock_utility()
	_asset_metadata_utility = _get_asset_metadata_utility()
	_debug_overlay_utility = _get_debug_overlay_utility()
	_runtime_inspector_utility = _get_runtime_inspector_utility()
	_screenshot_utility = _get_screenshot_utility()
	_register_console_commands()
	_configure_runtime_debug_tools()
	_refresh_project_tool_snapshots()


## 注销项目贡献，避免运行时重装 Architecture 时残留回调。
func dispose() -> void:
	if _diagnostics_utility != null:
		for tool_id: StringName in _registered_tool_ids:
			var _snapshot_removed: bool = _diagnostics_utility.remove_tool_snapshot(self, tool_id)
	_registered_tool_ids.clear()

	for subscription: GFLifetimeSubscription in _command_subscriptions:
		if subscription != null:
			var _command_cancelled: bool = subscription.cancel()
	_command_subscriptions.clear()

	if _runtime_inspector_utility != null:
		var _overlay_target_removed: bool = _runtime_inspector_utility.unregister_target(
			_RUNTIME_OVERLAY_TARGET_ID
		)
		var _screenshot_target_removed: bool = _runtime_inspector_utility.unregister_target(
			_RUNTIME_SCREENSHOT_TARGET_ID
		)
		_runtime_inspector_utility.detach_from_debug_overlay()
	if _debug_overlay_utility != null:
		_debug_overlay_utility.remove_panel(_PROJECT_OVERLAY_PANEL_ID)

	_last_report_path = ""
	_last_screenshot_record.clear()
	_diagnostics_utility = null
	_support_report_utility = null
	_console_utility = null
	_log_utility = null
	_clock_utility = null
	_asset_metadata_utility = null
	_debug_overlay_utility = null
	_runtime_inspector_utility = null
	_screenshot_utility = null


# --- 公共方法 ---

## 获取项目诊断接入状态。
func get_debug_snapshot() -> Dictionary:
	return {
		"registered_tool_ids": _registered_tool_ids.duplicate(),
		"registered_command_count": _command_subscriptions.size(),
		"support_report_command_registered": _console_has_command(_CMD_SUPPORT_REPORT),
		"screenshot_command_registered": _console_has_command(_CMD_SCREENSHOT),
		"overlay_panel_registered": (
			_debug_overlay_utility != null
			and _debug_overlay_utility.has_panel(_PROJECT_OVERLAY_PANEL_ID)
		),
		"runtime_inspector_attached": (
			_runtime_inspector_utility != null
			and _runtime_inspector_utility.has_target(_RUNTIME_OVERLAY_TARGET_ID)
		),
		"last_report_path": _last_report_path,
		"last_screenshot": _last_screenshot_record.duplicate(true),
	}


# --- 私有/辅助方法 ---

func _refresh_project_tool_snapshots() -> void:
	if _diagnostics_utility == null:
		return

	_publish_tool_snapshot(&"resource_catalog", _collect_resource_catalog_snapshot())
	_publish_tool_snapshot(&"save_graph", _collect_save_graph_snapshot())
	_publish_tool_snapshot(&"asset_library", _collect_asset_library_snapshot())
	_publish_tool_snapshot(&"theme_catalog", _collect_theme_catalog_snapshot())
	_publish_tool_snapshot(&"themes", _collect_themes_snapshot())
	_publish_tool_snapshot(&"game_modes", _collect_game_modes_snapshot())
	_publish_tool_snapshot(&"tile_catalog", _collect_tile_catalog_snapshot())
	_publish_tool_snapshot(&"tile_discoveries", _collect_tile_discoveries_snapshot())
	_publish_tool_snapshot(&"achievement_catalog", _collect_achievement_catalog_snapshot())
	_publish_tool_snapshot(&"achievements", _collect_achievements_snapshot())
	_publish_tool_snapshot(&"ui_routes", _collect_ui_routes_snapshot())
	_publish_tool_snapshot(&"scene_asset_metadata", _collect_scene_asset_metadata_snapshot())
	_publish_tool_snapshot(&"debug_overlay", _collect_debug_overlay_snapshot())
	_publish_tool_snapshot(&"runtime_inspector", _collect_runtime_inspector_snapshot())
	_publish_tool_snapshot(&"screenshots", _collect_screenshot_snapshot())
	_publish_tool_snapshot(&"architecture_dependencies", _collect_architecture_dependency_snapshot())
	_publish_tool_snapshot(&"project_diagnostics", get_debug_snapshot())
	_refresh_project_overlay_panel()


func _register_console_commands() -> void:
	if _console_utility == null:
		return
	_register_console_command(
		_CMD_SUPPORT_REPORT,
		Callable(self, &"_on_support_report_command"),
		"Build a GF support report and capture the current viewport. Optional arguments become the description."
	)
	_register_console_command(
		_CMD_SCREENSHOT,
		Callable(self, &"_on_screenshot_command"),
		"Capture the current viewport. The first optional argument sets the filename prefix."
	)


func _register_console_command(command: String, callback: Callable, description: String) -> void:
	var subscription: GFLifetimeSubscription = _console_utility.register_command(
		self,
		command,
		callback,
		description,
		{"tier": GFConsoleUtility.CommandTier.CONTROL}
	)
	if subscription != null:
		_command_subscriptions.append(subscription)


func _configure_runtime_debug_tools() -> void:
	if _runtime_inspector_utility == null:
		return

	if _debug_overlay_utility != null:
		var refresh_interval_property: GFRuntimeTunableProperty = _make_range_property(
			&"refresh_interval_seconds",
			NodePath("refresh_interval_seconds"),
			GFRuntimeTunableProperty.ValueKind.FLOAT,
			"Refresh interval",
			0.05,
			2.0,
			0.05
		)
		refresh_interval_property.setter = Callable(
			self,
			&"_set_overlay_refresh_interval"
		)
		var overlay_properties: Array[GFRuntimeTunableProperty] = [
			refresh_interval_property,
			_make_property(
				&"include_recent_logs",
				NodePath("include_recent_logs"),
				GFRuntimeTunableProperty.ValueKind.BOOL,
				"Include recent logs"
			),
			_make_range_property(
				&"recent_log_count",
				NodePath("recent_log_count"),
				GFRuntimeTunableProperty.ValueKind.INT,
				"Recent log count",
				0.0,
				64.0,
				1.0
			),
		]
		var _overlay_registered: bool = _runtime_inspector_utility.register_target(
			_RUNTIME_OVERLAY_TARGET_ID,
			_debug_overlay_utility,
			overlay_properties,
			{"label": "Debug Overlay", "group": "Diagnostics"}
		)

	if _screenshot_utility != null:
		var format_property: GFRuntimeTunableProperty = _make_property(
			&"default_format",
			NodePath("default_format"),
			GFRuntimeTunableProperty.ValueKind.STRING,
			"Image format"
		)
		var _format_options_configured: GFRuntimeTunableProperty = format_property.with_options([
			GFScreenshotUtility.FORMAT_PNG,
			GFScreenshotUtility.FORMAT_JPG,
			GFScreenshotUtility.FORMAT_WEBP,
		])
		var screenshot_properties: Array[GFRuntimeTunableProperty] = [
			format_property,
			_make_range_property(
				&"default_quality",
				NodePath("default_quality"),
				GFRuntimeTunableProperty.ValueKind.FLOAT,
				"Lossy quality",
				0.1,
				1.0,
				0.05
			),
			_make_property(
				&"default_unique_paths",
				NodePath("default_unique_paths"),
				GFRuntimeTunableProperty.ValueKind.BOOL,
				"Unique paths"
			),
		]
		var _screenshots_registered: bool = _runtime_inspector_utility.register_target(
			_RUNTIME_SCREENSHOT_TARGET_ID,
			_screenshot_utility,
			screenshot_properties,
			{"label": "Screenshots", "group": "Diagnostics"}
		)

	var _inspector_attached: bool = _runtime_inspector_utility.attach_to_debug_overlay()


func _make_property(
	property_id: StringName,
	property_name: NodePath,
	value_kind: GFRuntimeTunableProperty.ValueKind,
	label: String
) -> GFRuntimeTunableProperty:
	var property: GFRuntimeTunableProperty = GFRuntimeTunableProperty.new(
		property_id,
		property_name,
		value_kind
	)
	property.label = label
	property.group = "Diagnostics"
	return property


func _make_range_property(
	property_id: StringName,
	property_name: NodePath,
	value_kind: GFRuntimeTunableProperty.ValueKind,
	label: String,
	min_value: float,
	max_value: float,
	step: float
) -> GFRuntimeTunableProperty:
	var property: GFRuntimeTunableProperty = _make_property(
		property_id,
		property_name,
		value_kind,
		label
	)
	var _range_configured: bool = property.configure_range(min_value, max_value, step)
	return property


func _set_overlay_refresh_interval(
	target: Object,
	_property: GFRuntimeTunableProperty,
	value: Variant
) -> void:
	if target is GFDebugOverlayUtility:
		var overlay: GFDebugOverlayUtility = target
		overlay.set_refresh_interval(GFVariantData.to_float(value, 0.25))


func _publish_tool_snapshot(tool_id: StringName, snapshot: Dictionary) -> void:
	if _diagnostics_utility.publish_tool_snapshot(self, tool_id, snapshot):
		if _registered_tool_ids.has(tool_id):
			return
		_registered_tool_ids.append(tool_id)


func _collect_resource_catalog_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(ProjectResourceCatalogUtility)
	if utility_value is ProjectResourceCatalogUtility:
		var utility: ProjectResourceCatalogUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_save_graph_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameSaveGraphUtility)
	if utility_value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = utility_value
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
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var utility: GameModeCatalogUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_tile_catalog_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(TileCatalogUtility)
	if utility_value is TileCatalogUtility:
		var utility: TileCatalogUtility = utility_value
		return utility.get_debug_snapshot()
	return _make_unavailable_snapshot("TileCatalogUtility is unavailable.")


func _collect_tile_discoveries_snapshot() -> Dictionary:
	var system_value: Object = get_system(TileDiscoverySystem)
	if system_value is TileDiscoverySystem:
		var system: TileDiscoverySystem = system_value
		return system.get_discovery_summary()
	return _make_unavailable_snapshot("TileDiscoverySystem is unavailable.")


func _collect_achievement_catalog_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(AchievementCatalogUtility)
	if utility_value is AchievementCatalogUtility:
		var utility: AchievementCatalogUtility = utility_value
		return utility.get_debug_snapshot()
	return _make_unavailable_snapshot("AchievementCatalogUtility is unavailable.")


func _collect_achievements_snapshot() -> Dictionary:
	var system_value: Object = get_system(AchievementSystem)
	if system_value is AchievementSystem:
		var system: AchievementSystem = system_value
		return system.get_debug_snapshot()
	return _make_unavailable_snapshot("AchievementSystem is unavailable.")


func _collect_ui_routes_snapshot() -> Dictionary:
	var utility_value: Object = get_utility(GameUiRouterUtility)
	if utility_value is GameUiRouterUtility:
		var utility: GameUiRouterUtility = utility_value
		return utility.get_debug_snapshot()
	return {}


func _collect_scene_asset_metadata_snapshot() -> Dictionary:
	if _asset_metadata_utility == null:
		return _make_unavailable_snapshot("GFAssetMetadataUtility is unavailable.")
	var scene: Node = _get_current_scene()
	if scene == null:
		return _make_unavailable_snapshot("Current scene is unavailable.")
	return _asset_metadata_utility.build_node_tree_report(scene, {
		"source_path": scene.scene_file_path,
		"max_nodes": _MAX_SCENE_METADATA_NODES,
	})


func _collect_debug_overlay_snapshot() -> Dictionary:
	if _debug_overlay_utility == null:
		return _make_unavailable_snapshot("GFDebugOverlayUtility is unavailable.")
	return _debug_overlay_utility.get_debug_snapshot()


func _collect_runtime_inspector_snapshot() -> Dictionary:
	if _runtime_inspector_utility == null:
		return _make_unavailable_snapshot("GFRuntimeInspectorUtility is unavailable.")
	return _runtime_inspector_utility.get_debug_snapshot()


func _collect_screenshot_snapshot() -> Dictionary:
	return {
		"available": _screenshot_utility != null,
		"last_capture": _last_screenshot_record.duplicate(true),
		"save_directory": (
			_screenshot_utility.default_save_dir if _screenshot_utility != null else ""
		),
	}


func _collect_architecture_dependency_snapshot() -> Dictionary:
	var architecture: GFArchitecture = _get_architecture_or_null()
	if architecture == null:
		return {}
	return architecture.get_dependency_diagnostics({
		"include_parent_lookup": false,
		"include_factories": true,
	})


func _make_unavailable_snapshot(reason: String) -> Dictionary:
	return {
		"ok": true,
		"healthy": true,
		"available": false,
		"reason": reason,
	}


func _get_current_scene() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		return tree.current_scene
	return null


func _refresh_project_overlay_panel() -> void:
	if _debug_overlay_utility == null:
		return
	var scene: Node = _get_current_scene()
	var scene_path: String = scene.scene_file_path if scene != null else "<none>"
	var metadata: Dictionary = _collect_scene_asset_metadata_snapshot()
	var screenshot_path: String = GFVariantData.get_option_string(
		_last_screenshot_record,
		"path",
		"<none>"
	)
	var panel_text: String = "\n".join(PackedStringArray([
		"Scene: %s" % scene_path,
		"Project snapshots: %d" % _registered_tool_ids.size(),
		"Scene asset metadata: %d entries / %d nodes" % [
			GFVariantData.get_option_int(metadata, "entry_count"),
			GFVariantData.get_option_int(metadata, "visited_node_count"),
		],
		"Last support report: %s" % (_last_report_path if not _last_report_path.is_empty() else "<none>"),
		"Last screenshot: %s" % screenshot_path,
	]))
	var _panel_published: bool = _debug_overlay_utility.push_panel_text(
		_PROJECT_OVERLAY_PANEL_ID,
		panel_text,
		{"label": "2048 Project", "group": "Project"}
	)


func _on_support_report_command(args: PackedStringArray) -> void:
	if _support_report_utility == null:
		if _log_utility != null:
			_log_utility.error(_LOG_TAG, "GFSupportReportUtility is unavailable.")
		return
	if _clock_utility == null:
		if _log_utility != null:
			_log_utility.error(_LOG_TAG, "GameClockUtility is unavailable.")
		return

	_last_report_path = "%s/support_report_%d.json" % [
		_REPORT_DIRECTORY,
		_clock_utility.get_unix_timestamp(),
	]
	_capture_screenshot("support")
	_refresh_project_tool_snapshots()
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


func _on_screenshot_command(args: PackedStringArray) -> void:
	var prefix: String = "manual"
	if not args.is_empty() and not args[0].strip_edges().is_empty():
		prefix = args[0].strip_edges()
	_capture_screenshot(prefix)
	_refresh_project_tool_snapshots()


func _capture_screenshot(prefix: String) -> void:
	if _screenshot_utility == null:
		_last_screenshot_record = {
			"ok": false,
			"path": "",
			"reason": "screenshot_utility_unavailable",
		}
		_log_screenshot_result()
		return
	_last_screenshot_record = _screenshot_utility.save_viewport_screenshot("", {
		"directory": _SCREENSHOT_DIRECTORY,
		"prefix": prefix,
		"format": GFScreenshotUtility.FORMAT_PNG,
		"unique": true,
	})
	_log_screenshot_result()


func _log_screenshot_result() -> void:
	if _log_utility == null:
		return
	if GFVariantData.get_option_bool(_last_screenshot_record, "ok"):
		var path: String = GFVariantData.get_option_string(_last_screenshot_record, "path")
		_log_utility.info(
			_LOG_TAG,
			"Screenshot saved: %s" % ProjectSettings.globalize_path(path)
		)
		return
	_log_utility.warn(
		_LOG_TAG,
		"Screenshot capture failed: %s" % GFVariantData.get_option_string(
			_last_screenshot_record,
			"reason",
			"unknown"
		)
	)


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


func _console_has_command(command: String) -> bool:
	return _console_utility != null and _console_utility.has_command(command)


func _get_log_utility() -> GFLogUtility:
	var utility: Object = get_utility(GFLogUtility)
	if utility is GFLogUtility:
		var log_utility: GFLogUtility = utility
		return log_utility
	return null


func _get_clock_utility() -> GameClockUtility:
	var utility: Object = get_utility(GameClockUtility)
	if utility is GameClockUtility:
		var clock_utility: GameClockUtility = utility
		return clock_utility
	return null


func _get_asset_metadata_utility() -> GFAssetMetadataUtility:
	var utility: Object = get_utility(GFAssetMetadataUtility)
	if utility is GFAssetMetadataUtility:
		var asset_metadata: GFAssetMetadataUtility = utility
		return asset_metadata
	return null


func _get_debug_overlay_utility() -> GFDebugOverlayUtility:
	var utility: Object = get_utility(GFDebugOverlayUtility)
	if utility is GFDebugOverlayUtility:
		var debug_overlay: GFDebugOverlayUtility = utility
		return debug_overlay
	return null


func _get_runtime_inspector_utility() -> GFRuntimeInspectorUtility:
	var utility: Object = get_utility(GFRuntimeInspectorUtility)
	if utility is GFRuntimeInspectorUtility:
		var runtime_inspector: GFRuntimeInspectorUtility = utility
		return runtime_inspector
	return null


func _get_screenshot_utility() -> GFScreenshotUtility:
	var utility: Object = get_utility(GFScreenshotUtility)
	if utility is GFScreenshotUtility:
		var screenshots: GFScreenshotUtility = utility
		return screenshots
	return null
