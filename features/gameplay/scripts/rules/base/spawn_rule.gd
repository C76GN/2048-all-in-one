## SpawnRule: 方块生成规则的基类蓝图（基于Resource）。
##
## 所有具体的生成逻辑都应继承此类。它被设计为一个资源，
## 允许在编辑器中直接配置其行为，如触发器和优先级。
class_name SpawnRule
extends Resource


# --- 枚举 ---

## 定义了可以触发此规则执行的事件类型。
enum TriggerType {
	## 游戏开始时，用于初始化棋盘
	ON_INITIALIZE,
	## 玩家每次有效移动后
	ON_MOVE,
	## 玩家每次有效移动后，按概率触发
	ON_MOVE_PROBABILITY,
	## 由外部计时器触发
	ON_TIMER,
	## 当一个怪物被消灭时
	ON_KILL,
}


# --- 导出变量 ---

## 规则的触发条件。
@export var trigger: TriggerType = TriggerType.ON_MOVE

## 规则的执行优先级（数字越大，优先级越高）。
@export var priority: int = 0


# --- 公共方法 ---

## 在规则开始前进行必要的内部初始化（非事件绑定）。
func setup() -> void:
	pass


## RuleSystem调用此函数来执行规则的核心逻辑。
##
## @param _context: 包含游戏上下文的强类型数据对象，必须包含有效的 grid_model。
## @return: 返回 'true' 表示事件被"消费"，应中断处理链。否则返回 'false'。
func execute(_context: RuleContext) -> bool:
	# 子类重写此方法以实现具体逻辑。
	# 注意：在 GF 事件系统中，如果 event_instance 有 is_consumed 属性，
	# 并在回调中设为 true，GF 也会停止后续回调。
	# 但由于这里的 Execute 是由上面的包装函数调用的，
	# 且 SpawnRule 本身作为 Resource 并不是事件载体，
	# 所以我们通过返回 bool 来控制 RuleSystem 的内部逻辑（如果还需要它的话）。
	return false


## 在规则结束时执行清理。
func teardown() -> void:
	pass


## 获取用于在HUD上显示的动态统计数据。
##
## @param _context: 上下文数据，包含 grid_model。
## @param _stats: 要写入显示数据的 Dictionary 对象。
func get_hud_stats(_context: RuleContext, _stats: Dictionary) -> void:
	pass


## 获取规则当前的内部状态，用于保存。
##
## @return: 一个包含规则状态的可序列化变量 (如字典或基础类型)。
func get_state() -> Variant:
	return null


## 从一个状态值恢复规则的内部状态。
##
## @param _state: 从历史记录中加载的状态值。
func set_state(_state: Variant) -> void:
	pass
