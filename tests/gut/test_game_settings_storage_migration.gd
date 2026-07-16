## 验证项目设置可从旧版混淆 JSON 一次性迁移到当前二进制存储格式。
extends GutTest


# --- 常量 ---

const _SETTINGS_FILE_NAME: String = "settings.sav"


# --- 测试用例 ---

func test_legacy_json_settings_are_migrated_and_loaded_by_current_storage() -> void:
	var save_dir_name: String = "gut_settings_migration_%d" % Time.get_ticks_usec()
	var legacy_storage: GFStorageUtility = _make_storage(save_dir_name, GFStorageCodec.Format.JSON)
	var legacy_payload: Dictionary = {
		"appearance/theme_id": {
			"__gf_setting_type": "StringName",
			"value": "halftone_atlas",
		},
		"audio/Master/volume": 0.35,
		"audio/sound_theme_id": {
			"__gf_setting_type": "StringName",
			"value": "printworks",
		},
		"display/locale": "zh",
	}
	var legacy_save_error: Error = legacy_storage.save_data(_SETTINGS_FILE_NAME, legacy_payload)
	assert_true(legacy_save_error == OK, "旧版 JSON 设置夹具应成功写入。")
	legacy_storage.dispose()

	var current_storage: GFStorageUtility = _make_storage(save_dir_name, GFStorageCodec.Format.BINARY)
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.storage_file_name = _SETTINGS_FILE_NAME
	settings.auto_save_on_change = false
	settings.register_project_defaults()

	var architecture: GFArchitecture = GFArchitecture.new()
	await architecture.register_utility(GFStorageUtility, current_storage)
	await architecture.register_utility(GameSettingsUtility, settings)
	await architecture.init()

	assert_true(
		GFVariantData.to_string_name(settings.get_value(GameThemeUtility.VISUAL_THEME_SETTING_KEY)) == &"halftone_atlas",
		"迁移后应恢复视觉主题。"
	)
	assert_almost_eq(
		GFVariantData.to_float(settings.get_value(&"audio/Master/volume")),
		0.35,
		0.001,
		"迁移后应恢复主音量。"
	)
	assert_true(
		GFVariantData.to_string_name(settings.get_value(GameThemeUtility.SOUND_THEME_SETTING_KEY)) == &"printworks",
		"迁移后应恢复音效主题。"
	)

	var current_result: Dictionary = current_storage.load_data_result(_SETTINGS_FILE_NAME)
	assert_true(GFVariantData.get_option_bool(current_result, "ok"), "迁移后的文件应能按当前二进制 codec 读取。")
	var metadata: Dictionary = GFVariantData.get_option_dictionary(current_result, "metadata")
	assert_true(
		GFVariantData.get_option_string(metadata, GFStorageCodec.FORMAT_KEY) == "binary",
		"迁移应将文件重写为当前二进制格式。"
	)

	var cleanup_error: Error = current_storage.delete_file(_SETTINGS_FILE_NAME)
	assert_true(cleanup_error == OK or cleanup_error == ERR_FILE_NOT_FOUND, "测试设置文件应完成清理。")
	architecture.dispose()


func test_current_binary_settings_are_not_misidentified_as_legacy_json() -> void:
	var save_dir_name: String = "gut_settings_current_%d" % Time.get_ticks_usec()
	var current_storage: GFStorageUtility = _make_storage(save_dir_name, GFStorageCodec.Format.BINARY)
	var current_payload: Dictionary = {
		"display/locale": "zh",
		"audio/Master/volume": 0.5,
	}
	var save_error: Error = current_storage.save_data(_SETTINGS_FILE_NAME, current_payload)
	assert_true(save_error == OK, "当前二进制设置夹具应成功写入。")

	var report: Dictionary = GameSettingsStorageMigrationUtility.migrate_legacy_json(
		current_storage,
		_SETTINGS_FILE_NAME
	)
	assert_false(GFVariantData.get_option_bool(report, "matched"), "当前二进制设置不得被误判为旧版 JSON。")

	var load_result: Dictionary = current_storage.load_data_result(_SETTINGS_FILE_NAME)
	assert_true(GFVariantData.get_option_bool(load_result, "ok"), "迁移探测后当前二进制设置仍应可读。")
	var loaded_data: Dictionary = GFVariantData.get_option_dictionary(load_result, "data")
	assert_true(
		GFVariantData.get_option_string(loaded_data, "display/locale") == "zh",
		"未命中旧格式时不得改写当前语言设置。"
	)
	assert_almost_eq(
		GFVariantData.get_option_float(loaded_data, "audio/Master/volume"),
		0.5,
		0.001,
		"未命中旧格式时不得改写当前音量设置。"
	)

	var cleanup_error: Error = current_storage.delete_file(_SETTINGS_FILE_NAME)
	assert_true(cleanup_error == OK or cleanup_error == ERR_FILE_NOT_FOUND, "测试设置文件应完成清理。")
	current_storage.dispose()


# --- 私有/辅助方法 ---

func _make_storage(save_dir_name: String, format: GFStorageCodec.Format) -> GFStorageUtility:
	var storage: GFStorageUtility = GFStorageUtility.new()
	storage.save_dir_name = save_dir_name
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = format
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	storage.strict_integrity = true
	storage.require_integrity_checksum = true
	return storage
