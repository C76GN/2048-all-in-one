## GameCelebrationVfxPreset: 定义单个庆祝事件的时长、透明度和粒子表现参数。
class_name GameCelebrationVfxPreset
extends Resource


# --- 导出变量 ---

@export_range(0.05, 10.0, 0.01) var duration: float = 1.5
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.8
@export var loop_until_dismissed: bool = false
@export var fallback_color: Color = Color(0.8745, 0.6902, 0.3020, 0.16)
@export var shader_parameters: Dictionary = {}


# --- 公共方法 ---

## 返回隔离于资源原值的表现参数。
## 字段名为兼容已有主题资源保留，当前由有界粒子发射器消费。
func get_shader_parameters() -> Dictionary:
	return shader_parameters.duplicate(true)
