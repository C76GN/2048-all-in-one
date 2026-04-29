## RuleSystem: 游戏规则的事件总线和调度器。
##
## 接收核心游戏事件，并按触发器与优先级执行注册的生成规则。规则只描述业务结果，
## 事件派发由本系统统一完成，避免规则资源直接依赖全局架构。
class_name RuleSystem
extends GFSystem


# --- 私有变量 ---

var _grid_model: GridModel
var _seed_utility: GFSeedUtility

## 存储所有已注册的生成规则实例。
var _rules: Array[SpawnRule] = []


# --- Godot 生命周期方法 ---

func ready() -> void:
	_grid_model = get_model(GridModel) as GridModel
	_seed_utility = get_utility(GFSeedUtility) as GFSeedUtility

	register_event(MoveData, _on_move_made)
	register_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION, _on_request_board_init)
	register_simple_event(EventNames.MONSTER_KILLED, _on_monster_killed)


func dispose() -> void:
	unregister_event(MoveData, _on_move_made)
	unregister_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION, _on_request_board_init)
	unregister_simple_event(EventNames.MONSTER_KILLED, _on_monster_killed)

	clear_rules()
	_grid_model = null
	_seed_utility = null


# --- 公共方法 ---

## 注册一个规则列表到管理器中。
## @param p_rules: 包含所有 SpawnRule 实例的数组。
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

func _execute_rules(trigger_type: SpawnRule.TriggerType, move_data: MoveData = null) -> void:
	var context := RuleContext.new()
	context.grid_model = _grid_model
	context.move_data = move_data
	context.seed_utility = _seed_utility

	var active_rules: Array[SpawnRule] = []
	for rule in _rules:
		if _should_execute_rule(rule, trigger_type):
			active_rules.append(rule)
	active_rules.sort_custom(func(a: SpawnRule, b: SpawnRule) -> bool: return a.priority > b.priority)

	for rule in active_rules:
		var is_consumed: bool = rule.execute(context)
		_dispatch_context_outputs(context)
		if is_consumed:
			break


func _dispatch_context_outputs(context: RuleContext) -> void:
	for spawn_data in context.spawn_requests:
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


func _on_move_made(move_data: MoveData) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_MOVE, move_data)
	send_simple_event(EventNames.TURN_FINISHED)


func _on_monster_killed(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_KILL)
