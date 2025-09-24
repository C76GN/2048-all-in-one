# global/board_theme.gd

## BoardTheme: 定义了游戏棋盘和背景的颜色主题。
##
## 这个资源将所有非方块的全局颜色配置集中管理，方便实现整体的视觉风格切换。
class_name BoardTheme
extends Resource

## 整个游戏画面的主背景颜色。
@export var game_background_color: Color = Color.BLACK

## 棋盘区域的底板颜色。
@export var board_panel_color: Color = Color.GRAY

## 棋盘上空格子（未放置方块处）的颜色。
@export var empty_cell_color: Color = Color.DARK_GRAY
