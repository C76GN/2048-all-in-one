## TileInteractionCapability: 可组合方块交互能力的项目协议基类。
class_name TileInteractionCapability
extends GFCapability


# --- 公共方法 ---

func get_capability_id() -> StringName:
	return &""


func get_interaction_priority() -> int:
	return 0


## 为两个方块生成不直接修改状态的交互提案。
## @param _source: 发起移动的方块。
## @param _target: 移动目标位置上的方块。
func propose_interaction(_source: TileState, _target: TileState) -> TileInteractionProposal:
	return null


# --- 私有/辅助方法 ---

func _shares_active_capability_with(target: TileState) -> bool:
	if target == null:
		return false
	var capability_utility_value: Variant = get_utility(GFCapabilityUtility)
	if not capability_utility_value is GFCapabilityUtility:
		return false
	var capability_utility: GFCapabilityUtility = capability_utility_value
	var capability_script: Script = get_script()
	return (
		capability_script != null
		and capability_utility.get_capability_types(target).has(capability_script)
		and capability_utility.is_capability_active(target, capability_script)
	)


func _make_proposal(
	result_value: int,
	survivor_side: TileInteractionProposal.SurvivorSide = TileInteractionProposal.SurvivorSide.TARGET
) -> TileInteractionProposal:
	var proposal: TileInteractionProposal = TileInteractionProposal.new()
	proposal.rule_id = get_capability_id()
	proposal.priority = get_interaction_priority()
	proposal.result_value = result_value
	proposal.survivor_side = survivor_side
	return proposal
