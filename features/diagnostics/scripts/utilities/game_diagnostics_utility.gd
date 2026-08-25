## GameDiagnosticsUtility: 把项目业务工具接入 GF 诊断与支持报告能力。
class_name GameDiagnosticsUtility
extends GFUtility


# --- 常量 ---

const _CMD_SUPPORT_REPORT: String = "support_report"
const _CMD_SCREENSHOT: String = "screenshot"
const _CMD_ACCEPTANCE_BEGIN: String = "acceptance.begin"
const _CMD_ACCEPTANCE_END: String = "acceptance.end"
const _LOG_TAG: String = "GameDiagnosticsUtility"
const _REPORT_DIRECTORY: String = "user://diagnostics"
const _SCREENSHOT_DIRECTORY: String = "user://diagnostics/screenshots"
const _PROJECT_OVERLAY_PANEL_ID: StringName = &"game.project_diagnostics"
const _RUNTIME_OVERLAY_TARGET_ID: StringName = &"game.debug_overlay"
const _RUNTIME_SCREENSHOT_TARGET_ID: StringName = &"game.screenshots"
const _MAX_SCENE_METADATA_NODES: int = 256
const _RUNTIME_LOADING_PROVIDER_ID: StringName = &"runtime_loading"
const _MAX_RUNTIME_LOADING_PATHS: int = 32
const _RUNTIME_LOADING_MAX_DURATION_USEC: int = 50_000
const _MAX_ACCEPTANCE_COMMAND_JSON_BYTES: int = 2048
const _MAX_ACCEPTANCE_COMMAND_JSON_DEPTH: int = 4


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
var _performance_trace_utility: GamePerformanceTraceUtility
var _input_mapping_utility: GFInputMappingUtility
var _asset_utility: GFAssetUtility
var _scene_utility: GFSceneUtility
var _render_warmup_utility: GFRenderWarmupUtility
var _command_subscriptions: Array[GFLifetimeSubscription] = []
var _diagnostic_providers: Dictionary = {}


# --- GF 生命周期方法 ---

## 注册项目诊断 provider 和支持报告命令。
func get_required_utilities() -> Array[Script]:
	return [
		AchievementCatalogUtility,
		GameAssetLibraryUtility,
		GameClockUtility,
		GamePerformanceTraceUtility,
		GameModeCatalogUtility,
		GameSaveGraphUtility,
		GameThemeCatalogUtility,
		GameThemeUtility,
		GameUiRouterUtility,
		TileCatalogUtility,
		GFConsoleUtility,
		GFAssetUtility,
		GFAssetMetadataUtility,
		GFDebugOverlayUtility,
		GFDiagnosticsUtility,
		GFLogUtility,
		GFInputMappingUtility,
		GFRenderWarmupUtility,
		GFRuntimeInspectorUtility,
		GFSceneUtility,
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
	_performance_trace_utility = _get_performance_trace_utility()
	_input_mapping_utility = _get_input_mapping_utility()
	_asset_utility = _get_asset_utility()
	_scene_utility = _get_scene_utility()
	_render_warmup_utility = _get_render_warmup_utility()
	_register_console_commands()
	_configure_runtime_debug_tools()
	_refresh_project_tool_snapshots()


## 注销项目贡献，避免运行时重装 Architecture 时残留回调。
func dispose() -> void:
	if _diagnostics_utility != null:
		for provider_id_value: Variant in _diagnostic_providers.keys():
			var provider_id: StringName = GFVariantData.to_string_name(
				provider_id_value
			)
			var _provider_removed: bool = (
				_diagnostics_utility.unregister_diagnostic_provider(
					self,
					provider_id
				)
			)
		for tool_id: StringName in _registered_tool_ids:
			var _snapshot_removed: bool = _diagnostics_utility.remove_tool_snapshot(self, tool_id)
	_diagnostic_providers.clear()
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
	_performance_trace_utility = null
	_input_mapping_utility = null
	_asset_utility = null
	_scene_utility = null
	_render_warmup_utility = null


# --- 公共方法 ---

## 获取项目诊断接入状态。
func get_debug_snapshot() -> Dictionary:
	var provider_ids: PackedStringArray = PackedStringArray()
	for provider_id_value: Variant in _diagnostic_providers.keys():
		var _provider_id_appended: bool = provider_ids.append(
			String(GFVariantData.to_string_name(provider_id_value))
		)
	provider_ids.sort()
	return {
		"registered_tool_ids": _registered_tool_ids.duplicate(),
		"registered_provider_ids": provider_ids,
		"registered_command_count": _command_subscriptions.size(),
		"support_report_command_registered": _console_has_command(_CMD_SUPPORT_REPORT),
		"screenshot_command_registered": _console_has_command(_CMD_SCREENSHOT),
		"acceptance_begin_command_registered": _console_has_command(
			_CMD_ACCEPTANCE_BEGIN
		),
		"acceptance_end_command_registered": _console_has_command(
			_CMD_ACCEPTANCE_END
		),
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


## 由惰性 Provider 按稳定标识采集一次只读快照。
## @param provider_id: 已注册的项目诊断 Provider 标识。
func collect_diagnostic_snapshot(provider_id: StringName) -> Dictionary:
	match provider_id:
		&"resource_catalog":
			return _collect_resource_catalog_snapshot()
		&"save_graph":
			return _collect_save_graph_snapshot()
		&"asset_library":
			return _collect_asset_library_snapshot()
		&"theme_catalog":
			return _collect_theme_catalog_snapshot()
		&"themes":
			return _collect_themes_snapshot()
		&"game_modes":
			return _collect_game_modes_snapshot()
		&"tile_catalog":
			return _collect_tile_catalog_snapshot()
		&"tile_discoveries":
			return _collect_tile_discoveries_snapshot()
		&"achievement_catalog":
			return _collect_achievement_catalog_snapshot()
		&"achievements":
			return _collect_achievements_snapshot()
		&"ui_routes":
			return _collect_ui_routes_snapshot()
		&"scene_asset_metadata":
			return _collect_scene_asset_metadata_snapshot()
		&"debug_overlay":
			return _collect_debug_overlay_snapshot()
		&"runtime_inspector":
			return _collect_runtime_inspector_snapshot()
		&"screenshots":
			return _collect_screenshot_snapshot()
		&"project_diagnostics":
			return get_debug_snapshot()
		&"gameplay_move_trace":
			return _collect_gameplay_move_trace_snapshot()
		&"virtual_inputs":
			return _collect_virtual_input_sources_snapshot()
		_RUNTIME_LOADING_PROVIDER_ID:
			return _collect_runtime_loading_snapshot()
		_:
			return {}


## 显式开始一个与 GameplayAcceptanceMatrix 完整匹配的真实采样窗口。
##
## observed_contract 会先经过矩阵白名单与精确条件核对；匹配失败时不会创建
## GFMetricSeries，也不会把调用方附带的额外字段保留到诊断状态。
## @param case_id: GameplayAcceptanceMatrix 中待观测的验收 case 标识。
## @param observed_contract: 本次真实采样环境的受支持条件字典。
func begin_gameplay_acceptance_case(
	case_id: StringName,
	observed_contract: Dictionary
) -> Dictionary:
	var match_report: Dictionary = GameplayAcceptanceMatrix.match_observed_contract(
		case_id,
		observed_contract
	)
	if not GFVariantData.get_option_bool(match_report, &"ok"):
		return {
			&"accepted": false,
			&"reason": GFVariantData.get_option_string_name(
				match_report,
				&"reason",
				&"observed_contract_mismatch"
			),
			&"contract_match": match_report,
		}
	if not is_instance_valid(_performance_trace_utility):
		return {
			&"accepted": false,
			&"reason": &"performance_trace_unavailable",
			&"contract_match": match_report,
		}

	var acceptance_case: Dictionary = GameplayAcceptanceMatrix.get_case(case_id)
	var observation: GamePerformanceAcceptanceObservation = (
		GamePerformanceAcceptanceObservation.new().configure(
			case_id,
			GFVariantData.get_option_dictionary(
				match_report,
				&"observed_contract"
			),
			GFVariantData.get_option_int(
				acceptance_case,
				&"minimum_samples"
			)
		)
	)
	var result: Dictionary = (
		_performance_trace_utility.begin_acceptance_measurement(observation)
	)
	result[&"contract_match"] = match_report
	_refresh_gameplay_acceptance_tool_snapshot()
	return result


## 终结当前采样窗口并刷新 GF Diagnostics 缓存中的评估快照。
func finish_gameplay_acceptance_case() -> Dictionary:
	if not is_instance_valid(_performance_trace_utility):
		return {
			&"ok": false,
			&"measurement_status": &"not_measured",
			&"measurement_reason": &"performance_trace_unavailable",
		}
	var _finished: Dictionary = (
		_performance_trace_utility.finish_acceptance_measurement()
	)
	var snapshot: Dictionary = _collect_gameplay_acceptance_matrix_snapshot()
	if _diagnostics_utility != null:
		_publish_tool_snapshot(&"gameplay_acceptance_matrix", snapshot)
	return snapshot


# --- 私有/辅助方法 ---

func _refresh_project_tool_snapshots() -> void:
	if _diagnostics_utility == null:
		return

	_register_lazy_snapshot_provider(
		&"resource_catalog"
	)
	_register_lazy_snapshot_provider(
		&"save_graph"
	)
	_register_lazy_snapshot_provider(
		&"asset_library"
	)
	_register_lazy_snapshot_provider(
		&"theme_catalog"
	)
	_register_lazy_snapshot_provider(
		&"themes"
	)
	_register_lazy_snapshot_provider(
		&"game_modes"
	)
	_register_lazy_snapshot_provider(
		&"tile_catalog"
	)
	_register_lazy_snapshot_provider(
		&"tile_discoveries"
	)
	_register_lazy_snapshot_provider(
		&"achievement_catalog"
	)
	_register_lazy_snapshot_provider(
		&"achievements"
	)
	_register_lazy_snapshot_provider(
		&"ui_routes"
	)
	_register_lazy_snapshot_provider(
		&"scene_asset_metadata",
		75_000
	)
	_register_lazy_snapshot_provider(
		&"debug_overlay"
	)
	_register_lazy_snapshot_provider(
		&"runtime_inspector"
	)
	_register_lazy_snapshot_provider(
		&"screenshots"
	)
	_register_lazy_snapshot_provider(
		&"project_diagnostics"
	)
	_register_lazy_snapshot_provider(
		&"gameplay_move_trace"
	)
	_register_lazy_snapshot_provider(
		&"virtual_inputs"
	)
	_register_lazy_snapshot_provider(
		_RUNTIME_LOADING_PROVIDER_ID,
		_RUNTIME_LOADING_MAX_DURATION_USEC
	)

	# 仅发布架构就绪后不再变化、且采集成本固定的缓存事实。
	_refresh_gameplay_acceptance_tool_snapshot()
	_publish_tool_snapshot(&"architecture_dependencies", _collect_architecture_dependency_snapshot())
	_refresh_project_overlay_panel()


func _refresh_gameplay_acceptance_tool_snapshot() -> void:
	if _diagnostics_utility == null:
		return
	_publish_tool_snapshot(
		&"gameplay_acceptance_matrix",
		_collect_gameplay_acceptance_matrix_snapshot()
	)


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
	_register_console_command(
		_CMD_ACCEPTANCE_BEGIN,
		Callable(self, &"_on_acceptance_begin_command"),
		(
			"Begin an explicitly observed gameplay acceptance case. "
			+ "Arguments: <case_id> <bounded JSON object>."
		)
	)
	_register_console_command(
		_CMD_ACCEPTANCE_END,
		Callable(self, &"_on_acceptance_end_command"),
		"Finish the active gameplay acceptance capture and evaluate its evidence."
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


func _register_lazy_snapshot_provider(
	provider_id: StringName,
	max_duration_usec: int = GFDiagnosticSnapshotProvider.DEFAULT_MAX_DURATION_USEC
) -> void:
	if (
		_diagnostic_providers.has(provider_id)
		and _diagnostics_utility.has_diagnostic_provider(provider_id)
	):
		return
	var provider: GameDiagnosticSnapshotProvider = (
		GameDiagnosticSnapshotProvider.new()
	)
	var _provider_configured: GameDiagnosticSnapshotProvider = (
		provider.configure_collector(provider_id, self, {
			"max_duration_usec": max_duration_usec,
			"metadata": {
				"feature": "project",
				"collection": "explicit_support_request_only",
			},
		})
	)
	if _diagnostics_utility.register_diagnostic_provider(self, provider):
		_diagnostic_providers[provider_id] = provider


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


func _collect_gameplay_acceptance_matrix_snapshot() -> Dictionary:
	var validation_report: GFValidationReport = GameplayAcceptanceMatrix.get_validation_report()
	var snapshot: Dictionary = {
		&"ok": validation_report.is_ok(),
		&"validation": validation_report.to_dict(),
		&"cases": GameplayAcceptanceMatrix.get_cases(),
		&"measured_results": [],
		&"measurement_status": &"not_measured",
		&"measurement_reason": &"not_measured",
	}
	if not is_instance_valid(_performance_trace_utility):
		snapshot[&"measurement_reason"] = &"performance_trace_unavailable"
		return snapshot

	var state: Dictionary = (
		_performance_trace_utility.get_acceptance_measurement_state()
	)
	snapshot[&"measurement"] = state
	if not GFVariantData.get_option_bool(state, &"configured"):
		snapshot[&"measurement_reason"] = GFVariantData.get_option_string_name(
			state,
			&"reason",
			&"not_measured"
		)
		return snapshot
	if GFVariantData.get_option_bool(state, &"active"):
		snapshot[&"measurement_status"] = &"partial"
		snapshot[&"measurement_reason"] = &"capture_active"
		return snapshot
	if not GFVariantData.get_option_bool(state, &"eligible_for_evaluation"):
		snapshot[&"measurement_status"] = &"partial"
		snapshot[&"measurement_reason"] = GFVariantData.get_option_string_name(
			state,
			&"reason",
			&"evidence_invalidated"
		)
		return snapshot

	var bundle: Dictionary = (
		_performance_trace_utility.get_acceptance_measurement_bundle()
	)
	var observed_contract: Dictionary = GFVariantData.get_option_dictionary(
		bundle,
		&"observation"
	)
	var case_id: StringName = GFVariantData.get_option_string_name(
		observed_contract,
		&"case_id"
	)
	var match_report: Dictionary = GameplayAcceptanceMatrix.match_observed_contract(
		case_id,
		observed_contract
	)
	snapshot[&"contract_match"] = match_report
	if not GFVariantData.get_option_bool(match_report, &"ok"):
		snapshot[&"measurement_status"] = &"partial"
		snapshot[&"measurement_reason"] = &"observed_contract_mismatch"
		return snapshot

	var frame_series_value: Variant = bundle.get(&"frame_time_ms")
	var input_series_value: Variant = bundle.get(&"input_feedback_ms")
	if (
		not frame_series_value is GFMetricSeries
		or not input_series_value is GFMetricSeries
	):
		snapshot[&"measurement_status"] = &"partial"
		snapshot[&"measurement_reason"] = &"missing_metric_series"
		return snapshot
	var frame_series: GFMetricSeries = frame_series_value
	var input_series: GFMetricSeries = input_series_value
	var measured_result: Dictionary = GameplayAcceptanceMatrix.evaluate_case(
		case_id,
		frame_series,
		input_series
	)
	snapshot[&"measured_results"] = [measured_result]
	var evaluation_reason: StringName = GFVariantData.get_option_string_name(
		measured_result,
		&"reason"
	)
	if evaluation_reason != &"evaluated":
		snapshot[&"measurement_status"] = &"partial"
		snapshot[&"measurement_reason"] = evaluation_reason
		return snapshot
	snapshot[&"measurement_status"] = &"evaluated"
	snapshot[&"measurement_reason"] = &"evaluated"
	return snapshot


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


func _collect_gameplay_move_trace_snapshot() -> Dictionary:
	if not is_instance_valid(_performance_trace_utility):
		return _make_unavailable_snapshot(
			"GamePerformanceTraceUtility is unavailable."
		)
	return _performance_trace_utility.build_support_snapshot()


func _collect_virtual_input_sources_snapshot() -> Dictionary:
	if not is_instance_valid(_input_mapping_utility):
		return _make_unavailable_snapshot(
			"GFInputMappingUtility is unavailable."
		)
	return {
		"available": true,
		"touch_swipe": (
			_input_mapping_utility.get_virtual_source_snapshot_for_player(
				BoardWorldViewportController.TOUCH_INPUT_SOURCE_ID,
				-1
			)
		),
		"hud_controls": (
			_input_mapping_utility.get_virtual_source_snapshot_for_player(
				Hud.HUD_INPUT_SOURCE_ID,
				-1
			)
		),
	}


func _collect_runtime_loading_snapshot() -> Dictionary:
	return {
		"available": (
			is_instance_valid(_asset_utility)
			or is_instance_valid(_scene_utility)
			or is_instance_valid(_render_warmup_utility)
		),
		"collection": "explicit_support_request_only",
		"bounds": {
			"max_paths_per_list": _MAX_RUNTIME_LOADING_PATHS,
			"filesystem_scan": false,
			"scene_tree_scan": false,
			"absolute_paths": false,
		},
		"assets": _collect_asset_loading_snapshot(),
		"scenes": _collect_scene_loading_snapshot(),
		"render_warmup": _collect_render_warmup_snapshot(),
	}


func _collect_asset_loading_snapshot() -> Dictionary:
	if not is_instance_valid(_asset_utility):
		return _make_unavailable_snapshot("GFAssetUtility is unavailable.")
	var source: Dictionary = _asset_utility.get_debug_snapshot()
	var broker: Dictionary = GFVariantData.get_option_dictionary(
		source,
		"resource_broker"
	)
	return {
		"available": true,
		"max_cache_size": GFVariantData.get_option_int(
			source,
			"max_cache_size"
		),
		"cache_count": GFVariantData.get_option_int(source, "cache_count"),
		"pending_count": GFVariantData.get_option_int(source, "pending_count"),
		"queued_count": GFVariantData.get_option_int(source, "queued_count"),
		"pinned_count": GFVariantData.get_option_int(source, "pinned_count"),
		"group_count": GFVariantData.get_option_int(source, "group_count"),
		"active_preload_session_count": (
			_asset_utility.get_active_preload_session_count()
		),
		"cached_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "cached_paths")
		),
		"pending_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "pending_paths")
		),
		"queued_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "queued_paths")
		),
		"pinned_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "pinned_paths")
		),
		"resource_broker": _make_runtime_broker_snapshot(broker),
	}


func _collect_scene_loading_snapshot() -> Dictionary:
	if not is_instance_valid(_scene_utility):
		return _make_unavailable_snapshot("GFSceneUtility is unavailable.")
	var source: Dictionary = _scene_utility.get_scene_cache_debug_snapshot()
	var transition: Dictionary = GFVariantData.get_option_dictionary(
		source,
		"transition"
	)
	var preload_cache: Dictionary = GFVariantData.get_option_dictionary(
		source,
		"preload_cache"
	)
	var preloading: Dictionary = GFVariantData.get_option_dictionary(
		source,
		"preloading"
	)
	var background: Dictionary = GFVariantData.get_option_dictionary(
		source,
		"background"
	)
	return {
		"available": true,
		"is_loading": GFVariantData.get_option_bool(source, "is_loading"),
		"target_path": _sanitize_runtime_loading_path(
			GFVariantData.get_option_string(source, "target_path")
		),
		"loading_progress": clampf(
			GFVariantData.get_option_float(source, "loading_progress"),
			0.0,
			1.0
		),
		"current_scene": _sanitize_runtime_loading_path(
			GFVariantData.get_option_string(source, "current_scene")
		),
		"previous_scene": _sanitize_runtime_loading_path(
			GFVariantData.get_option_string(source, "previous_scene")
		),
		"transition": {
			"minimum_duration_seconds": GFVariantData.get_option_float(
				transition,
				"minimum_duration_seconds"
			),
			"cache_loaded_scene": GFVariantData.get_option_bool(
				transition,
				"cache_loaded_scene"
			),
			"history_size": GFVariantData.get_option_int(
				transition,
				"history_size"
			),
			"pending_completion": GFVariantData.get_option_bool(
				transition,
				"pending_completion"
			),
		},
		"preload_cache": {
			"size": GFVariantData.get_option_int(preload_cache, "size"),
			"max_size": GFVariantData.get_option_int(preload_cache, "max_size"),
			"fixed_size": GFVariantData.get_option_int(
				preload_cache,
				"fixed_size"
			),
			"temporary_size": GFVariantData.get_option_int(
				preload_cache,
				"temporary_size"
			),
			"paths": _make_bounded_runtime_path_list(
				GFVariantData.get_option_value(preload_cache, "paths")
			),
		},
		"preloading": {
			"size": GFVariantData.get_option_int(preloading, "size"),
			"paths": _make_bounded_runtime_path_list(
				GFVariantData.get_option_value(preloading, "paths")
			),
		},
		"background_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(background, "paths")
		),
		"resource_broker": _make_runtime_broker_snapshot(
			GFVariantData.get_option_dictionary(source, "resource_broker")
		),
	}


func _collect_render_warmup_snapshot() -> Dictionary:
	if not is_instance_valid(_render_warmup_utility):
		return _make_unavailable_snapshot(
			"GFRenderWarmupUtility is unavailable."
		)
	var source: Dictionary = _render_warmup_utility.get_debug_snapshot()
	return {
		"available": true,
		"queue_size": GFVariantData.get_option_int(source, "queue_size"),
		"cached_resource_count": GFVariantData.get_option_int(
			source,
			"cached_resource_count"
		),
		"processed_entry_count": GFVariantData.get_option_int(
			source,
			"processed_entry_count"
		),
		"failed_entry_count": GFVariantData.get_option_int(
			source,
			"failed_entry_count"
		),
		"default_entries_per_tick": GFVariantData.get_option_int(
			source,
			"default_entries_per_tick"
		),
		"default_max_seconds": GFVariantData.get_option_float(
			source,
			"default_max_seconds"
		),
		"default_touch_mode": GFVariantData.get_option_int(
			source,
			"default_touch_mode"
		),
		"keep_resources_cached": GFVariantData.get_option_bool(
			source,
			"keep_resources_cached"
		),
		"max_cached_resources": GFVariantData.get_option_int(
			source,
			"max_cached_resources"
		),
		"temporary_render_node_count": GFVariantData.get_option_int(
			source,
			"temporary_render_node_count"
		),
	}


func _make_runtime_broker_snapshot(source: Dictionary) -> Dictionary:
	if source.is_empty():
		return {
			"available": false,
			"healthy": false,
			"configured": false,
			"disposed": false,
			"error": "resource_broker_snapshot_missing",
			"request_error": ERR_UNCONFIGURED,
		}
	var configured: bool = GFVariantData.get_option_bool(
		source,
		"configured"
	)
	var disposed: bool = GFVariantData.get_option_bool(source, "disposed")
	var error_message: String = GFVariantData.get_option_string(
		source,
		"error"
	)
	var request_error: int = GFVariantData.get_option_int(
		source,
		"request_error",
		ERR_UNCONFIGURED
	)
	var healthy: bool = (
		configured
		and not disposed
		and error_message.is_empty()
		and request_error == OK
	)
	return {
		"available": configured,
		"healthy": healthy,
		"configured": configured,
		"disposed": disposed,
		"error": error_message,
		"request_error": request_error,
		"active_count": GFVariantData.get_option_int(source, "active_count"),
		"pending_count": GFVariantData.get_option_int(source, "pending_count"),
		"draining_count": GFVariantData.get_option_int(source, "draining_count"),
		"active_exclusive": GFVariantData.get_option_bool(
			source,
			"active_exclusive"
		),
		"max_active_requests": GFVariantData.get_option_int(
			source,
			"max_active_requests"
		),
		"max_pending_requests": GFVariantData.get_option_int(
			source,
			"max_pending_requests"
		),
		"active_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "active_paths")
		),
		"pending_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "pending_paths")
		),
		"draining_paths": _make_bounded_runtime_path_list(
			GFVariantData.get_option_value(source, "draining_paths")
		),
	}


func _make_bounded_runtime_path_list(value: Variant) -> Dictionary:
	var source_paths: PackedStringArray = PackedStringArray()
	if value is PackedStringArray:
		var packed_value: PackedStringArray = value
		source_paths = packed_value
	elif value is Array:
		for item: Variant in value:
			var _source_appended: bool = source_paths.append(str(item))
	var bounded_paths: PackedStringArray = PackedStringArray()
	var returned_count: int = mini(
		source_paths.size(),
		_MAX_RUNTIME_LOADING_PATHS
	)
	for index: int in range(returned_count):
		var _bounded_appended: bool = bounded_paths.append(
			_sanitize_runtime_loading_path(source_paths[index])
		)
	return {
		"total_count": source_paths.size(),
		"returned_count": bounded_paths.size(),
		"truncated": source_paths.size() > bounded_paths.size(),
		"values": bounded_paths,
	}


func _sanitize_runtime_loading_path(path: String) -> String:
	var normalized: String = path.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://"):
		return normalized
	if normalized.begins_with("user://"):
		return "user://<redacted>"
	return "<redacted>"


func _collect_architecture_dependency_snapshot() -> Dictionary:
	var architecture: GFArchitecture = _get_architecture_or_null()
	if architecture == null:
		return {}
	# GF 11 的生命周期计划已经冻结本地解析结果与工厂依赖；公开诊断入口
	# 直接返回同一份计划快照，不再接受调用方过滤选项。
	return architecture.get_dependency_diagnostics()


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
	var screenshot_path: String = GFVariantData.get_option_string(
		_last_screenshot_record,
		"path",
		"<none>"
	)
	var panel_text: String = "\n".join(PackedStringArray([
		"Scene: %s" % scene_path,
		"Cached project snapshots: %d" % _registered_tool_ids.size(),
		"Lazy project providers: %d" % _diagnostic_providers.size(),
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
	var provider_ids: PackedStringArray = PackedStringArray()
	for provider_id_value: Variant in _diagnostic_providers.keys():
		var _provider_id_appended: bool = provider_ids.append(
			String(GFVariantData.to_string_name(provider_id_value))
		)
	provider_ids.sort()
	var error: Error = _support_report_utility.build_and_save_report(_last_report_path, description, {
		"tags": PackedStringArray(["runtime", "manual"]),
		"diagnostics_options": {
			"include_scene_tree": true,
			"include_signal_graph": true,
			"diagnostic_provider_ids": provider_ids,
			"diagnostic_provider_request": {
				"reason": "explicit_support_report",
			},
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


func _on_acceptance_begin_command(args: PackedStringArray) -> void:
	if args.size() < 2:
		_log_acceptance_command_result(false, &"missing_case_or_observation")
		return
	var json_parts: PackedStringArray = PackedStringArray()
	for index: int in range(1, args.size()):
		var _part_appended: bool = json_parts.append(args[index])
	var read_report: Dictionary = GFBoundedJsonObjectReader.parse_object(
		" ".join(json_parts),
		_MAX_ACCEPTANCE_COMMAND_JSON_BYTES,
		_MAX_ACCEPTANCE_COMMAND_JSON_DEPTH
	)
	if not GFVariantData.get_option_bool(read_report, &"ok"):
		_log_acceptance_command_result(
			false,
			StringName(GFVariantData.get_option_string(
				read_report,
				&"error_kind",
				"invalid_observation_json"
			))
		)
		return
	var result: Dictionary = begin_gameplay_acceptance_case(
		StringName(args[0]),
		GFVariantData.get_option_dictionary(read_report, &"data")
	)
	_log_acceptance_command_result(
		GFVariantData.get_option_bool(result, &"accepted"),
		GFVariantData.get_option_string_name(result, &"reason", &"unknown")
	)


func _on_acceptance_end_command(_args: PackedStringArray) -> void:
	var snapshot: Dictionary = finish_gameplay_acceptance_case()
	_log_acceptance_command_result(
		GFVariantData.get_option_string_name(
			snapshot,
			&"measurement_status"
		) == &"evaluated",
		GFVariantData.get_option_string_name(
			snapshot,
			&"measurement_reason",
			&"unknown"
		)
	)


func _log_acceptance_command_result(
	succeeded: bool,
	reason: StringName
) -> void:
	if _log_utility == null:
		return
	var message: String = "Gameplay acceptance: %s." % String(reason)
	if succeeded:
		_log_utility.info(_LOG_TAG, message)
	else:
		_log_utility.warn(_LOG_TAG, message)


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


func _get_performance_trace_utility() -> GamePerformanceTraceUtility:
	var utility: Object = get_utility(GamePerformanceTraceUtility)
	if utility is GamePerformanceTraceUtility:
		var performance_trace: GamePerformanceTraceUtility = utility
		return performance_trace
	return null


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility: Object = get_utility(GFInputMappingUtility)
	if utility is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility
		return input_mapping
	return null


func _get_asset_utility() -> GFAssetUtility:
	var utility: Object = get_utility(GFAssetUtility)
	if utility is GFAssetUtility:
		var assets: GFAssetUtility = utility
		return assets
	return null


func _get_scene_utility() -> GFSceneUtility:
	var utility: Object = get_utility(GFSceneUtility)
	if utility is GFSceneUtility:
		var scenes: GFSceneUtility = utility
		return scenes
	return null


func _get_render_warmup_utility() -> GFRenderWarmupUtility:
	var utility: Object = get_utility(GFRenderWarmupUtility)
	if utility is GFRenderWarmupUtility:
		var warmup: GFRenderWarmupUtility = utility
		return warmup
	return null
