# scripts/core/rule_manager.gd

## RuleManager: 游戏规则的智能事件总线和调度器。
##
## 该节点负责接收游戏中的核心事件（如玩家移动），并根据已注册规则的
## 触发器（Trigger）和优先级（Priority），按正确的顺序执行它们。
## 它还支持“事件消费”机制，允许高优先级的规则阻止低优先级规则的执行。
class_name RuleManager
extends Node


# --- 信号 ---

## 当任何规则请求生成方块时，将此信号转发给 GamePlay。
## @param spawn_data: 包含生成方块所需信息的字典。
signal spawn_tile_requested(spawn_data: Dictionary)


# --- 枚举 ---

## 定义了可以触发规则执行的核心游戏事件。
enum Events {
	## 棋盘初始化事件
	INITIALIZE_BOARD,
	## 玩家成功移动后
	PLAYER_MOVED,
	## 怪物被消灭后
	MONSTER_KILLED,
}


# --- 私有变量 ---

## 存储所有已注册的规则实例。
var _rules: Array[SpawnRule] = []


# --- 公共方法 ---

## 注册一个规则列表到管理器中。
## @param p_rules: 一个包含所有 SpawnRule 实例的数组。
func register_rules(p_rules: Array[SpawnRule]) -> void:
	_rules = p_rules

	for rule in _rules:
		var current_rule: SpawnRule = rule
		if not current_rule.spawn_tile_requested.is_connected(self.spawn_tile_requested.emit):
			current_rule.spawn_tile_requested.connect(self.spawn_tile_requested.emit)


## 分发一个游戏事件，触发相应规则。
## @param event: 要分发的 Events 枚举成员。
## @param payload: 一个可选的字典，用于向规则传递附加上下文数据。
func dispatch_event(event: Events, payload: Dictionary = {}) -> void:
	var relevant_rules: Array[SpawnRule] = _get_relevant_rules(event)

	if relevant_rules.is_empty():
		return

	relevant_rules.sort_custom(func(a: SpawnRule, b: SpawnRule) -> bool: return a.priority > b.priority)

	for rule in relevant_rules:
		var current_rule: SpawnRule = rule
		var was_consumed: bool = current_rule.execute(payload)

		if was_consumed:
			break


# --- 私有/辅助方法 ---

## 根据事件类型筛选出所有监听该事件的规则。
## @param event: 要筛选的 Events 枚举成员。
## @return: 一个包含所有匹配规则实例的数组。
func _get_relevant_rules(event: Events) -> Array[SpawnRule]:
	var matched_rules: Array[SpawnRule] = []

	for rule in _rules:
		var current_rule: SpawnRule = rule

		match event:
			Events.INITIALIZE_BOARD:
				if current_rule.trigger == SpawnRule.TriggerType.ON_INITIALIZE:
					matched_rules.append(current_rule)
			Events.PLAYER_MOVED:
				if current_rule.trigger in [SpawnRule.TriggerType.ON_MOVE, SpawnRule.TriggerType.ON_MOVE_PROBABILITY]:
					matched_rules.append(current_rule)
			Events.MONSTER_KILLED:
				if current_rule.trigger == SpawnRule.TriggerType.ON_KILL:
					matched_rules.append(current_rule)

	return matched_rules
