## TileLabSimulationResult: 一次试验台方块对交互的无运行时所有权快照。
class_name TileLabSimulationResult
extends RefCounted


# --- 常量 ---

const STATUS_INVALID: StringName = &"invalid"
const STATUS_NO_INTERACTION: StringName = &"no_interaction"
const STATUS_INTERACTED: StringName = &"interacted"


# --- 公共变量 ---

var status: StringName = STATUS_INVALID
var error_code: Error = ERR_INVALID_DATA
var validation_summary: String = ""
var left_before: Dictionary = {}
var right_before: Dictionary = {}
var left_after: Dictionary = {}
var right_after: Dictionary = {}
var interaction_rule_id: StringName = &""
var feedback_cue_id: StringName = &""
var survivor_side: StringName = &""
var result_value: int = 0
var score_delta: int = 0
var ratio_resolution_count: int = 0
var transformed: bool = false


# --- 公共方法 ---

func is_valid_result() -> bool:
	return (
		error_code == OK
		and status in [STATUS_NO_INTERACTION, STATUS_INTERACTED]
		and not left_before.is_empty()
		and not right_before.is_empty()
	)


func did_interact() -> bool:
	return status == STATUS_INTERACTED


func to_dict() -> Dictionary:
	return {
		"status": status,
		"error_code": error_code,
		"validation_summary": validation_summary,
		"left_before": left_before.duplicate(true),
		"right_before": right_before.duplicate(true),
		"left_after": left_after.duplicate(true),
		"right_after": right_after.duplicate(true),
		"interaction_rule_id": interaction_rule_id,
		"feedback_cue_id": feedback_cue_id,
		"survivor_side": survivor_side,
		"result_value": result_value,
		"score_delta": score_delta,
		"ratio_resolution_count": ratio_resolution_count,
		"transformed": transformed,
	}
