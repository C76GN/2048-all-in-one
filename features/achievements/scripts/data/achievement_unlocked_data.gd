## AchievementUnlockedData: 本地真源确认完成后的成就解锁事件。
class_name AchievementUnlockedData
extends RefCounted


# --- 公共变量 ---

var achievement_id: StringName = &""
var completed_at: int = 0


# --- Godot 生命周期方法 ---

func _init(p_achievement_id: StringName = &"", p_completed_at: int = 0) -> void:
	achievement_id = p_achievement_id
	completed_at = p_completed_at


# --- 公共方法 ---

func is_valid() -> bool:
	return achievement_id != &"" and completed_at > 0
