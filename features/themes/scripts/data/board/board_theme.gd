## BoardTheme: 定义游戏棋盘与背景的稳定渲染契约。
##
## 这个资源将所有非方块的全局颜色配置集中管理，方便实现整体的视觉风格切换。
class_name BoardTheme
extends Resource


# --- 导出变量 ---

## 整个游戏画面的主背景颜色。
@export var game_background_color: Color = Color.BLACK

## 棋盘区域的底板颜色。
@export var board_panel_color: Color = Color.GRAY

## 棋盘外框和格子缝隙的描边颜色。
@export var board_border_color: Color = Color.BLACK

## 棋盘左上内高光颜色。
@export var board_highlight_color: Color = Color.WHITE

## 棋盘上空格子（未放置方块处）的颜色。
@export var empty_cell_color: Color = Color.DARK_GRAY

## 棋盘上空格子的描边颜色。
@export var empty_cell_border_color: Color = Color.BLACK

## 静态板框几何由主题统一投影到游戏与预览，切换主题时不改棋盘布局。
@export_range(0, 24, 1) var board_corner_radius: int = 12
@export_range(0, 4, 1) var board_border_width: int = 1
@export_range(0, 16, 1) var empty_cell_corner_radius: int = 6
@export_range(0, 4, 1) var empty_cell_border_width: int = 1
