## LucasMergeCapability: 相邻卢卡斯数相加的方块能力。
class_name LucasMergeCapability
extends TileInteractionCapability


# --- 私有变量 ---

var _lucas_sequence: Array[int] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	_lucas_sequence = SequenceMath.generate_lucas()


# --- 公共方法 ---

func get_capability_id() -> StringName:
	return &"tile.interaction.lucas_merge"


func get_interaction_priority() -> int:
	return 100


## 为相邻卢卡斯数方块生成求和提案。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func propose_interaction(source: TileState, target: TileState) -> TileInteractionProposal:
	if source == null or target == null or not _shares_active_capability_with(target):
		return null
	if not SequenceMath.are_consecutive_lucas(source.value, target.value, _lucas_sequence):
		return null
	var proposal: TileInteractionProposal = _make_proposal(source.value + target.value)
	proposal.score_delta = proposal.result_value
	proposal.feedback_cue_id = &"tile.merge.lucas"
	return proposal
