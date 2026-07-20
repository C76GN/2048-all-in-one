## GameSettingsUtility: 项目设置定义入口。
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
