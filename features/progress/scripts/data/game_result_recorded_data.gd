## GameResultRecordedData: 统计 SaveGraph 提交成功后的不可变对局结果事件。
##
## GameFlowSystem 已在写入前排除回放与调试污染对局，因此该事件可作为未来
## 成就和排行榜的本地可信输入；平台 Adapter 仍需执行自己的验签与限流。
class_name GameResultRecordedData
extends RefCounted


# --- 公共变量 ---

var mode_id: StringName = &""
var board_key: String = ""
var score: int = 0
var steps: int = 0
var max_tile: int = 0
var played_at: int = 0
var target_value: int = 0
var target_reached: bool = false


# --- Godot 生命周期方法 ---

func _init(
	p_mode_id: StringName = &"",
	p_board_key: String = "",
	p_score: int = 0,
	p_steps: int = 0,
	p_max_tile: int = 0,
	p_played_at: int = 0,
	p_target_value: int = 0,
	p_target_reached: bool = false
) -> void:
	mode_id = p_mode_id
	board_key = p_board_key
	score = p_score
	steps = p_steps
	max_tile = p_max_tile
	played_at = p_played_at
	target_value = p_target_value
	target_reached = p_target_reached


# --- 公共方法 ---

func is_valid() -> bool:
	return (
		mode_id != &""
		and not board_key.is_empty()
		and score >= 0
		and steps >= 0
		and max_tile >= 0
		and played_at > 0
		and target_value >= 0
		and (target_value > 0 or not target_reached)
	)


func to_dict() -> Dictionary:
	return {
		"mode_id": String(mode_id),
		"board_key": board_key,
		"score": score,
		"steps": steps,
		"max_tile": max_tile,
		"played_at": played_at,
		"target_value": target_value,
		"target_reached": target_reached,
	}
