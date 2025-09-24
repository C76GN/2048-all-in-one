# scripts/core/rule_manager.gd

## RuleManager: 游戏规则的智能事件总线和调度器。
##
## 该节点负责接收游戏中的核心事件（如玩家移动），并根据已注册规则的
## 触发器（Trigger）和优先级（Priority），按正确的顺序执行它们。
## 它还支持“事件消费”机制，允许高优先级的规则阻止低优先级规则的执行。
class_name RuleManager
extends Node

# --- 信号定义 ---

## 当任何规则请求生成方块时，将此信号转发给 GamePlay。
signal spawn_tile_requested(spawn_data: Dictionary)

# --- 枚举定义 ---

## 定义了可以触发规则执行的核心游戏事件。
enum Events {
	INITIALIZE_BOARD, # 棋盘初始化事件
	PLAYER_MOVED,     # 玩家成功移动后
	MONSTER_KILLED    # 怪物被消灭后
}

# --- 内部状态 ---

# 存储所有已注册的规则实例。
var _rules: Array[SpawnRule] = []

# --- 公共接口 ---

## 注册一个规则列表到管理器中。
func register_rules(p_rules: Array[SpawnRule]) -> void:
	_rules = p_rules
	for rule in _rules:
		# 将所有规则的 spawn_tile_requested 信号连接到管理器的转发信号上。
		if not rule.spawn_tile_requested.is_connected(self.spawn_tile_requested.emit):
			rule.spawn_tile_requested.connect(self.spawn_tile_requested.emit)

## 分发一个游戏事件，触发相应规则。
func dispatch_event(event: Events, payload: Dictionary = {}) -> void:
	# 1. 根据事件类型，筛选出所有相关的规则。
	var relevant_rules = _get_relevant_rules(event)
	if relevant_rules.is_empty():
		return
	
	# 2. 根据优先级对规则进行降序排序（高优先级在前）。
	relevant_rules.sort_custom(func(a, b): return a.priority > b.priority)
	
	# 3. 按顺序执行规则，并检查事件是否被“消费”。
	for rule in relevant_rules:
		var was_consumed = rule.execute(payload)
		if was_consumed:
			break # 事件已被消费，停止处理链。

# --- 内部辅助函数 ---

## 根据事件类型筛选出所有监听该事件的规则。
func _get_relevant_rules(event: Events) -> Array[SpawnRule]:
	var matched_rules: Array[SpawnRule] = []
	for rule in _rules:
		match event:
			Events.INITIALIZE_BOARD:
				if rule.trigger == SpawnRule.TriggerType.ON_INITIALIZE:
					matched_rules.append(rule)
			Events.PLAYER_MOVED:
				if rule.trigger in [SpawnRule.TriggerType.ON_MOVE, SpawnRule.TriggerType.ON_MOVE_PROBABILITY]:
					matched_rules.append(rule)
			Events.MONSTER_KILLED:
				if rule.trigger == SpawnRule.TriggerType.ON_KILL:
					matched_rules.append(rule)
	return matched_rules
