# scripts/systems/rule_system.gd

## RuleSystem: 游戏规则的智能事件总线和调度器。
##
## 该节点负责接收游戏中的核心事件（如玩家移动），并根据已注册规则的
## 触发器（Trigger）和优先级（Priority），按正确的顺序执行它们。
## 它还支持"事件消费"机制，允许高优先级的规则阻止低优先级规则的执行。
class_name RuleSystem
extends GFSystem


# --- 属性 ---
var _grid_model: GridModel


# --- 私有变量 ---

## 存储所有已注册的规则实例。
var _rules: Array[SpawnRule] = []


# --- 重写方法 ---

func init() -> void:
	_grid_model = get_model(GridModel) as GridModel


func ready() -> void:
	Gf.listen(MoveData, _on_move_made)
	Gf.listen_simple(EventNames.REQUEST_BOARD_INITIALIZATION, _on_request_board_init)
	Gf.listen_simple(EventNames.MONSTER_KILLED, _on_monster_killed)


func dispose() -> void:
	Gf.unlisten(MoveData, _on_move_made)
	Gf.unlisten_simple(EventNames.REQUEST_BOARD_INITIALIZATION, _on_request_board_init)
	Gf.unlisten_simple(EventNames.MONSTER_KILLED, _on_monster_killed)


# --- 公共方法 ---

## 注册一个规则列表到管理器中。
## @param p_rules: 一个包含所有 SpawnRule 实例的数组。
func register_rules(p_rules: Array[SpawnRule]) -> void:
	_rules = p_rules

	for rule in _rules:
		rule.setup() # 执行内部状态初始化


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
	# 对概率移动规则的特殊处理（目前合并在 _execute_rules 逻辑中）
	
	Gf.send_simple_event(EventNames.TURN_FINISHED)


func _on_monster_killed(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_KILL)


func _execute_rules(trigger_type: SpawnRule.TriggerType, move_data: MoveData = null) -> void:
	var context := RuleContext.new()
	context.grid_model = _grid_model
	context.move_data = move_data
	
	# 按优先级降序排序执行
	var active_rules := _rules.filter(func(r: SpawnRule): return r.trigger == trigger_type or (trigger_type == SpawnRule.TriggerType.ON_MOVE and r.trigger == SpawnRule.TriggerType.ON_MOVE_PROBABILITY))
	active_rules.sort_custom(func(a, b): return a.priority > b.priority)
	
	for rule in active_rules:
		var is_consumed: bool = rule.execute(context)
		if is_consumed:
			break
