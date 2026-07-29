## 项目自有的 UI 与场景路由性能证据采集器。
##
## UI 路由直接消费 GFUIRouteResult 的单调时钟与预加载终态；场景路由只监听
## GFSceneUtility 的公开信号。该工具不进入玩家运行时，也不复制 GF 的路由所有权。
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 2
const DEFAULT_REPORT_PATH: String = (
	"res://build/ui_route_performance/route_timing_report.json"
)
const DEFAULT_BUDGETS: Dictionary = {
	"ui_route_max_msec": 1000.0,
	"scene_route_total_max_msec": 1500.0,
	"scene_load_max_msec": 750.0,
	"scene_preload_max_msec": 1000.0,
}


# --- 私有变量 ---

var _budgets: Dictionary = DEFAULT_BUDGETS.duplicate(true)
var _ui_route_budget_by_id: Dictionary = {}
var _scene_route_budget_by_id: Dictionary = {}
var _minimum_ui_route_samples: int = 1
var _minimum_scene_route_samples: int = 1
var _metadata: Dictionary = {}
var _now_usec_provider: Callable = Callable()

var _ui_route_records: Array[Dictionary] = []
var _scene_route_records: Array[Dictionary] = []
var _scene_preload_records: Array[Dictionary] = []
var _recorded_ui_request_indices: Dictionary = {}

var _scene_utility: GFSceneUtility = null
var _screen_transition_utility: GFScreenTransitionUtility = null
var _active_scene_route: Dictionary = {}
var _active_scene_preloads: Dictionary = {}


# --- 公共方法 ---

## 配置预算、最低样本数、报告元数据与可选测试时钟。
##
## @param options: 支持 budgets、ui_route_budget_by_id、
## scene_route_budget_by_id、minimum_ui_route_samples、
## minimum_scene_route_samples、metadata 和 now_usec_provider。
## @return 当前采集器。
func configure(options: Dictionary = {}) -> RefCounted:
	_budgets = DEFAULT_BUDGETS.duplicate(true)
	var budget_overrides: Dictionary = GFVariantData.get_option_dictionary(
		options,
		"budgets"
	)
	for budget_key: String in DEFAULT_BUDGETS:
		var configured_value: float = GFVariantData.get_option_float(
			budget_overrides,
			budget_key,
			GFVariantData.get_option_float(DEFAULT_BUDGETS, budget_key)
		)
		if configured_value > 0.0:
			_budgets[budget_key] = configured_value

	_ui_route_budget_by_id = GFVariantData.get_option_dictionary(
		options,
		"ui_route_budget_by_id"
	).duplicate(true)
	_scene_route_budget_by_id = GFVariantData.get_option_dictionary(
		options,
		"scene_route_budget_by_id"
	).duplicate(true)
	_minimum_ui_route_samples = maxi(
		GFVariantData.get_option_int(options, "minimum_ui_route_samples", 1),
		0
	)
	_minimum_scene_route_samples = maxi(
		GFVariantData.get_option_int(options, "minimum_scene_route_samples", 1),
		0
	)
	_metadata = GFVariantData.get_option_dictionary(options, "metadata").duplicate(
		true
	)
	var provider_value: Variant = options.get("now_usec_provider")
	_now_usec_provider = (
		provider_value
		if provider_value is Callable
		else Callable()
	)
	return self


## 监听 GFSceneUtility 的加载、切换和预加载公开信号。
##
## @param scene_utility: 当前架构拥有的 GFSceneUtility。
## @return 绑定成功时返回 true。
func bind_scene_utility(scene_utility: GFSceneUtility) -> bool:
	unbind_scene_utility()
	if not is_instance_valid(scene_utility):
		return false
	_scene_utility = scene_utility
	_connect_scene_signal(
		_scene_utility.scene_load_started,
		_on_scene_load_started
	)
	_connect_scene_signal(
		_scene_utility.scene_load_completed,
		_on_scene_load_completed
	)
	_connect_scene_signal(
		_scene_utility.scene_load_failed,
		_on_scene_load_failed
	)
	_connect_scene_signal(
		_scene_utility.scene_switch_started,
		_on_scene_switch_started
	)
	_connect_scene_signal(
		_scene_utility.scene_switch_completed,
		_on_scene_switch_completed
	)
	_connect_scene_signal(
		_scene_utility.scene_switch_failed,
		_on_scene_switch_failed
	)
	_connect_scene_signal(
		_scene_utility.scene_preload_started,
		_on_scene_preload_started
	)
	_connect_scene_signal(
		_scene_utility.scene_preload_completed,
		_on_scene_preload_completed
	)
	_connect_scene_signal(
		_scene_utility.scene_preload_failed,
		_on_scene_preload_failed
	)
	_connect_scene_signal(
		_scene_utility.scene_preload_cancelled,
		_on_scene_preload_cancelled
	)
	return true


## 解除 GFSceneUtility 信号监听。
func unbind_scene_utility() -> void:
	if not is_instance_valid(_scene_utility):
		_scene_utility = null
		return
	_disconnect_scene_signal(
		_scene_utility.scene_load_started,
		_on_scene_load_started
	)
	_disconnect_scene_signal(
		_scene_utility.scene_load_completed,
		_on_scene_load_completed
	)
	_disconnect_scene_signal(
		_scene_utility.scene_load_failed,
		_on_scene_load_failed
	)
	_disconnect_scene_signal(
		_scene_utility.scene_switch_started,
		_on_scene_switch_started
	)
	_disconnect_scene_signal(
		_scene_utility.scene_switch_completed,
		_on_scene_switch_completed
	)
	_disconnect_scene_signal(
		_scene_utility.scene_switch_failed,
		_on_scene_switch_failed
	)
	_disconnect_scene_signal(
		_scene_utility.scene_preload_started,
		_on_scene_preload_started
	)
	_disconnect_scene_signal(
		_scene_utility.scene_preload_completed,
		_on_scene_preload_completed
	)
	_disconnect_scene_signal(
		_scene_utility.scene_preload_failed,
		_on_scene_preload_failed
	)
	_disconnect_scene_signal(
		_scene_utility.scene_preload_cancelled,
		_on_scene_preload_cancelled
	)
	_scene_utility = null


## 监听 GFScreenTransitionUtility 的开始、完成与取消公开信号。
##
## @param screen_transition_utility: 当前架构拥有的屏幕转场工具。
## @return 绑定成功时返回 true。
func bind_screen_transition_utility(
	screen_transition_utility: GFScreenTransitionUtility
) -> bool:
	unbind_screen_transition_utility()
	if not is_instance_valid(screen_transition_utility):
		return false
	_screen_transition_utility = screen_transition_utility
	_connect_scene_signal(
		_screen_transition_utility.transition_started,
		_on_transition_started
	)
	_connect_scene_signal(
		_screen_transition_utility.transition_finished,
		_on_transition_finished
	)
	_connect_scene_signal(
		_screen_transition_utility.transition_cancelled,
		_on_transition_cancelled
	)
	return true


## 解除 GFScreenTransitionUtility 信号监听。
func unbind_screen_transition_utility() -> void:
	if not is_instance_valid(_screen_transition_utility):
		_screen_transition_utility = null
		return
	_disconnect_scene_signal(
		_screen_transition_utility.transition_started,
		_on_transition_started
	)
	_disconnect_scene_signal(
		_screen_transition_utility.transition_finished,
		_on_transition_finished
	)
	_disconnect_scene_signal(
		_screen_transition_utility.transition_cancelled,
		_on_transition_cancelled
	)
	_screen_transition_utility = null


## 把 GF UI 路由终态转换为项目验收记录。
##
## @param result: GFUIRouterUtility 返回的不可变终态；null 会形成显式失败记录。
## @param context: 场景、冷暖状态、序号等调用方上下文。
## @return JSON 安全边界之前的记录副本。
func record_ui_route_result(
	result: GFUIRouteResult,
	context: Dictionary = {}
) -> Dictionary:
	if result == null:
		var missing_record: Dictionary = _make_missing_ui_route_record(context)
		_ui_route_records.append(missing_record)
		return missing_record.duplicate(true)

	var request_id: int = result.get_request_id()
	if (
		request_id > 0
		and _recorded_ui_request_indices.has(request_id)
	):
		var existing_index: int = GFVariantData.get_option_int(
			_recorded_ui_request_indices,
			request_id,
			-1
		)
		if existing_index >= 0 and existing_index < _ui_route_records.size():
			return _ui_route_records[existing_index].duplicate(true)

	var route_id: StringName = result.get_route_id()
	var duration_msec: float = float(result.get_duration_msec())
	var budget_msec: float = _resolve_route_budget(
		_ui_route_budget_by_id,
		route_id,
		"ui_route_max_msec"
	)
	var preload_result: GFAssetLoadSessionResult = result.get_preload_result()
	var preload_attempted: bool = result.was_preload_attempted()
	var preload_successful: bool = result.was_preload_successful()
	var record: Dictionary = {
		"kind": "ui_route",
		"request_id": request_id,
		"route_id": String(route_id),
		"operation": String(result.get_operation()),
		"status": String(result.get_status()),
		"reason": String(result.get_reason()),
		"ok": result.is_successful(),
		"duration_msec": duration_msec,
		"budget_msec": budget_msec,
		"within_budget": duration_msec <= budget_msec,
		"passed": result.is_successful() and duration_msec <= budget_msec,
		"preload": {
			"policy": String(result.get_preload_policy()),
			"attempted": preload_attempted,
			"successful": preload_successful,
			"degraded": preload_attempted and not preload_successful,
			"plan_report": result.get_preload_plan_report(),
			"result": (
				preload_result.to_dict()
				if preload_result != null
				else {}
			),
		},
		"context": context.duplicate(true),
	}
	var record_index: int = _ui_route_records.size()
	_ui_route_records.append(record)
	if request_id > 0:
		_recorded_ui_request_indices[request_id] = record_index
	return record.duplicate(true)


## 标记一个由 SceneRouterSystem 发起、由 GFSceneUtility 执行的场景路由。
##
## @param route_id: 项目验收用的稳定场景路线 ID。
## @param target_path: 目标 PackedScene 路径。
## @param context: 冷暖状态、来源页面等调用方上下文。
## @return 当前没有其它场景路线时返回 true。
func begin_scene_route(
	route_id: StringName,
	target_path: String,
	context: Dictionary = {}
) -> bool:
	if not _active_scene_route.is_empty():
		return false
	var normalized_path: String = target_path.strip_edges()
	if route_id == &"" or normalized_path.is_empty():
		return false
	_active_scene_route = {
		"route_id": route_id,
		"target_path": normalized_path,
		"started_usec": _now_usec(),
		"load_started_usec": 0,
		"load_completed_usec": 0,
		"load_duration_msec": -1.0,
		"load_status": "pending",
		"switch_started_usec": 0,
		"switch_completed_usec": 0,
		"switch_duration_msec": -1.0,
		"switch_status": "pending",
		"transitions": [],
		"active_transition_index": -1,
		"context": context.duplicate(true),
	}
	return true


## 在场景揭示完成并恢复交互后结束当前路线。
##
## @param succeeded: SceneRouterSystem 是否到达稳定成功终态。
## @param metadata: 页面可交互、焦点和额外错误证据。
## @return 没有活动路线时返回空字典，否则返回新记录。
func complete_scene_route(
	succeeded: bool,
	metadata: Dictionary = {}
) -> Dictionary:
	if _active_scene_route.is_empty():
		return {}
	var ended_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"started_usec",
		ended_usec
	)
	var total_duration_msec: float = _usec_delta_to_msec(
		started_usec,
		ended_usec
	)
	var route_id: StringName = GFVariantData.get_option_string_name(
		_active_scene_route,
		"route_id"
	)
	var total_budget_msec: float = _resolve_route_budget(
		_scene_route_budget_by_id,
		route_id,
		"scene_route_total_max_msec"
	)
	var load_duration_msec: float = GFVariantData.get_option_float(
		_active_scene_route,
		"load_duration_msec",
		-1.0
	)
	var load_budget_msec: float = GFVariantData.get_option_float(
		_budgets,
		"scene_load_max_msec"
	)
	var load_evidence_complete: bool = load_duration_msec >= 0.0
	var switch_duration_msec: float = GFVariantData.get_option_float(
		_active_scene_route,
		"switch_duration_msec",
		-1.0
	)
	var interactive_ready: bool = GFVariantData.get_option_bool(
		metadata,
		"interactive_ready",
		succeeded
	)
	var internal_transitions: Array = _active_scene_route.get(
		"transitions",
		[]
	)
	var transition_summary: Dictionary = _make_transition_summary(
		internal_transitions,
		started_usec,
		ended_usec,
		total_duration_msec,
		load_duration_msec
	)
	var transitions: Array[Dictionary] = _get_public_transition_records()
	var transition_evidence_complete: bool = GFVariantData.get_option_bool(
		transition_summary,
		"evidence_complete"
	)
	var passed: bool = (
		succeeded
		and interactive_ready
		and load_evidence_complete
		and transition_evidence_complete
		and total_duration_msec <= total_budget_msec
		and load_duration_msec <= load_budget_msec
	)
	var record: Dictionary = {
		"kind": "scene_route",
		"route_id": String(route_id),
		"target_path": GFVariantData.get_option_string(
			_active_scene_route,
			"target_path"
		),
		"ok": succeeded,
		"interactive_ready": interactive_ready,
		"duration_msec": total_duration_msec,
		"budget_msec": total_budget_msec,
		"within_budget": total_duration_msec <= total_budget_msec,
		"load": {
			"status": GFVariantData.get_option_string(
				_active_scene_route,
				"load_status"
			),
			"evidence_complete": load_evidence_complete,
			"duration_msec": load_duration_msec,
			"budget_msec": load_budget_msec,
			"within_budget": (
				load_evidence_complete
				and load_duration_msec <= load_budget_msec
			),
		},
		"switch": {
			"status": GFVariantData.get_option_string(
				_active_scene_route,
				"switch_status"
			),
			"evidence_complete": switch_duration_msec >= 0.0,
			"duration_msec": switch_duration_msec,
		},
		"transitions": transitions,
		"transition_summary": transition_summary,
		"passed": passed,
		"context": GFVariantData.get_option_dictionary(
			_active_scene_route,
			"context"
		).duplicate(true),
		"metadata": metadata.duplicate(true),
	}
	_scene_route_records.append(record)
	_active_scene_route = {}
	return record.duplicate(true)


## 构建包含原始证据、统计量和验收终态的报告。
##
## @param additional_metadata: 本次执行的额外环境元数据。
## @return 可经 GFReportValueCodec 转为 JSON 的报告。
func build_report(additional_metadata: Dictionary = {}) -> Dictionary:
	var ui_failures: int = _count_failed_records(_ui_route_records)
	var scene_failures: int = _count_failed_records(_scene_route_records)
	var preload_failures: int = _count_failed_records(
		_scene_preload_records
	)
	var ui_samples_complete: bool = (
		_ui_route_records.size() >= _minimum_ui_route_samples
	)
	var scene_samples_complete: bool = (
		_scene_route_records.size() >= _minimum_scene_route_samples
	)
	var no_active_work: bool = (
		_active_scene_route.is_empty()
		and _active_scene_preloads.is_empty()
	)
	var passed: bool = (
		ui_samples_complete
		and scene_samples_complete
		and no_active_work
		and ui_failures == 0
		and scene_failures == 0
		and preload_failures == 0
	)
	var report_metadata: Dictionary = _metadata.duplicate(true)
	report_metadata.merge(additional_metadata, true)
	return {
		"schema_version": SCHEMA_VERSION,
		"passed": passed,
		"evidence_kind": "rendered_route_smoke",
		"budgets": _budgets.duplicate(true),
		"minimum_samples": {
			"ui_routes": _minimum_ui_route_samples,
			"scene_routes": _minimum_scene_route_samples,
		},
		"summary": {
			"ui_route_count": _ui_route_records.size(),
			"ui_route_failure_count": ui_failures,
			"scene_route_count": _scene_route_records.size(),
			"scene_route_failure_count": scene_failures,
			"scene_preload_count": _scene_preload_records.size(),
			"scene_preload_failure_count": preload_failures,
			"ui_samples_complete": ui_samples_complete,
			"scene_samples_complete": scene_samples_complete,
			"no_active_work": no_active_work,
		},
		"metrics": {
			"ui_route_duration_msec": _make_metric_summary(
				&"ui_route_duration_msec",
				_ui_route_records,
				"duration_msec"
			),
			"scene_route_duration_msec": _make_metric_summary(
				&"scene_route_duration_msec",
				_scene_route_records,
				"duration_msec"
			),
			"scene_load_duration_msec": _make_nested_metric_summary(
				&"scene_load_duration_msec",
				_scene_route_records,
				"load",
				"duration_msec"
			),
			"scene_transition_configured_duration_msec": (
				_make_scene_transition_metric_summary(
					&"scene_transition_configured_duration_msec",
					"configured_duration_msec"
				)
			),
			"scene_transition_wall_duration_msec": (
				_make_scene_transition_metric_summary(
					&"scene_transition_wall_duration_msec",
					"wall_duration_msec"
				)
			),
			"scene_preload_duration_msec": _make_metric_summary(
				&"scene_preload_duration_msec",
				_scene_preload_records,
				"duration_msec"
			),
		},
		"ui_routes": _ui_route_records.duplicate(true),
		"scene_routes": _scene_route_records.duplicate(true),
		"scene_preloads": _scene_preload_records.duplicate(true),
		"metadata": report_metadata,
	}


## 把报告以 UTF-8 JSON 写入忽略提交的构建目录。
##
## @param report: build_report() 返回的报告。
## @param path: 目标项目路径。
## @return Godot Error。
func write_report(
	report: Dictionary,
	path: String = DEFAULT_REPORT_PATH
) -> Error:
	var normalized_path: String = path.strip_edges()
	if normalized_path.is_empty():
		return ERR_INVALID_PARAMETER
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(normalized_path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var json_safe_value: Variant = GFReportValueCodec.to_json_compatible(
		report.duplicate(true)
	)
	if not json_safe_value is Dictionary:
		return ERR_INVALID_DATA
	var file: FileAccess = FileAccess.open(normalized_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored: bool = file.store_string(
		JSON.stringify(json_safe_value, "\t") + "\n"
	)
	file.close()
	return OK if stored else ERR_FILE_CANT_WRITE


## 返回 UI 路由记录的隔离副本。
func get_ui_route_records() -> Array[Dictionary]:
	return _ui_route_records.duplicate(true)


## 返回场景路由记录的隔离副本。
func get_scene_route_records() -> Array[Dictionary]:
	return _scene_route_records.duplicate(true)


## 返回场景预加载记录的隔离副本。
func get_scene_preload_records() -> Array[Dictionary]:
	return _scene_preload_records.duplicate(true)


# --- 信号处理函数 ---

func _on_scene_load_started(path: String) -> void:
	if not _active_route_targets(path):
		return
	_active_scene_route["load_started_usec"] = _now_usec()
	_active_scene_route["load_status"] = "running"


func _on_scene_load_completed(path: String, _scene: PackedScene) -> void:
	if not _active_route_targets(path):
		return
	var completed_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"load_started_usec",
		0
	)
	_active_scene_route["load_completed_usec"] = completed_usec
	_active_scene_route["load_status"] = "completed"
	if started_usec > 0:
		_active_scene_route["load_duration_msec"] = _usec_delta_to_msec(
			started_usec,
			completed_usec
		)


func _on_scene_load_failed(path: String) -> void:
	if not _active_route_targets(path):
		return
	var failed_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"load_started_usec",
		0
	)
	_active_scene_route["load_completed_usec"] = failed_usec
	_active_scene_route["load_status"] = "failed"
	if started_usec > 0:
		_active_scene_route["load_duration_msec"] = _usec_delta_to_msec(
			started_usec,
			failed_usec
		)


func _on_scene_switch_started(path: String, _previous_path: String) -> void:
	if not _active_route_targets(path):
		return
	_active_scene_route["switch_started_usec"] = _now_usec()
	_active_scene_route["switch_status"] = "running"


func _on_scene_switch_completed(path: String, _previous_path: String) -> void:
	if not _active_route_targets(path):
		return
	var completed_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"switch_started_usec",
		0
	)
	_active_scene_route["switch_completed_usec"] = completed_usec
	_active_scene_route["switch_status"] = "completed"
	if started_usec > 0:
		_active_scene_route["switch_duration_msec"] = _usec_delta_to_msec(
			started_usec,
			completed_usec
		)


func _on_scene_switch_failed(
	path: String,
	_previous_path: String,
	_message: String
) -> void:
	if not _active_route_targets(path):
		return
	var failed_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"switch_started_usec",
		0
	)
	_active_scene_route["switch_completed_usec"] = failed_usec
	_active_scene_route["switch_status"] = "failed"
	if started_usec > 0:
		_active_scene_route["switch_duration_msec"] = _usec_delta_to_msec(
			started_usec,
			failed_usec
		)


func _on_transition_started(effect: GFScreenTransitionEffect) -> void:
	if _active_scene_route.is_empty() or effect == null:
		return
	var effect_metadata: Dictionary = effect.metadata.duplicate(true)
	var phase: String = GFVariantData.get_option_string(
		effect_metadata,
		"phase"
	)
	var phase_source: String = "effect_metadata"
	var transitions: Array = _active_scene_route.get("transitions", [])
	if phase.is_empty():
		phase = (
			"cover" if transitions.is_empty() else
			"reveal" if transitions.size() == 1 else
			"additional_%d" % (transitions.size() + 1)
		)
		phase_source = "route_sequence_fallback"
	var record: Dictionary = {
		"phase": phase,
		"phase_source": phase_source,
		"theme_id": GFVariantData.get_option_string(
			effect_metadata,
			"theme_id"
		),
		"configured_duration_msec": maxf(
			effect.duration_seconds * 1000.0,
			0.0
		),
		"wall_duration_msec": -1.0,
		"status": "running",
		"_started_usec": _now_usec(),
		"_effect_instance_id": effect.get_instance_id(),
	}
	transitions.append(record)
	_active_scene_route["transitions"] = transitions
	_active_scene_route["active_transition_index"] = transitions.size() - 1


func _on_transition_finished(effect: GFScreenTransitionEffect) -> void:
	_finish_active_transition(effect, "completed")


func _on_transition_cancelled(effect: GFScreenTransitionEffect) -> void:
	_finish_active_transition(effect, "cancelled")


func _on_scene_preload_started(path: String) -> void:
	_active_scene_preloads[path] = {
		"started_usec": _now_usec(),
	}


func _on_scene_preload_completed(path: String, _scene: PackedScene) -> void:
	_finish_scene_preload(path, "completed", true)


func _on_scene_preload_failed(path: String) -> void:
	_finish_scene_preload(path, "failed", false)


func _on_scene_preload_cancelled(path: String) -> void:
	_finish_scene_preload(path, "cancelled", false)


# --- 私有/辅助方法 ---

func _connect_scene_signal(signal_value: Signal, callback: Callable) -> void:
	if not signal_value.is_connected(callback):
		var _error: Error = signal_value.connect(callback) as Error


func _disconnect_scene_signal(signal_value: Signal, callback: Callable) -> void:
	if signal_value.is_connected(callback):
		signal_value.disconnect(callback)


func _active_route_targets(path: String) -> bool:
	return (
		not _active_scene_route.is_empty()
		and GFVariantData.get_option_string(
			_active_scene_route,
			"target_path"
		) == path
	)


func _finish_active_transition(
	effect: GFScreenTransitionEffect,
	status: String
) -> void:
	if _active_scene_route.is_empty():
		return
	var transitions: Array = _active_scene_route.get("transitions", [])
	var active_index: int = GFVariantData.get_option_int(
		_active_scene_route,
		"active_transition_index",
		-1
	)
	if active_index < 0 or active_index >= transitions.size():
		return
	var record_value: Variant = transitions[active_index]
	if not record_value is Dictionary:
		return
	var record: Dictionary = record_value
	var expected_effect_id: int = GFVariantData.get_option_int(
		record,
		"_effect_instance_id",
		0
	)
	if (
		effect != null
		and expected_effect_id > 0
		and effect.get_instance_id() != expected_effect_id
	):
		return
	var ended_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		record,
		"_started_usec",
		ended_usec
	)
	record["wall_duration_msec"] = _usec_delta_to_msec(
		started_usec,
		ended_usec
	)
	record["status"] = status
	record["_ended_usec"] = ended_usec
	transitions[active_index] = record
	_active_scene_route["transitions"] = transitions
	_active_scene_route["active_transition_index"] = -1


func _get_public_transition_records() -> Array[Dictionary]:
	var public_records: Array[Dictionary] = []
	var transitions: Array = _active_scene_route.get("transitions", [])
	for transition_value: Variant in transitions:
		if not transition_value is Dictionary:
			continue
		var record: Dictionary = GFVariantData.as_dictionary(
			transition_value
		).duplicate(true)
		var _started_erased: bool = record.erase("_started_usec")
		var _ended_erased: bool = record.erase("_ended_usec")
		var _effect_erased: bool = record.erase("_effect_instance_id")
		public_records.append(record)
	return public_records


func _make_transition_summary(
	transitions: Array,
	route_started_usec: int,
	route_ended_usec: int,
	total_duration_msec: float,
	load_duration_msec: float
) -> Dictionary:
	var configured_total_msec: float = 0.0
	var wall_total_msec: float = 0.0
	var cover_completed: bool = false
	var reveal_completed: bool = false
	var cover_started_usec: int = 0
	var cover_ended_usec: int = 0
	var reveal_started_usec: int = 0
	var reveal_ended_usec: int = 0
	for transition_value: Variant in transitions:
		if not transition_value is Dictionary:
			continue
		var transition: Dictionary = transition_value
		configured_total_msec += maxf(
			GFVariantData.get_option_float(
				transition,
				"configured_duration_msec"
			),
			0.0
		)
		var wall_duration_msec: float = GFVariantData.get_option_float(
			transition,
			"wall_duration_msec",
			-1.0
		)
		if wall_duration_msec >= 0.0:
			wall_total_msec += wall_duration_msec
		var phase: String = GFVariantData.get_option_string(
			transition,
			"phase"
		)
		var completed: bool = (
			GFVariantData.get_option_string(transition, "status")
			== "completed"
		)
		if phase == "cover":
			cover_completed = completed
			cover_started_usec = GFVariantData.get_option_int(
				transition,
				"_started_usec"
			)
			cover_ended_usec = GFVariantData.get_option_int(
				transition,
				"_ended_usec"
			)
		elif phase == "reveal":
			reveal_completed = completed
			reveal_started_usec = GFVariantData.get_option_int(
				transition,
				"_started_usec"
			)
			reveal_ended_usec = GFVariantData.get_option_int(
				transition,
				"_ended_usec"
			)
	var residual_msec: float = -1.0
	if load_duration_msec >= 0.0:
		residual_msec = maxf(
			total_duration_msec
			- wall_total_msec
			- load_duration_msec,
			0.0
		)
	var load_started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"load_started_usec"
	)
	var load_completed_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"load_completed_usec"
	)
	var request_to_cover_msec: float = _optional_usec_delta_to_msec(
		route_started_usec,
		cover_started_usec
	)
	var cover_to_load_msec: float = _optional_usec_delta_to_msec(
		cover_ended_usec,
		load_started_usec
	)
	var load_to_reveal_msec: float = _optional_usec_delta_to_msec(
		load_completed_usec,
		reveal_started_usec
	)
	var reveal_to_ready_msec: float = _optional_usec_delta_to_msec(
		reveal_ended_usec,
		route_ended_usec
	)
	var attributed_residual_msec: float = 0.0
	for gap_msec: float in [
		request_to_cover_msec,
		cover_to_load_msec,
		load_to_reveal_msec,
		reveal_to_ready_msec,
	]:
		if gap_msec >= 0.0:
			attributed_residual_msec += gap_msec
	return {
		"evidence_complete": cover_completed and reveal_completed,
		"cover_completed": cover_completed,
		"reveal_completed": reveal_completed,
		"configured_total_msec": configured_total_msec,
		"wall_total_msec": wall_total_msec,
		"orchestration_residual_msec": residual_msec,
		"wall_composition": {
			"request_to_cover_start_msec": request_to_cover_msec,
			"cover_complete_to_load_start_msec": cover_to_load_msec,
			"load_complete_to_reveal_start_msec": load_to_reveal_msec,
			"reveal_complete_to_route_ready_msec": reveal_to_ready_msec,
			"unattributed_msec": (
				maxf(
					residual_msec - attributed_residual_msec,
					0.0
				)
				if residual_msec >= 0.0
				else -1.0
			),
		},
		"composition_note": (
			"route_total = transition wall total + scene load wall time "
			+ "+ four orchestration gaps; switch overlaps load and is not added"
		),
	}


func _finish_scene_preload(
	path: String,
	status: String,
	succeeded: bool
) -> void:
	if not _active_scene_preloads.has(path):
		return
	var state: Dictionary = GFVariantData.get_option_dictionary(
		_active_scene_preloads,
		path
	)
	var ended_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		state,
		"started_usec",
		ended_usec
	)
	var duration_msec: float = _usec_delta_to_msec(
		started_usec,
		ended_usec
	)
	var budget_msec: float = GFVariantData.get_option_float(
		_budgets,
		"scene_preload_max_msec"
	)
	_scene_preload_records.append({
		"kind": "scene_preload",
		"path": path,
		"status": status,
		"ok": succeeded,
		"duration_msec": duration_msec,
		"budget_msec": budget_msec,
		"within_budget": duration_msec <= budget_msec,
		"passed": succeeded and duration_msec <= budget_msec,
	})
	var _erased: bool = _active_scene_preloads.erase(path)


func _make_missing_ui_route_record(context: Dictionary) -> Dictionary:
	var route_id: StringName = GFVariantData.get_option_string_name(
		context,
		"route_id"
	)
	var budget_msec: float = _resolve_route_budget(
		_ui_route_budget_by_id,
		route_id,
		"ui_route_max_msec"
	)
	return {
		"kind": "ui_route",
		"request_id": 0,
		"route_id": String(route_id),
		"operation": "",
		"status": "missing_result",
		"reason": "missing_route_result",
		"ok": false,
		"duration_msec": -1.0,
		"budget_msec": budget_msec,
		"within_budget": false,
		"passed": false,
		"preload": {
			"policy": "",
			"attempted": false,
			"successful": false,
			"degraded": false,
			"plan_report": {},
			"result": {},
		},
		"context": context.duplicate(true),
	}


func _resolve_route_budget(
	route_budgets: Dictionary,
	route_id: StringName,
	fallback_key: String
) -> float:
	var route_key: String = String(route_id)
	var configured_budget: float = GFVariantData.get_option_float(
		route_budgets,
		route_key,
		-1.0
	)
	if configured_budget > 0.0:
		return configured_budget
	return GFVariantData.get_option_float(_budgets, fallback_key)


func _count_failed_records(records: Array[Dictionary]) -> int:
	var count: int = 0
	for record: Dictionary in records:
		if not GFVariantData.get_option_bool(record, "passed"):
			count += 1
	return count


func _make_metric_summary(
	metric_id: StringName,
	records: Array[Dictionary],
	value_key: String
) -> Dictionary:
	var values: Array[float] = []
	for record: Dictionary in records:
		var value: float = GFVariantData.get_option_float(
			record,
			value_key,
			-1.0
		)
		if value >= 0.0:
			values.append(value)
	return _summarize_values(metric_id, values)


func _make_nested_metric_summary(
	metric_id: StringName,
	records: Array[Dictionary],
	container_key: String,
	value_key: String
) -> Dictionary:
	var values: Array[float] = []
	for record: Dictionary in records:
		var container: Dictionary = GFVariantData.get_option_dictionary(
			record,
			container_key
		)
		var value: float = GFVariantData.get_option_float(
			container,
			value_key,
			-1.0
		)
		if value >= 0.0:
			values.append(value)
	return _summarize_values(metric_id, values)


func _make_scene_transition_metric_summary(
	metric_id: StringName,
	value_key: String
) -> Dictionary:
	var values: Array[float] = []
	for route_record: Dictionary in _scene_route_records:
		var transitions_value: Variant = route_record.get("transitions", [])
		if not transitions_value is Array:
			continue
		for transition_value: Variant in transitions_value:
			if not transition_value is Dictionary:
				continue
			var transition: Dictionary = transition_value
			var value: float = GFVariantData.get_option_float(
				transition,
				value_key,
				-1.0
			)
			if value >= 0.0:
				values.append(value)
	return _summarize_values(metric_id, values)


func _summarize_values(
	metric_id: StringName,
	values: Array[float]
) -> Dictionary:
	var series: GFMetricSeries = GFMetricSeries.new().configure(
		metric_id,
		{"max_samples": maxi(values.size(), 1)}
	)
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	for index: int in range(sorted_values.size()):
		series.add_sample(sorted_values[index], float(index))
	var summary: Dictionary = series.to_dict(true)
	summary["p50"] = _nearest_rank(sorted_values, 0.50)
	summary["p95"] = _nearest_rank(sorted_values, 0.95)
	summary["p99"] = _nearest_rank(sorted_values, 0.99)
	return summary


func _nearest_rank(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(
		ceili(clampf(percentile, 0.0, 1.0) * float(values.size())) - 1,
		0,
		values.size() - 1
	)
	return values[index]


func _now_usec() -> int:
	if _now_usec_provider.is_valid():
		return maxi(
			GFVariantData.to_int(
				_now_usec_provider.call(),
				Time.get_ticks_usec()
			),
			0
		)
	return Time.get_ticks_usec()


func _usec_delta_to_msec(started_usec: int, ended_usec: int) -> float:
	return maxf(float(ended_usec - started_usec) / 1000.0, 0.0)


func _optional_usec_delta_to_msec(
	started_usec: int,
	ended_usec: int
) -> float:
	if started_usec <= 0 or ended_usec <= 0:
		return -1.0
	return _usec_delta_to_msec(started_usec, ended_usec)
