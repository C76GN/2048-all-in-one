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

const _MOVE_DURATION: float = 0.14
const _SPAWN_DURATION: float = 0.18
const _MERGE_PULSE_DURATION: float = 0.09
const _DESPAWN_DURATION: float = 0.14
const _STYLE_CORNER_RADIUS: int = 0


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

## 追踪当前正在执行的高光 Tween。
var _active_flash_tween: Tween


# --- @onready 变量 (节点引用) ---

@onready var background: Panel = $Background
@onready var value_label: Label = $ValueLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var panel_stylebox: StyleBox = background.get_theme_stylebox("panel").duplicate() as StyleBox
	if panel_stylebox != null:
		background.add_theme_stylebox_override("panel", panel_stylebox)
	_configure_pivots()


# --- 公共方法 ---

## 初始化或更新方块的状态和外观。
##
## 这是该节点的唯一公共接口，用于设置其所有核心属性。
## @param new_value: 方块的新数值。
## @param new_type: 方块的新类型。
## @param bg_color: 背景颜色。
## @param font_color: 字体颜色。
func setup(new_value: int, new_type: TileType, bg_color: Color, font_color: Color) -> void:
	self.value = new_value
	self.type = new_type
	
	value_label.text = str(int(value))
	_apply_background_style(bg_color)
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
	if _active_flash_tween and _active_flash_tween.is_valid():
		_active_flash_tween.kill()

	_active_move_tween = null
	_active_scale_tween = null
	_active_rotation_tween = null
	_active_flash_tween = null
	scale = Vector2.ONE
	rotation_degrees = 0
	modulate = Color.WHITE
	background.modulate = Color.WHITE
	value_label.modulate = Color.WHITE
	value_label.scale = Vector2.ONE


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

	scale = Vector2.ONE * 0.42
	rotation_degrees = -5.0
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_active_rotation_tween = create_tween()
	var _parallel_result: Tween = _active_rotation_tween.set_parallel(true)
	var _transition_result: Tween = _active_rotation_tween.set_trans(Tween.TRANS_BACK)
	var _ease_result: Tween = _active_rotation_tween.set_ease(Tween.EASE_OUT)
	var _scale_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "scale", Vector2.ONE, _SPAWN_DURATION)
	var _rotation_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", 0.0, _SPAWN_DURATION)
	var _fade_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "modulate:a", 1.0, _SPAWN_DURATION * 0.75)
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
	var _transition_result: Tween = _active_move_tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = _active_move_tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = _active_move_tween.tween_property(self, "position", new_position, _MOVE_DURATION)
	return _active_move_tween


## 播放方块合并或增强时的脉冲动画（放大后复原）。
## @return: 返回控制该动画的 Tween 对象。
func animate_merge() -> Tween:
	if _active_scale_tween and _active_scale_tween.is_valid():
		_active_scale_tween.kill()

	_active_scale_tween = create_tween()
	var _transition_result: Tween = _active_scale_tween.set_trans(Tween.TRANS_BACK)
	var _ease_result: Tween = _active_scale_tween.set_ease(Tween.EASE_OUT)
	var _scale_up_tweener: PropertyTweener = _active_scale_tween.tween_property(self, "scale", Vector2.ONE * 1.24, _MERGE_PULSE_DURATION)
	var _scale_down_tweener: PropertyTweener = _active_scale_tween.tween_property(self, "scale", Vector2.ONE, _MERGE_PULSE_DURATION)
	_play_flash(Color(1.0, 0.92, 0.62, 1.0), _MERGE_PULSE_DURATION * 2.0)
	return _active_scale_tween


## 播放方块离场时的缩小淡出动画。
## @return: 返回控制该动画的 Tween 对象。
func animate_despawn() -> Tween:
	reset_animation_state()

	_active_scale_tween = create_tween()
	var _parallel_result: Tween = _active_scale_tween.set_parallel(true)
	var _transition_result: Tween = _active_scale_tween.set_trans(Tween.TRANS_BACK)
	var _ease_result: Tween = _active_scale_tween.set_ease(Tween.EASE_IN)
	var _scale_tweener: PropertyTweener = _active_scale_tween.tween_property(self, "scale", Vector2.ONE * 0.28, _DESPAWN_DURATION)
	var _fade_tweener: PropertyTweener = _active_scale_tween.tween_property(self, "modulate:a", 0.0, _DESPAWN_DURATION)
	return _active_scale_tween


## 播放方块被强制转变类型时的“抖动”动画。
## @return: 返回控制该动画的 Tween 对象。
func animate_transform() -> Tween:
	if _active_rotation_tween and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()

	_active_rotation_tween = create_tween()
	var _transition_result: Tween = _active_rotation_tween.set_trans(Tween.TRANS_SINE)
	var _ease_result: Tween = _active_rotation_tween.set_ease(Tween.EASE_IN_OUT)
	var _rotate_left_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", -8.0, 0.04)
	var _rotate_right_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", 8.0, 0.06)
	var _rotate_settle_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", -5.0, 0.05)
	var _rotate_home_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", 0.0, 0.05)
	_play_flash(Color(0.72, 0.9, 1.0, 1.0), 0.16)
	return _active_rotation_tween


# --- 私有/辅助方法 ---

func _configure_pivots() -> void:
	if is_instance_valid(background):
		background.pivot_offset = background.size * 0.5
	if is_instance_valid(value_label):
		value_label.pivot_offset = value_label.size * 0.5


func _apply_background_style(bg_color: Color) -> void:
	var stylebox: StyleBoxFlat = background.get_theme_stylebox("panel") as StyleBoxFlat
	if stylebox == null:
		return

	stylebox.bg_color = bg_color
	stylebox.border_color = bg_color
	stylebox.set_border_width_all(0)
	stylebox.set_corner_radius_all(_STYLE_CORNER_RADIUS)
	stylebox.shadow_color = Color.TRANSPARENT
	stylebox.shadow_size = 0
	stylebox.shadow_offset = Vector2.ZERO


func _play_flash(color: Color, duration: float) -> void:
	if _active_flash_tween and _active_flash_tween.is_valid():
		_active_flash_tween.kill()

	background.modulate = color
	value_label.scale = Vector2.ONE * 1.08
	_active_flash_tween = create_tween()
	var _parallel_result: Tween = _active_flash_tween.set_parallel(true)
	var _transition_result: Tween = _active_flash_tween.set_trans(Tween.TRANS_SINE)
	var _ease_result: Tween = _active_flash_tween.set_ease(Tween.EASE_OUT)
	var _background_tweener: PropertyTweener = _active_flash_tween.tween_property(background, "modulate", Color.WHITE, duration)
	var _label_tweener: PropertyTweener = _active_flash_tween.tween_property(value_label, "scale", Vector2.ONE, duration)


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
