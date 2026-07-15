## GameMoveTurnAction: 将一次有效棋盘移动适配为 GF 回合行动。
class_name GameMoveTurnAction
extends GFTurnAction


# --- 常量 ---

const ACTION_ID: StringName = &"gameplay.move"


# --- 私有变量 ---

var _rule_system: RuleSystem
var _game_flow_system: GameFlowSystem


# --- Godot 生命周期方法 ---

func _init(board_actor: Object = null, move_data: MoveData = null) -> void:
	action_id = ACTION_ID
	actor = board_actor
	payload = move_data


# --- 可重写钩子 ---

func _inject_dependencies(architecture: GFArchitecture) -> void:
	var rule_value: Object = architecture.get_system(RuleSystem)
	if rule_value is RuleSystem:
		_rule_system = rule_value

	var flow_value: Object = architecture.get_system(GameFlowSystem)
	if flow_value is GameFlowSystem:
		_game_flow_system = flow_value


func _resolve(context: GFTurnContext) -> Variant:
	var move_data: MoveData = _get_move_data()
	if not is_instance_valid(move_data):
		push_error("[GameMoveTurnAction] 缺少 MoveData，无法解析回合。")
		return null
	if not is_instance_valid(_rule_system) or not is_instance_valid(_game_flow_system):
		push_error("[GameMoveTurnAction] GF 未注入 RuleSystem 或 GameFlowSystem。")
		return null

	_game_flow_system.apply_move_turn(move_data)
	_rule_system.execute_move_rules(move_data)
	_game_flow_system.settle_move_turn()

	context.metadata[&"last_move_direction"] = move_data.direction
	context.metadata[&"resolved_turn_count"] = (
		GFVariantData.get_option_int(context.metadata, &"resolved_turn_count", 0) + 1
	)
	return null


# --- 私有/辅助方法 ---

func _get_move_data() -> MoveData:
	var payload_value: Variant = payload
	if payload_value is MoveData:
		var move_data: MoveData = payload_value
		return move_data
	return null
