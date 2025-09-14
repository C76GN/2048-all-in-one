# tile.gd
# (升级版，支持玩家和怪物类型)
extends Control

# 新增：定义方块类型
enum TileType { PLAYER, MONSTER }

# --- 常量定义 ---
const PLAYER_COLOR_MAP = {
	2: Color("eee4da"), 4: Color("ede0c8"), 8: Color("f2b179"), 16: Color("f59563"),
	32: Color("f67c5f"), 64: Color("f65e3b"), 128: Color("edcf72"), 256: Color("edcc61"),
	512: Color("edc850"), 1024: Color("edc53f"), 2048: Color("edc22e"), 4096: Color("3c3a32")
}
# 新增：为怪物设计的专属颜色
const MONSTER_COLOR_MAP = {
	2: Color("eabfff"), 4: Color("d6a4ff"), 8: Color("c18aff"), 16: Color("ac70ff"),
	32: Color("9757ff"), 64: Color("823eff"), 128: Color("6d24ff"), 256: Color("580aff"),
	512: Color("4300d1"), 1024: Color("3700ab"), 2048: Color("2b0085"), 4096: Color("1f0060")
}

# --- 节点引用 ---
@onready var background: ColorRect = $Background
@onready var value_label: Label = $ValueLabel

# --- 变量 ---
var value: int = 0
var type: TileType = TileType.PLAYER # 默认为玩家方块

# 旧的 set_value 已被新的 setup 函数替代
# 新的 setup 函数更强大，可以同时设置数值和类型
func setup(new_value: int, new_type: TileType) -> void:
	self.value = new_value
	self.type = new_type
	
	value_label.text = str(value)
	
	var current_color_map = PLAYER_COLOR_MAP
	if type == TileType.MONSTER:
		current_color_map = MONSTER_COLOR_MAP
	
	# 根据数值从对应的颜色 MAP 中查找颜色
	if current_color_map.has(value):
		background.color = current_color_map[value]
	else:
		background.color = Color.BLACK
	
	# 根据类型和数值优化文本颜色
	if type == TileType.PLAYER:
		if value <= 4:
			value_label.add_theme_color_override("font_color", Color("776e65"))
		else:
			value_label.add_theme_color_override("font_color", Color("f9f6f2"))
	else: # 怪物方块统一使用高亮的白色字体
		value_label.add_theme_color_override("font_color", Color("ffffff"))
