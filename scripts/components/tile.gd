# scripts/components/tile.gd

## Tile: 定义了棋盘上单个方块的行为、外观和动画。
##
## 每个方块节点都挂载此脚本。它负责管理自身的数值、类型（玩家或怪物），
## 并根据这些属性更新背景颜色、文本内容和字体大小。
## 同时，它也封装了所有与自身相关的动画，如生成、移动、合并等。
class_name Tile
extends Node2D


# --- 枚举 ---

## 定义了方块的两种基本类型，用于区分游戏逻辑和视觉表现。
enum TileType {
	## 玩家控制的方块
	PLAYER,
	## 游戏生成的障碍或敌对方块
	MONSTER,
}


# --- 常量 ---

## 方块内文本的水平内边距，用于动态字体大小计算。
const HORIZONTAL_PADDING: float = 10.0

## 动态字体大小计算的基础字号。
const BASE_FONT_SIZE: int = 48


# --- 公共变量 ---

## 方块当前的数值。
var value: int = 0

## 方块当前的类型。
var type: TileType = TileType.PLAYER

## 存储所有可用配色方案的字典。 (已废弃，由 Controller 计算颜色)
var color_schemes: Dictionary


# --- 私有变量 ---

## 追踪当前正在执行的移动 Tween，并在重定向时打断。
var _active_move_tween: Tween

## 追踪当前正在执行的缩放 Tween（如合并时）。
var _active_scale_tween: Tween

## 追踪当前正在执行的旋转 Tween。
var _active_rotation_tween: Tween


# --- @onready 变量 (节点引用) ---

@onready var background: Panel = $Background
@onready var value_label: Label = $ValueLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	background.add_theme_stylebox_override("panel", background.get_theme_stylebox("panel").duplicate())


# --- 公共方法 ---

## 初始化或更新方块的状态和外观。
##
## 这是该节点的唯一公共接口，用于设置其所有核心属性。
## @param new_value: 方块的新数值。
## @param bg_color: 背景颜色。
## @param font_color: 字体颜色。
func setup(new_value: int, bg_color: Color, font_color: Color) -> void:
	self.value = new_value
	
	value_label.text = str(int(value))
	(background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = bg_color
	value_label.add_theme_color_override("font_color", font_color)
	_update_font_size()


## 停止当前动画并恢复基础变换状态，供对象池复用前调用。
func reset_animation_state() -> void:
	if _active_move_tween and _active_move_tween.is_valid():
		_active_move_tween.kill()
	if _active_scale_tween and _active_scale_tween.is_valid():
		_active_scale_tween.kill()
	if _active_rotation_tween and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()

	_active_move_tween = null
	_active_scale_tween = null
	_active_rotation_tween = null
	scale = Vector2.ONE
	rotation_degrees = 0
	modulate = Color.WHITE


## GFObjectPoolUtility 取出节点时调用，确保复用节点没有残留 Tween。
func on_gf_pool_acquire() -> void:
	reset_animation_state()


## GFObjectPoolUtility 归还节点时调用，确保节点进入池前已停止动画。
func on_gf_pool_release() -> void:
	reset_animation_state()


## 播放方块生成时的动画（从小到大旋转出现）。
## @return: 返回控制该动画的 Tween 对象。
func animate_spawn() -> Tween:
	if _active_rotation_tween and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()

	scale = Vector2.ZERO
	rotation_degrees = -360
	_active_rotation_tween = create_tween()
	_active_rotation_tween.set_parallel(true)
	_active_rotation_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_rotation_tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	_active_rotation_tween.tween_property(self, "rotation_degrees", 0, 0.1)
	return _active_rotation_tween


## 播放方块在棋盘上移动时的动画。
## @param new_position: 移动的目标位置。
## @return: 返回控制该动画的 Tween 对象。
func animate_move(new_position: Vector2) -> Tween:
	if position.is_equal_approx(new_position):
		return null

	if _active_move_tween and _active_move_tween.is_valid():
		_active_move_tween.kill()

	_active_move_tween = create_tween()
	_active_move_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_move_tween.tween_property(self, "position", new_position, 0.1)
	return _active_move_tween


## 播放方块合并或增强时的脉冲动画（放大后复原）。
## @return: 返回控制该动画的 Tween 对象。
func animate_merge() -> Tween:
	if _active_scale_tween and _active_scale_tween.is_valid():
		_active_scale_tween.kill()

	_active_scale_tween = create_tween()
	_active_scale_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_scale_tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.1)
	_active_scale_tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	return _active_scale_tween


## 播放方块离场时的缩小淡出动画。
## @return: 返回控制该动画的 Tween 对象。
func animate_despawn() -> Tween:
	reset_animation_state()

	_active_scale_tween = create_tween()
	_active_scale_tween.set_parallel(true)
	_active_scale_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_active_scale_tween.tween_property(self, "scale", Vector2.ZERO, 0.12)
	_active_scale_tween.tween_property(self, "modulate:a", 0.0, 0.12)
	return _active_scale_tween


## 播放方块被强制转变类型时的“抖动”动画。
## @return: 返回控制该动画的 Tween 对象。
func animate_transform() -> Tween:
	if _active_rotation_tween and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()

	_active_rotation_tween = create_tween()
	_active_rotation_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_active_rotation_tween.tween_property(self, "rotation_degrees", -15, 0.05)
	_active_rotation_tween.tween_property(self, "rotation_degrees", 15, 0.05)
	_active_rotation_tween.tween_property(self, "rotation_degrees", -10, 0.05)
	_active_rotation_tween.tween_property(self, "rotation_degrees", 10, 0.05)
	_active_rotation_tween.tween_property(self, "rotation_degrees", 0, 0.05)
	return _active_rotation_tween


# --- 私有/辅助方法 ---

# _update_visuals 已整合进 setup 中


## 动态计算并应用最佳字体大小。
func _update_font_size() -> void:
	var new_font_size: int = BASE_FONT_SIZE
	var available_width: float = background.size.x - (HORIZONTAL_PADDING * 2)
	var font: Font = value_label.get_theme_font("font")
	var text_width: float = font.get_string_size(value_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, BASE_FONT_SIZE).x

	if text_width > available_width:
		var scale_factor: float = available_width / text_width
		new_font_size = floori(BASE_FONT_SIZE * scale_factor)

	value_label.add_theme_font_size_override("font_size", new_font_size)
