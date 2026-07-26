## GameSettingsUtility: 项目设置定义入口。
class_name GameSettingsUtility
extends "res://addons/gf/standard/utilities/settings/gf_settings_utility.gd"


# --- 信号 ---

## 设置持久化健康状态发生变化时发出。
## @param snapshot: 由 get_persistence_health_snapshot() 返回的只读快照。
signal persistence_health_changed(snapshot: Dictionary)


# --- 常量 ---

const DEFAULT_LOCALE: String = "zh"
const AUDIO_BUS_MASTER: String = "Master"
const AUDIO_BUS_BGM: String = "BGM"
const AUDIO_BUS_SFX: String = "SFX"


# --- 私有变量 ---

var _storage_recovery_pending: bool = false
var _last_storage_recovery: Dictionary = {}
var _persistence_blocked_error: Error = OK
var _last_persistence_error: Error = OK


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
	_last_persistence_error = recreate_error
	_emit_persistence_health_changed()
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


## 返回设置物理存储当前是否可以正常写入。
func is_persistence_healthy() -> bool:
	return _get_effective_persistence_error() == OK


## 返回设置持久化健康快照，供 UI 和支持报告展示。
func get_persistence_health_snapshot() -> Dictionary:
	var error: Error = _get_effective_persistence_error()
	return {
		"healthy": error == OK,
		"error_code": error,
		"persistence_blocked": _persistence_blocked_error != OK,
		"blocked_error_code": _persistence_blocked_error,
		"last_write_error_code": _last_persistence_error,
	}


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
	var _bgm_volume_setting: GFSettingDefinition = register_setting(
		StringName("audio/%s/volume" % AUDIO_BUS_BGM),
		1.0,
		GFSettingDefinition.ValueType.FLOAT,
		true,
		{"group": "audio", "label": "BGM_VOLUME_LABEL"}
	)
	var _sfx_volume_setting: GFSettingDefinition = register_setting(
		StringName("audio/%s/volume" % AUDIO_BUS_SFX),
		1.0,
		GFSettingDefinition.ValueType.FLOAT,
		true,
		{"group": "audio", "label": "SFX_VOLUME_LABEL"}
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
	var _turn_subtitles_setting: GFSettingDefinition = register_setting(
		GameAccessibilityState.TURN_SUBTITLES_ENABLED_SETTING_KEY,
		true,
		GFSettingDefinition.ValueType.BOOL,
		true,
		{"group": "accessibility", "label": "TURN_SUBTITLES_LABEL"}
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
		_last_persistence_error = OK
		_emit_persistence_health_changed()
		return read_result.payload.duplicate(true)
	if read_result.error_code == ERR_FILE_NOT_FOUND:
		_last_storage_recovery.clear()
		_persistence_blocked_error = OK
		_last_persistence_error = OK
		_emit_persistence_health_changed()
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
		_last_persistence_error = _persistence_blocked_error
		_emit_persistence_health_changed()
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
	_last_persistence_error = _persistence_blocked_error
	_emit_persistence_health_changed()
	return {}


func _write_persisted_data(file_name: String, data: Dictionary) -> Error:
	var error: Error = OK
	if _persistence_blocked_error != OK:
		error = _persistence_blocked_error
	else:
		error = super._write_persisted_data(file_name, data)
	_last_persistence_error = error
	_emit_persistence_health_changed()
	return error


# --- 私有/辅助方法 ---

func _get_effective_persistence_error() -> Error:
	if _persistence_blocked_error != OK:
		return _persistence_blocked_error
	return _last_persistence_error


func _emit_persistence_health_changed() -> void:
	persistence_health_changed.emit(get_persistence_health_snapshot())
