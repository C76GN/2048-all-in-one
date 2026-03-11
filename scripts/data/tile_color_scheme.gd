# scripts/global/tile_color_scheme.gd

## TileColorScheme: 定义了一套方块的颜色主题。
##
## 它包含一个样式数组，代表了方块数值从小到大的视觉表现梯度。
## 每个样式都包含了背景色和字体色。
class_name TileColorScheme
extends Resource


# --- 导出变量 ---

## 样式数组，索引 0 对应最低阶的方块。
@export var styles: Array[TileLevelStyle] = []
