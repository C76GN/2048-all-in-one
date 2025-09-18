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
	2: Color("cce5ff"), 4: Color("99ccff"), 8: Color("66b2ff"), 16: Color("3399ff"),
	32: Color("007fff"), 64: Color("0066cc"), 128: Color("0052a3"), 256: Color("003d7a"),
	512: Color("002952"), 1024: Color("001429"), 2048: Color("000a14"), 4096: Color("00050a")
}

# 字典：存储怪物方块不同数值对应的背景颜色。
const MONSTER_COLOR_MAP = {
	2: Color("f9baba"), 4: Color("f79494"), 8: Color("f26b6b"), 16: Color("ef4e4e"),
	32: Color("e83a3a"), 64: Color("d92b2b"), 128: Color("c91d1d"), 256: Color("b51313"),
	512: Color("a30a0a"), 1024: Color("8f0303"), 2048: Color("7d0000"), 4096: Color("680000")
}

# --- 节点引用 ---

# 对背景颜色矩形（ColorRect）节点的引用。
@onready var background: ColorRect = $Background
# 对显示数值的标签（Label）节点的引用。
@onready var value_label: Label = $ValueLabel

# --- 核心状态变量 ---

# 方块当前的数值。
var value: int = 0
# 方块当前的类型，默认为玩家方块。
var type: TileType = TileType.PLAYER


# --- 公共接口 ---

## 初始化或更新方块的状态和外观。
## 这是该节点的唯一公共接口，用于设置其所有核心属性。
## @param new_value: 方块的新数值。
## @param new_type: 方块的新类型 (PLAYER 或 MONSTER)。
func setup(new_value: int, new_type: TileType) -> void:
	self.value = new_value
	self.type = new_type
	_update_visuals()

# --- 视觉更新辅助函数 ---
# 将所有更新外观的代码（颜色、文本）集中到这里，方便复用。
func _update_visuals() -> void:
	# 步骤 1: 更新显示的文本。
	value_label.text = str(int(value))
	
	# 步骤 2: 根据方块类型选择对应的颜色映射表。
	var current_color_map = PLAYER_COLOR_MAP
	if type == TileType.MONSTER:
		current_color_map = MONSTER_COLOR_MAP
	
	# 步骤 3: 设置背景颜色。
	# 如果当前数值在颜色映射表中存在，则使用预设颜色。
	if current_color_map.has(value):
		background.color = current_color_map[value]
	# 否则，使用默认的黑色作为后备，以应对未定义的超大数值。
	else:
		background.color = Color.BLACK
	
	# 步骤 4: 优化文本颜色可读性。
	# 对于数值较小的方块，使用深色字体。
	if value <= 4:
		value_label.add_theme_color_override("font_color", Color("776e65"))
	# 对于数值较大的方块，使用浅色字体。
	else:
		value_label.add_theme_color_override("font_color", Color("f9f6f2"))


# -------------------- 动画函数 --------------------

# 常规生成动画（从小旋转放大）
func animate_spawn():
	scale = Vector2.ZERO
	rotation_degrees = -90
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	tween.tween_property(self, "scale", Vector2.ONE, 0.25)
	tween.tween_property(self, "rotation_degrees", 0, 0.25)


# 移动动画
func animate_move(new_position: Vector2):
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", new_position, 0.15)
	return tween
