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
	assert_true(
		settings.has_setting(
			GameSettingsUtility.LOCAL_PERFORMANCE_TRACE_SETTING_KEY
		),
		"项目设置必须注册本地性能诊断的显式同意项。"
	)
	assert_false(
		GFVariantData.to_bool(
			settings.get_value(
				GameSettingsUtility.LOCAL_PERFORMANCE_TRACE_SETTING_KEY,
				true
			),
			true
		),
		"本地性能轨迹必须默认关闭。"
	)


func test_storage_recovery_policy_only_resets_physical_format_failures() -> void:
	var envelope_failure: GFStorageReadResult = GFStorageReadResult.new().configure_failure(
		"Storage document envelope missing or malformed",
		ERR_FILE_UNRECOGNIZED,
		{},
		GFStorageReadResult.IntegrityStatus.NOT_CHECKED,
		0,
		GFStorageReadResult.FailureKind.CORRUPT
	)
	var future_version_failure: GFStorageReadResult = GFStorageReadResult.new().configure_failure(
		"Unsupported future storage version: 2 > 1",
		ERR_FILE_UNRECOGNIZED,
		{"data_version": 2},
		GFStorageReadResult.IntegrityStatus.NOT_CHECKED,
		0,
		GFStorageReadResult.FailureKind.FUTURE_VERSION
	)

	assert_true(
		ProjectStorageRecoveryPolicy.should_reset_failed_read(envelope_failure),
		"不可识别的物理 envelope 应允许按 reset_allowed 策略重建。"
	)
	assert_false(
		ProjectStorageRecoveryPolicy.should_reset_failed_read(future_version_failure),
		"未来存储版本必须保留原档并显式失败，不能破坏性重置。"
	)


func test_startup_settings_load_records_successful_terminal_diagnostic() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage("gut_loaded_game_settings")
	var seed_error: Error = storage.save_data(
		"settings.sav",
		{String(GFDisplaySettingsUtility.LOCALE_KEY): "en"}
	)
	assert_true(seed_error == OK, "应能构造合法设置启动夹具。")
	var diagnostics: GFOperationDiagnosticsUtility = (
		GFOperationDiagnosticsUtility.new()
	)
	var clock: GFManualClock = GFManualClock.new(5_000_000, 10_000)
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	assert_true(settings.set_clock(clock), "设置工具应接受共享 GFClock 注入。")
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		diagnostics
	)
	await architecture.register_utility(GameSettingsUtility, settings)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "设置启动诊断夹具必须完成 GF 架构初始化。")

	assert_true(
		GFVariantData.to_text(
			settings.get_value(GFDisplaySettingsUtility.LOCALE_KEY)
		) == "en",
		"启动加载必须应用合法持久化设置。"
	)
	_assert_startup_settings_diagnostic(
		diagnostics,
		true,
		GFSettingsLoadResult.STATUS_LOADED,
		false
	)

	var cleanup_error: Error = storage.delete_file(settings.storage_file_name)
	assert_true(cleanup_error == OK, "合法设置启动夹具应可清理。")
	architecture.dispose()


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

	var diagnostics: GFOperationDiagnosticsUtility = (
		GFOperationDiagnosticsUtility.new()
	)
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		diagnostics
	)
	await architecture.register_utility(GameSettingsUtility, settings)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "未来版本设置夹具必须完成 GF 架构初始化。")
	assert_push_error(
		"Unsupported future storage version: 2 > 1",
		"GFStorage 应明确拒绝未来物理存储版本。"
	)
	_assert_startup_settings_diagnostic(
		diagnostics,
		false,
		GFSettingsLoadResult.STATUS_FUTURE_SCHEMA,
		false
	)

	var recovery: Dictionary = settings.get_storage_recovery_snapshot()
	var persistence_health: Dictionary = settings.get_persistence_health_snapshot()
	var load_result: GFSettingsLoadResult = settings.get_last_load_result()
	assert_not_null(load_result, "未来版本读取必须保留 GFSettingsLoadResult 终态。")
	if load_result != null:
		assert_false(load_result.is_successful(), "未来版本不得被设置恢复策略吞掉。")
		assert_true(
			load_result.get_status() == GFSettingsLoadResult.STATUS_FUTURE_SCHEMA,
			"未来版本必须保留稳定 future_schema 分类。"
		)
		assert_false(load_result.was_recovered(), "未来版本不得标记为已恢复。")
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


func test_settings_menu_handles_cancel_before_synchronous_route_detach() -> void:
	var packed_menu: PackedScene = load(
		"res://features/settings/scenes/menus/settings_menu.tscn"
	) as PackedScene
	assert_not_null(packed_menu, "设置菜单回归夹具必须可加载。")
	var menu_node: Node = packed_menu.instantiate()
	menu_node.set_script(_DetachingSettingsMenu)
	var menu: _DetachingSettingsMenu = menu_node as _DetachingSettingsMenu
	assert_not_null(menu, "设置菜单场景必须可替换为同步关闭探针。")
	autofree(menu)
	add_child(menu)
	var viewport: Viewport = menu.get_viewport()
	assert_not_null(viewport, "设置菜单进入树后必须拥有输入 Viewport。")
	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true

	menu._unhandled_input(cancel_event)

	assert_engine_error_count(
		0,
		"同步关闭设置弹层后不得再解引用已丢失的 Viewport。"
	)
	assert_true(viewport.is_input_handled(), "关闭弹层前必须消费取消输入，避免泄漏到玩法层。")
	assert_true(menu.back_request_count == 1, "一次取消输入只能发起一次返回。")
	assert_false(menu.is_inside_tree(), "探针应同步模拟路由移除设置弹层。")


func test_serialization_failure_updates_health_once_before_storage_write() -> void:
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.register_project_defaults()
	var circular_value: Dictionary = {}
	circular_value[&"self"] = circular_value
	settings.set_value(&"test/circular_value", circular_value, false)
	watch_signals(settings)

	var save_error: Error = settings.save_settings()
	var health: Dictionary = settings.get_persistence_health_snapshot()
	assert_push_error(
		"设置数据包含循环引用",
		"GF 序列化边界应明确报告拒绝循环引用。"
	)

	assert_true(
		save_error == ERR_INVALID_DATA,
		"循环引用应在进入物理写入钩子前被拒绝。"
	)
	assert_false(
		GFVariantData.get_option_bool(health, &"healthy", true),
		"序列化前置失败也必须使设置持久化健康状态失败。"
	)
	assert_true(
		GFVariantData.get_option_int(health, &"error_code", OK)
		== ERR_INVALID_DATA,
		"设置健康快照必须保留序列化失败错误码。"
	)
	assert_signal_emit_count(
		settings,
		"persistence_health_changed",
		1,
		"公共保存边界与物理写入钩子不得重复发布同一健康结果。"
	)
	circular_value.clear()


func test_strict_settings_load_preserves_corrupt_storage_evidence() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage("gut_strict_game_settings")
	var fixture_error: Error = _write_raw_storage_file(
		storage,
		"settings.sav",
		_make_legacy_storage_bytes({"strict_marker": "preserve-me"})
	)
	assert_true(fixture_error == OK, "无法写入严格读取损坏设置夹具。")
	var storage_path: String = storage.get_storage_directory_path().path_join(
		"settings.sav"
	)
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(storage_path)

	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(GameSettingsUtility, settings)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "严格读取设置夹具必须完成 GF 架构初始化。")

	var load_result: GFSettingsLoadResult = settings.load_settings()
	assert_push_error(
		"Storage document envelope missing or malformed",
		"严格读取应保留 GFStorage 的损坏分类。"
	)

	assert_not_null(load_result, "严格读取必须返回结构化终态。")
	if load_result != null:
		assert_false(load_result.is_successful(), "无恢复策略时损坏设置必须严格失败。")
		assert_true(
			load_result.get_status() == GFSettingsLoadResult.STATUS_CORRUPT,
			"损坏设置必须保留 corrupt 终态。"
		)
		assert_false(load_result.was_recovered(), "严格读取不得伪装为已恢复。")
	assert_true(FileAccess.file_exists(storage_path), "严格读取不得删除损坏文件。")
	assert_true(
		FileAccess.get_file_as_bytes(storage_path) == original_bytes,
		"严格读取不得改写损坏文件或丢失原始证据。"
	)
	assert_false(
		settings.is_persistence_healthy(),
		"损坏文件未获恢复授权时应继续阻断设置写入。"
	)

	var cleanup_error: Error = storage.delete_file(settings.storage_file_name)
	assert_true(cleanup_error == OK, "严格读取设置夹具应可手动清理。")
	architecture.dispose()


func test_unreadable_settings_file_is_reset_to_current_format() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage("gut_game_settings")
	var fixture_error: Error = _write_raw_storage_file(
		storage,
		"settings.sav",
		_make_legacy_storage_bytes({"legacy_settings": true})
	)
	assert_true(fixture_error == OK, "无法写入不可读设置回归夹具。")

	var diagnostics: GFOperationDiagnosticsUtility = (
		GFOperationDiagnosticsUtility.new()
	)
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		diagnostics
	)
	await architecture.register_utility(GameSettingsUtility, settings)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "设置恢复夹具必须完成 GF 架构初始化。")
	assert_push_error(
		"Storage document envelope missing or malformed",
		"GFStorage 应明确拒绝旧物理文档。"
	)
	_assert_startup_settings_diagnostic(
		diagnostics,
		true,
		GFSettingsLoadResult.STATUS_RECOVERED,
		true
	)

	var recovery: Dictionary = settings.get_storage_recovery_snapshot()
	var load_result: GFSettingsLoadResult = settings.get_last_load_result()
	assert_false(recovery.is_empty(), "设置应公开最近一次物理存储恢复诊断。")
	assert_true(
		GFVariantData.get_option_bool(recovery, "ok", false),
		"无法按当前 codec 解码的设置应按项目 reset_allowed 策略重建。"
	)
	assert_true(
		GFVariantData.get_option_bool(recovery, "recovered", false),
		"设置诊断应明确记录物理存储格式重建。"
	)
	assert_not_null(load_result, "损坏设置恢复必须保留 GFSettingsLoadResult 终态。")
	if load_result != null:
		assert_true(load_result.is_successful(), "显式 reset_to_defaults 应完成恢复。")
		assert_true(
			load_result.get_status() == GFSettingsLoadResult.STATUS_RECOVERED,
			"损坏设置不得伪装为正常 loaded。"
		)
		assert_true(load_result.was_recovered(), "加载终态必须标记显式恢复。")
		var storage_result: GFStorageReadResult = load_result.get_storage_result()
		assert_not_null(storage_result, "加载终态必须保留原始存储失败证据。")
		if storage_result != null:
			assert_true(
				storage_result.failure_kind == GFStorageReadResult.FailureKind.CORRUPT,
				"恢复终态必须保留 corrupt 分类。"
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


func test_settings_quiesce_flushes_open_batch_and_closes_mutation_admission() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage("gut_quiesce_game_settings")
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(GameSettingsUtility, settings)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "设置 quiesce 夹具必须完成 GF 架构初始化。")
	if not initialized:
		architecture.dispose()
		return

	settings.begin_batch()
	settings.set_value(GFDisplaySettingsUtility.LOCALE_KEY, "en")
	settings.stage_value(GFDisplaySettingsUtility.LOCALE_KEY, "zh")
	var completion: GFAsyncCompletion = settings.begin_quiesce(
		GFAsyncScope.new()
	)
	assert_not_null(completion)
	assert_true(
		completion != null and completion.is_successful(),
		"静默设置 Utility 必须冲刷尚未 end_batch 的已接纳变更。"
	)

	var stored: GFStorageReadResult = storage.load_data(
		settings.storage_file_name
	)
	assert_true(stored.ok, "quiesce 应写出当前 GFStorage 设置文档。")
	assert_true(
		GFVariantData.get_option_string(
			stored.payload,
			String(GFDisplaySettingsUtility.LOCALE_KEY)
		) == "en",
		"未闭合批次的当前设置也必须在关闭前持久化。"
	)

	settings.set_value(GFDisplaySettingsUtility.LOCALE_KEY, "zh")
	settings.reset_all()
	var staged_report: Dictionary = settings.apply_staged_values()
	assert_true(
		GFVariantData.get_option_string(
			settings.to_dict(false),
			String(GFDisplaySettingsUtility.LOCALE_KEY)
		) == "en",
		"quiesce 后 set/reset/apply 不得再改变设置权威状态。"
	)
	assert_false(
		GFVariantData.get_option_bool(staged_report, &"ok", true),
		"quiesce 后 staged 应用必须返回明确拒绝。"
	)
	assert_true(
		GFVariantData.get_option_int(
			staged_report,
			&"staged_remaining_count"
		) == 1,
		"拒绝 staged 应用时不得消费尚未接纳的候选。"
	)

	var cleanup_error: Error = storage.delete_file(settings.storage_file_name)
	assert_true(cleanup_error == OK, "设置 quiesce 夹具应可清理。")
	architecture.dispose()


func test_settings_quiesce_preserves_queued_target_before_flushing_open_batch() -> void:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = _make_storage(
		"gut_quiesce_settings_target_change"
	)
	var settings: GameSettingsUtility = GameSettingsUtility.new()
	settings.auto_load_on_init = false
	settings.register_project_defaults()
	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFOperationDiagnosticsUtility,
		GFOperationDiagnosticsUtility.new()
	)
	await architecture.register_utility(GameSettingsUtility, settings)
	var initialized: bool = await architecture.init()
	assert_true(initialized, "设置目标切换夹具必须完成 GF 架构初始化。")
	if not initialized:
		architecture.dispose()
		return

	var queued_file_name: String = "queued-settings.sav"
	var active_file_name: String = "active-settings.sav"
	settings.storage_file_name = queued_file_name
	settings.set_value(GFDisplaySettingsUtility.LOCALE_KEY, "en")
	settings.storage_file_name = active_file_name
	settings.begin_batch()
	settings.set_value(GFDisplaySettingsUtility.LOCALE_KEY, "zh")

	var completion: GFAsyncCompletion = settings.begin_quiesce(
		GFAsyncScope.new()
	)
	assert_true(
		completion != null and completion.is_successful(),
		"quiesce 必须同时兑现旧 debounce 目标与当前 batch 目标。"
	)
	var queued_read: GFStorageReadResult = storage.load_data(queued_file_name)
	var active_read: GFStorageReadResult = storage.load_data(active_file_name)
	assert_true(queued_read.ok, "已接纳的旧 debounce 文件目标不得被覆盖。")
	assert_true(active_read.ok, "打开批次的最新状态必须写入当前设置目标。")
	assert_true(
		GFVariantData.get_option_string(
			active_read.payload,
			String(GFDisplaySettingsUtility.LOCALE_KEY)
		) == "zh",
		"当前设置目标必须保存 quiesce 时的最新批次值。"
	)

	assert_true(storage.delete_file(queued_file_name) == OK)
	assert_true(storage.delete_file(active_file_name) == OK)
	architecture.dispose()


# --- 私有/辅助方法 ---

func _assert_startup_settings_diagnostic(
	diagnostics: GFOperationDiagnosticsUtility,
	expected_success: bool,
	expected_load_status: StringName,
	expected_recovered: bool
) -> void:
	var operations: Array[Dictionary] = diagnostics.get_operations(
		0,
		{&"operation_type": &"game.settings_persistence"}
	)
	assert_true(
		operations.size() == 1,
		"一次启动自动加载必须只归档一个设置持久化操作。"
	)
	if operations.size() != 1:
		return
	var operation: Dictionary = operations[0]
	var metadata: Dictionary = GFVariantData.get_option_dictionary(
		operation,
		&"metadata"
	)
	assert_true(
		GFVariantData.get_option_bool(operation, &"success")
		== expected_success,
		"设置启动诊断必须保留真实成功终态。"
	)
	assert_true(
		GFVariantData.get_option_string_name(operation, &"state")
		== (&"completed" if expected_success else &"failed"),
		"设置启动诊断必须直接进入 completed/failed 终态。"
	)
	assert_true(
		GFVariantData.get_option_int(operation, &"ended_ticks_usec") > 0,
		"设置启动诊断必须保留结束 tick。"
	)
	assert_true(
		GFVariantData.get_option_string_name(metadata, &"action")
		== &"startup_load",
		"启动自动加载必须使用稳定 action 分类。"
	)
	assert_true(
		GFVariantData.get_option_string_name(metadata, &"load_status")
		== expected_load_status,
		"设置启动诊断必须保留 GFSettingsLoadResult 稳定状态。"
	)
	assert_true(
		GFVariantData.get_option_bool(metadata, &"recovered")
		== expected_recovered,
		"设置启动诊断必须区分正常加载与显式恢复。"
	)
	var health: Dictionary = diagnostics.get_health_snapshot(0)
	assert_true(
		GFVariantData.get_option_int(health, &"active_operation_count") == 0,
		"启动加载归档不得遗留 running 操作。"
	)

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


# --- 内部类 ---

class _DetachingSettingsMenu extends SettingsMenu:
	var back_request_count: int = 0

	func _ready() -> void:
		pass

	func _on_back_button_pressed() -> void:
		back_request_count += 1
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			parent.remove_child(self)
