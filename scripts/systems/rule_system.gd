# scripts/systems/rule_system.gd

## RuleSystem: 游戏规则的智能事件总线和调度器。
##
## 该节点负责接收游戏中的核心事件（如玩家移动），并根据已注册规则的
## 触发器（Trigger）和优先级（Priority），按正确的顺序执行它们。
## 它还支持"事件消费"机制，允许高优先级的规则阻止低优先级规则的执行。
class_name RuleSystem
extends GFSystem


# --- 私有变量 ---

var _grid_model: GridModel

## 存储所有已注册的规则实例。
var _rules: Array[SpawnRule] = []


# --- Godot 生命周期方法 ---

func ready() -> void:
	_grid_model = get_model(GridModel) as GridModel
	register_event(MoveData, _on_move_made)
	register_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION, _on_request_board_init)
	register_simple_event(EventNames.MONSTER_KILLED, _on_monster_killed)


func dispose() -> void:
	unregister_event(MoveData, _on_move_made)
	unregister_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION, _on_request_board_init)
	unregister_simple_event(EventNames.MONSTER_KILLED, _on_monster_killed)
	clear_rules()


# --- 公共方法 ---

## 注册一个规则列表到管理器中。
## @param p_rules: 一个包含所有 SpawnRule 实例的数组。
func register_rules(p_rules: Array[SpawnRule]) -> void:
	var next_rules := p_rules.duplicate()
	clear_rules()
	_rules = next_rules

	for rule in _rules:
		rule.setup()


## 获取所有的生成规则，用于序列化。
func get_all_spawn_rules() -> Array[SpawnRule]:
	return _rules


## 清除所有规则。
func clear_rules() -> void:
	for rule in _rules:
		rule.teardown()
	_rules.clear()


# --- 私有/辅助方法 ---

func _on_request_board_init(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_INITIALIZE)


func _on_move_made(move_data: MoveData) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_MOVE, move_data)
	
	send_simple_event(EventNames.TURN_FINISHED)


func _on_monster_killed(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_KILL)


func _execute_rules(trigger_type: SpawnRule.TriggerType, move_data: MoveData = null) -> void:
	var context := RuleContext.new()
	context.grid_model = _grid_model
	context.move_data = move_data
	
	# 按优先级降序排序执行
	var active_rules: Array[SpawnRule] = []
	for rule in _rules:
		if _should_execute_rule(rule, trigger_type):
			active_rules.append(rule)
	active_rules.sort_custom(func(a, b): return a.priority > b.priority)
	
	for rule in active_rules:
		var is_consumed: bool = rule.execute(context)
		if is_consumed:
			break


func _should_execute_rule(rule: SpawnRule, trigger_type: SpawnRule.TriggerType) -> bool:
	if rule.trigger == trigger_type:
		return true

	return (
		trigger_type == SpawnRule.TriggerType.ON_MOVE
		and rule.trigger == SpawnRule.TriggerType.ON_MOVE_PROBABILITY
	)
