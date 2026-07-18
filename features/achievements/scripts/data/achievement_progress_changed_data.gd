## AchievementProgressChangedData: 已持久化的成就进度变更事件。
class_name AchievementProgressChangedData
extends RefCounted


# --- 公共变量 ---

var achievement_id: StringName = &""
var current_value: int = 0
var target_value: int = 0


# --- Godot 生命周期方法 ---

func _init(
	p_achievement_id: StringName = &"",
	p_current_value: int = 0,
	p_target_value: int = 0
) -> void:
	achievement_id = p_achievement_id
	current_value = p_current_value
	target_value = p_target_value


# --- 公共方法 ---

func is_valid() -> bool:
	return (
		achievement_id != &""
		and target_value > 0
		and current_value >= 0
		and current_value <= target_value
	)
