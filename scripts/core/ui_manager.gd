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

# --- 枚举定义 ---

## 定义了可以被 UIManager 管理的UI类型。
enum UIType {
	PAUSE,
	GAME_OVER,
	# 未来可以添加更多，如 SETTINGS, ACHIEVEMENTS 等
}

# --- 导出变量 ---

## 在编辑器中配置每种UI类型对应的场景资源。
@export var ui_scenes: Dictionary = {}

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

## 显示指定类型的模态UI。
## @param ui_type: 要显示的UI类型的枚举值 (UIManager.UIType)。
func show_ui(ui_type: UIType) -> void:
	# 如果当前已有UI显示，或请求的类型未配置，则不执行任何操作。
	if is_instance_valid(_current_ui) or not ui_scenes.has(ui_type):
		return

	var ui_scene: PackedScene = ui_scenes[ui_type]
	if not is_instance_valid(ui_scene):
		push_error("UIManager: UI类型 '%s' 配置的场景无效。" % UIType.keys()[ui_type])
		return

	# 根据UI类型执行特定逻辑
	match ui_type:
		UIType.PAUSE:
			get_tree().paused = true
		UIType.GAME_OVER:
			# 游戏结束时，树不需要暂停，因为游戏逻辑已经停止。
			pass

	_current_ui = ui_scene.instantiate()
	_canvas_layer.add_child(_current_ui)

	# 连接新菜单实例可能发出的所有信号到处理函数
	# 即使菜单没有某个信号，也不会报错
	if _current_ui.has_signal("resume_game"):
		_current_ui.resume_game.connect(_on_resume_requested)
	if _current_ui.has_signal("restart_game"):
		# 根据UI类型连接到不同的重启处理逻辑
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
