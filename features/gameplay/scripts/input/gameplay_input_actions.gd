## GameplayInputActions: 玩法输入上下文使用的抽象动作标识。
##
## 物理设备、触控手势和自动化输入都只向这些动作写值，玩法系统统一消费动作，
## 避免输入适配层直接调用命令或游戏规则。
class_name GameplayInputActions
extends RefCounted


# --- 常量 ---

const PAUSE: StringName = &"pause"
const UNDO: StringName = &"undo"
const REDO: StringName = &"redo"
const SAVE_BOOKMARK: StringName = &"save_bookmark"
const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"


# --- 公共方法 ---

## 将棋盘单位方向映射为玩法抽象动作；不支持的方向返回空标识。
## @param direction: 四向棋盘单位方向。
## @return 对应的玩法抽象动作标识。
static func action_for_direction(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP:
			return MOVE_UP
		Vector2i.DOWN:
			return MOVE_DOWN
		Vector2i.LEFT:
			return MOVE_LEFT
		Vector2i.RIGHT:
			return MOVE_RIGHT
		_:
			return &""
