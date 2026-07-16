## ClassicMergeCapability: 相同数值翻倍的经典 2048 能力。
class_name ClassicMergeCapability
extends TileInteractionCapability


func get_capability_id() -> StringName:
	return &"tile.interaction.classic_merge"


func get_interaction_priority() -> int:
	return 100


## 为相同数值的经典方块生成翻倍提案。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func propose_interaction(source: TileState, target: TileState) -> TileInteractionProposal:
	if source == null or target == null or not _shares_active_capability_with(target):
		return null
	if source.value != target.value:
		return null
	var proposal: TileInteractionProposal = _make_proposal(source.value * 2)
	proposal.score_delta = proposal.result_value
	proposal.feedback_cue_id = &"tile.merge.classic"
	return proposal
