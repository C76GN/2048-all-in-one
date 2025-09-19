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

# 字典：存储玩家方块不同数值对应的背景颜色。
const PLAYER_COLOR_MAP = {
	2: Color("f0f4f8"), 4: Color("d9e2ec"), 8: Color("bcc8d6"), 16: Color("9fb0c4"),
	32: Color("8298b0"), 64: Color("66809b"), 128: Color("4d6a87"), 256: Color("335372"),
	512: Color("193d5c"), 1024: Color("002747"), 2048: Color("002747"), 4096: Color("002747"),
	8192: Color("002747"), 16384: Color("002747"), 32768: Color("002747"), 65536: Color("002747")
}

# 字典：存储怪物方块不同数值对应的背景颜色。
const MONSTER_COLOR_MAP = {
	2: Color("f9e0e0"), 4: Color("f2baba"), 8: Color("eb9494"), 16: Color("e36d6d"),
	32: Color("db4646"), 64: Color("d22020"), 128: Color("c21313"), 256: Color("b00a0a"),
	512: Color("9e0505"), 1024: Color("8c0202"), 2048: Color("7d0000"), 4096: Color("7d0000"),
	8192: Color("7d0000"), 16384: Color("7d0000"), 32768: Color("7d0000"), 65536: Color("7d0000")
}

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
func setup(new_value: int, new_type: TileType) -> void:
	var old_value = self.value
	self.value = new_value
	self.type = new_type
	_update_visuals()
	
	# 如果方块的数值变大了（意味着它刚刚合并或被增强），则播放合并动画。
	if new_value > old_value and old_value != 0:
		animate_merge()

# --- 视觉更新 ---

## [内部函数] 根据当前状态更新方块的所有视觉表现。
## 包括背景颜色、文本内容、字体颜色和动态字体大小。
func _update_visuals() -> void:
	# 步骤1: 更新显示的文本。
	value_label.text = str(int(value))
	
	# 步骤2: 根据方块类型选择对应的颜色映射表。
	var current_color_map = PLAYER_COLOR_MAP
	if type == TileType.MONSTER:
		current_color_map = MONSTER_COLOR_MAP
	
	# 步骤3: 设置背景颜色。
	var color_key = value
	# 如果数值超过了颜色映射表定义的最大值，则统一使用最大值的颜色。
	if color_key > 65536:
		color_key = 65536
	# 从映射表中获取并应用颜色，如果找不到则使用最大值的颜色作为后备。
	if current_color_map.has(color_key):
		(background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = current_color_map[color_key]
	else:
		(background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = current_color_map[65536]
	
	# 步骤4: 根据数值大小调整字体颜色以保证可读性。
	if value <= 4:
		# 数值较小时使用深色字体。
		value_label.add_theme_color_override("font_color", Color("776e65"))
	else:
		# 数值较大时使用浅色字体。
		value_label.add_theme_color_override("font_color", Color("f9f6f2"))
	
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
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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
