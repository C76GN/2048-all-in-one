# scripts/core/ui_manager.gd

## UIManager: 游戏内模态UI的中心化控制器。
##
## 该节点负责实例化、显示、隐藏和销毁所有模态UI元素（如暂停菜单、
## 游戏结束菜单等）。它通过一个专用的CanvasLayer来确保UI始终在游戏内容之上，
## 并通过动态管理节点的添加/移除，从根本上解决了process_mode和输入焦点的冲突问题。
class_name UIManager
extends Node

# --- 信号定义 ---
signal resume_requested
signal restart_requested(from_bookmark: bool)
signal main_menu_requested

# --- 预加载UI场景 ---
const PauseMenuScene = preload("res://scenes/ui/pause_menu.tscn")
const GameOverMenuScene = preload("res://scenes/ui/game_over_menu.tscn")

# --- 内部状态 ---
var _canvas_layer: CanvasLayer
var _current_ui: Control = null # 当前正在显示的UI控件

## Godot生命周期函数：当节点进入场景树时调用。
func _ready() -> void:
	# 创建一个CanvasLayer来承载所有UI，确保它们在最顶层。
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "UICanvasLayer"
	add_child(_canvas_layer)

# --- 公共接口 ---

## 显示暂停菜单。
func show_pause_menu() -> void:
	# 如果当前已有UI显示，则不执行任何操作。
	if is_instance_valid(_current_ui):
		return

	get_tree().paused = true
	_current_ui = PauseMenuScene.instantiate()
	_canvas_layer.add_child(_current_ui)
	
	# 连接新菜单实例的信号到处理函数
	_current_ui.resume_game.connect(_on_resume_requested)
	_current_ui.restart_game.connect(_on_restart_from_pause_menu)
	_current_ui.return_to_main_menu.connect(_on_main_menu_requested)

## 显示游戏结束菜单。
func show_game_over_menu() -> void:
	if is_instance_valid(_current_ui):
		return
	
	# 游戏结束时，树不需要暂停，因为游戏逻辑已经停止。
	_current_ui = GameOverMenuScene.instantiate()
	_canvas_layer.add_child(_current_ui)
	
	_current_ui.restart_game.connect(_on_restart_from_game_over)
	_current_ui.return_to_main_menu.connect(_on_main_menu_requested)

## 关闭当前显示的任何UI。
func close_current_ui() -> void:
	if is_instance_valid(_current_ui):
		_current_ui.queue_free()
		_current_ui = null
		get_tree().paused = false

# --- 信号处理函数 ---

func _on_resume_requested() -> void:
	close_current_ui()
	resume_requested.emit()

# 暂停菜单中的“重新开始”总是询问式的
func _on_restart_from_pause_menu() -> void:
	# 这里的逻辑将由GamePlay处理，UIManager只负责转发信号
	# 参数 true/false 在这里不重要，因为GamePlay会根据游戏状态判断
	restart_requested.emit(false) 

# 游戏结束菜单中的“重来”总是作为新游戏开始
func _on_restart_from_game_over() -> void:
	# 明确地将 from_bookmark 设为 false
	restart_requested.emit(false) 

func _on_main_menu_requested() -> void:
	# 在切换场景前，确保游戏状态恢复正常
	close_current_ui()
	main_menu_requested.emit()
