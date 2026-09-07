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
		&"active_cell_count": 256,
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
	# 1280x720 是当前 16:9 微信目标机实际观测的根 Viewport 逻辑尺寸；
	# canvas_items/expand 在其他宽高比会得到不同尺寸，必须另建精确匹配用例。
	{
		&"id": &"wechat_touch_default",
		&"platform": &"wechat",
		&"input_modality": InputModality.TOUCH,
		&"viewport_size": Vector2i(1280, 720),
		&"prefer_compact": true,
		&"expected_layout": GameplayResponsiveLayoutController.LayoutMode.COMPACT_LANDSCAPE,
		&"board_bounds": Vector2i(4, 4),
		&"active_cell_count": 16,
		&"shape": &"rectangle",
		&"vfx_quality": GameAccessibilityState.VfxQuality.MINIMAL,
		&"frame_p95_budget_ms": 25.0,
		&"input_feedback_p95_budget_ms": 50.0,
		&"minimum_samples": 120,
		&"minimum_touch_target_px": 44.0,
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


## 核对显式观测的运行条件是否完整匹配一个验收用例。
##
## 输入会被收敛为固定白名单；额外字段既不参与匹配，也不会进入诊断证据，
## 从而避免把账号、设备身份或棋盘内容意外带入 Support Report。
## @param case_id: 要匹配的稳定验收用例 ID。
## @param observed_contract: 调试工具显式提供的运行条件。
static func match_observed_contract(
	case_id: StringName,
	observed_contract: Dictionary
) -> Dictionary:
	var acceptance_case: Dictionary = get_case(case_id)
	if acceptance_case.is_empty():
		return {
			&"ok": false,
			&"case_id": case_id,
			&"reason": &"unknown_case",
			&"mismatches": [{&"field": &"case_id"}],
			&"observed_contract": {},
		}

	var missing_fields: PackedStringArray = PackedStringArray()
	for required_field: StringName in [
		&"platform",
		&"input_modality",
		&"viewport_size",
		&"prefer_compact",
		&"board_bounds",
		&"active_cell_count",
		&"shape",
		&"vfx_quality",
	]:
		if not observed_contract.has(required_field):
			var _missing_appended: bool = missing_fields.append(
				String(required_field)
			)
	var required_touch_target_px: float = GFVariantData.get_option_float(
		acceptance_case,
		&"minimum_touch_target_px"
	)
	if (
		required_touch_target_px > 0.0
		and not observed_contract.has(&"minimum_touch_target_px")
	):
		var _touch_missing_appended: bool = missing_fields.append(
			"minimum_touch_target_px"
		)
	if not missing_fields.is_empty():
		return {
			&"ok": false,
			&"case_id": case_id,
			&"reason": &"missing_observed_fields",
			&"mismatches": [{
				&"field": &"required_fields",
				&"missing": missing_fields,
			}],
			&"observed_contract": {},
		}

	var normalized: Dictionary = {
		&"platform": _normalize_string_name(
			observed_contract.get(&"platform")
		),
		&"input_modality": _normalize_input_modality(
			observed_contract.get(&"input_modality")
		),
		&"viewport_size": _normalize_vector2i(
			observed_contract.get(&"viewport_size")
		),
		&"prefer_compact": _normalize_bool(
			observed_contract.get(&"prefer_compact")
		),
		&"board_bounds": _normalize_vector2i(
			observed_contract.get(&"board_bounds")
		),
		&"active_cell_count": _normalize_integer(
			observed_contract.get(&"active_cell_count")
		),
		&"shape": _normalize_string_name(observed_contract.get(&"shape")),
		&"vfx_quality": _normalize_vfx_quality(
			observed_contract.get(&"vfx_quality")
		),
		&"minimum_touch_target_px": _normalize_nonnegative_float(
			observed_contract.get(&"minimum_touch_target_px", 0.0)
		),
	}
	var mismatches: Array[Dictionary] = []
	_append_exact_mismatch(
		mismatches,
		&"platform",
		GFVariantData.get_option_string_name(acceptance_case, &"platform"),
		normalized.get(&"platform")
	)
	_append_exact_mismatch(
		mismatches,
		&"input_modality",
		GFVariantData.get_option_int(acceptance_case, &"input_modality"),
		normalized.get(&"input_modality")
	)
	_append_exact_mismatch(
		mismatches,
		&"viewport_size",
		Vector2i(GFVariantData.get_option_vector2(
			acceptance_case,
			&"viewport_size"
		)),
		normalized.get(&"viewport_size")
	)
	_append_exact_mismatch(
		mismatches,
		&"prefer_compact",
		GFVariantData.get_option_bool(acceptance_case, &"prefer_compact"),
		normalized.get(&"prefer_compact")
	)
	_append_exact_mismatch(
		mismatches,
		&"board_bounds",
		Vector2i(GFVariantData.get_option_vector2(
			acceptance_case,
			&"board_bounds"
		)),
		normalized.get(&"board_bounds")
	)
	_append_exact_mismatch(
		mismatches,
		&"active_cell_count",
		GFVariantData.get_option_int(acceptance_case, &"active_cell_count"),
		normalized.get(&"active_cell_count")
	)
	_append_exact_mismatch(
		mismatches,
		&"shape",
		GFVariantData.get_option_string_name(acceptance_case, &"shape"),
		normalized.get(&"shape")
	)
	_append_exact_mismatch(
		mismatches,
		&"vfx_quality",
		GFVariantData.get_option_int(acceptance_case, &"vfx_quality"),
		normalized.get(&"vfx_quality")
	)
	var observed_touch_target_px: float = GFVariantData.get_option_float(
		normalized,
		&"minimum_touch_target_px",
		-1.0
	)
	if observed_touch_target_px < required_touch_target_px:
		mismatches.append({
			&"field": &"minimum_touch_target_px",
			&"minimum": required_touch_target_px,
			&"observed": observed_touch_target_px,
		})

	var viewport_size: Vector2i = _normalize_vector2i(
		normalized.get(&"viewport_size")
	)
	var observed_layout: int = GameplayResponsiveLayoutController.classify_layout(
		Vector2(viewport_size),
		GFVariantData.get_option_bool(normalized, &"prefer_compact")
	)
	_append_exact_mismatch(
		mismatches,
		&"expected_layout",
		GFVariantData.get_option_int(acceptance_case, &"expected_layout", -1),
		observed_layout
	)
	return {
		&"ok": mismatches.is_empty(),
		&"case_id": case_id,
		&"reason": (
			&"matched" if mismatches.is_empty() else &"observed_contract_mismatch"
		),
		&"mismatches": mismatches,
		&"observed_contract": normalized,
	}


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


static func _normalize_string_name(value: Variant) -> StringName:
	if value is StringName:
		return value
	if value is String:
		var string_value: String = value
		var text: String = string_value.strip_edges().to_lower()
		return StringName(text)
	return &""


static func _normalize_input_modality(value: Variant) -> int:
	var numeric_value: int = _normalize_integer(value)
	if numeric_value in InputModality.values():
		return numeric_value
	match _normalize_string_name(value):
		&"keyboard_mouse":
			return InputModality.KEYBOARD_MOUSE
		&"gamepad":
			return InputModality.GAMEPAD
		&"touch":
			return InputModality.TOUCH
		_:
			return -1


static func _normalize_vfx_quality(value: Variant) -> int:
	var numeric_value: int = _normalize_integer(value)
	if numeric_value in GameAccessibilityState.VfxQuality.values():
		return numeric_value
	match _normalize_string_name(value):
		&"full":
			return GameAccessibilityState.VfxQuality.FULL
		&"reduced":
			return GameAccessibilityState.VfxQuality.REDUCED
		&"minimal":
			return GameAccessibilityState.VfxQuality.MINIMAL
		_:
			return -1


static func _normalize_bool(value: Variant) -> Variant:
	return value if value is bool else null


static func _normalize_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_finite(number) and is_equal_approx(number, float(roundi(number))):
			return roundi(number)
	return -1


static func _normalize_nonnegative_float(value: Variant) -> float:
	var number: float = -1.0
	if value is int:
		var integer_value: int = value
		number = float(integer_value)
	elif value is float:
		number = value
	if is_finite(number) and number >= 0.0:
		return number
	return -1.0


static func _normalize_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		var vector: Vector2 = value
		if (
			is_finite(vector.x)
			and is_finite(vector.y)
			and is_equal_approx(vector.x, float(roundi(vector.x)))
			and is_equal_approx(vector.y, float(roundi(vector.y)))
		):
			return Vector2i(roundi(vector.x), roundi(vector.y))
	if value is Array:
		var values: Array = value
		if values.size() == 2:
			var x: int = _normalize_integer(values[0])
			var y: int = _normalize_integer(values[1])
			if x >= 0 and y >= 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _append_exact_mismatch(
	mismatches: Array[Dictionary],
	field: StringName,
	expected: Variant,
	observed: Variant
) -> void:
	if expected == observed:
		return
	mismatches.append({
		&"field": field,
		&"expected": expected,
		&"observed": observed,
	})


static func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key)
