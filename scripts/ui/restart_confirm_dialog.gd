# scripts/ui/restart_confirm_dialog.gd

## RestartConfirmDialog: 一个专用于处理游戏重启选择的对话框。
##
## 该对话框封装了自身的显示逻辑和用户选择。它不执行任何游戏逻辑，
## 而是通过发出明确的信号来通知外部监听者（如GamePlay）用户的最终决定。
## 这种设计使得该组件是自包含和可复用的。
class_name RestartConfirmDialog
extends ConfirmationDialog


# --- 信号 ---

## 当用户选择“从书签位置重启”时发出。
signal restart_from_bookmark

## 当用户选择“作为新游戏重启”时发出。
signal restart_as_new_game

## 当对话框被用户以“取消”的方式关闭时（如按Esc或点击窗口关闭按钮）发出。
signal dismissed


# --- Godot 生命周期方法 ---

func _ready() -> void:
	# 连接内置按钮和事件到具名处理函数
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	close_requested.connect(_on_close_requested)


# --- 私有/辅助方法 ---

## 检查对话框是否因非按钮操作（如按Esc）而关闭。
func _check_for_dismissal() -> void:
	# 如果对话框变得不可见，且不是通过点击OK或Cancel按钮触发的，
	# 那么就认为是用户“取消”了操作。
	if not visible and is_inside_tree():
		if not get_ok_button().is_pressed() and not get_cancel_button().is_pressed():
			dismissed.emit()


# --- 信号处理函数 ---

## 当OK按钮（“从书签位置重启”）被按下时调用。
func _on_confirmed() -> void:
	restart_from_bookmark.emit()


## 当Cancel按钮（“作为新游戏重启”）被按下时调用。
func _on_canceled() -> void:
	restart_as_new_game.emit()


## 当用户点击窗口的关闭按钮('X')时调用。
func _on_close_requested() -> void:
	dismissed.emit()
