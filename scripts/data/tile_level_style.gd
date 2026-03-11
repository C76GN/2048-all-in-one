# scripts/global/tile_level_style.gd

## TileLevelStyle: 定义了单个方块等级的完整视觉样式。
##
## 它将背景颜色和字体颜色绑定在一起，确保了视觉上的一致性。
class_name TileLevelStyle
extends Resource


# --- 导出变量 ---

## 方块的背景颜色。
@export var background_color: Color = Color.WHITE

## 方块上数值文本的颜色。
@export var font_color: Color = Color.BLACK
