# scripts/tile.gd

# 该脚本定义了棋盘上单个方块的行为和外观。
# 每个方块节点都挂载此脚本，负责管理自身的数值、类型（玩家或怪物），
# 并根据这些属性更新其背景颜色和显示的文本。
extends Node2D

# --- 枚举定义 ---

# 定义方块的两种基本类型，用于区分逻辑和视觉表现。
enum TileType {PLAYER, MONSTER}

# --- 常量定义 ---

# 字典：存储玩家方块不同数值对应的背景颜色。
const PLAYER_COLOR_MAP = {
	2: Color("eee4da"), 4: Color("ede0c8"), 8: Color("f2b179"), 16: Color("f59563"),
	32: Color("f67c5f"), 64: Color("f65e3b"), 128: Color("edcf72"), 256: Color("edcc61"),
	512: Color("edc850"), 1024: Color("edc53f"), 2048: Color("edc22e"), 4096: Color("3c3a32")
}

# 字典：存储怪物方块不同数值对应的背景颜色。
const MONSTER_COLOR_MAP = {
	2: Color("eabfff"), 4: Color("d6a4ff"), 8: Color("c18aff"), 16: Color("ac70ff"),
	32: Color("9757ff"), 64: Color("823eff"), 128: Color("6d24ff"), 256: Color("580aff"),
	512: Color("4300d1"), 1024: Color("3700ab"), 2048: Color("2b0085"), 4096: Color("1f0060")
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
	# 步骤 1: 更新内部状态变量。
	self.value = new_value
	self.type = new_type
	
	# 步骤 2: 更新显示的文本。
	value_label.text = str(value)
	
	# 步骤 3: 根据方块类型选择对应的颜色映射表。
	var current_color_map = PLAYER_COLOR_MAP
	if type == TileType.MONSTER:
		current_color_map = MONSTER_COLOR_MAP
	
	# 步骤 4: 设置背景颜色。
	# 如果当前数值在颜色映射表中存在，则使用预设颜色。
	if current_color_map.has(value):
		background.color = current_color_map[value]
	# 否则，使用默认的黑色作为后备，以应对未定义的超大数值。
	else:
		background.color = Color.BLACK
	
	# 步骤 5: 根据类型和数值优化文本颜色，以确保可读性。
	if type == TileType.PLAYER:
		# 对于数值较小的玩家方块，使用深色字体。
		if value <= 4:
			value_label.add_theme_color_override("font_color", Color("776e65"))
		# 对于数值较大的玩家方块，使用浅色字体。
		else:
			value_label.add_theme_color_override("font_color", Color("f9f6f2"))
	# 对于所有怪物方块，统一使用高对比度的白色字体。
	else:
		value_label.add_theme_color_override("font_color", Color("ffffff"))
