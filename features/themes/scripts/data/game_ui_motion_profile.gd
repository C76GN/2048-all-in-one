## GameUiMotionProfile: 主题拥有的通用 UI 动效语义与节拍。
##
## Profile 只描述项目视觉语言，不拥有 Tween 生命周期。GameUiMotionUtility
## 与 GameButtonMotionPresenter 仍是唯一运行时执行者。
class_name GameUiMotionProfile
extends Resource


# --- 语义预设 ---

const PRESET_BUTTON_ACTIVE: StringName = &"ui.button.active"
const PRESET_BUTTON_PRESS: StringName = &"ui.button.press"
const PRESET_BUTTON_RESTORE: StringName = &"ui.button.restore"
const PRESET_BUTTON_DEAL: StringName = &"ui.button.deal"
const PRESET_PANEL_ENTER: StringName = &"ui.panel.enter"
const PRESET_MODAL_ENTER: StringName = &"ui.modal.enter"
const PRESET_MODAL_EXIT: StringName = &"ui.modal.exit"
const PRESET_CONTROL_REVEAL: StringName = &"ui.control.reveal"
const PRESET_CONTROL_PULSE: StringName = &"ui.control.pulse"
const PRESET_CONTENT_SWITCH: StringName = &"ui.content.switch"
const PRESET_PIECE_ASSEMBLY: StringName = &"ui.piece.assembly"
const PRESET_SCROLL_ACTIVE: StringName = &"ui.scroll.active"
const PRESET_SCROLL_IDLE: StringName = &"ui.scroll.idle"
const PRESET_NUMERIC_CHANGE: StringName = &"ui.number.change"
const PRESET_NUMERIC_DELTA: StringName = &"ui.number.delta"
const PRESET_TOAST_ENTER: StringName = &"ui.toast.enter"
const PRESET_TOAST_EXIT: StringName = &"ui.toast.exit"
const PRESET_LOADING_DELAY: StringName = &"ui.loading.delay"
const PRESET_PROGRESS_CHANGE: StringName = &"ui.progress.change"
const PRESET_ERROR_LOCAL: StringName = &"ui.error.local"
const PRESET_REWARD_RESULT_REVEAL: StringName = &"reward.result.reveal"


# --- 导出变量 ---

@export_group("Button")
@export_range(0.001, 1.0, 0.001) var button_active_overshoot_duration: float = 0.058
@export_range(0.001, 1.0, 0.001) var button_active_settle_duration: float = 0.092
@export_range(0.001, 1.0, 0.001) var button_restore_duration: float = 0.092
@export_range(0.001, 1.0, 0.001) var button_press_duration: float = 0.052
@export_range(0.001, 1.0, 0.001) var button_deal_duration: float = 0.180
@export_range(0.001, 1.0, 0.001) var button_text_reveal_duration: float = 0.105
@export var button_deal_offset: Vector2 = Vector2(18.0, 0.0)
@export_range(0.0, 0.25, 0.001) var button_deal_stagger: float = 0.032
@export var button_deal_start_scale: Vector2 = Vector2(0.82, 0.72)
@export_range(0.0, 1.0, 0.01) var button_deal_fade_ratio: float = 0.62
@export_range(0.0, 0.15, 0.001) var button_max_tilt_radians: float = 0.020
@export var button_toggle_compress_scale: Vector2 = Vector2(0.975, 0.94)
@export_range(0.001, 1.0, 0.001) var button_toggle_compress_duration: float = 0.052
@export_range(0.001, 1.0, 0.001) var button_toggle_restore_duration: float = 0.088

@export_group("Panel And Modal")
@export var panel_enter_offset: Vector2 = Vector2(0.0, 10.0)
@export_range(0.5, 1.0, 0.001) var panel_enter_start_scale: float = 0.992
@export_range(0.001, 1.0, 0.001) var panel_enter_duration: float = 0.180
@export_range(0.5, 1.0, 0.001) var modal_enter_start_scale: float = 0.972
@export_range(0.001, 1.0, 0.001) var modal_enter_scale_duration: float = 0.200
@export_range(0.001, 1.0, 0.001) var modal_enter_fade_duration: float = 0.160
@export_range(0.5, 1.0, 0.001) var modal_exit_end_scale: float = 0.985
@export_range(0.001, 1.0, 0.001) var modal_exit_scale_duration: float = 0.130
@export_range(0.001, 1.0, 0.001) var modal_exit_surface_fade_duration: float = 0.110
@export_range(0.001, 1.0, 0.001) var modal_exit_backdrop_fade_duration: float = 0.130
@export_range(1.0, 2.0, 0.01) var control_pulse_start_scale: float = 1.035
@export_range(0.001, 1.0, 0.001) var control_pulse_duration: float = 0.220
@export var control_pulse_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)

@export_group("Reveal And Switch")
@export var control_reveal_offset: Vector2 = Vector2(8.0, 0.0)
@export_range(0.001, 1.0, 0.001) var control_reveal_duration: float = 0.140
@export_range(0.0, 0.25, 0.001) var control_reveal_stagger: float = 0.025
@export_range(0.5, 1.0, 0.001) var control_reveal_start_scale: float = 0.985
@export_range(0.0, 1.0, 0.01) var control_reveal_maximum_stagger: float = 0.160
@export var content_switch_offset: Vector2 = Vector2(12.0, 0.0)
@export_range(0.001, 1.0, 0.001) var content_switch_duration: float = 0.150
@export_range(0.5, 1.0, 0.001) var content_switch_start_scale: float = 0.992

@export_group("Assembly")
@export_range(0.001, 2.0, 0.001) var piece_assembly_duration: float = 0.280
@export_range(0.0, 0.25, 0.001) var piece_assembly_stagger: float = 0.055
@export_range(0.1, 1.0, 0.01) var piece_assembly_start_scale: float = 0.72
@export_range(0.0, 0.5, 0.001) var piece_assembly_start_rotation: float = 0.10

@export_group("Scroll")
@export_range(0.0, 1.0, 0.01) var scroll_idle_alpha: float = 0.48
@export_range(0.1, 1.0, 0.01) var scroll_idle_thickness_scale: float = 0.72
@export_range(0.001, 1.0, 0.001) var scroll_active_duration: float = 0.110
@export_range(0.0, 2.0, 0.01) var scroll_idle_delay: float = 0.420
@export_range(0.001, 1.0, 0.001) var scroll_idle_duration: float = 0.200

@export_group("Numeric")
@export_range(0.001, 1.0, 0.001) var numeric_change_duration: float = 0.220
@export_range(0.001, 2.0, 0.001) var numeric_delta_duration: float = 0.360
@export_range(1.0, 2.0, 0.01) var numeric_start_scale: float = 1.08
@export_range(0.0, 1.0, 0.01) var numeric_color_mix: float = 0.22
@export_range(0.0, 100.0, 0.5) var numeric_delta_start_distance: float = 5.0
@export_range(0.0, 200.0, 0.5) var numeric_delta_end_distance: float = 38.0
@export_range(0.1, 1.0, 0.01) var numeric_delta_start_scale: float = 0.78
@export_range(0.0, 1.0, 0.01) var numeric_delta_fade_delay_ratio: float = 0.28
@export var numeric_gain_color: Color = Color(0.82, 0.69, 0.34, 1.0)
@export var numeric_loss_color: Color = Color(0.58, 0.27, 0.19, 1.0)

@export_group("Feedback And Async")
@export var toast_enter_offset: Vector2 = Vector2(0.0, 8.0)
@export_range(0.001, 1.0, 0.001) var toast_enter_duration: float = 0.160
@export var toast_exit_offset: Vector2 = Vector2(0.0, -6.0)
@export_range(0.001, 1.0, 0.001) var toast_exit_duration: float = 0.120
@export_range(0.0, 2.0, 0.01) var loading_indicator_delay: float = 0.180
@export_range(0.001, 1.0, 0.001) var progress_change_duration: float = 0.160
@export_range(1.0, 1.25, 0.001) var progress_change_start_scale: float = 1.015
@export_range(0.001, 1.0, 0.001) var local_error_duration: float = 0.180
@export_range(0.0, 1.0, 0.01) var local_error_color_mix: float = 0.16
@export_range(0.001, 2.0, 0.001) var reward_result_reveal_duration: float = 0.420
@export_range(0.0, 0.25, 0.001) var reward_result_reveal_stagger: float = 0.055
@export_range(0.5, 1.0, 0.001) var reward_result_start_scale: float = 0.92


# --- 公共方法 ---

## 返回语义预设的主时长；多阶段预设返回完整可见阶段的时长。
## @param preset_id: 要查询的语义预设标识。
func get_duration(preset_id: StringName) -> float:
	match preset_id:
		PRESET_BUTTON_ACTIVE:
			return button_active_overshoot_duration + button_active_settle_duration
		PRESET_BUTTON_PRESS:
			return button_press_duration
		PRESET_BUTTON_RESTORE:
			return button_restore_duration
		PRESET_BUTTON_DEAL:
			return button_deal_duration
		PRESET_PANEL_ENTER:
			return panel_enter_duration
		PRESET_MODAL_ENTER:
			return maxf(modal_enter_scale_duration, modal_enter_fade_duration)
		PRESET_MODAL_EXIT:
			return maxf(
				modal_exit_scale_duration,
				maxf(modal_exit_surface_fade_duration, modal_exit_backdrop_fade_duration)
			)
		PRESET_CONTROL_REVEAL:
			return control_reveal_duration
		PRESET_CONTROL_PULSE:
			return control_pulse_duration
		PRESET_CONTENT_SWITCH:
			return content_switch_duration
		PRESET_PIECE_ASSEMBLY:
			return piece_assembly_duration
		PRESET_SCROLL_ACTIVE:
			return scroll_active_duration
		PRESET_SCROLL_IDLE:
			return scroll_idle_duration
		PRESET_NUMERIC_CHANGE:
			return numeric_change_duration
		PRESET_NUMERIC_DELTA:
			return numeric_delta_duration
		PRESET_TOAST_ENTER:
			return toast_enter_duration
		PRESET_TOAST_EXIT:
			return toast_exit_duration
		PRESET_PROGRESS_CHANGE:
			return progress_change_duration
		PRESET_ERROR_LOCAL:
			return local_error_duration
		PRESET_REWARD_RESULT_REVEAL:
			return reward_result_reveal_duration
		_:
			return 0.0


## 返回具有空间来源的语义预设偏移。
## @param preset_id: 要查询的语义预设标识。
func get_offset(preset_id: StringName) -> Vector2:
	match preset_id:
		PRESET_BUTTON_DEAL:
			return button_deal_offset
		PRESET_PANEL_ENTER:
			return panel_enter_offset
		PRESET_CONTROL_REVEAL:
			return control_reveal_offset
		PRESET_CONTENT_SWITCH:
			return content_switch_offset
		PRESET_TOAST_ENTER:
			return toast_enter_offset
		PRESET_TOAST_EXIT:
			return toast_exit_offset
		_:
			return Vector2.ZERO


## 返回语义预设的错峰间隔。
## @param preset_id: 要查询的语义预设标识。
func get_stagger(preset_id: StringName) -> float:
	match preset_id:
		PRESET_BUTTON_DEAL:
			return button_deal_stagger
		PRESET_CONTROL_REVEAL:
			return control_reveal_stagger
		PRESET_PIECE_ASSEMBLY:
			return piece_assembly_stagger
		PRESET_REWARD_RESULT_REVEAL:
			return reward_result_reveal_stagger
		_:
			return 0.0


## 返回语义预设在开始执行前的非阻塞等待时间。
## @param preset_id: 要查询的语义预设标识。
func get_delay(preset_id: StringName) -> float:
	if preset_id == PRESET_LOADING_DELAY:
		return loading_indicator_delay
	return 0.0


## 返回语义预设的起始缩放；无缩放语义时返回 1。
## @param preset_id: 要查询的语义预设标识。
func get_start_scale(preset_id: StringName) -> float:
	match preset_id:
		PRESET_PANEL_ENTER:
			return panel_enter_start_scale
		PRESET_MODAL_ENTER:
			return modal_enter_start_scale
		PRESET_CONTROL_REVEAL:
			return control_reveal_start_scale
		PRESET_CONTROL_PULSE:
			return control_pulse_start_scale
		PRESET_CONTENT_SWITCH:
			return content_switch_start_scale
		PRESET_PIECE_ASSEMBLY:
			return piece_assembly_start_scale
		PRESET_PROGRESS_CHANGE:
			return progress_change_start_scale
		PRESET_REWARD_RESULT_REVEAL:
			return reward_result_start_scale
		_:
			return 1.0


func is_valid_profile() -> bool:
	return get_validation_report().is_ok()


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameUiMotionProfile",
		{"resource_path": resource_path}
	)
	var required_durations: Dictionary = {
		&"button_active_overshoot_duration": button_active_overshoot_duration,
		&"button_active_settle_duration": button_active_settle_duration,
		&"button_restore_duration": button_restore_duration,
		&"button_press_duration": button_press_duration,
		&"button_deal_duration": button_deal_duration,
		&"button_text_reveal_duration": button_text_reveal_duration,
		&"panel_enter_duration": panel_enter_duration,
		&"modal_enter_scale_duration": modal_enter_scale_duration,
		&"modal_enter_fade_duration": modal_enter_fade_duration,
		&"modal_exit_scale_duration": modal_exit_scale_duration,
		&"modal_exit_surface_fade_duration": modal_exit_surface_fade_duration,
		&"modal_exit_backdrop_fade_duration": modal_exit_backdrop_fade_duration,
		&"control_pulse_duration": control_pulse_duration,
		&"control_reveal_duration": control_reveal_duration,
		&"content_switch_duration": content_switch_duration,
		&"piece_assembly_duration": piece_assembly_duration,
		&"scroll_active_duration": scroll_active_duration,
		&"scroll_idle_duration": scroll_idle_duration,
		&"numeric_change_duration": numeric_change_duration,
		&"numeric_delta_duration": numeric_delta_duration,
		&"toast_enter_duration": toast_enter_duration,
		&"toast_exit_duration": toast_exit_duration,
		&"progress_change_duration": progress_change_duration,
		&"local_error_duration": local_error_duration,
		&"reward_result_reveal_duration": reward_result_reveal_duration,
	}
	for property_name: Variant in required_durations:
		if GFVariantData.to_float(required_durations[property_name], 0.0) <= 0.0:
			_add_error(
				report,
				&"invalid_duration",
				"%s 必须大于 0。" % GFVariantData.to_text(property_name),
				property_name
			)
	if button_deal_stagger < 0.0 or control_reveal_stagger < 0.0:
		_add_error(report, &"invalid_stagger", "错峰间隔不能小于 0。", &"stagger")
	if (
		piece_assembly_stagger < 0.0
		or reward_result_reveal_stagger < 0.0
		or scroll_idle_delay < 0.0
		or loading_indicator_delay < 0.0
	):
		_add_error(report, &"invalid_delay", "等待时间不能小于 0。", &"delay")
	if (
		button_deal_start_scale.x <= 0.0
		or button_deal_start_scale.y <= 0.0
		or button_toggle_compress_scale.x <= 0.0
		or button_toggle_compress_scale.y <= 0.0
	):
		_add_error(report, &"invalid_button_scale", "按钮缩放必须大于 0。", &"button_scale")
	if numeric_delta_end_distance < numeric_delta_start_distance:
		_add_error(
			report,
			&"invalid_numeric_delta_distance",
			"数值飘字终点距离不能小于起点距离。",
			&"numeric_delta_end_distance"
		)
	var positive_scales: Dictionary = {
		&"panel_enter_start_scale": panel_enter_start_scale,
		&"modal_enter_start_scale": modal_enter_start_scale,
		&"modal_exit_end_scale": modal_exit_end_scale,
		&"control_pulse_start_scale": control_pulse_start_scale,
		&"control_reveal_start_scale": control_reveal_start_scale,
		&"content_switch_start_scale": content_switch_start_scale,
		&"piece_assembly_start_scale": piece_assembly_start_scale,
		&"scroll_idle_thickness_scale": scroll_idle_thickness_scale,
		&"numeric_start_scale": numeric_start_scale,
		&"numeric_delta_start_scale": numeric_delta_start_scale,
		&"progress_change_start_scale": progress_change_start_scale,
		&"reward_result_start_scale": reward_result_start_scale,
	}
	for property_name: Variant in positive_scales:
		if GFVariantData.to_float(positive_scales[property_name], 0.0) <= 0.0:
			_add_error(
				report,
				&"invalid_scale",
				"%s 必须大于 0。" % GFVariantData.to_text(property_name),
				property_name
			)
	var normalized_values: Dictionary = {
		&"button_deal_fade_ratio": button_deal_fade_ratio,
		&"scroll_idle_alpha": scroll_idle_alpha,
		&"numeric_color_mix": numeric_color_mix,
		&"numeric_delta_fade_delay_ratio": numeric_delta_fade_delay_ratio,
		&"local_error_color_mix": local_error_color_mix,
	}
	for property_name: Variant in normalized_values:
		var value: float = GFVariantData.to_float(
			normalized_values[property_name],
			-1.0
		)
		if value < 0.0 or value > 1.0:
			_add_error(
				report,
				&"invalid_normalized_value",
				"%s 必须位于 0 到 1 之间。" % GFVariantData.to_text(property_name),
				property_name
			)
	return report


# --- 私有/辅助方法 ---

func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
