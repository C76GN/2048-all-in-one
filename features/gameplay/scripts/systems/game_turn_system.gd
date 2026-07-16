## GameTurnSystem: 将项目移动事件接入 GF 回合行动生命周期。
class_name GameTurnSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 私有变量 ---

var _turn_flow: GFTurnFlowSystem
var _grid_model: GridModel
var _turn_context: GFTurnContext
var _is_session_active: bool = false
var _is_resolving: bool = false


# --- GF 生命周期方法 ---

func get_required_models() -> Array[Script]:
	return [GridModel]


func get_required_systems() -> Array[Script]:
	return [GFTurnFlowSystem]


func ready() -> void:
	_turn_flow = _get_turn_flow_system()
	_grid_model = _get_grid_model()

	register_event(GameReadyData, GFEventListener.from_method(self, &"_on_game_ready", 1))
	register_event(MoveData, GFEventListener.from_method(self, &"_on_move_made", 1))
	register_simple_event(EventNames.SCENE_WILL_CHANGE, GFEventListener.from_method(self, &"_on_scene_will_change", 1))

	if not is_instance_valid(_turn_flow):
		push_error("[GameTurnSystem] 缺少由 gf.turn_based 装配的 GFTurnFlowSystem。")
	if not is_instance_valid(_grid_model):
		push_error("[GameTurnSystem] 缺少 GridModel，无法建立回合上下文。")


func dispose() -> void:
	_stop_session()
	_turn_context = null
	_turn_flow = null
	_grid_model = null
	_is_resolving = false


# --- 私有/辅助方法 ---

func _start_session(data: GameReadyData) -> void:
	if not is_instance_valid(_turn_flow) or not is_instance_valid(_grid_model):
		return

	_stop_session()
	_turn_context = GFTurnContext.new()
	_turn_context.add_actor(_grid_model)
	_turn_context.metadata = {
		&"feature": &"gameplay",
		&"is_replay_mode": data.is_replay_mode,
		&"resolved_turn_count": 0,
	}
	_turn_flow.set_context(_turn_context)
	_turn_flow.start(true)
	_is_session_active = true


func _stop_session() -> void:
	_is_session_active = false
	if is_instance_valid(_turn_flow):
		_turn_flow.stop(true)
	if _turn_context != null:
		_turn_context.metadata.clear()


func _drain_pending_actions() -> void:
	if _is_resolving or not _is_session_active or not is_instance_valid(_turn_flow):
		return

	_is_resolving = true
	while _is_session_active and _turn_flow.get_action_count() > 0:
		await _turn_flow.resolve_actions()
	_is_resolving = false


func _get_turn_flow_system() -> GFTurnFlowSystem:
	var system_value: Object = get_system(GFTurnFlowSystem)
	if system_value is GFTurnFlowSystem:
		var turn_flow: GFTurnFlowSystem = system_value
		return turn_flow
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


# --- 信号处理函数 ---

func _on_game_ready(data: GameReadyData) -> void:
	if is_instance_valid(data):
		_start_session(data)


func _on_move_made(move_data: MoveData) -> void:
	if not _is_session_active or not is_instance_valid(move_data):
		return

	_turn_flow.enqueue_action(GameMoveTurnAction.new(_grid_model, move_data))
	await _drain_pending_actions()


func _on_scene_will_change(_payload: Variant = null) -> void:
	_stop_session()
