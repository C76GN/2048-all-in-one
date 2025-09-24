# scripts/ui/mode_selection.gd

## ModeSelection: 模式选择界面的UI控制器。
##
## 该脚本负责处理用户在模式选择界面的交互，
## 如选择一个游戏模式或返回主菜单。它通过调用 GlobalGameManager 来执行场景切换。
extends Control

# --- 节点引用 ---

## 对场景中各个按钮节点的引用（使用唯一名称%）。
@onready var test_mode_1_button: Button = %TestMode1Button
@onready var test_mode_2_button: Button = %TestMode2Button
@onready var classic_mode_button: Button = %ClassicModeButton
@onready var fibonacci_mode_button: Button = %FibonacciModeButton
@onready var back_button: Button = %BackButton


## Godot生命周期函数：当节点及其子节点进入场景树时调用。
func _ready() -> void:
	# 在此连接所有按钮的 `pressed` 信号到对应的处理函数，
	# 以响应用户的点击操作。
	test_mode_1_button.pressed.connect(_on_test_mode_1_button_pressed)
	test_mode_2_button.pressed.connect(_on_test_mode_2_button_pressed)
	classic_mode_button.pressed.connect(_on_classic_mode_button_pressed)
	fibonacci_mode_button.pressed.connect(_on_fibonacci_mode_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

# --- 信号处理函数 ---
# 以下函数在对应的按钮被按下时由信号触发。

## 响应“测试模式1”按钮的点击事件。
func _on_test_mode_1_button_pressed() -> void:
	# 设置要加载的模式配置文件路径
	GlobalGameManager.selected_mode_config_path = "res://scenes/modes/test_mode1_config.tres"
	# 委托全局管理器切换到通用的游戏场景。
	GlobalGameManager.goto_scene("res://scenes/modes/game_play.tscn")

## 响应“测试模式2”按钮的点击事件（占位功能）。
func _on_test_mode_2_button_pressed() -> void:
	print("测试模式2按钮被按下 (功能待开发)")
	# TODO: 未来在此处实现其他2048变种模式的切换逻辑。

## 响应“经典模式”按钮的点击事件。
func _on_classic_mode_button_pressed() -> void:
	# 设置要加载的模式配置文件路径
	GlobalGameManager.selected_mode_config_path = "res://scenes/modes/classic_mode_config.tres"
	# 委托全局管理器切换到通用的游戏场景。
	GlobalGameManager.goto_scene("res://scenes/modes/game_play.tscn")

## 响应“斐波那契模式”按钮的点击事件。
func _on_fibonacci_mode_button_pressed() -> void:
	# 设置要加载的模式配置文件路径
	GlobalGameManager.selected_mode_config_path = "res://scenes/modes/fibonacci_mode_config.tres"
	# 委托全局管理器切换到通用的游戏场景。
	GlobalGameManager.goto_scene("res://scenes/modes/game_play.tscn")

## 响应“返回”按钮的点击事件。
func _on_back_button_pressed() -> void:
	# 委托全局管理器返回主菜单场景。
	GlobalGameManager.goto_scene("res://scenes/main_menu.tscn")
