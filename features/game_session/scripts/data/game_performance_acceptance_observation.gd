## GamePerformanceAcceptanceObservation: 一次性能验收采样的脱敏运行条件。
##
## 本值对象只承载 GameplayAcceptanceMatrix 匹配所需的公开分类事实，不包含
## 设备身份、账号、棋盘内容、路径或原始输入事件。矩阵归 diagnostics Feature
## 所有；game_session 只持有已经由调用方验证的观测快照与采样生命周期。
class_name GamePerformanceAcceptanceObservation
extends RefCounted


# --- 公共变量 ---

var case_id: StringName = &""
var platform: StringName = &""
var input_modality: int = -1
var viewport_size: Vector2i = Vector2i.ZERO
var prefer_compact: bool = false
var board_bounds: Vector2i = Vector2i.ZERO
var active_cell_count: int = 0
var shape: StringName = &""
var vfx_quality: int = -1
var minimum_touch_target_px: float = 0.0
var minimum_samples: int = 0


# --- 公共方法 ---

## 从 GameplayAcceptanceMatrix 已规范化的条件构造只读采样快照。
## @param acceptance_case_id: 稳定验收用例 ID。
## @param observed_contract: 仅包含矩阵匹配所需字段的规范字典。
## @param required_samples: 两条指标各自需要的最少样本数。
func configure(
	acceptance_case_id: StringName,
	observed_contract: Dictionary,
	required_samples: int
) -> GamePerformanceAcceptanceObservation:
	case_id = acceptance_case_id
	platform = GFVariantData.get_option_string_name(
		observed_contract,
		&"platform"
	)
	input_modality = GFVariantData.get_option_int(
		observed_contract,
		&"input_modality",
		-1
	)
	viewport_size = Vector2i(
		GFVariantData.get_option_vector2(observed_contract, &"viewport_size")
	)
	prefer_compact = GFVariantData.get_option_bool(
		observed_contract,
		&"prefer_compact"
	)
	board_bounds = Vector2i(
		GFVariantData.get_option_vector2(observed_contract, &"board_bounds")
	)
	active_cell_count = GFVariantData.get_option_int(
		observed_contract,
		&"active_cell_count"
	)
	shape = GFVariantData.get_option_string_name(observed_contract, &"shape")
	vfx_quality = GFVariantData.get_option_int(
		observed_contract,
		&"vfx_quality",
		-1
	)
	minimum_touch_target_px = GFVariantData.get_option_float(
		observed_contract,
		&"minimum_touch_target_px"
	)
	minimum_samples = required_samples
	return self


## 判断本观测是否满足基础结构约束与样本预算。
## @param maximum_samples: 单项指标允许持有的最大样本数。
func is_structurally_valid(maximum_samples: int) -> bool:
	return (
		case_id != &""
		and platform != &""
		and input_modality >= 0
		and viewport_size.x > 0
		and viewport_size.y > 0
		and board_bounds.x > 0
		and board_bounds.y > 0
		and active_cell_count > 0
		and active_cell_count <= board_bounds.x * board_bounds.y
		and shape != &""
		and vfx_quality >= 0
		and minimum_touch_target_px >= 0.0
		and minimum_samples > 0
		and minimum_samples <= maximum_samples
	)


## 判断当前根视口尺寸是否仍与冻结的验收条件一致。
## @param observed_viewport_size: 当前玩家可见帧的根视口像素尺寸。
func matches_viewport(observed_viewport_size: Vector2i) -> bool:
	return observed_viewport_size == viewport_size


func to_dict() -> Dictionary:
	return {
		&"case_id": case_id,
		&"platform": platform,
		&"input_modality": input_modality,
		&"viewport_size": viewport_size,
		&"prefer_compact": prefer_compact,
		&"board_bounds": board_bounds,
		&"active_cell_count": active_cell_count,
		&"shape": shape,
		&"vfx_quality": vfx_quality,
		&"minimum_touch_target_px": minimum_touch_target_px,
		&"minimum_samples": minimum_samples,
	}
