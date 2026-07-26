## GameTileMotionProfile: 主题拥有的核心方块动画节拍与幅度。
##
## 所有时长都以完整表现档为基准；运行时由 GameFeedbackBudget 统一缩放。
class_name GameTileMotionProfile
extends Resource


# --- 导出变量 ---

@export_group("Timing")
@export_range(0.001, 1.0, 0.001) var move_duration: float = 0.10
@export_range(0.001, 1.0, 0.001) var spawn_duration: float = 0.14
@export_range(0.0, 1.0, 0.01) var spawn_fade_ratio: float = 0.75
@export_range(0.001, 1.0, 0.001) var merge_pulse_duration: float = 0.085
@export_range(0.001, 1.0, 0.001) var value_growth_duration: float = 0.13
@export_range(0.001, 1.0, 0.001) var despawn_duration: float = 0.12
@export_range(0.001, 1.0, 0.001) var transform_left_duration: float = 0.04
@export_range(0.001, 1.0, 0.001) var transform_right_duration: float = 0.05
@export_range(0.001, 1.0, 0.001) var transform_settle_duration: float = 0.04
@export_range(0.001, 1.0, 0.001) var transform_home_duration: float = 0.05
@export_range(0.001, 1.0, 0.001) var transform_flash_duration: float = 0.14

@export_group("Amplitude")
@export_range(0.0, 1.0, 0.01) var spawn_start_scale: float = 0.64
@export_range(1.0, 2.0, 0.01) var merge_peak_scale: float = 1.19
@export_range(0.0, 1.0, 0.01) var despawn_end_scale: float = 0.28
@export_range(0.0, 15.0, 0.1) var transform_peak_rotation_degrees: float = 4.0
@export_range(-15.0, 0.0, 0.1) var transform_settle_rotation_degrees: float = -2.0
@export_range(1.0, 2.0, 0.01) var flash_label_peak_scale: float = 1.15


# --- 公共方法 ---

func is_valid_profile() -> bool:
	return (
		move_duration > 0.0
		and spawn_duration > 0.0
		and spawn_fade_ratio >= 0.0
		and spawn_fade_ratio <= 1.0
		and merge_pulse_duration > 0.0
		and value_growth_duration > 0.0
		and despawn_duration > 0.0
		and transform_left_duration > 0.0
		and transform_right_duration > 0.0
		and transform_settle_duration > 0.0
		and transform_home_duration > 0.0
		and transform_flash_duration > 0.0
		and spawn_start_scale >= 0.0
		and spawn_start_scale <= 1.0
		and merge_peak_scale >= 1.0
		and despawn_end_scale >= 0.0
		and despawn_end_scale <= 1.0
		and transform_peak_rotation_degrees >= 0.0
		and transform_settle_rotation_degrees <= 0.0
		and flash_label_peak_scale >= 1.0
	)


## 判断当前反馈预算是否允许方块运动。
## @param budget: 当前无障碍反馈预算快照。
func is_motion_enabled(budget: GameFeedbackBudget) -> bool:
	return budget == null or budget.motion_scale > 0.0


## 按当前反馈预算缩放动画时长。
## @param duration: 完整表现档的基准时长。
## @param budget: 当前无障碍反馈预算快照。
func scale_duration(duration: float, budget: GameFeedbackBudget) -> float:
	if not is_motion_enabled(budget):
		return 0.0
	return duration * _get_duration_scale(budget)


## 在中性值与完整表现值之间按反馈预算插值。
## @param neutral_value: 无运动时使用的中性值。
## @param full_value: 完整表现档使用的值。
## @param budget: 当前无障碍反馈预算快照。
func scale_from_neutral(
	neutral_value: float,
	full_value: float,
	budget: GameFeedbackBudget
) -> float:
	return lerpf(neutral_value, full_value, _get_motion_scale(budget))


## 获取移动动画的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_move_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(move_duration, budget)


## 获取生成动画的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_spawn_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(spawn_duration, budget)


## 获取合并脉冲单段的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_merge_pulse_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(merge_pulse_duration, budget)


## 获取完整合并动画的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_merge_duration(budget: GameFeedbackBudget) -> float:
	return get_merge_pulse_duration(budget) * 2.0


## 获取数值增长动画的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_value_growth_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(value_growth_duration, budget)


## 获取消失动画的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_despawn_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(despawn_duration, budget)


## 获取变换左摆阶段的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_left_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(transform_left_duration, budget)


## 获取变换右摆阶段的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_right_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(transform_right_duration, budget)


## 获取变换回弹阶段的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_settle_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(transform_settle_duration, budget)


## 获取变换归位阶段的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_home_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(transform_home_duration, budget)


## 获取变换闪光阶段的预算化时长。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_flash_duration(budget: GameFeedbackBudget) -> float:
	return scale_duration(transform_flash_duration, budget)


## 获取生成动画的预算化起始缩放。
## @param budget: 当前无障碍反馈预算快照。
func get_spawn_start_scale(budget: GameFeedbackBudget) -> float:
	return scale_from_neutral(1.0, spawn_start_scale, budget)


## 获取合并动画的预算化峰值缩放。
## @param budget: 当前无障碍反馈预算快照。
func get_merge_peak_scale(budget: GameFeedbackBudget) -> float:
	return scale_from_neutral(1.0, merge_peak_scale, budget)


## 获取消失动画的预算化结束缩放。
## @param budget: 当前无障碍反馈预算快照。
func get_despawn_end_scale(budget: GameFeedbackBudget) -> float:
	return scale_from_neutral(1.0, despawn_end_scale, budget)


## 获取变换动画的预算化峰值旋转角。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_peak_rotation_degrees(budget: GameFeedbackBudget) -> float:
	return transform_peak_rotation_degrees * _get_motion_scale(budget)


## 获取变换动画的预算化回弹旋转角。
## @param budget: 当前无障碍反馈预算快照。
func get_transform_settle_rotation_degrees(budget: GameFeedbackBudget) -> float:
	return transform_settle_rotation_degrees * _get_motion_scale(budget)


## 获取闪光标签的预算化峰值缩放。
## @param budget: 当前无障碍反馈预算快照。
func get_flash_label_peak_scale(budget: GameFeedbackBudget) -> float:
	return scale_from_neutral(1.0, flash_label_peak_scale, budget)


## 获取从白色到完整闪光色预算化后的颜色。
## @param full_color: 完整表现档使用的闪光颜色。
## @param budget: 当前无障碍反馈预算快照。
func get_flash_color(full_color: Color, budget: GameFeedbackBudget) -> Color:
	return Color.WHITE.lerp(full_color, _get_motion_scale(budget))


# --- 私有/辅助方法 ---

func _get_motion_scale(budget: GameFeedbackBudget) -> float:
	return maxf(budget.motion_scale, 0.0) if budget != null else 1.0


func _get_duration_scale(budget: GameFeedbackBudget) -> float:
	return maxf(budget.duration_scale, 0.001) if budget != null else 1.0
