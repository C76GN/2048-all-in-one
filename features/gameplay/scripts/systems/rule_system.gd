## RuleSystem: 游戏规则的事件总线和调度器。
##
## 接收核心游戏事件，并按触发器与优先级执行注册的生成规则。规则只描述业务结果，
## 事件派发由本系统统一完成，避免规则资源直接依赖全局架构。
class_name RuleSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 私有变量 ---

var _grid_model: GridModel
var _seed_utility: GFSeedUtility

## 存储所有已注册的生成规则实例。
var _rules: Array[SpawnRule] = []


# --- Godot 生命周期方法 ---

func ready() -> void:
	_grid_model = _get_grid_model()
	_seed_utility = _get_seed_utility()

	register_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION, GFEventListener.from_method(self, &"_on_request_board_init", 1))
	register_simple_event(EventNames.MONSTER_KILLED, GFEventListener.from_method(self, &"_on_monster_killed", 1))


func dispose() -> void:
	clear_rules()
	_grid_model = null
	_seed_utility = null


# --- 公共方法 ---

## 注册一个规则列表到管理器中。
## @param p_rules: 包含所有 SpawnRule 实例的数组。
func register_rules(p_rules: Array[SpawnRule]) -> void:
	var next_rules: Array[SpawnRule] = p_rules.duplicate()
	clear_rules()
	_rules = next_rules

	for rule: SpawnRule in _rules:
		rule.setup()


## 获取所有的生成规则，用于序列化。
func get_all_spawn_rules() -> Array[SpawnRule]:
	return _rules


## 清除所有规则。
func clear_rules() -> void:
	for rule: SpawnRule in _rules:
		rule.teardown()
	_rules.clear()


## 执行一次移动回合对应的生成规则。
## @param move_data: 已完成的有效棋盘移动。
func execute_move_rules(move_data: MoveData) -> void:
	if not is_instance_valid(move_data):
		return
	_execute_rules(SpawnRule.TriggerType.ON_MOVE, move_data)


# --- 私有/辅助方法 ---

func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null


func _execute_rules(trigger_type: SpawnRule.TriggerType, move_data: MoveData = null) -> void:
	var context: RuleContext = RuleContext.new()
	context.grid_model = _grid_model
	context.move_data = move_data
	context.seed_utility = _seed_utility

	var active_rules: Array[SpawnRule] = []
	for rule: SpawnRule in _rules:
		if _should_execute_rule(rule, trigger_type):
			active_rules.append(rule)
	active_rules.sort_custom(func(a: SpawnRule, b: SpawnRule) -> bool: return a.priority > b.priority)

	for rule: SpawnRule in active_rules:
		var is_consumed: bool = rule.execute(context)
		_dispatch_context_outputs(context)
		if is_consumed:
			break


func _dispatch_context_outputs(context: RuleContext) -> void:
	for spawn_data: Variant in context.spawn_requests:
		send_simple_event(EventNames.SPAWN_TILE_REQUESTED, spawn_data)

	if context.score_delta != 0:
		send_simple_event(EventNames.SCORE_UPDATED, context.score_delta)

	if context.monsters_killed > 0:
		send_simple_event(EventNames.MONSTER_KILLED, context.monsters_killed)

	context.clear_runtime_outputs()


func _should_execute_rule(rule: SpawnRule, trigger_type: SpawnRule.TriggerType) -> bool:
	if rule.trigger == trigger_type:
		return true

	return (
		trigger_type == SpawnRule.TriggerType.ON_MOVE
		and rule.trigger == SpawnRule.TriggerType.ON_MOVE_PROBABILITY
	)


# --- 信号处理函数 ---

func _on_request_board_init(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_INITIALIZE)


func _on_monster_killed(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_KILL)
