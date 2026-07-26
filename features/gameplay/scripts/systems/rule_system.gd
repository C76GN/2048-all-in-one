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

func get_required_models() -> Array[Script]:
	return [GridModel]


func get_required_utilities() -> Array[Script]:
	return [GFSeedUtility]


func ready() -> void:
	_grid_model = _get_grid_model()
	_seed_utility = _get_seed_utility()

	register_simple_event(EventNames.REQUEST_BOARD_INITIALIZATION, GFEventListener.from_method(self, &"_on_request_board_init", 1))
	register_simple_event(EventNames.RATIO_RESOLVED, GFEventListener.from_method(self, &"_on_ratio_resolved", 1))


func dispose() -> void:
	clear_rules()
	_grid_model = null
	_seed_utility = null


# --- 公共方法 ---

## 注册一个规则列表到管理器中。
## @param p_rules: 包含所有 SpawnRule 实例的数组。
## @return: 规则状态身份完整且唯一时返回 true；失败时保留原规则。
func register_rules(p_rules: Array[SpawnRule]) -> bool:
	if not are_rules_state_compatible(p_rules):
		push_error("[RuleSystem] 拒绝注册缺少稳定状态 ID、schema 无效或 ID 重复的规则列表。")
		return false

	var next_rules: Array[SpawnRule] = p_rules.duplicate()
	clear_rules()
	_rules = next_rules

	for rule: SpawnRule in _rules:
		rule.setup()
	return true


## 获取所有的生成规则，用于序列化。
func get_all_spawn_rules() -> Array[SpawnRule]:
	return _rules


## 按稳定 rule_state_id 捕获规则状态，数组重排不会改变恢复语义。
static func capture_rule_states(rules: Array[SpawnRule]) -> Dictionary:
	if not are_rules_state_compatible(rules):
		return {}
	var result: Dictionary = {}
	for rule: SpawnRule in rules:
		var state_id: String = String(rule.rule_state_id)
		result[state_id] = {
			&"rule_state_id": rule.rule_state_id,
			&"schema_version": rule.rule_state_schema_version,
			&"state": GFVariantData.duplicate_variant(rule.get_state(), true, false),
		}
	return result


## 校验规则状态字典是否与目标规则集合完全一致。
static func are_rule_states_valid(
	rules_states: Dictionary,
	rules: Array[SpawnRule]
) -> bool:
	if not are_rules_state_compatible(rules) or rules_states.size() != rules.size():
		return false

	for state_key: Variant in rules_states.keys():
		if not state_key is String:
			return false

	for rule: SpawnRule in rules:
		var state_id: String = String(rule.rule_state_id)
		if not rules_states.has(state_id):
			return false
		var entry_value: Variant = rules_states[state_id]
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		if not (
			entry.size() == 3
			and GFVariantData.get_option_value(entry, &"rule_state_id") is StringName
			and GFVariantData.get_option_value(entry, &"schema_version") is int
			and entry.has(&"state")
		):
			return false
		if (
			GFVariantData.get_option_string_name(entry, &"rule_state_id")
			!= rule.rule_state_id
			or GFVariantData.get_option_int(entry, &"schema_version", 0)
			!= rule.rule_state_schema_version
			or not rule.is_state_valid(entry[&"state"])
		):
			return false
	return true


## 原子应用一组已经按稳定 ID 键控的规则状态。
static func restore_rule_states(
	rules_states: Dictionary,
	rules: Array[SpawnRule]
) -> bool:
	if not are_rule_states_valid(rules_states, rules):
		return false

	var previous_states: Dictionary = capture_rule_states(rules)
	for rule: SpawnRule in rules:
		var state_id: String = String(rule.rule_state_id)
		var entry: Dictionary = rules_states[state_id]
		if rule.set_state(GFVariantData.duplicate_variant(entry[&"state"], true, false)):
			continue

		for rollback_rule: SpawnRule in rules:
			var rollback_id: String = String(rollback_rule.rule_state_id)
			var rollback_entry: Dictionary = previous_states[rollback_id]
			var _rolled_back: bool = rollback_rule.set_state(
				GFVariantData.duplicate_variant(rollback_entry[&"state"], true, false)
			)
		return false
	return true


## 判断规则集合是否具备稳定且唯一的状态身份。
static func are_rules_state_compatible(rules: Array[SpawnRule]) -> bool:
	var seen_ids: Dictionary = {}
	for rule: SpawnRule in rules:
		if (
			not is_instance_valid(rule)
			or rule.rule_state_id == &""
			or rule.rule_state_schema_version <= 0
			or seen_ids.has(rule.rule_state_id)
		):
			return false
		seen_ids[rule.rule_state_id] = true
	return true


## 清除所有规则。
func clear_rules() -> void:
	for rule: SpawnRule in _rules:
		rule.teardown()
	_rules.clear()


## 执行一次移动回合对应的生成规则。
## @param turn_result: 已完成的有效棋盘移动结果。
func execute_move_rules(turn_result: TurnResult) -> void:
	if not is_instance_valid(turn_result):
		return
	_execute_rules(SpawnRule.TriggerType.ON_MOVE, turn_result)


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


func _execute_rules(
	trigger_type: SpawnRule.TriggerType,
	turn_result: TurnResult = null
) -> void:
	var context: RuleContext = RuleContext.new()
	context.grid_model = _grid_model
	context.turn_result = turn_result
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
		if spawn_data is SpawnData:
			spawn_data.turn_result = context.turn_result
		send_simple_event(EventNames.SPAWN_TILE_REQUESTED, spawn_data)

	if context.score_delta != 0:
		send_simple_event(EventNames.SCORE_UPDATED, context.score_delta)

	if context.ratio_resolutions > 0:
		send_simple_event(EventNames.RATIO_RESOLVED, context.ratio_resolutions)

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


func _on_ratio_resolved(_payload: Variant = null) -> void:
	_execute_rules(SpawnRule.TriggerType.ON_RATIO_RESOLVED)
