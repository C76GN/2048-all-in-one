## TileInteractionProposal: 能力对一次方块交互给出的强类型、可仲裁提案。
class_name TileInteractionProposal
extends RefCounted


# --- 枚举 ---

enum SurvivorSide {
	SOURCE,
	TARGET,
}


# --- 公共变量 ---

var rule_id: StringName = &""
var priority: int = 0
var survivor_side: SurvivorSide = SurvivorSide.TARGET
var result_value: int = 0
var score_delta: int = 0
var state_patch: Dictionary = {}
var feedback_cue_id: StringName = &""
var metadata: Dictionary = {}


# --- 公共方法 ---

func is_valid_proposal() -> bool:
	return rule_id != &"" and result_value > 0


## 判断另一个提案是否产生完全相同的状态变更。
## @param other: 待比较的交互提案。
func has_same_effect(other: TileInteractionProposal) -> bool:
	if other == null:
		return false
	return (
		survivor_side == other.survivor_side
		and result_value == other.result_value
		and score_delta == other.score_delta
		and state_patch == other.state_patch
		and metadata == other.metadata
	)


## 将提案投影为移动系统消费的交互结果。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func to_result_dictionary(source: TileState, target: TileState) -> Dictionary:
	var survivor: TileState = source if survivor_side == SurvivorSide.SOURCE else target
	var consumed: TileState = target if survivor_side == SurvivorSide.SOURCE else source
	var result: Dictionary = {
		&"merged_tile": survivor,
		&"consumed_tile": consumed,
		&"interaction_rule_id": rule_id,
		&"feedback_cue_id": feedback_cue_id,
	}
	if score_delta != 0:
		result[&"score"] = score_delta
	for key: Variant in metadata:
		result[key] = metadata[key]
	return result
