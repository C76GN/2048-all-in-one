# scripts/tile.gd

## Tile: 定义了棋盘上单个方块的行为、外观和动画。
##
## 每个方块节点都挂载此脚本。它负责管理自身的数值、类型（玩家或怪物），
## 并根据这些属性更新背景颜色、文本内容和字体大小。
## 同时，它也封装了所有与自身相关的动画，如生成、移动、合并等。
class_name Tile
extends Node2D

# --- 枚举定义 ---

# 定义方块的两种基本类型，用于区分游戏逻辑和视觉表现。
enum TileType {PLAYER, MONSTER}

# --- 常量定义 ---

# 方块内文本的水平内边距，用于动态字体大小计算。
const HORIZONTAL_PADDING: float = 10.0
# 动态字体大小计算的基础字号。
const BASE_FONT_SIZE: int = 48

# --- 节点引用 ---

## 对背景面板（Panel）节点的引用。
@onready var background: Panel = $Background
## 对显示数值的标签（Label）节点的引用。
@onready var value_label: Label = $ValueLabel

# --- 核心状态变量 ---

# 方块当前的数值。
var value: int = 0
# 方块当前的类型。
var type: TileType = TileType.PLAYER
var interaction_rule: InteractionRule
# 存储所有配色方案的字典
var color_schemes: Dictionary

## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 复制主题样式资源，确保每个方块实例的颜色可以被独立修改，
	# 避免所有方块共享同一个颜色设置。
	background.add_theme_stylebox_override("panel", background.get_theme_stylebox("panel").duplicate())

# --- 公共接口 ---

## 初始化或更新方块的状态和外观。
##
## 这是该节点的唯一公共接口，用于设置其所有核心属性。
## 当方块数值变大时，会自动触发合并动画。
## @param new_value: 方块的新数值。
## @param new_type: 方块的新类型 (PLAYER 或 MONSTER)。
func setup(new_value: int, new_type: TileType, p_rule: InteractionRule, p_color_schemes: Dictionary) -> void:
	var old_value = self.value
	self.value = new_value
	self.type = new_type
	self.interaction_rule = p_rule
	self.color_schemes = p_color_schemes
	_update_visuals()

	if new_value > old_value and old_value != 0:
		animate_merge()

# --- 视觉更新 ---

## [内部函数] 根据当前状态更新方块的所有视觉表现。
## 包括背景颜色、文本内容、字体颜色和动态字体大小。
func _update_visuals() -> void:
	# 步骤1: 更新显示的文本。
	value_label.text = str(int(value))

	if not is_instance_valid(interaction_rule):
		return

	# 步骤2: 根据方块类型或数值，动态查询颜色主题。
	# 明确指定 scheme_index 为 int 类型，以解决类型转换警告。
	var scheme_index: int = type
	if type == TileType.PLAYER:
		# 对于玩家方块，查询交互规则来决定使用哪个配色方案
		scheme_index = interaction_rule.get_color_scheme_index(value)

	var current_scheme: TileColorScheme = color_schemes.get(scheme_index)

	if not is_instance_valid(current_scheme) or current_scheme.styles.is_empty():
		return

	# 步骤3: 获取当前数值等级对应的样式。
	var level = interaction_rule.get_level_by_value(value)
	# 如果等级超出样式数组范围，使用最后一个样式。
	if level >= current_scheme.styles.size():
		level = current_scheme.styles.size() - 1

	var current_style: TileLevelStyle = current_scheme.styles[level]
	if not is_instance_valid(current_style):
		return

	# 步骤4: 应用背景颜色和字体颜色。
	(background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = current_style.background_color
	value_label.add_theme_color_override("font_color", current_style.font_color)

	# 步骤5: 动态计算并设置字体大小，防止文本溢出。
	_update_font_size()

## [内部函数] 动态计算并应用最佳字体大小。
func _update_font_size() -> void:
	var new_font_size = BASE_FONT_SIZE
	var available_width = background.size.x - (HORIZONTAL_PADDING * 2)
	var font = value_label.get_theme_font("font")
	# 使用基础字号来测量当前文本的渲染宽度。
	var text_width = font.get_string_size(value_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, BASE_FONT_SIZE).x

	# 如果文本宽度超出了可用空间，则按比例缩小字体。
	if text_width > available_width:
		var scale_factor = available_width / text_width
		new_font_size = floor(BASE_FONT_SIZE * scale_factor)

	# 应用最终计算出的字体大小。
	value_label.add_theme_font_size_override("font_size", new_font_size)

# --- 动画函数 ---

## 播放方块生成时的动画（从小到大旋转出现）。
## @return: 返回控制该动画的 Tween 对象。
func animate_spawn() -> Tween:
	scale = Vector2.ZERO
	rotation_degrees = -360
	var tween = create_tween()
	tween.set_parallel(true) # 缩放和旋转同时进行。
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	tween.tween_property(self, "rotation_degrees", 0, 0.1)
	return tween

## 播放方块在棋盘上移动时的动画。
## @param new_position: 移动的目标位置。
## @return: 返回控制该动画的 Tween 对象。
func animate_move(new_position: Vector2) -> Tween:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", new_position, 0.1)
	return tween

## 播放方块合并或增强时的脉冲动画（放大后复原）。
func animate_merge() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 链式调用：先放大，完成后再缩小回正常大小，形成“脉冲”效果。
	tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)

## 播放方块被强制转变类型时的“抖动”动画。
func animate_transform() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 通过链式调用快速左右晃动，制造“转变”或“受击”的视觉效果。
	tween.tween_property(self, "rotation_degrees", -15, 0.05)
	tween.tween_property(self, "rotation_degrees", 15, 0.05)
	tween.tween_property(self, "rotation_degrees", -10, 0.05)
	tween.tween_property(self, "rotation_degrees", 10, 0.05)
	tween.tween_property(self, "rotation_degrees", 0, 0.05)
