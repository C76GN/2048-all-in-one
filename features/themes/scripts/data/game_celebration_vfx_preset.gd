## GameCelebrationVfxPreset: 定义单个庆祝事件的时长、透明度和 Shader 参数覆盖。
class_name GameCelebrationVfxPreset
extends Resource


# --- 导出变量 ---

@export_range(0.05, 10.0, 0.01) var duration: float = 1.5
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.8
@export var loop_until_dismissed: bool = false
@export var shader_parameters: Dictionary = {}


# --- 公共方法 ---

## 返回隔离于资源原值的 Shader 参数覆盖。
func get_shader_parameters() -> Dictionary:
	return shader_parameters.duplicate(true)
