## GameplayAcceptanceMatrix: 输入、视口、棋盘规模与性能预算的可执行验收契约。
##
## 矩阵只声明目标并评估 GFMetricSeries 采样，不把未经测量的目标伪装成结果。
class_name GameplayAcceptanceMatrix
extends RefCounted


# --- 枚举 ---

enum InputModality {
	KEYBOARD_MOUSE,
	GAMEPAD,
	TOUCH,
}


# --- 常量 ---

const _MINIMUM_TOUCH_TARGET_PX: float = 44.0
const _CASES: Array[Dictionary] = [
	{
		&"id": &"steam_keyboard_standard",
		&"platform": &"steam_windows",
		&"input_modality": InputModality.KEYBOARD_MOUSE,
		&"viewport_size": Vector2i(1920, 1080),
		&"prefer_compact": false,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.DESKTOP,
		&"board_bounds": Vector2i(4, 4),
		&"active_cell_count": 16,
		&"shape": &"rectangle",
		&"vfx_quality": GameAccessibilityState.VfxQuality.FULL,
		&"frame_p95_budget_ms": 16.667,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 0.0,
	},
	{
		&"id": &"steam_gamepad_large_irregular",
		&"platform": &"steam_windows",
		&"input_modality": InputModality.GAMEPAD,
		&"viewport_size": Vector2i(1280, 720),
		&"prefer_compact": false,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.DESKTOP,
		&"board_bounds": Vector2i(32, 32),
		&"active_cell_count": 420,
		&"shape": &"irregular",
		&"vfx_quality": GameAccessibilityState.VfxQuality.FULL,
		&"frame_p95_budget_ms": 16.667,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 0.0,
	},
	{
		&"id": &"web_keyboard_rectangular",
		&"platform": &"web",
		&"input_modality": InputModality.KEYBOARD_MOUSE,
		&"viewport_size": Vector2i(960, 540),
		&"prefer_compact": false,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE,
		&"board_bounds": Vector2i(12, 8),
		&"active_cell_count": 80,
		&"shape": &"rectangle",
		&"vfx_quality": GameAccessibilityState.VfxQuality.REDUCED,
		&"frame_p95_budget_ms": 20.0,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 0.0,
	},
	{
		&"id": &"wechat_touch_landscape",
		&"platform": &"wechat",
		&"input_modality": InputModality.TOUCH,
		&"viewport_size": Vector2i(1280, 720),
		&"prefer_compact": true,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE,
		&"board_bounds": Vector2i(12, 8),
		&"active_cell_count": 72,
		&"shape": &"irregular",
		&"vfx_quality": GameAccessibilityState.VfxQuality.REDUCED,
		&"frame_p95_budget_ms": 25.0,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 44.0,
	},
	{
		&"id": &"mobile_touch_portrait",
		&"platform": &"mobile",
		&"input_modality": InputModality.TOUCH,
		&"viewport_size": Vector2i(390, 844),
		&"prefer_compact": true,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.PORTRAIT,
		&"board_bounds": Vector2i(6, 10),
		&"active_cell_count": 48,
		&"shape": &"irregular",
		&"vfx_quality": GameAccessibilityState.VfxQuality.REDUCED,
		&"frame_p95_budget_ms": 25.0,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 44.0,
	},
	{
		&"id": &"low_end_touch_sparse",
		&"platform": &"mobile_low_end",
		&"input_modality": InputModality.TOUCH,
		&"viewport_size": Vector2i(360, 640),
		&"prefer_compact": true,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.PORTRAIT,
		&"board_bounds": Vector2i(20, 30),
		&"active_cell_count": 180,
		&"shape": &"sparse",
		&"vfx_quality": GameAccessibilityState.VfxQuality.MINIMAL,
		&"frame_p95_budget_ms": 33.3,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 44.0,
	},
]


# --- 公共方法 ---

static func get_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for acceptance_case: Dictionary in _CASES:
		result.append(acceptance_case.duplicate(true))
	return result


## @param case_id: 要查询的稳定验收用例 ID。
static func get_case(case_id: StringName) -> Dictionary:
	for acceptance_case: Dictionary in _CASES:
		if GFVariantData.get_option_string_name(acceptance_case, &"id") == case_id:
			return acceptance_case.duplicate(true)
	return {}


## 校验矩阵覆盖与每个用例的静态契约。
static func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new("GameplayAcceptanceMatrix")
	var seen_ids: Dictionary = {}
	var covered_inputs: Dictionary = {}
	var covered_layouts: Dictionary = {}
	var covered_qualities: Dictionary = {}
	var covered_shapes: Dictionary = {}

	for acceptance_case: Dictionary in _CASES:
		_validate_case(
			report,
			acceptance_case,
			seen_ids,
			covered_inputs,
			covered_layouts,
			covered_qualities,
			covered_shapes
		)

	for modality: InputModality in InputModality.values():
		if not covered_inputs.has(modality):
			_add_error(report, &"missing_input_coverage", "输入方式未被矩阵覆盖。", modality)
	for layout: GameplayResponsiveLayoutController.LayoutMode in (
		GameplayResponsiveLayoutController.LayoutMode.values()
	):
		if not covered_layouts.has(layout):
			_add_error(report, &"missing_layout_coverage", "响应式布局未被矩阵覆盖。", layout)
	for quality: GameAccessibilityState.VfxQuality in GameAccessibilityState.VfxQuality.values():
		if not covered_qualities.has(quality):
			_add_error(report, &"missing_quality_coverage", "反馈质量档位未被矩阵覆盖。", quality)
	for shape: StringName in [&"rectangle", &"irregular", &"sparse"]:
		if not covered_shapes.has(shape):
			_add_error(report, &"missing_board_shape_coverage", "棋盘形态未被矩阵覆盖。", shape)
	return report


## 用两条 GFMetricSeries 评估指定用例，输出可持久化的证据快照。
## @param case_id: 要执行的稳定验收用例 ID。
## @param frame_time_ms: 帧时毫秒采样。
## @param input_feedback_ms: 输入到首个主要反馈的毫秒采样。
static func evaluate_case(
	case_id: StringName,
	frame_time_ms: GFMetricSeries,
	input_feedback_ms: GFMetricSeries
) -> Dictionary:
	var acceptance_case: Dictionary = get_case(case_id)
	if acceptance_case.is_empty():
		return {
			&"case_id": case_id,
			&"configured": false,
			&"passed": false,
			&"reason": &"unknown_case",
		}
	if frame_time_ms == null or input_feedback_ms == null:
		return {
			&"case_id": case_id,
			&"configured": true,
			&"passed": false,
			&"reason": &"missing_metric_series",
		}

	var minimum_samples: int = GFVariantData.get_option_int(
		acceptance_case,
		&"minimum_samples"
	)
	var frame_sample_count: int = frame_time_ms.get_sample_count()
	var input_sample_count: int = input_feedback_ms.get_sample_count()
	var evidence_complete: bool = (
		frame_sample_count >= minimum_samples
		and input_sample_count >= minimum_samples
	)
	var frame_p95_ms: float = _percentile(frame_time_ms, 0.95)
	var input_p95_ms: float = _percentile(input_feedback_ms, 0.95)
	var frame_budget_ms: float = GFVariantData.get_option_float(
		acceptance_case,
		&"frame_p95_budget_ms"
	)
	var input_budget_ms: float = GFVariantData.get_option_float(
		acceptance_case,
		&"input_feedback_p95_budget_ms"
	)
	var passed: bool = (
		evidence_complete
		and frame_p95_ms <= frame_budget_ms
		and input_p95_ms <= input_budget_ms
	)
	return {
		&"case_id": case_id,
		&"configured": true,
		&"passed": passed,
		&"reason": &"evaluated" if evidence_complete else &"insufficient_samples",
		&"targets": {
			&"frame_p95_budget_ms": frame_budget_ms,
			&"input_feedback_p95_budget_ms": input_budget_ms,
			&"minimum_samples": minimum_samples,
		},
		&"measurements": {
			&"frame_p50_ms": _percentile(frame_time_ms, 0.50),
			&"frame_p95_ms": frame_p95_ms,
			&"frame_p99_ms": _percentile(frame_time_ms, 0.99),
			&"input_feedback_p50_ms": _percentile(input_feedback_ms, 0.50),
			&"input_feedback_p95_ms": input_p95_ms,
			&"input_feedback_p99_ms": _percentile(input_feedback_ms, 0.99),
		},
		&"series": {
			&"frame_time_ms": frame_time_ms.to_dict(false),
			&"input_feedback_ms": input_feedback_ms.to_dict(false),
		},
		&"case": acceptance_case,
	}


# --- 私有/辅助方法 ---

static func _validate_case(
	report: GFValidationReport,
	acceptance_case: Dictionary,
	seen_ids: Dictionary,
	covered_inputs: Dictionary,
	covered_layouts: Dictionary,
	covered_qualities: Dictionary,
	covered_shapes: Dictionary
) -> void:
	var case_id: StringName = GFVariantData.get_option_string_name(acceptance_case, &"id")
	if case_id == &"":
		_add_error(report, &"missing_case_id", "验收用例缺少稳定 ID。", &"id")
		return
	if seen_ids.has(case_id):
		_add_error(report, &"duplicate_case_id", "验收用例 ID 重复。", case_id)
		return
	seen_ids[case_id] = true

	var viewport_size: Vector2i = Vector2i(
		GFVariantData.get_option_vector2(acceptance_case, &"viewport_size")
	)
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		_add_error(report, &"invalid_viewport_size", "视口尺寸必须为正数。", case_id)
	var expected_layout: int = GFVariantData.get_option_int(
		acceptance_case,
		&"expected_layout",
		-1
	)
	var actual_layout: int = GameplayResponsiveLayoutController.classify_layout(
		Vector2(viewport_size),
		GFVariantData.get_option_bool(acceptance_case, &"prefer_compact")
	)
	if expected_layout != actual_layout:
		_add_error(report, &"layout_contract_mismatch", "用例声明的布局与运行时分类不一致。", case_id)

	var board_bounds: Vector2i = Vector2i(
		GFVariantData.get_option_vector2(acceptance_case, &"board_bounds")
	)
	var active_cell_count: int = GFVariantData.get_option_int(
		acceptance_case,
		&"active_cell_count"
	)
	if (
		board_bounds.x <= 0
		or board_bounds.y <= 0
		or active_cell_count <= 0
		or active_cell_count > board_bounds.x * board_bounds.y
	):
		_add_error(report, &"invalid_board_scale", "棋盘边界或有效格数量不合法。", case_id)

	var input_modality: int = GFVariantData.get_option_int(
		acceptance_case,
		&"input_modality",
		-1
	)
	var quality: int = GFVariantData.get_option_int(acceptance_case, &"vfx_quality", -1)
	var shape: StringName = GFVariantData.get_option_string_name(acceptance_case, &"shape")
	covered_inputs[input_modality] = true
	covered_layouts[expected_layout] = true
	covered_qualities[quality] = true
	covered_shapes[shape] = true

	if (
		GFVariantData.get_option_float(acceptance_case, &"frame_p95_budget_ms") <= 0.0
		or GFVariantData.get_option_float(
			acceptance_case,
			&"input_feedback_p95_budget_ms"
		) <= 0.0
		or GFVariantData.get_option_int(acceptance_case, &"minimum_samples") <= 0
	):
		_add_error(report, &"invalid_performance_budget", "性能预算必须为正数。", case_id)
	if input_modality == InputModality.TOUCH:
		var touch_target_px: float = GFVariantData.get_option_float(
			acceptance_case,
			&"minimum_touch_target_px"
		)
		if touch_target_px < _MINIMUM_TOUCH_TARGET_PX:
			_add_error(report, &"touch_target_too_small", "触控目标不得小于 44px。", case_id)


static func _percentile(series: GFMetricSeries, percentile: float) -> float:
	if series == null or series.get_sample_count() == 0:
		return 0.0
	var values: Array[float] = []
	for sample: Dictionary in series.get_samples():
		values.append(GFVariantData.get_option_float(sample, &"value"))
	values.sort()
	var position: float = clampf(percentile, 0.0, 1.0) * float(values.size() - 1)
	var lower_index: int = floori(position)
	var upper_index: int = ceili(position)
	return lerpf(values[lower_index], values[upper_index], position - float(lower_index))


static func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key)
