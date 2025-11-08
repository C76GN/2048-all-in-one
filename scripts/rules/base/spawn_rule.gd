# scripts/spawn_rule.gd

## SpawnRule: 方块生成规则的基类蓝图（基于Resource）。
##
## 所有具体的生成逻辑都应继承此类。现在它是一个资源，
## 允许在编辑器中直接配置其行为，如触发器和优先级。
class_name SpawnRule
extends Resource

# --- 信号定义 ---

## 当此规则决定要生成一个新方块时发出。
@warning_ignore("unused_signal")
signal spawn_tile_requested(spawn_data: Dictionary)

# --- 枚举定义 ---

## 定义了可以触发此规则执行的事件类型。
enum TriggerType {
	ON_INITIALIZE,       # 游戏开始时，用于初始化棋盘
	ON_MOVE,             # 玩家每次有效移动后
	ON_MOVE_PROBABILITY, # 玩家每次有效移动后，按概率触发
	ON_TIMER,            # 由外部计时器触发
	ON_KILL              # 当一个怪物被消灭时
}

# --- 可配置属性 ---

## 规则的触发条件。
@export var trigger: TriggerType = TriggerType.ON_MOVE
## 规则的执行优先级（数字越大，优先级越高）。
@export var priority: int = 0

# --- 内部状态 ---

# 对GameBoard的引用，由GamePlay在运行时注入。
var game_board: Control

# --- 虚函数 (需要子类实现) ---

## 在游戏开始时被调用，用于设置此规则所需的依赖（如GameBoard）。
## 子类可以重写此方法来接收额外的节点（如Timer）。
func setup(p_game_board: Control, _required_nodes: Dictionary = {}) -> void:
	self.game_board = p_game_board

## RuleManager调用此函数来执行规则的核心逻辑。
## @param _payload: 一个字典，可能包含来自事件的额外数据。
## @return: 返回 'true' 表示事件被“消费”，应中断处理链。否则返回 'false'。
func execute(_payload: Dictionary = {}) -> bool:
	return false

## 允许规则声明它需要哪些额外的Node节点（如Timer）。
## @return: 返回一个字典，键是节点标识，值是节点类型（如"Timer"）。
func get_required_nodes() -> Dictionary:
	return {}

## 在游戏结束时被调用，用于清理（如停止计时器）。
func teardown() -> void:
	pass

## 获取用于在HUD上显示的动态数据。
## 子类可以重写此方法，返回一个字典，供HUD展示。
## 例如: {"timer_label": "怪物将在: 5.2s 后出现"}
func get_display_data() -> Dictionary:
	return {}

## 获取规则当前的内部状态，用于保存。
## @return: 一个包含规则状态的可序列化变量 (如字典或基础类型)。
func get_state() -> Variant:
	return null # 默认无状态

## 从一个状态值恢复规则的内部状态。
## @param state: 从历史记录中加载的状态值。
func set_state(_state: Variant) -> void:
	pass # 默认无状态，无需恢复
