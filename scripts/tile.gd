# scripts/tile.gd

# 该脚本定义了棋盘上单个方块的行为和外观。
# 每个方块节点都挂载此脚本，负责管理自身的数值、类型（玩家或怪物），
# 并根据这些属性更新其背景颜色和显示的文本。
class_name Tile
extends Node2D

# --- 枚举定义 ---

# 定义方块的两种基本类型，用于区分逻辑和视觉表现。
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

# 定义方块内容的内边距（padding），即文本距离背景边缘的距离。
const HORIZONTAL_PADDING: float = 10.0
# 定义一个基础的、理想的字体大小作为计算起点。
const BASE_FONT_SIZE: int = 48

# --- 节点引用 ---

# 对背景颜色矩形（ColorRect）节点的引用。
@onready var background: Panel = $Background
# 对显示数值的标签（Label）节点的引用。
@onready var value_label: Label = $ValueLabel

# --- 核心状态变量 ---

# 方块当前的数值。
var value: int = 0
# 方块当前的类型，默认为玩家方块。
var type: TileType = TileType.PLAYER

func _ready() -> void:
	# 复制主题样式，确保每个方块实例的颜色可以被独立修改，
	background.add_theme_stylebox_override("panel", background.get_theme_stylebox("panel").duplicate())

# --- 公共接口 ---

## 初始化或更新方块的状态和外观。
## 这是该节点的唯一公共接口，用于设置其所有核心属性。
## @param new_value: 方块的新数值。
## @param new_type: 方块的新类型 (PLAYER 或 MONSTER)。
func setup(new_value: int, new_type: TileType) -> void:
	var old_value = self.value
	self.value = new_value
	self.type = new_type
	_update_visuals()
	
	# 如果方块的数值变大了（意味着它刚刚合并了别的方块），就播放合并动画
	if new_value > old_value and old_value != 0:
		animate_merge()

# --- 视觉更新辅助函数 ---
# 将所有更新外观的代码（颜色、文本）集中到这里，方便复用。
func _update_visuals() -> void:
	# 更新显示的文本。
	value_label.text = str(int(value))
	# 根据方块类型选择对应的颜色映射表。
	var current_color_map = PLAYER_COLOR_MAP
	
	if type == TileType.MONSTER:
		current_color_map = MONSTER_COLOR_MAP
	
	# 设置背景颜色。
	var color_key = value
	
	# 如果数值超过了我们定义的最大值，就统一使用最大值的颜色。
	if color_key > 65536:
		color_key = 65536
	
	# 如果当前数值在颜色映射表中存在，则使用预设颜色。
	if current_color_map.has(color_key):
		(background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = current_color_map[color_key]
	# 否则，则使用为65536定义的颜色作为后备颜色。
	else:
		(background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = current_color_map[65536]
	
	# 优化文本颜色可读性。
	# 对于数值较小的方块，使用深色字体。
	if value <= 4:
		value_label.add_theme_color_override("font_color", Color("776e65"))
	# 对于数值较大的方块，使用浅色字体。
	else:
		value_label.add_theme_color_override("font_color", Color("f9f6f2"))
	
	# 动态字体大小计算逻辑
	# 始终以 BASE_FONT_SIZE 作为计算的起点
	var new_font_size = BASE_FONT_SIZE
	var available_width = background.size.x - (HORIZONTAL_PADDING * 2)
	var font = value_label.get_theme_font("font")
	# 使用基础字号来测量文本宽度
	var text_width = font.get_string_size(value_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, BASE_FONT_SIZE).x
	
	# 如果基于基础字号的文本宽度超出了可用空间，则按比例缩小字体
	if text_width > available_width:
		var scale_factor = available_width / text_width
		new_font_size = floor(BASE_FONT_SIZE * scale_factor)
	
	# 无论如何，总是在最后应用最终计算出的字体大小。
	value_label.add_theme_font_size_override("font_size", new_font_size)

# -------------------- 动画函数 --------------------

# 常规生成动画（从小旋转放大）
func animate_spawn():
	scale = Vector2.ZERO
	rotation_degrees = -360
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	tween.tween_property(self, "rotation_degrees", 0, 0.1)
	return tween

# 移动动画
func animate_move(new_position: Vector2):
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", new_position, 0.1)
	return tween

# 合并时的脉冲动画
func animate_merge():
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 链式调用：先放大，完成后再缩小回正常大小
	tween.tween_property(self, "scale", Vector2.ONE * 0.5, 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)

# 方块被强制转变时的动画
func animate_transform():
	var tween = create_tween()
	# 使用一个有弹性的过渡效果
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 链式调用，制作一个快速左右晃动的效果
	tween.tween_property(self, "rotation_degrees", -15, 0.02)
	tween.tween_property(self, "rotation_degrees", 15, 0.02)
	tween.tween_property(self, "rotation_degrees", -10, 0.02)
	tween.tween_property(self, "rotation_degrees", 10, 0.02)
	tween.tween_property(self, "rotation_degrees", 0, 0.02)
