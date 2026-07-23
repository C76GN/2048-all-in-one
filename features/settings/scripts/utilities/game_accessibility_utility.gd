## GameAccessibilityUtility: 通过 GFSettingsUtility 维护无障碍偏好的单一运行时状态。
class_name GameAccessibilityUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal state_changed(state: GameAccessibilityState)


# --- 常量 ---

const REDUCED_MOTION_SETTING_KEY: StringName = GameAccessibilityState.REDUCED_MOTION_SETTING_KEY
const HIGH_CONTRAST_FEEDBACK_SETTING_KEY: StringName = GameAccessibilityState.HIGH_CONTRAST_FEEDBACK_SETTING_KEY
const HAPTICS_ENABLED_SETTING_KEY: StringName = GameAccessibilityState.HAPTICS_ENABLED_SETTING_KEY
const SHADER_EFFECTS_ENABLED_SETTING_KEY: StringName = GameAccessibilityState.SHADER_EFFECTS_ENABLED_SETTING_KEY
const VFX_QUALITY_SETTING_KEY: StringName = GameAccessibilityState.VFX_QUALITY_SETTING_KEY


# --- 私有变量 ---

var _settings: GFSettingsUtility = null
var _signal_utility: GFSignalUtility = null
var _state: GameAccessibilityState = GameAccessibilityState.new()


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFSettingsUtility, GFSignalUtility]


func ready() -> void:
	_settings = _get_settings_utility()
	_signal_utility = _get_signal_utility()
	_refresh_state(false)
	if is_instance_valid(_settings) and is_instance_valid(_signal_utility):
		var _connection: GFSignalConnection = _signal_utility.connect_signal(
			_settings.setting_changed,
			Callable(self, &"_on_setting_changed"),
			self
		)


func dispose() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_settings = null
	_signal_utility = null
	_state = GameAccessibilityState.new()


# --- 公共方法 ---

func get_state() -> GameAccessibilityState:
	return _state.duplicate_state()


## 设置是否减少动态效果。
## @param enabled: `true` 时所有表现消费者使用静态或零位移路径。
func set_reduced_motion(enabled: bool) -> void:
	_set_value(REDUCED_MOTION_SETTING_KEY, enabled)


## 设置是否使用高对比反馈色。
## @param enabled: `true` 时 recipe 使用高对比颜色和轮廓。
func set_high_contrast_feedback(enabled: bool) -> void:
	_set_value(HIGH_CONTRAST_FEEDBACK_SETTING_KEY, enabled)


## 设置设备触觉是否可用。
## @param enabled: `false` 时不提交 GF Haptic 请求。
func set_haptics_enabled(enabled: bool) -> void:
	_set_value(HAPTICS_ENABLED_SETTING_KEY, enabled)


## 设置可选 Shader 表现是否可用。
## @param enabled: `false` 时使用静态视觉降级。
func set_shader_effects_enabled(enabled: bool) -> void:
	_set_value(SHADER_EFFECTS_ENABLED_SETTING_KEY, enabled)


## 设置统一 VFX 质量档位。
## @param quality: `GameAccessibilityState.VfxQuality` 对应的持久化整数。
func set_vfx_quality(quality: int) -> void:
	_set_value(
		VFX_QUALITY_SETTING_KEY,
		GameAccessibilityState.normalize_vfx_quality(quality)
	)


# --- 私有/辅助方法 ---

func _set_value(key: StringName, value: Variant) -> void:
	if not is_instance_valid(_settings):
		return
	_settings.set_value(key, value)


func _on_setting_changed(key: StringName, _old_value: Variant, _new_value: Variant) -> void:
	if not _is_accessibility_key(key):
		return
	_refresh_state(true)


func _refresh_state(emit_change: bool) -> void:
	var next_state: GameAccessibilityState = GameAccessibilityState.new()
	if is_instance_valid(_settings):
		next_state.reduced_motion = GFVariantData.to_bool(
			_settings.get_value(REDUCED_MOTION_SETTING_KEY, false),
			false
		)
		next_state.high_contrast_feedback = GFVariantData.to_bool(
			_settings.get_value(HIGH_CONTRAST_FEEDBACK_SETTING_KEY, false),
			false
		)
		next_state.haptics_enabled = GFVariantData.to_bool(
			_settings.get_value(HAPTICS_ENABLED_SETTING_KEY, true),
			true
		)
		next_state.shader_effects_enabled = GFVariantData.to_bool(
			_settings.get_value(SHADER_EFFECTS_ENABLED_SETTING_KEY, true),
			true
		)
		next_state.vfx_quality = GameAccessibilityState.normalize_vfx_quality(
			GFVariantData.to_int(
				_settings.get_value(
					VFX_QUALITY_SETTING_KEY,
					GameAccessibilityState.VfxQuality.FULL
				),
				GameAccessibilityState.VfxQuality.FULL
			)
		)
	_state = next_state
	if emit_change:
		state_changed.emit(get_state())


func _is_accessibility_key(key: StringName) -> bool:
	return key in [
		REDUCED_MOTION_SETTING_KEY,
		HIGH_CONTRAST_FEEDBACK_SETTING_KEY,
		HAPTICS_ENABLED_SETTING_KEY,
		SHADER_EFFECTS_ENABLED_SETTING_KEY,
		VFX_QUALITY_SETTING_KEY,
	]


func _get_settings_utility() -> GFSettingsUtility:
	var value: Object = get_utility(GFSettingsUtility)
	return value if value is GFSettingsUtility else null


func _get_signal_utility() -> GFSignalUtility:
	var value: Object = get_utility(GFSignalUtility)
	return value if value is GFSignalUtility else null
