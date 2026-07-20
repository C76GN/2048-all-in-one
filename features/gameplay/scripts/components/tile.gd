## Tile: 定义了棋盘上单个方块的行为、外观和动画。
##
## 每个方块节点都挂载此脚本。它负责管理自身的数值、定义表现，
## 并根据这些属性更新背景颜色、文本内容和字体大小。
## 同时，它也封装了所有与自身相关的动画，如生成、移动、合并等。
class_name Tile
extends Node2D


# --- 常量 ---

## 方块文本适配边距，顺序为左、上、右、下。
const _TEXT_CONTENT_INSETS: Vector4 = Vector4(10.0, 6.0, 10.0, 6.0)
const _MIN_FONT_SIZE: int = 12
const _MAX_FONT_SIZE: int = 48

const _MOVE_DURATION: float = 0.10
const _SPAWN_DURATION: float = 0.14
const _MERGE_PULSE_DURATION: float = 0.085
const _VALUE_GROWTH_DURATION: float = 0.13
const _DESPAWN_DURATION: float = 0.12
const _STYLE_OUTLINE_LIGHT: Color = Color(1.0, 0.972549, 0.9098039, 0.66)
const _STYLE_OUTLINE_DARK: Color = Color(0.0, 0.0, 0.0, 0.35)
const _FLASH_MERGE_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _FLASH_TRANSFORM_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)


# --- 公共变量 ---

## 方块当前的数值。
var value: int = 0

## 方块当前的稳定定义 ID。
var definition_id: StringName = &""

## 方块身份定义提供的稳定视觉家族。
var visual_family_id: StringName = &""

## 当前 GF Recipe 组合提供的视觉标记层。
var visual_layer_ids: Array[StringName] = []

## 当前主题注入的家族视觉配置。
var visual_style: TileVisualFamilyStyle

# --- 私有变量 ---

## 追踪当前正在执行的移动 Tween，并在重定向时打断。
var _active_move_tween: Tween

## 追踪当前正在执行的缩放 Tween（如合并时）。
var _active_scale_tween: Tween

## 追踪当前正在执行的旋转 Tween。
var _active_rotation_tween: Tween

## 追踪当前正在执行的高光 Tween。
var _active_flash_tween: Tween

## 追踪合并数值与色阶的成长 Tween。
var _active_value_tween: Tween


# --- @onready 变量 (节点引用) ---

@onready var background: TileShapeSurface = $Background
@onready var pattern_overlay: TilePatternOverlay = $PatternOverlay
@onready var value_label: Label = $ValueLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_configure_pivots()


# --- 公共方法 ---

## 初始化或更新方块的状态和外观。
##
## 这是该节点的唯一公共接口，用于设置其所有核心属性。
## @param new_value: 方块的新数值。
## @param new_definition_id: 方块的稳定定义 ID。
## @param bg_color: 背景颜色。
## @param font_color: 字体颜色。
## @param new_visual_family_id: 方块定义提供的稳定视觉家族 ID。
## @param new_visual_layer_ids: 当前 Recipe 组合提供的视觉标记层。
## @param new_visual_style: 当前主题中对应视觉家族的配置。
func setup(
	new_value: int,
	new_definition_id: StringName,
	bg_color: Color,
	font_color: Color,
	new_visual_family_id: StringName,
	new_visual_layer_ids: Array[StringName],
	new_visual_style: TileVisualFamilyStyle
) -> void:
	self.value = new_value
	definition_id = new_definition_id
	visual_family_id = new_visual_family_id
	visual_layer_ids = new_visual_layer_ids.duplicate()
	visual_style = new_visual_style
	
	value_label.text = str(int(value))
	_apply_background_style(bg_color)
	_apply_pattern_style(bg_color)
	value_label.add_theme_color_override("font_color", font_color)
	value_label.add_theme_color_override("font_outline_color", _get_label_outline_color(bg_color))
	value_label.add_theme_constant_override("outline_size", 2)
	_fit_value_text()


## 停止当前动画并恢复基础变换状态，供对象池复用前调用。
func reset_animation_state() -> void:
	if is_instance_valid(_active_move_tween) and _active_move_tween.is_valid():
		_active_move_tween.kill()
	if is_instance_valid(_active_scale_tween) and _active_scale_tween.is_valid():
		_active_scale_tween.kill()
	if is_instance_valid(_active_rotation_tween) and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()
	if is_instance_valid(_active_flash_tween) and _active_flash_tween.is_valid():
		_active_flash_tween.kill()
	if is_instance_valid(_active_value_tween) and _active_value_tween.is_valid():
		_active_value_tween.kill()

	_active_move_tween = null
	_active_scale_tween = null
	_active_rotation_tween = null
	_active_flash_tween = null
	_active_value_tween = null
	scale = Vector2.ONE
	rotation_degrees = 0
	modulate = Color.WHITE
	background.modulate = Color.WHITE
	pattern_overlay.modulate = Color.WHITE
	value_label.modulate = Color.WHITE
	value_label.scale = Vector2.ONE


## GFObjectPoolUtility 取出节点时调用，确保复用节点没有残留 Tween。
func on_gf_pool_acquire() -> void:
	reset_animation_state()


## GFObjectPoolUtility 归还节点时调用，确保节点进入池前已停止动画。
func on_gf_pool_release() -> void:
	reset_animation_state()


## 播放方块生成时的动画（短促放大出现）。
## @return: 返回控制该动画的 Tween 对象。
func animate_spawn() -> Tween:
	if is_instance_valid(_active_rotation_tween) and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()

	scale = Vector2.ONE * 0.64
	rotation_degrees = 0.0
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_active_rotation_tween = create_tween()
	var _parallel_result: Tween = _active_rotation_tween.set_parallel(true)
	var _transition_result: Tween = _active_rotation_tween.set_trans(Tween.TRANS_BACK)
	var _ease_result: Tween = _active_rotation_tween.set_ease(Tween.EASE_OUT)
	var _scale_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "scale", Vector2.ONE, _SPAWN_DURATION)
	var _fade_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "modulate:a", 1.0, _SPAWN_DURATION * 0.75)
	return _active_rotation_tween


## 播放方块在棋盘上移动时的动画。
## @param new_position: 移动的目标位置。
## @return: 返回控制该动画的 Tween 对象。
func animate_move(new_position: Vector2) -> Tween:
	if position.is_equal_approx(new_position):
		return null

	if is_instance_valid(_active_move_tween) and _active_move_tween.is_valid():
		_active_move_tween.kill()

	_active_move_tween = create_tween()
	var _transition_result: Tween = _active_move_tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = _active_move_tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = _active_move_tween.tween_property(self, "position", new_position, _MOVE_DURATION)
	return _active_move_tween


## 播放方块合并或增强时的脉冲动画（放大后复原）。
## @param on_impact: 到达碰撞时刻后、脉冲开始前执行的表现更新。
## @param delay_seconds: 合并冲击开始前的等待时间，通常与移动动画时长一致。
## @return: 返回控制该动画的 Tween 对象。
func animate_merge(
	on_impact: Callable = Callable(),
	delay_seconds: float = 0.0
) -> Tween:
	if is_instance_valid(_active_scale_tween) and _active_scale_tween.is_valid():
		_active_scale_tween.kill()

	_active_scale_tween = create_tween()
	if delay_seconds > 0.0:
		var _delay_tweener: IntervalTweener = _active_scale_tween.tween_interval(delay_seconds)
	if on_impact.is_valid():
		var _impact_tweener: CallbackTweener = _active_scale_tween.tween_callback(on_impact)
	var _flash_tweener: CallbackTweener = _active_scale_tween.tween_callback(
		_play_flash.bind(_FLASH_MERGE_COLOR, _MERGE_PULSE_DURATION * 2.0)
	)
	var scale_up_tweener: PropertyTweener = _active_scale_tween.tween_property(
		self,
		"scale",
		Vector2.ONE * 1.19,
		_MERGE_PULSE_DURATION
	)
	var _scale_up_transition: Tweener = scale_up_tweener.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var scale_down_tweener: PropertyTweener = _active_scale_tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		_MERGE_PULSE_DURATION
	)
	var _scale_down_transition: Tweener = scale_down_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
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
## @param on_impact: 转化反馈开始时执行的回调。
## @param delay_seconds: 转化反馈开始前的等待时间。
## @return: 返回控制该动画的 Tween 对象。
func animate_transform(
	on_impact: Callable = Callable(),
	delay_seconds: float = 0.0
) -> Tween:
	if is_instance_valid(_active_rotation_tween) and _active_rotation_tween.is_valid():
		_active_rotation_tween.kill()

	_active_rotation_tween = create_tween()
	var _transition_result: Tween = _active_rotation_tween.set_trans(Tween.TRANS_SINE)
	var _ease_result: Tween = _active_rotation_tween.set_ease(Tween.EASE_IN_OUT)
	if delay_seconds > 0.0:
		var _delay_tweener: IntervalTweener = _active_rotation_tween.tween_interval(delay_seconds)
	if on_impact.is_valid():
		var _impact_tweener: CallbackTweener = _active_rotation_tween.tween_callback(on_impact)
	var _flash_tweener: CallbackTweener = _active_rotation_tween.tween_callback(
		_play_flash.bind(_FLASH_TRANSFORM_COLOR, 0.14)
	)
	var _rotate_left_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", -4.0, 0.04)
	var _rotate_right_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", 4.0, 0.05)
	var _rotate_settle_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", -2.0, 0.04)
	var _rotate_home_tweener: PropertyTweener = _active_rotation_tween.tween_property(self, "rotation_degrees", 0.0, 0.05)
	return _active_rotation_tween


## 返回移动反馈的标准时长，供批量表现动作安排冲击时刻。
static func get_move_animation_duration() -> float:
	return _MOVE_DURATION


## 返回合并脉冲的完整时长，供后续表现动作顺序衔接。
static func get_merge_animation_duration() -> float:
	return _MERGE_PULSE_DURATION * 2.0


## 返回当前方块主题背景色，供粒子和浮动文字继承视觉语义。
func get_feedback_color() -> Color:
	if not is_instance_valid(background):
		return Color.WHITE
	return background.get_fill_color()


## 合并冲击后让数字与色阶共同经历一次短促成长，而不是瞬间跳值。
## @param from_value: 合并前显示的数值。
## @param to_value: 合并后显示的数值。
## @param from_background_color: 合并前的方块底色。
## @param to_background_color: 合并后的方块底色。
## @param from_font_color: 合并前的数字颜色。
## @param to_font_color: 合并后的数字颜色。
func animate_value_growth(
	from_value: int,
	to_value: int,
	from_background_color: Color,
	to_background_color: Color,
	from_font_color: Color,
	to_font_color: Color
) -> Tween:
	if is_instance_valid(_active_value_tween) and _active_value_tween.is_valid():
		_active_value_tween.kill()
	if from_value == to_value:
		return null

	_set_value_growth_progress(
		0.0,
		from_value,
		to_value,
		from_background_color,
		to_background_color,
		from_font_color,
		to_font_color
	)
	_active_value_tween = create_tween()
	var growth_tweener: MethodTweener = _active_value_tween.tween_method(
		_set_value_growth_progress.bind(
			from_value,
			to_value,
			from_background_color,
			to_background_color,
			from_font_color,
			to_font_color
		),
		0.0,
		1.0,
		_VALUE_GROWTH_DURATION
	)
	var _growth_curve: Tweener = growth_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var _finished_connection: int = _active_value_tween.finished.connect(
		_finish_value_growth.bind(to_value, to_background_color, to_font_color),
		CONNECT_ONE_SHOT
	)
	return _active_value_tween


# --- 私有/辅助方法 ---

func _configure_pivots() -> void:
	if is_instance_valid(background):
		background.pivot_offset = background.size * 0.5
	if is_instance_valid(value_label):
		value_label.pivot_offset = value_label.size * 0.5


func _apply_background_style(bg_color: Color) -> void:
	background.setup(visual_style, bg_color)


func _apply_pattern_style(bg_color: Color) -> void:
	if not is_instance_valid(pattern_overlay):
		return

	pattern_overlay.setup(visual_style, bg_color, visual_layer_ids)


func _get_pattern_type() -> TilePatternOverlay.PatternType:
	return pattern_overlay.get_pattern_type() if is_instance_valid(pattern_overlay) else TilePatternOverlay.PatternType.NONE


func _set_value_growth_progress(
	progress: float,
	from_value: int,
	to_value: int,
	from_background_color: Color,
	to_background_color: Color,
	from_font_color: Color,
	to_font_color: Color
) -> void:
	var safe_progress: float = clampf(progress, 0.0, 1.0)
	value_label.text = str(roundi(lerpf(float(from_value), float(to_value), safe_progress)))
	background.set_fill_color(from_background_color.lerp(to_background_color, safe_progress))
	value_label.add_theme_color_override(
		"font_color",
		from_font_color.lerp(to_font_color, safe_progress)
	)


func _finish_value_growth(
	to_value: int,
	to_background_color: Color,
	to_font_color: Color
) -> void:
	value_label.text = str(to_value)
	background.set_fill_color(to_background_color)
	value_label.add_theme_color_override("font_color", to_font_color)
	_active_value_tween = null


func _get_label_outline_color(bg_color: Color) -> Color:
	var luminance: float = (
		bg_color.r * 0.299
		+ bg_color.g * 0.587
		+ bg_color.b * 0.114
	)
	return _STYLE_OUTLINE_LIGHT if luminance < 0.50 else _STYLE_OUTLINE_DARK


func _play_flash(color: Color, duration: float) -> void:
	if is_instance_valid(_active_flash_tween) and _active_flash_tween.is_valid():
		_active_flash_tween.kill()

	background.modulate = color
	value_label.scale = Vector2.ONE * 1.15
	_active_flash_tween = create_tween()
	var _parallel_result: Tween = _active_flash_tween.set_parallel(true)
	var _transition_result: Tween = _active_flash_tween.set_trans(Tween.TRANS_SINE)
	var _ease_result: Tween = _active_flash_tween.set_ease(Tween.EASE_OUT)
	var _background_tweener: PropertyTweener = _active_flash_tween.tween_property(background, "modulate", Color.WHITE, duration)
	var _label_tweener: PropertyTweener = _active_flash_tween.tween_property(value_label, "scale", Vector2.ONE, duration)


## 以一次字体测量计算并应用最大可读字号。
## GFTextFitter 的重复候选测量在 Godot 4.7 会放大退出期 ShapedText RID 残留；
## 上游修复发布前保留这个单次测量边界，禁止改成逐字号循环。
func _fit_value_text() -> void:
	var available_size: Vector2 = Vector2(
		background.size.x - _TEXT_CONTENT_INSETS.x - _TEXT_CONTENT_INSETS.z,
		background.size.y - _TEXT_CONTENT_INSETS.y - _TEXT_CONTENT_INSETS.w
	)
	var font: Font = value_label.get_theme_font("font")
	var measured_size: Vector2 = font.get_string_size(
		value_label.text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		_MAX_FONT_SIZE
	)
	var scale_factor: float = minf(
		available_size.x / maxf(measured_size.x, 1.0),
		available_size.y / maxf(measured_size.y, 1.0)
	)
	var font_size: int = clampi(
		floori(float(_MAX_FONT_SIZE) * minf(scale_factor, 1.0)),
		_MIN_FONT_SIZE,
		_MAX_FONT_SIZE
	)
	value_label.add_theme_font_size_override("font_size", font_size)
