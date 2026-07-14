## TestArchitectureContext: 为依赖 GFNodeContext 的 UI 测试提供显式架构上下文。
class_name TestArchitectureContext
extends GFNodeContext


# --- 公共变量 ---

var test_architecture: GFArchitecture


# --- Godot 生命周期方法 ---

func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	test_architecture = null


# --- 公共方法 ---

func get_architecture() -> GFArchitecture:
	return test_architecture
