# scripts/ui/mode_selection.gd

## ModeSelection: 模式选择界面的脚本，处理不同游戏模式的启动和返回主菜单。
extends Control

# --- 节点引用 ---
@onready var test_mode_1_button: Button = %TestMode1Button
@onready var test_mode_2_button: Button = %TestMode2Button
@onready var back_button: Button = %BackButton

func _ready() -> void:
	# 连接按钮的 pressed 信号
	test_mode_1_button.pressed.connect(_on_test_mode_1_button_pressed)
	test_mode_2_button.pressed.connect(_on_test_mode_2_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

# --- 信号处理函数 ---

## 当“测试1”按钮被按下时调用。
func _on_test_mode_1_button_pressed() -> void:
	# 通过全局游戏管理器切换到第一个测试模式场景
	GlobalGameManager.goto_scene("res://scenes/modes/test_mode_1.tscn")

## 当“测试2”按钮被按下时调用（占位功能）。
func _on_test_mode_2_button_pressed() -> void:
	print("测试模式2按钮被按下 (功能待开发)")
	# TODO: 未来在这里实现其他2048变种模式的切换逻辑
	pass # 占位

## 当“返回”按钮被按下时调用。
func _on_back_button_pressed() -> void:
	# 通过全局游戏管理器返回主菜单场景
	GlobalGameManager.goto_scene("res://scenes/main_menu.tscn")
