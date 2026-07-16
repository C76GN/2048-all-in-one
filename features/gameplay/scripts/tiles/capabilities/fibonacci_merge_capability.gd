## FibonacciMergeCapability: 相邻斐波那契数相加的方块能力。
class_name FibonacciMergeCapability
extends TileInteractionCapability


func get_capability_id() -> StringName:
	return &"tile.interaction.fibonacci_merge"


func get_interaction_priority() -> int:
	return 100


## 为相邻斐波那契数方块生成求和提案。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func propose_interaction(source: TileState, target: TileState) -> TileInteractionProposal:
	if source == null or target == null or not _shares_active_capability_with(target):
		return null
	if not SequenceMath.are_consecutive_fibonacci(source.value, target.value):
		return null
	var proposal: TileInteractionProposal = _make_proposal(source.value + target.value)
	proposal.score_delta = proposal.result_value
	proposal.feedback_cue_id = &"tile.merge.fibonacci"
	return proposal
