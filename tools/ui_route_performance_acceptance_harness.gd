## 项目自有的 UI 与场景路由性能证据采集器。
##
## UI 路由直接消费 GFUIRouteResult 的单调时钟与预加载终态；场景路由只监听
## GFSceneUtility 的公开信号。该工具不进入玩家运行时，也不复制 GF 的路由所有权。
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 3
const DEFAULT_REPORT_PATH: String = (
	"res://build/ui_route_performance/route_timing_report.json"
)
const _REPORT_ALLOWED_ROOTS: PackedStringArray = [
	"res://build/ui_route_performance",
	"user://ui_route_performance",
]
const _REPORT_MAX_TOTAL_NODES: int = 65_536
const _REPORT_MAX_TOTAL_BYTES: int = 4 * 1024 * 1024
const DEFAULT_BUDGETS: Dictionary = {
	"boot_motion_settled_max_msec": 12_000.0,
	"ui_route_max_msec": 1000.0,
	"ui_route_post_draw_max_msec": 1200.0,
	"ui_route_motion_settled_max_msec": 1500.0,
	"scene_route_total_max_msec": 1500.0,
	"scene_load_max_msec": 750.0,
	"scene_route_post_draw_max_msec": 1800.0,
	"scene_route_motion_settled_max_msec": 2500.0,
	"scene_preload_max_msec": 1000.0,
}
const _PHASE_READY: StringName = &"ready"
const _PHASE_POST_DRAW: StringName = &"post_draw"
const _PHASE_MOTION_SETTLED: StringName = &"motion_settled"
const _MEASURED_PHASE_IDS: Array[StringName] = [
	_PHASE_READY,
	_PHASE_POST_DRAW,
	_PHASE_MOTION_SETTLED,
]


# --- 私有变量 ---

var _budgets: Dictionary = DEFAULT_BUDGETS.duplicate(true)
var _ui_route_budget_by_id: Dictionary = {}
var _scene_route_budget_by_id: Dictionary = {}
var _minimum_ui_route_samples: int = 1
var _minimum_scene_route_samples: int = 1
var _minimum_boot_samples: int = 0
var _require_phase_evidence: bool = false
var _metadata: Dictionary = {}
var _now_usec_provider: Callable = Callable()

var _ui_route_records: Array[Dictionary] = []
var _scene_route_records: Array[Dictionary] = []
var _scene_preload_records: Array[Dictionary] = []
var _boot_records: Array[Dictionary] = []
var _recorded_ui_request_indices: Dictionary = {}

var _scene_utility: GFSceneUtility = null
var _screen_transition_utility: GFScreenTransitionUtility = null
var _active_scene_route: Dictionary = {}
var _active_scene_preloads: Dictionary = {}
var _preloading_scene_paths_at_bind: Dictionary = {}


# --- 公共方法 ---

## 配置预算、最低样本数、报告元数据与可选测试时钟。
##
## @param options: 支持 budgets、ui_route_budget_by_id、
## scene_route_budget_by_id、minimum_ui_route_samples、
## minimum_scene_route_samples、minimum_boot_samples、require_phase_evidence、
## metadata 和 now_usec_provider。
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
	_minimum_boot_samples = maxi(
		GFVariantData.get_option_int(options, "minimum_boot_samples", 0),
		0
	)
	_require_phase_evidence = GFVariantData.get_option_bool(
		options,
		"require_phase_evidence",
		false
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


## 记录一次由工具进程边界定义的启动样本。
##
## 启动没有可复用的 GF 路由终态，因此调用方必须提供同一单调时钟上的绝对
## 时间戳。ready 表示 MainMenu 已入树并完成 `_ready`，post_draw 表示其首帧
## 已提交，motion_settled 表示采样器观察到约定的动效安静窗口。
## @param started_usec: 加载 Boot PackedScene 前的单调时间。
## @param ready_usec: MainMenu ready 的单调时间。
## @param post_draw_usec: MainMenu 首次 post draw 的单调时间。
## @param motion_settled_usec: MainMenu 动效安静窗口完成的单调时间。
## @param context: 冷暖口径、安静窗口策略和环境上下文。
func record_boot_observation(
	started_usec: int,
	ready_usec: int,
	post_draw_usec: int,
	motion_settled_usec: int,
	context: Dictionary = {}
) -> Dictionary:
	var phases: Dictionary = _make_phase_observation(
		started_usec,
		ready_usec,
		post_draw_usec,
		motion_settled_usec,
		GFVariantData.get_option_bool(
			context,
			"motion_settled_observed",
			motion_settled_usec >= post_draw_usec
		)
	)
	var duration_msec: float = GFVariantData.get_option_float(
		phases,
		"motion_settled_msec",
		-1.0
	)
	var budget_msec: float = GFVariantData.get_option_float(
		_budgets,
		"boot_motion_settled_max_msec"
	)
	var evidence_complete: bool = GFVariantData.get_option_bool(
		phases,
		"evidence_complete"
	)
	var record: Dictionary = {
		"kind": "boot",
		"sample_index": _boot_records.size(),
		"cache_state": GFVariantData.get_option_string(
			context,
			"cache_state",
			"process_first_boot"
		),
		"duration_msec": duration_msec,
		"budget_msec": budget_msec,
		"within_budget": (
			evidence_complete
			and duration_msec <= budget_msec
		),
		"phases": phases,
		"passed": (
			evidence_complete
			and duration_msec <= budget_msec
		),
		"context": context.duplicate(true),
	}
	_boot_records.append(record)
	return record.duplicate(true)


## 监听 GFSceneUtility 的加载、切换和预加载公开信号。
##
## @param scene_utility: 当前架构拥有的 GFSceneUtility。
## @return 绑定成功时返回 true。
func bind_scene_utility(scene_utility: GFSceneUtility) -> bool:
	unbind_scene_utility()
	if not is_instance_valid(scene_utility):
		return false
	_scene_utility = scene_utility
	for path: String in _scene_utility.get_preloading_scene_paths():
		_preloading_scene_paths_at_bind[path] = true
	var connected: bool = _connect_scene_signal(
		_scene_utility.scene_load_started,
		_on_scene_load_started
	)
	connected = _connect_scene_signal(
		_scene_utility.scene_load_completed,
		_on_scene_load_completed
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_load_failed,
		_on_scene_load_failed
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_switch_started,
		_on_scene_switch_started
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_switch_completed,
		_on_scene_switch_completed
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_switch_failed,
		_on_scene_switch_failed
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_preload_started,
		_on_scene_preload_started
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_preload_completed,
		_on_scene_preload_completed
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_preload_failed,
		_on_scene_preload_failed
	) and connected
	connected = _connect_scene_signal(
		_scene_utility.scene_preload_cancelled,
		_on_scene_preload_cancelled
	) and connected
	if not connected:
		unbind_scene_utility()
	return connected


## 解除 GFSceneUtility 信号监听。
func unbind_scene_utility() -> void:
	if not is_instance_valid(_scene_utility):
		_scene_utility = null
		_active_scene_preloads.clear()
		_preloading_scene_paths_at_bind.clear()
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
	_active_scene_preloads.clear()
	_preloading_scene_paths_at_bind.clear()


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
	var connected: bool = _connect_scene_signal(
		_screen_transition_utility.transition_started,
		_on_transition_started
	)
	connected = _connect_scene_signal(
		_screen_transition_utility.transition_finished,
		_on_transition_finished
	) and connected
	connected = _connect_scene_signal(
		_screen_transition_utility.transition_cancelled,
		_on_transition_cancelled
	) and connected
	if not connected:
		unbind_screen_transition_utility()
	return connected


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
## @param observation: 工具单调时钟上的 started/ready/post_draw/
## motion_settled 时间戳和 motion_settled_observed 终态。
## @return JSON 安全边界之前的记录副本。
func record_ui_route_result(
	result: GFUIRouteResult,
	context: Dictionary = {},
	observation: Dictionary = {}
) -> Dictionary:
	if result == null:
		var missing_record: Dictionary = _make_missing_ui_route_record(
			context,
			observation
		)
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
	var phases: Dictionary = _make_phase_observation_from_dictionary(
		observation,
		duration_msec
	)
	var phase_evidence_complete: bool = GFVariantData.get_option_bool(
		phases,
		"evidence_complete"
	)
	var phase_budget: Dictionary = _make_phase_budget_result(
		phases,
		"ui_route_post_draw_max_msec",
		"ui_route_motion_settled_max_msec"
	)
	var phase_budget_passed: bool = GFVariantData.get_option_bool(
		phase_budget,
		"passed"
	)
	var record: Dictionary = {
		"kind": "ui_route",
		"sample_index": _ui_route_records.size(),
		"request_id": request_id,
		"route_id": String(route_id),
		"operation": String(result.get_operation()),
		"status": String(result.get_status()),
		"reason": String(result.get_reason()),
		"ok": result.is_successful(),
		"duration_msec": duration_msec,
		"budget_msec": budget_msec,
		"within_budget": duration_msec <= budget_msec,
		"phases": phases,
		"phase_budget": phase_budget,
		"passed": (
			result.is_successful()
			and duration_msec <= budget_msec
			and phase_budget_passed
			and (phase_evidence_complete or not _require_phase_evidence)
		),
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
		"milestones_usec": {},
		"context": context.duplicate(true),
	}
	return true


## 记录当前场景路线的 ready、post_draw 或 motion_settled 里程碑。
##
## 重复里程碑保持首次观测时间；未知里程碑被拒绝，避免报告 schema 漂移。
func mark_scene_route_milestone(milestone_id: StringName) -> bool:
	if (
		_active_scene_route.is_empty()
		or not _MEASURED_PHASE_IDS.has(milestone_id)
	):
		return false
	var milestones: Dictionary = GFVariantData.get_option_dictionary(
		_active_scene_route,
		"milestones_usec"
	)
	if milestones.has(milestone_id):
		return true
	milestones[milestone_id] = _now_usec()
	_active_scene_route["milestones_usec"] = milestones
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
	var observation_ended_usec: int = _now_usec()
	var started_usec: int = GFVariantData.get_option_int(
		_active_scene_route,
		"started_usec",
		observation_ended_usec
	)
	var requested_route_ready_usec: int = GFVariantData.get_option_int(
		metadata,
		"route_ready_usec",
		observation_ended_usec
	)
	var ended_usec: int = (
		requested_route_ready_usec
		if (
			requested_route_ready_usec >= started_usec
			and requested_route_ready_usec <= observation_ended_usec
		)
		else observation_ended_usec
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
	var load_status: String = GFVariantData.get_option_string(
		_active_scene_route,
		"load_status"
	)
	var load_terminal_success: bool = (
		load_evidence_complete
		and load_status == "completed"
	)
	var switch_duration_msec: float = GFVariantData.get_option_float(
		_active_scene_route,
		"switch_duration_msec",
		-1.0
	)
	var switch_status: String = GFVariantData.get_option_string(
		_active_scene_route,
		"switch_status"
	)
	var switch_evidence_complete: bool = switch_duration_msec >= 0.0
	var switch_terminal_success: bool = (
		switch_evidence_complete
		and switch_status == "completed"
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
	var milestones: Dictionary = GFVariantData.get_option_dictionary(
		_active_scene_route,
		"milestones_usec"
	)
	var phases: Dictionary = _make_phase_observation(
		started_usec,
		GFVariantData.get_option_int(milestones, _PHASE_READY),
		GFVariantData.get_option_int(milestones, _PHASE_POST_DRAW),
		GFVariantData.get_option_int(milestones, _PHASE_MOTION_SETTLED),
		GFVariantData.get_option_bool(
			metadata,
			"motion_settled_observed",
			milestones.has(_PHASE_MOTION_SETTLED)
		)
	)
	var phase_evidence_complete: bool = GFVariantData.get_option_bool(
		phases,
		"evidence_complete"
	)
	var phase_budget: Dictionary = _make_phase_budget_result(
		phases,
		"scene_route_post_draw_max_msec",
		"scene_route_motion_settled_max_msec"
	)
	var phase_budget_passed: bool = GFVariantData.get_option_bool(
		phase_budget,
		"passed"
	)
	var passed: bool = (
		succeeded
		and interactive_ready
		and load_terminal_success
		and switch_terminal_success
		and transition_evidence_complete
		and total_duration_msec <= total_budget_msec
		and load_duration_msec <= load_budget_msec
		and phase_budget_passed
		and (phase_evidence_complete or not _require_phase_evidence)
	)
	var record: Dictionary = {
		"kind": "scene_route",
		"sample_index": _scene_route_records.size(),
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
			"status": load_status,
			"evidence_complete": load_evidence_complete,
			"terminal_success": load_terminal_success,
			"duration_msec": load_duration_msec,
			"budget_msec": load_budget_msec,
			"within_budget": (
				load_evidence_complete
				and load_duration_msec <= load_budget_msec
			),
		},
		"switch": {
			"status": switch_status,
			"evidence_complete": switch_evidence_complete,
			"terminal_success": switch_terminal_success,
			"duration_msec": switch_duration_msec,
		},
		"transitions": transitions,
		"transition_summary": transition_summary,
		"phases": phases,
		"phase_budget": phase_budget,
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
	var boot_failures: int = _count_failed_records(_boot_records)
	var ui_failures: int = _count_failed_records(_ui_route_records)
	var scene_failures: int = _count_failed_records(_scene_route_records)
	var preload_failures: int = _count_failed_records(
		_scene_preload_records
	)
	var ui_samples_complete: bool = (
		_ui_route_records.size() >= _minimum_ui_route_samples
	)
	var boot_samples_complete: bool = (
		_boot_records.size() >= _minimum_boot_samples
	)
	var scene_samples_complete: bool = (
		_scene_route_records.size() >= _minimum_scene_route_samples
	)
	var no_active_scene_work: bool = (
		_active_scene_route.is_empty()
		and _active_scene_preloads.is_empty()
		and _preloading_scene_paths_at_bind.is_empty()
	)
	var active_asset_preload_session_count: int = maxi(
		GFVariantData.get_option_int(
			additional_metadata,
			"active_asset_preload_session_count",
			0
		),
		0
	)
	var no_active_asset_work: bool = active_asset_preload_session_count == 0
	var no_active_work: bool = no_active_scene_work and no_active_asset_work
	var passed: bool = (
		boot_samples_complete
		and ui_samples_complete
		and scene_samples_complete
		and no_active_work
		and boot_failures == 0
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
			"boot": _minimum_boot_samples,
			"ui_routes": _minimum_ui_route_samples,
			"scene_routes": _minimum_scene_route_samples,
		},
		"summary": {
			"boot_count": _boot_records.size(),
			"boot_failure_count": boot_failures,
			"ui_route_count": _ui_route_records.size(),
			"ui_route_failure_count": ui_failures,
			"scene_route_count": _scene_route_records.size(),
			"scene_route_failure_count": scene_failures,
			"scene_preload_count": _scene_preload_records.size(),
			"scene_preload_failure_count": preload_failures,
			"preexisting_scene_preload_pending_count": (
				_preloading_scene_paths_at_bind.size()
			),
			"boot_samples_complete": boot_samples_complete,
			"ui_samples_complete": ui_samples_complete,
			"scene_samples_complete": scene_samples_complete,
			"active_asset_preload_session_count": (
				active_asset_preload_session_count
			),
			"no_active_scene_work": no_active_scene_work,
			"no_active_asset_work": no_active_asset_work,
			"no_active_work": no_active_work,
		},
		"metrics": {
			"boot_ready_msec": _make_nested_metric_summary(
				&"boot_ready_msec",
				_boot_records,
				"phases",
				"ready_msec"
			),
			"boot_post_draw_msec": _make_nested_metric_summary(
				&"boot_post_draw_msec",
				_boot_records,
				"phases",
				"post_draw_msec"
			),
			"boot_motion_settled_msec": _make_nested_metric_summary(
				&"boot_motion_settled_msec",
				_boot_records,
				"phases",
				"motion_settled_msec"
			),
			"ui_route_duration_msec": _make_metric_summary(
				&"ui_route_duration_msec",
				_ui_route_records,
				"duration_msec"
			),
			"ui_route_ready_msec": _make_nested_metric_summary(
				&"ui_route_ready_msec",
				_ui_route_records,
				"phases",
				"ready_msec"
			),
			"ui_route_post_draw_msec": _make_nested_metric_summary(
				&"ui_route_post_draw_msec",
				_ui_route_records,
				"phases",
				"post_draw_msec"
			),
			"ui_route_motion_settled_msec": _make_nested_metric_summary(
				&"ui_route_motion_settled_msec",
				_ui_route_records,
				"phases",
				"motion_settled_msec"
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
			"scene_route_ready_msec": _make_nested_metric_summary(
				&"scene_route_ready_msec",
				_scene_route_records,
				"phases",
				"ready_msec"
			),
			"scene_route_post_draw_msec": _make_nested_metric_summary(
				&"scene_route_post_draw_msec",
				_scene_route_records,
				"phases",
				"post_draw_msec"
			),
			"scene_route_motion_settled_msec": _make_nested_metric_summary(
				&"scene_route_motion_settled_msec",
				_scene_route_records,
				"phases",
				"motion_settled_msec"
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
		"route_groups": {
			"ui": _make_grouped_metric_summaries(
				&"ui_route_duration_msec",
				_ui_route_records,
				"route_id",
				"duration_msec"
			),
			"scene": _make_grouped_metric_summaries(
				&"scene_route_duration_msec",
				_scene_route_records,
				"route_id",
				"duration_msec"
			),
		},
		"sample_protocol": _make_sample_protocol(),
		"boot": _boot_records.duplicate(true),
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
	var json_safe_value: Variant = GFReportValueCodec.to_json_compatible(
		report.duplicate(true),
		{
			"max_depth": 64,
			"max_total_nodes": _REPORT_MAX_TOTAL_NODES,
			"max_total_bytes": _REPORT_MAX_TOTAL_BYTES,
		}
	)
	if not json_safe_value is Dictionary:
		return ERR_INVALID_DATA
	var artifact_report: Dictionary = GFGeneratedArtifactReport.save_text(
		normalized_path,
		JSON.stringify(json_safe_value, "\t") + "\n",
		{
			"allowed_roots": _REPORT_ALLOWED_ROOTS,
			"artifact_owner": GFGeneratedArtifactReport.OWNER_GENERATED,
			"generator_id": "UIRoutePerformanceAcceptanceHarness",
			"source_id": "route_timing_report",
			"scan_filesystem": false,
			"label": "UiRoutePerformance",
		}
	)
	return GFGeneratedArtifactReport.get_error_code(artifact_report)


## 返回 UI 路由记录的隔离副本。
func get_ui_route_records() -> Array[Dictionary]:
	return _ui_route_records.duplicate(true)


## 返回启动记录的隔离副本。
func get_boot_records() -> Array[Dictionary]:
	return _boot_records.duplicate(true)


## 返回场景路由记录的隔离副本。
func get_scene_route_records() -> Array[Dictionary]:
	return _scene_route_records.duplicate(true)


## 返回场景预加载记录的隔离副本。
func get_scene_preload_records() -> Array[Dictionary]:
	return _scene_preload_records.duplicate(true)


## 返回绑定后仍等待唯一终态的场景预加载数量。
func get_pending_scene_preload_count() -> int:
	return (
		_active_scene_preloads.size()
		+ _preloading_scene_paths_at_bind.size()
	)


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
	var _was_preloading_at_bind: bool = (
		_preloading_scene_paths_at_bind.erase(path)
	)
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

func _connect_scene_signal(signal_value: Signal, callback: Callable) -> bool:
	if signal_value.is_connected(callback):
		return true
	return signal_value.connect(callback) == OK


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
		var was_preloading_at_bind: bool = (
			_preloading_scene_paths_at_bind.erase(path)
		)
		if status == "completed" and was_preloading_at_bind:
			return
		_record_scene_preload_without_started(
			path,
			status,
			succeeded,
			was_preloading_at_bind
		)
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


func _record_scene_preload_without_started(
	path: String,
	status: String,
	succeeded: bool,
	was_preloading_at_bind: bool
) -> void:
	var budget_msec: float = GFVariantData.get_option_float(
		_budgets,
		"scene_preload_max_msec"
	)
	_scene_preload_records.append({
		"kind": "scene_preload",
		"path": path,
		"status": status,
		"ok": succeeded,
		"evidence_complete": false,
		"observation_scope": (
			"preexisting_at_bind"
			if was_preloading_at_bind
			else "started_after_bind_without_started_signal"
		),
		"duration_msec": -1.0,
		"budget_msec": budget_msec,
		"within_budget": false,
		"passed": false,
	})


func _make_missing_ui_route_record(
	context: Dictionary,
	observation: Dictionary = {}
) -> Dictionary:
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
		"sample_index": _ui_route_records.size(),
		"request_id": 0,
		"route_id": String(route_id),
		"operation": "",
		"status": "missing_result",
		"reason": "missing_route_result",
		"ok": false,
		"duration_msec": -1.0,
		"budget_msec": budget_msec,
		"within_budget": false,
		"phases": _make_phase_observation_from_dictionary(
			observation,
			-1.0
		),
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


func _make_phase_observation_from_dictionary(
	observation: Dictionary,
	fallback_ready_msec: float
) -> Dictionary:
	var started_usec: int = GFVariantData.get_option_int(
		observation,
		"started_usec"
	)
	var ready_usec: int = GFVariantData.get_option_int(
		observation,
		"ready_usec"
	)
	var post_draw_usec: int = GFVariantData.get_option_int(
		observation,
		"post_draw_usec"
	)
	var motion_settled_usec: int = GFVariantData.get_option_int(
		observation,
		"motion_settled_usec"
	)
	if (
		started_usec <= 0
		or ready_usec <= 0
		or post_draw_usec <= 0
		or motion_settled_usec <= 0
	):
		return {
			"evidence_complete": false,
			"motion_settled_observed": false,
			"ready_msec": fallback_ready_msec,
			"post_draw_msec": -1.0,
			"motion_settled_msec": -1.0,
			"source": "gf_terminal_only",
		}
	var phases: Dictionary = _make_phase_observation(
		started_usec,
		ready_usec,
		post_draw_usec,
		motion_settled_usec,
		GFVariantData.get_option_bool(
			observation,
			"motion_settled_observed",
			false
		)
	)
	phases["source"] = "tool_monotonic_clock"
	return phases


func _make_phase_observation(
	started_usec: int,
	ready_usec: int,
	post_draw_usec: int,
	motion_settled_usec: int,
	motion_settled_observed: bool
) -> Dictionary:
	var monotonic: bool = (
		started_usec >= 0
		and ready_usec >= started_usec
		and post_draw_usec >= ready_usec
		and motion_settled_usec >= post_draw_usec
	)
	return {
		"evidence_complete": monotonic and motion_settled_observed,
		"motion_settled_observed": motion_settled_observed,
		"ready_msec": (
			_usec_delta_to_msec(started_usec, ready_usec)
			if monotonic
			else -1.0
		),
		"post_draw_msec": (
			_usec_delta_to_msec(started_usec, post_draw_usec)
			if monotonic
			else -1.0
		),
		"motion_settled_msec": (
			_usec_delta_to_msec(started_usec, motion_settled_usec)
			if monotonic
			else -1.0
		),
	}


func _make_phase_budget_result(
	phases: Dictionary,
	post_draw_budget_key: String,
	motion_settled_budget_key: String
) -> Dictionary:
	var evidence_complete: bool = GFVariantData.get_option_bool(
		phases,
		"evidence_complete"
	)
	var post_draw_msec: float = GFVariantData.get_option_float(
		phases,
		"post_draw_msec",
		-1.0
	)
	var motion_settled_msec: float = GFVariantData.get_option_float(
		phases,
		"motion_settled_msec",
		-1.0
	)
	var post_draw_budget_msec: float = GFVariantData.get_option_float(
		_budgets,
		post_draw_budget_key
	)
	var motion_settled_budget_msec: float = GFVariantData.get_option_float(
		_budgets,
		motion_settled_budget_key
	)
	var post_draw_within_budget: bool = (
		post_draw_msec >= 0.0
		and post_draw_msec <= post_draw_budget_msec
	)
	var motion_settled_within_budget: bool = (
		motion_settled_msec >= 0.0
		and motion_settled_msec <= motion_settled_budget_msec
	)
	var within_budget: bool = (
		evidence_complete
		and post_draw_within_budget
		and motion_settled_within_budget
	)
	return {
		"evidence_complete": evidence_complete,
		"post_draw_budget_msec": post_draw_budget_msec,
		"post_draw_within_budget": post_draw_within_budget,
		"motion_settled_budget_msec": motion_settled_budget_msec,
		"motion_settled_within_budget": motion_settled_within_budget,
		"within_budget": within_budget,
		"passed": within_budget or (
			not evidence_complete
			and not _require_phase_evidence
		),
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


func _make_grouped_metric_summaries(
	metric_id: StringName,
	records: Array[Dictionary],
	group_key: String,
	value_key: String
) -> Dictionary:
	var grouped_values: Dictionary = {}
	var grouped_sample_indices: Dictionary = {}
	var grouped_cache_states: Dictionary = {}
	for record: Dictionary in records:
		var group_id: String = GFVariantData.get_option_string(
			record,
			group_key
		)
		if group_id.is_empty():
			continue
		var value: float = GFVariantData.get_option_float(
			record,
			value_key,
			-1.0
		)
		if value < 0.0:
			continue
		var values: Array[float] = []
		if grouped_values.has(group_id):
			values.assign(GFVariantData.get_option_array(
				grouped_values,
				group_id
			))
		values.append(value)
		grouped_values[group_id] = values

		var sample_indices: Array[int] = []
		if grouped_sample_indices.has(group_id):
			sample_indices.assign(GFVariantData.get_option_array(
				grouped_sample_indices,
				group_id
			))
		sample_indices.append(GFVariantData.get_option_int(
			record,
			"sample_index",
			sample_indices.size()
		))
		grouped_sample_indices[group_id] = sample_indices

		var cache_states: Array[String] = []
		if grouped_cache_states.has(group_id):
			cache_states.assign(GFVariantData.get_option_array(
				grouped_cache_states,
				group_id
			))
		var context: Dictionary = GFVariantData.get_option_dictionary(
			record,
			"context"
		)
		cache_states.append(
			GFVariantData.get_option_string(context, "cache_state", "unspecified")
		)
		grouped_cache_states[group_id] = cache_states

	var result: Dictionary = {}
	for group_id_value: Variant in grouped_values.keys():
		var group_id: String = str(group_id_value)
		var values: Array[float] = []
		values.assign(GFVariantData.get_option_array(grouped_values, group_id))
		result[group_id] = {
			"metric": _summarize_values(
				StringName("%s.%s" % [metric_id, group_id]),
				values
			),
			"sample_indices": GFVariantData.get_option_array(
				grouped_sample_indices,
				group_id
			).duplicate(),
			"cache_states": GFVariantData.get_option_array(
				grouped_cache_states,
				group_id
			).duplicate(),
		}
	return result


func _make_sample_protocol() -> Dictionary:
	return {
		"clock": "Time.get_ticks_usec monotonic wall clock",
		"sequence_semantics": (
			"GFMetricSeries samples, latest_value and sparkline preserve the "
			+ "recorded execution order; percentile calculations sort a copy"
		),
		"boot": {
			"cache_state": "process_first_boot",
			"ready": "MainMenu is in-tree and node-ready",
			"post_draw": "first RenderingServer.frame_post_draw after ready",
			"motion_settled": "configured tween quiet-window observation",
		},
		"ui_route": {
			"request_duration": "GFUIRouteResult typed terminal duration",
			"first_open_in_process": (
				"first request for the route in this process; boot and adjacent "
				+ "preloads may already have populated shared caches"
			),
			"warm_reopen_in_process": (
				"immediate second request after closing the first panel"
			),
			"ready": (
				"submitted panel is in-tree/node-ready and any route-specific typed "
				+ "semantic contract (editor context, profile snapshot or list content) is terminal"
			),
			"post_draw": "first RenderingServer.frame_post_draw after ready",
			"motion_settled": "configured tween quiet-window observation",
		},
		"scene_route": {
			"request_start": "immediately before SceneRouterSystem intent",
			"route_duration": (
				"request start through SceneRouterSystem idle/interactive ready; "
				+ "motion settling is reported separately"
			),
			"ready": (
				"target scene is in-tree/node-ready and any route-specific "
				+ "list-content or gameplay-board contract is ready"
			),
			"post_draw": "first RenderingServer.frame_post_draw after ready",
			"motion_settled": "configured tween quiet-window observation",
			"load": "GFSceneUtility public load signal interval",
		},
	}


func _summarize_values(
	metric_id: StringName,
	values: Array[float]
) -> Dictionary:
	var series: GFMetricSeries = GFMetricSeries.new().configure(
		metric_id,
		{"max_samples": maxi(values.size(), 1)}
	)
	for index: int in range(values.size()):
		series.add_sample(values[index], float(index))
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
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
