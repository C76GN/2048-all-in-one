## TileInteractionResult: 一次方块规则交互的强类型业务结果。
class_name TileInteractionResult
extends RefCounted


# --- 公共变量 ---

var survivor: TileState
var consumed: TileState
var interaction_rule_id: StringName = &""
var feedback_cue_id: StringName = &""
var score_delta: int = 0
var ratio_resolution_count: int = 0
var transformed: bool = false
var metadata: Dictionary = {}


# --- 公共方法 ---

func is_valid_result() -> bool:
	return (
		is_instance_valid(survivor)
		and is_instance_valid(consumed)
		and survivor != consumed
		and interaction_rule_id != &""
	)
