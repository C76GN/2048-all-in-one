# scripts/core/ui_manager.gd

## UIManager: 游戏内模态UI的中心化控制器。
##
## 该节点负责实例化、显示、隐藏和销毁所有模态UI元素（如暂停菜单、
## 游戏结束菜单等）。它通过一个专用的CanvasLayer来确保UI始终在游戏内容之上，
## 并通过动态管理节点的添加/移除，从根本上解决了process_mode和输入焦点的冲突问题。
class_name UIManager
extends Node


# --- 信号 ---

## 当玩家请求继续游戏时发出。
signal resume_requested

## 当玩家请求重新开始游戏时发出。
## @param from_bookmark: 指示是否应从书签重启。
signal restart_requested(from_bookmark: bool)

## 当玩家请求返回主菜单时发出。
signal main_menu_requested


# --- 枚举 ---

## 定义了可以被 UIManager 管理的UI类型。
enum UIType {
	## 暂停菜单
	PAUSE,
	## 游戏结束菜单
	GAME_OVER,
}


# --- 导出变量 ---

## 在编辑器中配置每种UI类型对应的场景资源。
@export var ui_scenes: Dictionary = {}


# --- 私有变量 ---

## 用于承载所有UI的CanvasLayer，确保它们在最顶层。
var _canvas_layer: CanvasLayer

## 对当前正在显示的UI控件的引用。
var _current_ui: Control = null


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "UICanvasLayer"
	add_child(_canvas_layer)


# --- 公共方法 ---

## 显示指定类型的模态UI。
## @param ui_type: 要显示的UI类型的枚举值 (UIManager.UIType)。
func show_ui(ui_type: UIType) -> void:
	if is_instance_valid(_current_ui) or not ui_scenes.has(ui_type):
		return

	var ui_scene: PackedScene = ui_scenes[ui_type]

	if not is_instance_valid(ui_scene):
		push_error("UIManager: UI类型 '%s' 配置的场景无效。" % UIType.keys()[ui_type])
		return

	match ui_type:
		UIType.PAUSE:
			get_tree().paused = true
		UIType.GAME_OVER:
			pass

	_current_ui = ui_scene.instantiate()
	_canvas_layer.add_child(_current_ui)

	if _current_ui.has_signal("resume_game"):
		_current_ui.resume_game.connect(_on_resume_requested)

	if _current_ui.has_signal("restart_game"):
		if ui_type == UIType.PAUSE:
			_current_ui.restart_game.connect(_on_restart_from_pause_menu)
		elif ui_type == UIType.GAME_OVER:
			_current_ui.restart_game.connect(_on_restart_from_game_over)

	if _current_ui.has_signal("return_to_main_menu"):
		_current_ui.return_to_main_menu.connect(_on_main_menu_requested)


## 关闭当前显示的任何UI。
func close_current_ui() -> void:
	if is_instance_valid(_current_ui):
		_current_ui.queue_free()
		_current_ui = null
		get_tree().paused = false


# --- 信号处理函数 ---

## 当玩家请求继续游戏时调用。
func _on_resume_requested() -> void:
	close_current_ui()
	resume_requested.emit()


## 当玩家从暂停菜单请求重新开始游戏时调用。
func _on_restart_from_pause_menu() -> void:
	restart_requested.emit(false)


## 当玩家从游戏结束菜单请求重新开始游戏时调用。
func _on_restart_from_game_over() -> void:
	restart_requested.emit(false)


## 当玩家请求返回主菜单时调用。
func _on_main_menu_requested() -> void:
	close_current_ui()
	main_menu_requested.emit()
