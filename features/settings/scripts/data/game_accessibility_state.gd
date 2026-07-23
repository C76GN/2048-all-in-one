## GameAccessibilityState: 玩家无障碍与表现质量偏好的只读快照。
class_name GameAccessibilityState
extends RefCounted


# --- 枚举 ---

enum VfxQuality {
	MINIMAL,
	REDUCED,
	FULL,
}


# --- 常量 ---

const REDUCED_MOTION_SETTING_KEY: StringName = &"accessibility/reduced_motion"
const HIGH_CONTRAST_FEEDBACK_SETTING_KEY: StringName = &"accessibility/high_contrast_feedback"
const HAPTICS_ENABLED_SETTING_KEY: StringName = &"accessibility/haptics_enabled"
const SHADER_EFFECTS_ENABLED_SETTING_KEY: StringName = &"accessibility/shader_effects_enabled"
const VFX_QUALITY_SETTING_KEY: StringName = &"accessibility/vfx_quality"


# --- 公共变量 ---

var reduced_motion: bool = false
var high_contrast_feedback: bool = false
var haptics_enabled: bool = true
var shader_effects_enabled: bool = true
var vfx_quality: VfxQuality = VfxQuality.FULL


# --- 公共方法 ---

func duplicate_state() -> GameAccessibilityState:
	var result: GameAccessibilityState = GameAccessibilityState.new()
	result.reduced_motion = reduced_motion
	result.high_contrast_feedback = high_contrast_feedback
	result.haptics_enabled = haptics_enabled
	result.shader_effects_enabled = shader_effects_enabled
	result.vfx_quality = vfx_quality
	return result


func is_valid_state() -> bool:
	return vfx_quality >= VfxQuality.MINIMAL and vfx_quality <= VfxQuality.FULL


## 把持久化整数收窄为当前支持的 VFX 枚举。
## @param value: 任意外部整数值。
static func normalize_vfx_quality(value: int) -> VfxQuality:
	match clampi(value, VfxQuality.MINIMAL, VfxQuality.FULL):
		VfxQuality.MINIMAL:
			return VfxQuality.MINIMAL
		VfxQuality.REDUCED:
			return VfxQuality.REDUCED
		_:
			return VfxQuality.FULL
