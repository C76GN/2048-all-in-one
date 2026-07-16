## CrossDefinitionRatioCapability: 不同方块定义之间执行整数求商的能力。
class_name CrossDefinitionRatioCapability
extends TileInteractionCapability


func get_capability_id() -> StringName:
	return &"tile.interaction.cross_definition_ratio"


func get_interaction_priority() -> int:
	return 200


## 为不同定义的方块生成整数求商提案；相同定义交由其他能力处理。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func propose_interaction(source: TileState, target: TileState) -> TileInteractionProposal:
	if source == null or target == null or not _shares_active_capability_with(target):
		return null
	if source.definition_id == target.definition_id:
		return null
	var source_survives: bool = source.value > target.value
	var larger_value: int = maxi(source.value, target.value)
	var smaller_value: int = mini(source.value, target.value)
	@warning_ignore("integer_division")
	var result_value: int = larger_value / smaller_value
	var survivor_side: TileInteractionProposal.SurvivorSide = TileInteractionProposal.SurvivorSide.TARGET
	if source_survives:
		survivor_side = TileInteractionProposal.SurvivorSide.SOURCE
	var proposal: TileInteractionProposal = _make_proposal(
		maxi(result_value, 1),
		survivor_side
	)
	proposal.score_delta = proposal.result_value
	proposal.metadata[&"ratio_resolved"] = 1
	proposal.metadata[&"transform"] = true
	proposal.feedback_cue_id = &"tile.ratio.resolve"
	return proposal
