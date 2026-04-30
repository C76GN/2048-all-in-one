## ReplayContinueData: 从回放恢复为普通对局时传递的事件数据。
class_name ReplayContinueData
extends GFPayload


# --- 公共变量 ---

## 当前正在恢复的回放资源。
var replay_data: ReplayData = null

## 恢复时所在的回放步数。
var current_step: int = 0

## 回放总步数。
var total_steps: int = 0

## 当前步数之前已确认执行的操作序列。
var actions: Array[Vector2i] = []


# --- Godot 生命周期方法 ---

func _init(
	p_replay_data: ReplayData = null,
	p_current_step: int = 0,
	p_total_steps: int = 0,
	p_actions: Array[Vector2i] = []
) -> void:
	replay_data = p_replay_data
	current_step = p_current_step
	total_steps = p_total_steps
	actions = p_actions.duplicate()
