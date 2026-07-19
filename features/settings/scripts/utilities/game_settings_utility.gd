## GameSettingsUtility: 项目设置工具，过滤存储层保留元信息。
class_name GameSettingsUtility
extends "res://addons/gf/standard/utilities/settings/gf_settings_utility.gd"


# --- 常量 ---

const DEFAULT_LOCALE: String = "zh"
const AUDIO_BUS_MASTER: String = "Master"


# --- 公共方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFStorageUtility]


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


## 将设置导出为字典，并移除存储层元信息。
## @param persistent_only: 是否只导出持久化设置。
func to_dict(persistent_only: bool = true) -> Dictionary:
	var data: Dictionary = super.to_dict(persistent_only)
	var _erase_result: bool = data.erase(GFStorageCodec.META_KEY)
	return data


## 从字典完整恢复设置，并忽略存储层元信息。
## @param data: 设置字典。
## @param emit_changes: 是否派发设置变更通知。
func replace_from_dict(data: Dictionary, emit_changes: bool = true) -> void:
	super.replace_from_dict(_without_storage_metadata(data), emit_changes)


## 将字典合并到当前设置，并忽略存储层元信息。
## @param data: 设置字典。
## @param emit_changes: 是否派发设置变更通知。
func merge_from_dict(data: Dictionary, emit_changes: bool = true) -> void:
	super.merge_from_dict(_without_storage_metadata(data), emit_changes)


# --- 私有/辅助方法 ---

func _without_storage_metadata(data: Dictionary) -> Dictionary:
	var clean_data: Dictionary = data.duplicate(true)
	var _erase_result: bool = clean_data.erase(GFStorageCodec.META_KEY)
	return clean_data
