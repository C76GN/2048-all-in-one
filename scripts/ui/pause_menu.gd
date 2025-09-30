# scripts/ui/pause_menu.gd

## PauseMenu: 游戏内暂停菜单的UI控制器。
##
## 负责处理暂停菜单的显示/隐藏，以及响应各个按钮的点击事件。
## 它通过信号与主游戏场景通信，以执行继续、重启等操作。
extends Control

# --- 信号定义 ---

## 当玩家请求继续游戏时发出。
signal resume_game
## 当玩家确认要重新开始游戏时发出。
signal restart_game
## 当玩家请求返回主菜单时发出。
signal return_to_main_menu

# --- 节点引用 ---

@onready var continue_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/ContinueButton
@onready var restart_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $CanvasLayer/CenterContainer/VBoxContainer/MainMenuButton
@onready var restart_confirm_dialog: ConfirmationDialog = $CanvasLayer/RestartConfirmDialog

func _ready() -> void:
	# 将处理模式设置为“暂停时处理”，以确保菜单在游戏暂停时仍可交互。
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# 连接按钮信号
	continue_button.pressed.connect(func(): resume_game.emit())
	restart_button.pressed.connect(func(): restart_game.emit())
	main_menu_button.pressed.connect(func(): return_to_main_menu.emit())
