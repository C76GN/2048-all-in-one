## GameSettingsUtility: 项目设置定义入口。
class_name GameSettingsUtility
extends "res://addons/gf/standard/utilities/settings/gf_settings_utility.gd"


# --- 常量 ---

const DEFAULT_LOCALE: String = "zh"
const AUDIO_BUS_MASTER: String = "Master"


# --- 私有变量 ---

var _storage_recovery_pending: bool = false
var _last_storage_recovery: Dictionary = {}
var _persistence_blocked_error: Error = OK


# --- GF 生命周期方法 ---

func init() -> void:
	super.init()
	if not _storage_recovery_pending:
		return
	var recreate_error: Error = save_settings()
	_last_storage_recovery["ok"] = recreate_error == OK
	_last_storage_recovery["recovered"] = recreate_error == OK
	_last_storage_recovery["recreate_error_code"] = recreate_error
	_last_storage_recovery["persistence_blocked"] = recreate_error != OK
	_storage_recovery_pending = false
	_persistence_blocked_error = recreate_error
	if recreate_error != OK:
		push_error(
			"[GameSettingsUtility] 无法按当前 GFStorage 格式重建设置，错误码：%d。"
			% recreate_error
		)


# --- 公共方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFStorageUtility]


## 返回最近一次设置物理存储恢复诊断。
func get_storage_recovery_snapshot() -> Dictionary:
	return _last_storage_recovery.duplicate(true)


## 注册项目设置定义。
func register_project_defaults() -> void:
	var _locale_setting: GFSettingDefinition = register_setting(
		GFDisplaySettingsUtility.LOCALE_KEY,
		DEFAULT_LOCALE,
		GFSettingDefinition.ValueType.STRING,
		true,
		{"group": "language", "label": "LANGUAGE_LABEL"}
	)
	var _master_volume_setting: GFSettingDefinition = register_setting(
		StringName("audio/%s/volume" % AUDIO_BUS_MASTER),
		1.0,
		GFSettingDefinition.ValueType.FLOAT,
		true,
		{"group": "audio", "label": "MASTER_VOLUME_LABEL"}
	)
	var _visual_theme_setting: GFSettingDefinition = register_setting(
		GameThemeUtility.VISUAL_THEME_SETTING_KEY,
		GameThemeUtility.DEFAULT_THEME_ID,
		GFSettingDefinition.ValueType.STRING_NAME,
		true,
		{"group": "appearance", "label": "VISUAL_THEME_LABEL"}
	)
	var _sound_theme_setting: GFSettingDefinition = register_setting(
		GameThemeUtility.SOUND_THEME_SETTING_KEY,
		GameThemeUtility.DEFAULT_SOUND_THEME_ID,
		GFSettingDefinition.ValueType.STRING_NAME,
		true,
		{"group": "audio", "label": "SOUND_THEME_LABEL"}
	)
	var _input_remap_setting: GFSettingDefinition = register_setting(
		GameInputProfileUtility.INPUT_REMAP_SETTING_KEY,
		{
			"remapped_events": {},
			"custom_data": {},
		},
		GFSettingDefinition.ValueType.DICTIONARY,
		true,
		{"group": "input", "label": "INPUT_BINDINGS_TITLE"}
	)
	var _input_timing_setting: GFSettingDefinition = register_setting(
		GameInputProfileUtility.INPUT_TIMING_SETTING_KEY,
		GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET,
		GFSettingDefinition.ValueType.INT,
		true,
		{"group": "input", "label": "INPUT_TIMING_MODE_LABEL"}
	)
	var _reduced_motion_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.REDUCED_MOTION_SETTING_KEY,
		false,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "REDUCED_MOTION_LABEL"}
	)
	var _high_contrast_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.HIGH_CONTRAST_FEEDBACK_SETTING_KEY,
		false,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "HIGH_CONTRAST_FEEDBACK_LABEL"}
	)
	var _haptics_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.HAPTICS_ENABLED_SETTING_KEY,
		true,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "HAPTICS_ENABLED_LABEL"}
	)
	var _shader_effects_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.SHADER_EFFECTS_ENABLED_SETTING_KEY,
		true,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "SHADER_EFFECTS_LABEL"}
	)
	var _vfx_quality_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.VFX_QUALITY_SETTING_KEY,
		GameAccessibilityState.VfxQuality.FULL,
		GFSettingDefinition.ValueType.INT,
		true,
		{"group": "accessibility", "label": "VFX_QUALITY_LABEL"}
	)


# --- 可重写钩子 ---

func _read_persisted_data(file_name: String) -> Dictionary:
	var storage: GFStorageUtility = _get_storage_utility()
	if storage == null:
		return super._read_persisted_data(file_name)

	var read_result: GFStorageReadResult = storage.load_data(file_name)
	if read_result.ok:
		_last_storage_recovery.clear()
		_persistence_blocked_error = OK
		return read_result.payload.duplicate(true)
	if read_result.error_code == ERR_FILE_NOT_FOUND:
		_last_storage_recovery.clear()
		_persistence_blocked_error = OK
		return {}
	if not ProjectStorageRecoveryPolicy.should_reset_failed_read(read_result):
		_persistence_blocked_error = (
			read_result.error_code
			if read_result.error_code != OK
			else ERR_INVALID_DATA
		)
		_last_storage_recovery = {
			"ok": false,
			"recovered": false,
			"persistence_blocked": true,
			"file_name": file_name,
			"error_code": _persistence_blocked_error,
			"error": read_result.error,
		}
		return {}

	var reset_error: Error = ProjectStorageRecoveryPolicy.reset_failed_file(
		storage,
		file_name,
		read_result
	)
	_last_storage_recovery = {
		"ok": false,
		"recovered": false,
		"file_name": file_name,
		"discarded_error_code": read_result.error_code,
		"discarded_error": read_result.error,
		"reset_error_code": reset_error,
		"persistence_blocked": reset_error != OK,
	}
	_storage_recovery_pending = reset_error == OK
	_persistence_blocked_error = OK if reset_error == OK else reset_error
	return {}


func _write_persisted_data(file_name: String, data: Dictionary) -> Error:
	if _persistence_blocked_error != OK:
		return _persistence_blocked_error
	return super._write_persisted_data(file_name, data)
