## GameRealtimeTimerUtility: 不受玩法暂停与 time scale 影响的 GF 定时策略。
##
## 用于必须按真实时间收敛的短生命周期输入脉冲。通用玩法计时仍应使用遵循
## GFTimeUtility 的 GFTimerUtility 或项目 GameClockUtility。
class_name GameRealtimeTimerUtility
extends GFTimerUtility


# --- Godot 生命周期方法 ---

func _init() -> void:
	ignore_pause = true
	ignore_time_scale = true
