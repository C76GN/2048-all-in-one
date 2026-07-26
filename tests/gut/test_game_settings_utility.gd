## 验证项目设置在 GFStorage 物理格式升级后的恢复策略。
extends GutTest


# --- 测试用例 ---

func test_project_defaults_register_independent_audio_bus_volumes() -> void:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.register_project_defaults()

	for bus_name: String in [
		GameSettingsUtility.AUDIO_BUS_MASTER,
		GameSettingsUtility.AUDIO_BUS_BGM,
		GameSettingsUtility.AUDIO_BUS_SFX,
	]:
		var setting_key: StringName = StringName("audio/%s/volume" % bus_name)
		assert_true(
			settings.has_setting(setting_key),
			"%s 音频总线必须注册持久化音量设置。" % bus_name
		)
		assert_almost_eq(
			GFVariantData.to_float(settings.get_value(setting_key), -1.0),
			1.0,
			0.001,
			"%s 音频总线默认音量应为 100%%。" % bus_name
		)


func test_storage_recovery_policy_only_resets_physical_format_failures() -> void:
	var envelope_failure: GFStorageReadResult = GFStorageReadResult.new().configure_failure(
		"Storage document envelope missing or malformed",
		ERR_FILE_UNRECOGNIZED
	)
	var future_version_failure: GFStorageReadResult = GFStorageReadResult.new().configure_failure(
		"Unsupported future storage version: 2 > 1",
		ERR_INVALID_DATA,
		{"data_version": 2}
	)

	assert_true(
		ProjectStorageRecoveryPolicy.should_reset_failed_read(envelope_failure),
		"不可识别的物理 envelope 应允许按 reset_allowed 策略重建。"
	)
	assert_false(
		ProjectStorageRecoveryPolicy.should_reset_failed_read(future_version_failure),
		"未来存储版本必须保留原档并显式失败，不能破坏性重置。"
	)


func test_future_settings_storage_version_is_preserved_and_blocks_writes() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage("gut_future_game_settings")
	storage.save_version = 2
	var seed_error: Error = storage.save_data(
		"settings.sav",
		{"future_marker": "preserve-me"}
	)
	assert_true(seed_error == OK, "应能构造未来存储版本夹具。")
	storage.save_version = 1

	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GameSettingsUtility, settings)
	await architecture.init()
	assert_push_error(
		"Unsupported future storage version: 2 > 1",
		"GFStorage 应明确拒绝未来物理存储版本。"
	)

	var recovery: Dictionary = settings.get_storage_recovery_snapshot()
	var persistence_health: Dictionary = settings.get_persistence_health_snapshot()
	assert_false(
		GFVariantData.get_option_bool(recovery, "recovered", false),
		"未来存储版本不能进入破坏性恢复。"
	)
	assert_false(
		GFVariantData.get_option_bool(persistence_health, "healthy", true),
		"未来存储版本阻断写入后必须公开不健康持久化状态。"
	)
	assert_true(
		GFVariantData.get_option_int(persistence_health, "error_code") == ERR_INVALID_DATA,
		"持久化健康快照必须保留阻断写入的错误码。"
	)
	assert_false(
		settings.is_persistence_healthy(),
		"设置 UI 不得把已阻断的物理存储描述为可自动保存。"
	)
	assert_true(
		settings.save_settings() == ERR_INVALID_DATA,
		"未来版本读取失败后必须阻断设置写入。"
	)
	storage.save_version = 2
	var preserved_result: GFStorageReadResult = storage.load_data(settings.storage_file_name)
	assert_true(
		preserved_result.ok
		and GFVariantData.get_option_string(
			preserved_result.payload,
			"future_marker"
		) == "preserve-me",
		"阻断写入后必须完整保留未来版本载荷。"
	)

	var cleanup_error: Error = storage.delete_file(settings.storage_file_name)
	assert_true(cleanup_error == OK, "未来设置测试文件应可清理。")
	architecture.dispose()


func test_settings_menu_exposes_blocked_storage_in_compact_layout() -> void:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings._persistence_blocked_error = ERR_INVALID_DATA
	var menu: SettingsMenu = SettingsMenu.new()
	var status_label: Label = Label.new()
	menu.add_child(status_label)
	menu._settings_utility = settings
	menu._auto_save_label = status_label
	menu._is_compact_layout = true

	menu._update_persistence_status()

	assert_true(
		status_label.text == menu.tr("SETTINGS_SAVE_FAILED_HINT") % int(ERR_INVALID_DATA),
		"设置持久化失败时不得继续显示自动保存成功语义。"
	)
	assert_true(status_label.visible, "紧凑布局也必须展示设置持久化失败。")
	menu.free()


func test_unreadable_settings_file_is_reset_to_current_format() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage("gut_game_settings")
	var fixture_error: Error = _write_raw_storage_file(
		storage,
		"settings.sav",
		_make_legacy_storage_bytes({"legacy_settings": true})
	)
	assert_true(fixture_error == OK, "无法写入不可读设置回归夹具。")

	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(GameSettingsUtility, settings)
	await architecture.init()
	assert_push_error(
		"Storage document envelope missing or malformed",
		"GFStorage 应明确拒绝旧物理文档。"
	)

	var recovery: Dictionary = settings.get_storage_recovery_snapshot()
	assert_false(recovery.is_empty(), "设置应公开最近一次物理存储恢复诊断。")
	assert_true(
		GFVariantData.get_option_bool(recovery, "ok", false),
		"无法按当前 codec 解码的设置应按项目 reset_allowed 策略重建。"
	)
	assert_true(
		GFVariantData.get_option_bool(recovery, "recovered", false),
		"设置诊断应明确记录物理存储格式重建。"
	)
	assert_true(
		GFVariantData.to_text(
			settings.get_value(GFDisplaySettingsUtility.LOCALE_KEY)
		) == GameSettingsUtility.DEFAULT_LOCALE,
		"重建设置必须恢复项目默认值。"
	)
	var persisted_result: GFStorageReadResult = storage.load_data(settings.storage_file_name)
	assert_true(persisted_result.ok, "设置文件必须已改写为当前 GFStorage 文档格式。")

	var cleanup_error: Error = storage.delete_file(settings.storage_file_name)
	assert_true(cleanup_error == OK, "测试设置文件应可清理。")
	architecture.dispose()


# --- 私有/辅助方法 ---

func _write_raw_storage_file(
	storage: GFStorageUtility,
	file_name: String,
	bytes: PackedByteArray
) -> Error:
	var directory_error: Error = storage.ensure_directory()
	if directory_error != OK:
		return directory_error
	var path: String = storage.get_storage_directory_path().path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var _store_result: Variant = file.store_buffer(bytes)
	file.close()
	return OK


func _make_storage(prefix: String) -> GFStorageUtility:
	var storage: GFStorageUtility = GFStorageUtility.new()
	storage.save_dir_name = "%s_%d" % [prefix, Time.get_ticks_usec()]
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true
	return storage


func _make_legacy_storage_bytes(data: Dictionary, obfuscation_key: int = 42) -> PackedByteArray:
	var bytes: PackedByteArray = var_to_bytes(data)
	var key_byte: int = obfuscation_key & 0xff
	for index: int in range(bytes.size()):
		bytes[index] = bytes[index] ^ key_byte
	return Marshalls.raw_to_base64(bytes).to_utf8_buffer()
