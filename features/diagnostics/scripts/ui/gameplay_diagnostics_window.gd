## GameplayDiagnosticsWindow: 与玩家画面分离的对局诊断工作区窗口。
class_name GameplayDiagnosticsWindow
extends Window


# --- 常量 ---

const DEFAULT_SIZE: Vector2i = Vector2i(390, 560)
const MINIMUM_SIZE: Vector2i = Vector2i(340, 480)


# --- Godot 生命周期方法 ---

func _init() -> void:
	title = "2048 对局实验台"
	size = DEFAULT_SIZE
	min_size = MINIMUM_SIZE
	transient = false
	exclusive = false
	wrap_controls = true
	visible = false


# --- 公共方法 ---

## 显示并居中独立工作区。
func popup_workspace() -> void:
	if size.x <= 0 or size.y <= 0:
		size = DEFAULT_SIZE
	popup_centered(size)


## 隐藏工作区但保留当前对局上下文。
func hide_workspace() -> void:
	hide()


## 返回窗口内的规则驱动测试面板。
func get_test_panel() -> TestPanel:
	var node_value: Node = get_node_or_null("Panel/Margin/TestPanel")
	if node_value is TestPanel:
		var panel: TestPanel = node_value
		return panel
	return null
