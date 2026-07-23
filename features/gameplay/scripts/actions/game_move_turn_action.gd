## GameMoveTurnAction: 将一次有效棋盘移动适配为 GF 回合行动。
class_name GameMoveTurnAction
extends GFTurnAction


# --- 常量 ---

const ACTION_ID: StringName = &"gameplay.move"


# --- 私有变量 ---

var _rule_system: RuleSystem
var _game_flow_system: GameFlowSystem


# --- Godot 生命周期方法 ---

func _init(board_actor: Object = null, turn_result: TurnResult = null) -> void:
	action_id = ACTION_ID
	actor = board_actor
	payload = turn_result


# --- 可重写钩子 ---

func _inject_dependencies(architecture: GFArchitecture) -> void:
	var rule_value: Object = architecture.get_system(RuleSystem)
	if rule_value is RuleSystem:
		_rule_system = rule_value

	var flow_value: Object = architecture.get_system(GameFlowSystem)
	if flow_value is GameFlowSystem:
		_game_flow_system = flow_value


func _resolve(context: GFTurnContext) -> Variant:
	var turn_result: TurnResult = _get_turn_result()
	if not is_instance_valid(turn_result):
		push_error("[GameMoveTurnAction] 缺少 TurnResult，无法解析回合。")
		return null
	if not is_instance_valid(_rule_system) or not is_instance_valid(_game_flow_system):
		push_error("[GameMoveTurnAction] GF 未注入 RuleSystem 或 GameFlowSystem。")
		return null

	_game_flow_system.apply_move_turn(turn_result)
	_rule_system.execute_move_rules(turn_result)
	_game_flow_system.finalize_turn_result(turn_result)
	_game_flow_system.settle_move_turn()

	context.metadata[&"last_move_direction"] = turn_result.direction
	context.metadata[&"resolved_turn_count"] = (
		GFVariantData.get_option_int(context.metadata, &"resolved_turn_count", 0) + 1
	)
	return null


# --- 私有/辅助方法 ---

func _get_turn_result() -> TurnResult:
	var payload_value: Variant = payload
	if payload_value is TurnResult:
		return payload_value
	return null
