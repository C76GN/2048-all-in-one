## LucasBridgeCapability: 跨一阶斐波那契数合成为卢卡斯数的桥接能力。
class_name LucasBridgeCapability
extends TileInteractionCapability


# --- 私有变量 ---

var _fibonacci_sequence: Array[int] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	_fibonacci_sequence = SequenceMath.generate_fibonacci()


# --- 公共方法 ---

func get_capability_id() -> StringName:
	return &"tile.interaction.lucas_bridge"


func get_interaction_priority() -> int:
	return 100


## 为跨一阶斐波那契数方块生成卢卡斯桥接提案。
## @param source: 发起移动的方块。
## @param target: 移动目标位置上的方块。
func propose_interaction(source: TileState, target: TileState) -> TileInteractionProposal:
	if source == null or target == null or not _shares_active_capability_with(target):
		return null
	var source_index: int = _fibonacci_sequence.find(source.value)
	var target_index: int = _fibonacci_sequence.find(target.value)
	if source_index < 0 or target_index < 0 or absi(source_index - target_index) != 2:
		return null
	var proposal: TileInteractionProposal = _make_proposal(source.value + target.value)
	proposal.score_delta = proposal.result_value
	proposal.feedback_cue_id = &"tile.merge.lucas_bridge"
	return proposal
