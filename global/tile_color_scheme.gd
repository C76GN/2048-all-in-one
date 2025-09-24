# global/tile_color_scheme.gd

## TileColorScheme: 定义了一套方块的颜色主题。
##
## 它包含一个颜色数组，代表了方块数值从小到大的颜色梯度。
class_name TileColorScheme
extends Resource

## 颜色数组，索引 0 对应最低阶的方块。
@export var colors: Array[Color] = []
