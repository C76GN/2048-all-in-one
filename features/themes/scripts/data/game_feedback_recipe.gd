## GameFeedbackRecipe: 一个语义反馈事件的完整数据配方。
class_name GameFeedbackRecipe
extends Resource


# --- 导出变量 ---

@export var recipe_id: StringName = &""
@export var accent_color: Color = Color.WHITE
@export var high_contrast_color: Color = Color(0.12, 0.13, 0.15, 1.0)
@export var shake_preset: GFShakePreset
@export var haptic_preset: GFHapticPreset
@export_range(0.0, 64.0, 0.1) var root_impulse: float = 8.0
@export_range(0.0, 12.0, 0.1) var root_rotation_degrees: float = 1.6
@export_range(0.0, 0.2, 0.001) var root_compression: float = 0.025
@export_range(0.01, 1.0, 0.001) var impact_duration: float = 0.055
@export_range(0.01, 2.0, 0.001) var settle_duration: float = 0.15
@export_range(0.01, 3.0, 0.001) var background_duration: float = 0.325
@export_range(0.0, 1.0, 0.01) var background_energy: float = 0.38
@export_range(0, 32, 1) var edge_fragment_count: int = 5
@export_range(0.01, 2.0, 0.001) var tile_burst_duration: float = 0.30
@export_range(0, 24, 1) var tile_shard_count: int = 4


# --- 公共方法 ---

## 获取普通或高对比模式的语义强调色。
## @param high_contrast: 是否请求高对比反馈色。
func get_color(high_contrast: bool) -> Color:
	return high_contrast_color if high_contrast else accent_color


func is_valid_recipe() -> bool:
	return (
		recipe_id != &""
		and accent_color.a > 0.0
		and high_contrast_color.a > 0.0
		and impact_duration > 0.0
		and settle_duration > 0.0
		and background_duration > 0.0
		and tile_burst_duration > 0.0
		and edge_fragment_count >= 0
		and tile_shard_count >= 0
	)
