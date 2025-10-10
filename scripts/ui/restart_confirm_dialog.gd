# scripts/ui/restart_confirm_dialog.gd

## RestartConfirmDialog: 一个专用于处理游戏重启选择的对话框。
##
## 该对话框封装了自身的显示逻辑和用户选择。它不执行任何游戏逻辑，
## 而是通过发出明确的信号来通知外部监听者（如GamePlay）用户的最终决定。
## 这种设计使得该组件是自包含和可复用的。
class_name RestartConfirmDialog
extends ConfirmationDialog

## 当用户选择“从书签位置重启”时发出。
signal restart_from_bookmark
## 当用户选择“作为新游戏重启”时发出。
signal restart_as_new_game

## 当对话框被用户以“取消”的方式关闭时（如按Esc或点击窗口关闭按钮）发出。
signal dismissed

func _ready() -> void:
	
	# 1. 获取OK按钮（“从书签重启”），连接其 pressed 信号。
	get_ok_button().pressed.connect(func(): 
		restart_from_bookmark.emit()
		hide() 
	)
	
	# 2. 获取Cancel按钮（“作为新游戏重启”），连接其 pressed 信号。
	get_cancel_button().pressed.connect(func(): 
		restart_as_new_game.emit()
		hide()
	)
	
	# 3. 连接窗口的关闭请求（点击'X'按钮），将其视为“取消”操作。
	close_requested.connect(func(): 
		dismissed.emit()
	)
	
	# 4. 捕获 visibility_changed 信号来处理 Esc 键。
	visibility_changed.connect(_on_visibility_changed)

## 当对话框的可见性改变时调用。用它来捕获 Esc 键的按下。
func _on_visibility_changed() -> void:
	if not visible and is_inside_tree():
		# 检查OK和Cancel按钮是否都没有被按下。
		if not get_ok_button().is_pressed() and not get_cancel_button().is_pressed():
			dismissed.emit()
