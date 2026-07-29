## 验证方块试验台严格蓝图、Profile 隔离、配方冲突、真实交互和 UI 契约。
extends GutTest


# --- 常量 ---

const _TILE_LAB_SCENE: PackedScene = preload(
	"res://features/tile_lab/scenes/ui/tile_lab_dialog.tscn"
)
const _TEST_PLATFORM_STUB_SCRIPT: GDScript = preload(
	"res://tests/gut/fixtures/test_game_platform_utility_stub.gd"
)
const _BASE_DEFINITION_ID: StringName = &"tile.classic.numeric"
const _CLASSIC_RECIPE_ID: StringName = &"tile.recipe.classic_merge"
const _MINIMUM_TOUCH_TARGET_SIZE: float = 44.0


# --- 测试用例 ---

func test_blueprint_schema_is_strict_and_preserves_recipe_order() -> void:
	var blueprint: CustomTileBlueprintData = _make_strict_blueprint(
		[&"tile.recipe.fibonacci_merge", _CLASSIC_RECIPE_ID]
	)
	var restored: CustomTileBlueprintData = (
		CustomTileBlueprintData.from_dict(blueprint.to_dict())
	)
	assert_not_null(restored)
	if restored != null:
		assert_true(
			restored.recipe_ids
			== [&"tile.recipe.fibonacci_merge", _CLASSIC_RECIPE_ID],
			"蓝图必须保留玩家选择的 Recipe 顺序。"
		)

	var unknown_field: Dictionary = blueprint.to_dict()
	unknown_field["legacy_recipe"] = "classic"
	assert_null(
		CustomTileBlueprintData.from_dict(unknown_field),
		"严格蓝图不得接受未知字段。"
	)

	var old_schema: Dictionary = blueprint.to_dict()
	old_schema["schema_version"] = 0
	assert_null(
		CustomTileBlueprintData.from_dict(old_schema),
		"运行时不得隐式接受旧蓝图 schema。"
	)

	var duplicate_recipe: Dictionary = blueprint.to_dict()
	duplicate_recipe["recipe_ids"] = [
		_CLASSIC_RECIPE_ID,
		_CLASSIC_RECIPE_ID,
	]
	assert_null(
		CustomTileBlueprintData.from_dict(duplicate_recipe),
		"严格蓝图必须拒绝重复 Recipe ID。"
	)


func test_blueprints_are_crud_isolated_between_player_profiles() -> void:
	var setup: Dictionary = await _create_setup()
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var tile_lab: TileLabSystem = _get_tile_lab(setup)
	var first_id: String = GFUuid.generate_v7(1_000_000)
	var second_id: String = GFUuid.generate_v7(1_000_001)
	var first_file: String = "profiles/%s.save" % first_id
	var second_file: String = "profiles/%s.save" % second_id

	assert_true(save_graph.activate_profile(first_file, true) == OK)
	var first_blueprint: CustomTileBlueprintData = _make_blueprint("第一份")
	var first_save: GameSaveSectionResult = await _save_blueprint(
		tile_lab,
		first_blueprint,
		setup
	)
	assert_true(first_save != null and first_save.is_successful())
	assert_true(GFUuid.is_valid(first_blueprint.blueprint_id, 7))
	first_blueprint.display_name = "第一份已更新"
	var update_save: GameSaveSectionResult = await _save_blueprint(
		tile_lab,
		first_blueprint,
		setup
	)
	assert_true(update_save != null and update_save.is_successful())
	assert_true(tile_lab.load_blueprints().size() == 1)
	assert_true(
		tile_lab.load_blueprints()[0].display_name == "第一份已更新"
	)

	assert_true(save_graph.activate_profile(second_file) == OK)
	assert_true(
		tile_lab.load_blueprints().is_empty(),
		"新账号 Profile 不得读取另一个账号的试验台蓝图。"
	)
	var second_blueprint: CustomTileBlueprintData = _make_blueprint("第二份")
	var second_save: GameSaveSectionResult = await _save_blueprint(
		tile_lab,
		second_blueprint,
		setup
	)
	assert_true(second_save != null and second_save.is_successful())

	assert_true(save_graph.activate_profile(first_file) == OK)
	assert_true(tile_lab.load_blueprints().size() == 1)
	assert_true(
		tile_lab.load_blueprints()[0].blueprint_id
		== first_blueprint.blueprint_id
	)
	var delete_result: GameSaveSectionResult = await _delete_blueprint(
		tile_lab,
		first_blueprint.blueprint_id,
		setup
	)
	assert_true(delete_result != null and delete_result.is_successful())
	assert_true(tile_lab.load_blueprints().is_empty())

	assert_true(save_graph.activate_profile(second_file) == OK)
	assert_true(
		tile_lab.load_blueprints().size() == 1,
		"删除第一账号蓝图不得影响第二账号 Profile。"
	)
	_dispose_setup(setup, [first_file, second_file])


func test_overlapping_capability_recipes_are_rejected() -> void:
	var setup: Dictionary = await _create_setup()
	var tile_lab: TileLabSystem = _get_tile_lab(setup)
	var conflicting_recipe: GFCapabilityRecipe = GFCapabilityRecipe.new()
	conflicting_recipe.recipe_id = &"tile.recipe.test.classic_conflict"
	conflicting_recipe.display_name = "Conflicting Classic"
	conflicting_recipe.groups = [&"tile", &"tile.interaction"]
	conflicting_recipe.metadata = {
		&"display_name_key": &"TILE_RECIPE_CLASSIC_MERGE",
		&"visual_layer_id": &"tile.visual_trait.test_conflict",
		&"audio_layer_id": &"tile.audio_trait.test_conflict",
	}
	var conflicting_entry: GFCapabilityRecipeEntry = (
		GFCapabilityRecipeEntry.new()
	)
	conflicting_entry.capability_type = ClassicMergeCapability
	conflicting_recipe.entries = [conflicting_entry]
	tile_lab._recipes_by_id[conflicting_recipe.recipe_id] = conflicting_recipe
	tile_lab._ordered_recipe_ids.append(conflicting_recipe.recipe_id)

	var report: GFValidationReport = tile_lab.validate_composition(
		_BASE_DEFINITION_ID,
		[_CLASSIC_RECIPE_ID, conflicting_recipe.recipe_id]
	)
	assert_false(report.is_ok())
	assert_true(
		_report_has_issue(report, &"overlapping_recipe_capability"),
		"两个 Recipe 不能共同拥有同一顶层 Capability。"
	)
	_dispose_setup(setup)


func test_simulation_applies_existing_composition_interaction_and_releases() -> void:
	var setup: Dictionary = await _create_setup()
	var tile_lab: TileLabSystem = _get_tile_lab(setup)
	var result: TileLabSimulationResult = tile_lab.simulate_composition(
		_BASE_DEFINITION_ID,
		[_CLASSIC_RECIPE_ID],
		2,
		2
	)
	assert_not_null(result)
	assert_true(result.is_valid_result())
	assert_true(result.did_interact())
	assert_true(result.result_value == 4)
	assert_true(result.score_delta == 4)
	assert_true(result.survivor_side == &"right")
	assert_true(
		result.interaction_rule_id == &"tile.interaction.classic_merge"
	)

	var capabilities_value: Variant = setup.get(&"capabilities")
	assert_true(capabilities_value is GFCapabilityUtility)
	if capabilities_value is GFCapabilityUtility:
		var capabilities: GFCapabilityUtility = capabilities_value
		assert_true(
			capabilities.get_receivers_with(
				ClassicMergeCapability
			).is_empty(),
			"交互完成后不得由试验台保留运行时方块能力所有权。"
		)
	_dispose_setup(setup)


func test_simulation_does_not_publish_discovery_or_mutate_profile_progress() -> void:
	var setup: Dictionary = await _create_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var composition: TileCompositionUtility = _get_composition(setup)
	var discovery: TileDiscoverySystem = _get_discovery(setup)
	var save_graph: GameSaveGraphUtility = _get_save_graph(setup)
	var tile_lab: TileLabSystem = _get_tile_lab(setup)
	var discovery_section_before: Dictionary = save_graph.get_section_data(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID
	).duplicate(true)
	var progress_event_count: Dictionary = {&"value": 0}

	watch_signals(composition)
	watch_signals(discovery)
	architecture.register_event(
		DiscoveryProgressChangedData,
		GFEventListener.from_callable(
			func(_payload: Variant) -> void:
				progress_event_count[&"value"] = (
					GFVariantData.get_option_int(
						progress_event_count,
						&"value",
						0
					)
					+ 1
				),
			1
		)
	)

	var result: TileLabSimulationResult = tile_lab.simulate_composition(
		_BASE_DEFINITION_ID,
		[_CLASSIC_RECIPE_ID],
		2,
		2
	)
	await get_tree().process_frame

	assert_not_null(result)
	assert_true(result.did_interact())
	assert_signal_emit_count(
		composition,
		"tile_composition_observed",
		0
	)
	assert_signal_emit_count(discovery, "tile_discovery_changed", 0)
	assert_true(
		GFVariantData.get_option_int(
			progress_event_count,
			&"value",
			-1
		)
		== 0,
		"试验台沙盒不得发布会驱动成就的发现进度事件。"
	)
	assert_true(
		discovery.get_tile_discoveries().is_empty(),
		"试验台沙盒不得把预览方块写入玩家图鉴。"
	)
	assert_true(
		save_graph.get_section_data(
			GameSaveGraphUtility.DISCOVERIES_SECTION_ID
		)
		== discovery_section_before,
		"试验台沙盒不得改变当前账号 Profile 的 discoveries section。"
	)
	_dispose_setup(setup)


func test_blueprint_count_is_bounded_to_thirty_two() -> void:
	var setup: Dictionary = await _create_setup()
	var tile_lab: TileLabSystem = _get_tile_lab(setup)
	for index: int in range(TileLabSaveData.MAX_BLUEPRINT_COUNT):
		var blueprint: CustomTileBlueprintData = _make_blueprint(
			"蓝图 %02d" % index
		)
		var result: GameSaveSectionResult = await _save_blueprint(
			tile_lab,
			blueprint,
			setup
		)
		assert_true(
			result != null and result.is_successful(),
			"第 %d 份蓝图应在上限内保存。" % index
		)
	assert_true(
		tile_lab.load_blueprints().size()
		== TileLabSaveData.MAX_BLUEPRINT_COUNT
	)
	var overflow_result: GameSaveSectionResult = await _save_blueprint(
		tile_lab,
		_make_blueprint("超出上限"),
		setup
	)
	assert_true(
		overflow_result != null
		and overflow_result.get_error_code() == ERR_OUT_OF_MEMORY,
		"第 33 份蓝图必须被明确拒绝。"
	)
	_dispose_setup(setup)


func test_save_failure_rolls_back_profile_and_caller_identity() -> void:
	var storage: _FailingStorage = _FailingStorage.new()
	var setup: Dictionary = await _create_setup(storage)
	var tile_lab: TileLabSystem = _get_tile_lab(setup)
	var blueprint: CustomTileBlueprintData = _make_blueprint("不可写蓝图")
	storage.async_save_errors.append(ERR_CANT_CREATE)

	var save_result: GameSaveSectionResult = await _save_blueprint(
		tile_lab,
		blueprint,
		setup
	)
	assert_true(
		save_result != null
		and save_result.get_error_code() == ERR_CANT_CREATE
	)
	assert_true(
		blueprint.blueprint_id.is_empty(),
		"持久化失败不得让调用方误以为蓝图已保存。"
	)
	assert_true(
		tile_lab.load_blueprints().is_empty(),
		"SaveGraph 同步保存失败后必须回滚 section 内存快照。"
	)
	_dispose_setup(setup)


func test_tile_lab_ui_has_touch_targets_confirmation_and_initial_focus() -> void:
	var dialog_node: Node = _TILE_LAB_SCENE.instantiate()
	assert_true(dialog_node is TileLabDialog)
	if not dialog_node is TileLabDialog:
		dialog_node.queue_free()
		return
	var dialog: TileLabDialog = dialog_node
	autofree(dialog)
	add_child(dialog)
	await get_tree().process_frame

	for control_name: StringName in [
		&"BackButton",
		&"BlueprintOption",
		&"NameInput",
		&"NewButton",
		&"SaveButton",
		&"DeleteButton",
		&"BaseDefinitionOption",
		&"LeftValueSpin",
		&"RightValueSpin",
		&"RunSimulationButton",
	]:
		var node: Node = dialog.find_child(String(control_name), true, false)
		assert_true(node is Control, "试验台缺少交互控件：%s。" % control_name)
		if node is Control:
			var control: Control = node
			assert_gte(
				control.custom_minimum_size.x,
				_MINIMUM_TOUCH_TARGET_SIZE,
				"%s 触控宽度不得小于 44px。" % control_name
			)
			assert_gte(
				control.custom_minimum_size.y,
				_MINIMUM_TOUCH_TARGET_SIZE,
				"%s 触控高度不得小于 44px。" % control_name
			)

	assert_true(
		dialog.find_child("DeleteConfirmation", true, false)
		is ConfirmationDialog,
		"删除蓝图必须经过确认弹窗。"
	)
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	assert_true(
		focus_owner == dialog.find_child("BlueprintOption", true, false),
		"打开试验台时必须给键盘/手柄一个确定的初始焦点。"
	)
	var operation_token: int = dialog._begin_persistence_operation(
		&"save",
		"blueprint-under-test"
	)
	assert_true(operation_token > 0)
	assert_true(dialog._new_button.disabled, "保存操作在途时必须禁用新建，避免状态漂移。")
	assert_true(
		dialog._blueprint_option.disabled,
		"保存操作在途时必须禁用蓝图切换。"
	)
	assert_false(dialog._name_input.editable, "保存操作在途时不得继续编辑名称。")
	dialog._persistence_outcome_unknown = true
	dialog._pending_persistence_transaction_id = 91
	await dialog._on_section_reconciliation_settled({
		&"transaction_id": 91,
		&"status": "late_failure_rolled_back",
		&"candidate_persisted": false,
		&"memory_rolled_back": true,
	})
	assert_false(
		dialog._persistence_outcome_unknown,
		"晚到回滚终态必须解除试验台的持久化锁定。"
	)
	assert_false(dialog._persistence_operation_busy)
	assert_false(dialog._new_button.disabled, "对账收敛后必须恢复新建操作。")
	assert_false(dialog._blueprint_option.disabled, "对账收敛后必须恢复蓝图切换。")
	assert_true(dialog._name_input.editable, "对账收敛后必须恢复名称编辑。")
	assert_true(
		dialog._status_label.text
		== dialog.tr("TILE_LAB_RECONCILIATION_ROLLED_BACK"),
		"蓝图库回滚终态必须使用稳定本地化文案。"
	)


# --- 私有/辅助方法 ---

func _save_blueprint(
	tile_lab: TileLabSystem,
	blueprint: CustomTileBlueprintData,
	setup: Dictionary
) -> GameSaveSectionResult:
	return await GameSaveSectionOperationTestSupport.await_result(
		tile_lab.request_save_blueprint(blueprint),
		_get_architecture(setup),
		get_tree()
	)


func _delete_blueprint(
	tile_lab: TileLabSystem,
	blueprint_id: String,
	setup: Dictionary
) -> GameSaveSectionResult:
	return await GameSaveSectionOperationTestSupport.await_result(
		tile_lab.request_delete_blueprint(blueprint_id),
		_get_architecture(setup),
		get_tree()
	)


func _create_setup(
	storage_override: GFStorageUtility = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var storage: GFStorageUtility = (
		storage_override
		if storage_override != null
		else GFStorageUtility.new()
	)
	storage.save_dir_name = "gut_tile_lab_%d" % Time.get_ticks_usec()
	storage.allow_absolute_paths = false
	storage.create_directories_for_nested_paths = true
	storage.file_format = GFStorageCodec.Format.BINARY
	storage.include_storage_metadata = true
	storage.use_integrity_checksum = true

	var clock: GameClockUtility = GameClockUtility.new()
	assert_true(clock.set_clock(GFManualClock.new(0, 1_000_000)))
	var save_graph: GameSaveGraphUtility = GameSaveGraphUtility.new()
	assert_true(save_graph.register_section(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		TileDiscoverySaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	))
	assert_true(save_graph.register_section(
		TileLabSaveData.SECTION_ID,
		TileLabSaveData.new(),
		GameSaveGraphUtility.SectionOrder.NORMAL
	))
	var catalog: TileCatalogUtility = TileCatalogUtility.new()
	var composition: TileCompositionUtility = TileCompositionUtility.new()
	var capabilities: GFCapabilityUtility = GFCapabilityUtility.new()
	var discovery: TileDiscoverySystem = TileDiscoverySystem.new()
	var tile_lab: TileLabSystem = TileLabSystem.new()
	var platform_stub: GamePlatformUtility = (
		_TEST_PLATFORM_STUB_SCRIPT.new()
	)
	assert_not_null(platform_stub)

	await architecture.register_utility(GFStorageUtility, storage)
	await architecture.register_utility(
		GFSaveProfileUtility,
		GFSaveProfileUtility.new()
	)
	await architecture.register_utility(
		GFBackgroundWorkUtility,
		GFBackgroundWorkUtility.new()
	)
	await architecture.register_utility(GFLogUtility, GFLogUtility.new())
	await architecture.register_utility(
		GamePlatformUtility,
		platform_stub
	)
	await architecture.register_utility(GameClockUtility, clock)
	await architecture.register_utility(GFSignalUtility, GFSignalUtility.new())
	await architecture.register_utility(GameSaveGraphUtility, save_graph)
	await architecture.register_utility(GFAssetUtility, GFAssetUtility.new())
	await architecture.register_utility(
		GFResourceResolverUtility,
		GFResourceResolverUtility.new()
	)
	await architecture.register_utility(
		ProjectResourceCatalogUtility,
		ProjectResourceCatalogUtility.new()
	)
	await architecture.register_utility(GFCapabilityUtility, capabilities)
	await architecture.register_utility(TileCatalogUtility, catalog)
	await architecture.register_utility(TileCompositionUtility, composition)
	await architecture.register_system(TileDiscoverySystem, discovery)
	await architecture.register_system(TileLabSystem, tile_lab)
	await architecture.init()
	return {
		&"architecture": architecture,
		&"storage": storage,
		&"save_graph": save_graph,
		&"composition": composition,
		&"discovery": discovery,
		&"tile_lab": tile_lab,
		&"capabilities": capabilities,
	}


func _dispose_setup(
	setup: Dictionary,
	extra_profile_files: Array[String] = []
) -> void:
	var save_graph_value: Variant = setup.get(&"save_graph")
	if save_graph_value is GameSaveGraphUtility:
		var save_graph: GameSaveGraphUtility = save_graph_value
		var _flush_error: Error = save_graph.flush_pending_save()
	var architecture_value: Variant = setup.get(&"architecture")
	if architecture_value is GFArchitecture:
		var architecture: GFArchitecture = architecture_value
		architecture.dispose()
	var storage_value: Variant = setup.get(&"storage")
	if storage_value is GFStorageUtility:
		var storage: GFStorageUtility = storage_value
		var _legacy_delete_error: Error = storage.delete_file(
			GameSaveGraphUtility.PROFILE_FILE_NAME
		)
		for profile_file: String in extra_profile_files:
			var _profile_delete_error: Error = storage.delete_file(profile_file)


func _make_blueprint(display_name: String) -> CustomTileBlueprintData:
	var blueprint: CustomTileBlueprintData = CustomTileBlueprintData.new()
	blueprint.display_name = display_name
	blueprint.base_definition_id = _BASE_DEFINITION_ID
	blueprint.recipe_ids = [_CLASSIC_RECIPE_ID]
	blueprint.preview_left_value = 2
	blueprint.preview_right_value = 2
	return blueprint


func _make_strict_blueprint(
	recipe_ids: Array[StringName]
) -> CustomTileBlueprintData:
	var blueprint: CustomTileBlueprintData = CustomTileBlueprintData.new()
	blueprint.blueprint_id = GFUuid.generate_v7(1_000_000)
	blueprint.display_name = "严格蓝图"
	blueprint.base_definition_id = _BASE_DEFINITION_ID
	blueprint.recipe_ids = recipe_ids.duplicate()
	blueprint.preview_left_value = 2
	blueprint.preview_right_value = 3
	blueprint.created_at = 1_000
	blueprint.updated_at = 1_001
	return blueprint


func _report_has_issue(
	report: GFValidationReport,
	kind: StringName
) -> bool:
	for issue_value: Variant in GFVariantData.get_option_array(
		report.to_dict(),
		&"issues"
	):
		if not issue_value is Dictionary:
			continue
		if (
			GFVariantData.get_option_string_name(
				GFVariantData.as_dictionary(issue_value),
				&"kind"
			)
			== kind
		):
			return true
	return false


func _get_save_graph(setup: Dictionary) -> GameSaveGraphUtility:
	var value: Variant = setup.get(&"save_graph")
	if value is GameSaveGraphUtility:
		return value
	assert_true(false, "测试 setup 缺少 GameSaveGraphUtility。")
	return GameSaveGraphUtility.new()


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get(&"architecture")
	if value is GFArchitecture:
		return value
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_composition(setup: Dictionary) -> TileCompositionUtility:
	var value: Variant = setup.get(&"composition")
	if value is TileCompositionUtility:
		return value
	assert_true(false, "测试 setup 缺少 TileCompositionUtility。")
	return TileCompositionUtility.new()


func _get_discovery(setup: Dictionary) -> TileDiscoverySystem:
	var value: Variant = setup.get(&"discovery")
	if value is TileDiscoverySystem:
		return value
	assert_true(false, "测试 setup 缺少 TileDiscoverySystem。")
	return TileDiscoverySystem.new()


func _get_tile_lab(setup: Dictionary) -> TileLabSystem:
	var value: Variant = setup.get(&"tile_lab")
	if value is TileLabSystem:
		return value
	assert_true(false, "测试 setup 缺少 TileLabSystem。")
	return TileLabSystem.new()


# --- 内部类 ---

class _FailingStorage extends GFStorageUtility:
	var async_save_errors: Array[Error] = []
	var _next_request_id: int = 1


	## 为 GFSaveProfileUtility 的请求专属异步写入注入错误队列。
	## @param file_name: GFStorage 相对文件名。
	## @param data: 要持久化的完整数据字典。
	func save_data_request_async(
		file_name: String,
		data: Dictionary
	) -> GFStorageAsyncOperation:
		if async_save_errors.is_empty():
			return super.save_data_request_async(file_name, data)
		var scripted_error: Error = async_save_errors.pop_front()
		if scripted_error == OK:
			return super.save_data_request_async(file_name, data)
		var operation: GFStorageAsyncOperation = GFStorageAsyncOperation.new()
		var request_id: int = _next_request_id
		_next_request_id += 1
		var _configured_operation: bool = (
			operation.configure_for_framework(
				request_id,
				GFStorageAsyncOperation.OPERATION_SAVE,
				file_name
			)
		)
		var result: GFStorageAsyncResult = GFStorageAsyncResult.new()
		var _configured_result: bool = result.configure_for_framework(
			request_id,
			GFStorageAsyncOperation.OPERATION_SAVE,
			file_name,
			false,
			scripted_error
		)
		var _completed: bool = operation.complete_for_framework(result)
		return operation
