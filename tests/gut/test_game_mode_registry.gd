## 验证游戏模式配置通过 GFResourceRegistry 暴露并接入 GFAssetUtility 分组。
extends GutTest


# --- 常量 ---

const EXPECTED_MODE_CONFIG_PATHS: Array[String] = [
	"res://features/gameplay/resources/modes/classic_mode_config.tres",
	"res://features/gameplay/resources/modes/fibonacci_mode_config.tres",
	"res://features/gameplay/resources/modes/lucas_fibonacci_mode_config.tres",
	"res://features/gameplay/resources/modes/progressive_mode_config.tres",
	"res://features/gameplay/resources/modes/step_by_step_mode_config.tres",
	"res://features/gameplay/resources/modes/ratio_mode_config.tres",
]

const EXPECTED_MODE_RESOURCE_KEYS: Array[String] = [
	"game.mode_config.classic",
	"game.mode_config.fibonacci",
	"game.mode_config.lucas_fibonacci",
	"game.mode_config.progressive",
	"game.mode_config.step_by_step",
	"game.mode_config.ratio",
]


# --- 测试用例 ---

func test_registered_mode_paths_match_registry_order() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var mode_paths: PackedStringArray = mode_catalog.get_registered_config_paths()

	assert_true(
		_packed_paths_to_array(mode_paths) == EXPECTED_MODE_CONFIG_PATHS,
		"模式配置路径应由 GFResourceRegistry 按注册顺序提供。"
	)

	architecture.dispose()


func test_registered_mode_paths_load_valid_game_mode_configs() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	for config_path: String in mode_catalog.get_registered_config_paths():
		var mode_config: GameModeConfig = mode_catalog.get_config(config_path)

		assert_true(is_instance_valid(mode_config), "注册表路径应能加载 GameModeConfig: %s" % config_path)
		assert_true(mode_config.validate(), "注册表中的模式配置应通过自身校验: %s" % config_path)

	architecture.dispose()


func test_mode_config_hot_path_never_falls_back_to_synchronous_loading() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var asset_utility: GFAssetUtility = _get_asset_utility(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var config_path: String = EXPECTED_MODE_CONFIG_PATHS[0]
	asset_utility.remove_cache(config_path)

	var mode_config: GameModeConfig = mode_catalog.get_config(config_path)
	assert_push_error("模式配置缓存不可用")

	assert_null(
		mode_config,
		"预载缓存缺失时业务热路径必须失败，不得静默退回同步 ResourceLoader。"
	)
	assert_false(
		asset_utility.is_cached(config_path),
		"get_config() 不得自行同步加载并回填 GF asset cache。"
	)
	architecture.dispose()


func test_classic_style_modes_define_optional_2048_target() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	for config_path: String in mode_catalog.get_registered_config_paths():
		var mode_config: GameModeConfig = mode_catalog.get_config(config_path)
		var expected_target: int = _get_expected_target_for_mode(config_path)

		assert_true(is_instance_valid(mode_config), "注册表路径应能加载 GameModeConfig: %s" % config_path)
		if not is_instance_valid(mode_config):
			continue
		assert_true(
			mode_config.target_tile_value == expected_target,
			"模式目标值应与玩法语义一致: %s" % config_path
		)
		assert_true(
			mode_config.has_target() == (expected_target > 0),
			"has_target() 应仅在配置目标值时返回 true: %s" % config_path
		)
		if expected_target > 0:
			assert_true(mode_config.is_target_reached(expected_target), "达到目标值时应判定目标达成。")
			assert_true(not mode_config.is_target_reached(floori(float(expected_target) / 2.0)), "未达到目标值时不应判定目标达成。")

	architecture.dispose()


func test_mode_registry_registers_asset_group_paths_when_utility_is_ready() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var asset_utility: GFAssetUtility = _get_asset_utility(setup)

	var group_paths: PackedStringArray = asset_utility.get_group_paths(&"game_modes")
	var sorted_group_paths: Array[String] = _packed_paths_to_array(group_paths)
	var sorted_expected_paths: Array[String] = EXPECTED_MODE_CONFIG_PATHS.duplicate()
	sorted_group_paths.sort()
	sorted_expected_paths.sort()

	assert_true(sorted_group_paths == sorted_expected_paths, "模式缓存 Utility ready 后应把注册表路径登记为 GFAssetUtility 分组。")

	architecture.dispose()


func test_mode_catalog_primes_registered_configs_through_gf_asset_group() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var asset_utility: GFAssetUtility = _get_asset_utility(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)

	for _frame_index: int in range(180):
		asset_utility.tick()
		var all_cached: bool = true
		for config_path: String in EXPECTED_MODE_CONFIG_PATHS:
			if not asset_utility.is_cached(config_path):
				all_cached = false
				break
		if all_cached:
			break
		await get_tree().process_frame

	for config_path: String in EXPECTED_MODE_CONFIG_PATHS:
		assert_true(
			asset_utility.is_cached(config_path),
			"模式目录 ready 后应通过 GFAssetUtility 异步预热配置：%s"
			% config_path
		)
	var preload_session: GFAssetLoadSession = mode_catalog.get_preload_session()
	assert_not_null(preload_session, "模式目录应持有 GFAssetLoadSession。")
	var preload_result: GFAssetLoadSessionResult = (
		preload_session.get_result() if preload_session != null else null
	)
	var loaded_paths: Array[String] = (
		_packed_paths_to_array(preload_result.get_loaded_paths())
		if preload_result != null
		else []
	)
	var expected_loaded_paths: Array[String] = EXPECTED_MODE_CONFIG_PATHS.duplicate()
	loaded_paths.sort()
	expected_loaded_paths.sort()
	assert_not_null(preload_result, "模式目录预载应提供 GF typed 终态。")
	assert_true(
		preload_result != null
		and preload_result.get_status() == GFAssetLoadSessionResult.STATUS_COMMITTED,
		"模式目录应以 committed GFAssetLoadSession 作为成功终态。"
	)
	assert_true(
		preload_result != null and preload_result.get_plan_id() == &"game_modes.preload",
		"模式目录会话应暴露稳定 preload plan identity。"
	)
	assert_true(
		loaded_paths == expected_loaded_paths,
		"模式目录 typed 终态应记录完整的已加载配置集合。"
	)
	assert_true(
		preload_result != null and preload_result.get_failed_paths().is_empty(),
		"成功提交的模式目录会话不应包含失败路径。"
	)
	assert_true(
		asset_utility.get_active_preload_session_count() == 0,
		"会话提交后 GFAssetUtility 不应保留活动模式预载会话。"
	)

	architecture.dispose()


func test_mode_catalog_dispose_rolls_back_loading_asset_session_before_group_release() -> void:
	var asset_utility: _DeferredAssetUtility = _DeferredAssetUtility.new()
	var setup: Dictionary = await _create_mode_catalog_setup(false, asset_utility)
	var architecture: GFArchitecture = _get_architecture(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var preload_session: GFAssetLoadSession = mode_catalog.get_preload_session()

	assert_not_null(preload_session, "模式目录应创建可回滚的 GFAssetLoadSession。")
	assert_true(
		preload_session != null
		and preload_session.get_state() == GFAssetLoadSession.State.LOADING,
		"延迟加载夹具应让模式目录会话保持 LOADING。"
	)
	mode_catalog.dispose()
	assert_true(
		preload_session != null
		and preload_session.get_state() == GFAssetLoadSession.State.ROLLBACK_PENDING,
		"目录销毁必须先请求回滚，再释放目标 group。"
	)
	asset_utility.settle_pending_success()
	var result: GFAssetLoadSessionResult = (
		preload_session.get_result() if preload_session != null else null
	)
	assert_true(
		result != null
		and result.get_status() == GFAssetLoadSessionResult.STATUS_ROLLED_BACK,
		"迟到加载收敛后必须保持 rolled_back，不能重新提交目标 group。"
	)
	assert_true(
		result != null and result.get_rollback_reason() == &"catalog_disposed",
		"模式目录销毁原因应进入 GF typed 终态。"
	)
	assert_true(
		asset_utility.get_group_paths(&"game_modes").is_empty(),
		"回滚完成后不得留下孤儿模式资源 group。"
	)
	assert_true(
		asset_utility.get_active_preload_session_count() == 0,
		"回滚终态后 GFAssetUtility 不应保留活动会话。"
	)

	architecture.dispose()


func test_catalog_unregister_owns_loading_session_rollback_without_mode_assistance() -> void:
	var asset_utility: _DeferredAssetUtility = _DeferredAssetUtility.new()
	var setup: Dictionary = await _create_mode_catalog_setup(false, asset_utility)
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var preload_session: GFAssetLoadSession = mode_catalog.get_preload_session()

	assert_not_null(preload_session, "模式目录应创建由 Catalog 关联的活动会话。")
	assert_true(
		catalog.unregister_catalog(&"game_modes", true),
		"直接注销目录应成功接管活动会话的回滚。"
	)
	assert_true(
		preload_session != null
		and preload_session.get_state() == GFAssetLoadSession.State.ROLLBACK_PENDING,
		"ProjectResourceCatalogUtility 必须在释放 group 前回滚活动会话。"
	)
	asset_utility.settle_pending_success()
	var result: GFAssetLoadSessionResult = (
		preload_session.get_result() if preload_session != null else null
	)
	assert_true(
		result != null
		and result.get_status() == GFAssetLoadSessionResult.STATUS_ROLLED_BACK,
		"直接注销后的迟到加载不得重新创建目标 group。"
	)
	assert_true(
		result != null and result.get_rollback_reason() == &"catalog_unregistered",
		"Catalog 所有权回滚应保留明确注销原因。"
	)
	assert_true(
		asset_utility.get_group_paths(&"game_modes").is_empty(),
		"直接注销目录后不得残留或迟到重建模式资源 group。"
	)
	assert_true(
		asset_utility.get_active_preload_session_count() == 0,
		"Catalog 所有权回滚收敛后 GFAssetUtility 不应保留活动会话。"
	)

	architecture.dispose()


func test_catalog_replacement_rejects_preload_reentry_from_rollback_signal() -> void:
	var asset_utility: _DeferredAssetUtility = _DeferredAssetUtility.new()
	var setup: Dictionary = await _create_mode_catalog_setup(false, asset_utility)
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var preload_session: GFAssetLoadSession = mode_catalog.get_preload_session()
	var reentry_probe: _CatalogReentryProbe = _CatalogReentryProbe.new(catalog)

	assert_not_null(preload_session, "模式目录应创建可用于替换回归的活动会话。")
	if preload_session == null:
		architecture.dispose()
		return
	var connect_error: int = preload_session.state_changed.connect(reentry_probe.on_state_changed)
	assert_true(connect_error == OK, "替换回归应能监听旧会话的回滚状态。")
	var replacement_report: GFValidationReport = catalog.register_catalog(
		&"game_modes",
		GameModeCatalogUtility.DEFAULT_MODE_REGISTRY,
		"game.mode_config.",
		"Resource",
		&"game_modes",
		{"registry": "replacement_game_mode_registry"}
	)

	assert_true(replacement_report.is_ok(), "合法目录替换应完成。")
	assert_true(reentry_probe.attempt_count == 1, "回滚状态信号应触发一次同步重入探针。")
	assert_null(
		reentry_probe.attempted_session,
		"目录替换事务期间必须拒绝从旧会话状态信号重入启动预载。"
	)
	asset_utility.settle_pending_success()
	var old_result: GFAssetLoadSessionResult = preload_session.get_result()
	assert_true(
		old_result != null
		and old_result.get_status() == GFAssetLoadSessionResult.STATUS_ROLLED_BACK,
		"旧目录会话迟到收敛后必须保持 rolled_back。"
	)
	assert_true(
		old_result != null and old_result.get_rollback_reason() == &"catalog_replaced",
		"旧目录会话应保留明确的替换回滚原因。"
	)

	architecture.dispose()


func test_catalog_preload_supersede_rejects_reentrant_catalog_replacement() -> void:
	var asset_utility: _DeferredAssetUtility = _DeferredAssetUtility.new()
	var setup: Dictionary = await _create_mode_catalog_setup(false, asset_utility)
	var architecture: GFArchitecture = _get_architecture(setup)
	var catalog: ProjectResourceCatalogUtility = _get_resource_catalog(setup)
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog(setup)
	var old_session: GFAssetLoadSession = mode_catalog.get_preload_session()
	var replacement_probe: _CatalogReplacementReentryProbe = (
		_CatalogReplacementReentryProbe.new(catalog)
	)

	assert_not_null(old_session, "模式目录应创建可用于 supersede 回归的活动会话。")
	if old_session == null:
		architecture.dispose()
		return
	var connect_error: int = old_session.state_changed.connect(
		replacement_probe.on_state_changed
	)
	assert_true(connect_error == OK, "supersede 回归应能监听旧会话回滚。")
	var new_session: GFAssetLoadSession = catalog.start_catalog_preload_session(
		&"game_modes",
		{
			"plan_id": &"game_modes.replacement_guard",
			"max_concurrent_loads": 2,
			"lane_id": &"game_mode_catalog",
		}
	)

	assert_not_null(new_session, "拒绝重入替换后，外层 supersede 应继续启动当前目录会话。")
	assert_true(replacement_probe.attempt_count == 1, "旧会话回滚应触发一次目录替换重入探针。")
	assert_not_null(replacement_probe.replacement_report, "重入替换应返回可诊断的校验报告。")
	assert_true(
		replacement_probe.replacement_report != null
		and not replacement_probe.replacement_report.is_ok(),
		"会话 supersede 事务期间必须拒绝目录替换重入。"
	)
	assert_true(
		replacement_probe.replacement_report != null
		and GFVariantData.get_option_int(
			replacement_probe.replacement_report.get_issue_counts_by_kind(),
			&"catalog_mutation_in_progress"
		) == 1,
		"重入失败应报告稳定的 catalog_mutation_in_progress 原因。"
	)
	asset_utility.settle_pending_success()
	asset_utility.settle_pending_success()
	var old_result: GFAssetLoadSessionResult = old_session.get_result()
	var new_result: GFAssetLoadSessionResult = (
		new_session.get_result() if new_session != null else null
	)
	assert_true(
		old_result != null
		and old_result.get_status() == GFAssetLoadSessionResult.STATUS_ROLLED_BACK,
		"被 supersede 的旧会话必须以 rolled_back 收敛。"
	)
	assert_true(
		new_result != null
		and new_result.get_status() == GFAssetLoadSessionResult.STATUS_COMMITTED,
		"重入替换被拒绝后，新会话应提交当前目录定义。"
	)

	architecture.dispose()


func test_mode_registry_registers_resolver_resource_keys_when_utility_is_ready() -> void:
	var setup: Dictionary = await _create_mode_catalog_setup()
	var architecture: GFArchitecture = _get_architecture(setup)
	var resolver: GFResourceResolverUtility = _get_resolver(setup)

	for resource_key: String in EXPECTED_MODE_RESOURCE_KEYS:
		assert_true(
			resolver.has_registered_key(StringName(resource_key)),
			"模式缓存 Utility ready 后应把模式配置注册为 GFResourceResolverUtility 资源键: %s" % resource_key
		)

	var resource: Resource = resolver.load(&"game.mode_config.classic", "Resource")
	assert_true(resource is GameModeConfig, "应能通过稳定资源键加载经典模式配置。")

	architecture.dispose()


func test_mode_validation_rejects_unknown_spawn_definition_reference() -> void:
	var resource: Resource = load("res://features/gameplay/resources/modes/ratio_mode_config.tres")
	assert_true(resource is GameModeConfig, "应加载比值模式配置。")
	if not resource is GameModeConfig:
		return
	var mode_config: GameModeConfig = resource.duplicate(true)
	var ratio_spawn_rule: ProbabilisticRatioSpawnRule = null
	for spawn_rule: SpawnRule in mode_config.spawn_rules:
		if spawn_rule is ProbabilisticRatioSpawnRule:
			ratio_spawn_rule = spawn_rule
			break
	assert_not_null(ratio_spawn_rule, "比值模式应包含概率因子方块生成规则。")
	if ratio_spawn_rule == null:
		return
	ratio_spawn_rule.alternate_definition_id = &"tile.ratio.unknown"

	var report: GFValidationReport = mode_config.get_validation_report()
	assert_false(report.is_ok(), "生成规则引用未声明定义时模式配置必须无效。")
	assert_true(
		GFVariantData.get_option_int(report.get_issue_counts_by_kind(), &"unknown_spawn_definition_id") == 1,
		"模式校验应明确报告未知的生成 definition_id。"
	)


func test_mode_validation_rejects_unimplemented_timer_spawn_trigger() -> void:
	var resource: Resource = load("res://features/gameplay/resources/modes/classic_mode_config.tres")
	assert_true(resource is GameModeConfig, "应加载经典模式配置。")
	if not resource is GameModeConfig:
		return
	var mode_config: GameModeConfig = resource.duplicate(true)
	assert_false(mode_config.spawn_rules.is_empty(), "经典模式应包含生成规则。")
	if mode_config.spawn_rules.is_empty():
		return
	var isolated_spawn_rules: Array[SpawnRule] = mode_config.spawn_rules.duplicate()
	var isolated_rule_value: Resource = isolated_spawn_rules[0].duplicate(true)
	assert_true(isolated_rule_value is SpawnRule, "负例必须使用独立的 SpawnRule 副本。")
	if not isolated_rule_value is SpawnRule:
		return
	var isolated_rule: SpawnRule = isolated_rule_value
	isolated_spawn_rules[0] = isolated_rule
	mode_config.spawn_rules = isolated_spawn_rules
	isolated_rule.trigger = SpawnRule.TriggerType.ON_TIMER

	var report: GFValidationReport = mode_config.get_validation_report()
	assert_false(report.is_ok(), "没有确定性调度入口的 ON_TIMER 规则必须在加载前被拒绝。")
	assert_true(
		GFVariantData.get_option_int(
			report.get_issue_counts_by_kind(),
			&"unsupported_timer_trigger"
		) == 1,
		"模式校验应明确报告未实现的计时生成触发器。"
	)


# --- 私有/辅助方法 ---

func _create_mode_catalog_setup(
	wait_for_preload: bool = true,
	asset_utility_override: GFAssetUtility = null
) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var asset_utility: GFAssetUtility = (
		asset_utility_override
		if asset_utility_override != null
		else GFAssetUtility.new()
	)
	var resolver: GFResourceResolverUtility = GFResourceResolverUtility.new()
	var catalog: ProjectResourceCatalogUtility = ProjectResourceCatalogUtility.new()
	var mode_catalog: GameModeCatalogUtility = GameModeCatalogUtility.new()

	await architecture.register_utility(GFResourceBroker, GFResourceBroker.new())
	await architecture.register_utility(GFAssetUtility, asset_utility)
	await architecture.register_utility(GFResourceResolverUtility, resolver)
	await architecture.register_utility(ProjectResourceCatalogUtility, catalog)
	await architecture.register_utility(GameModeCatalogUtility, mode_catalog)
	await architecture.init()
	var preload_session: GFAssetLoadSession = mode_catalog.get_preload_session()
	if wait_for_preload:
		for _frame_index: int in range(240):
			asset_utility.tick()
			if preload_session != null and preload_session.is_completed():
				break
			await get_tree().process_frame
		assert_not_null(preload_session, "模式目录应暴露 GFAssetLoadSession 唯一终态。")
		if preload_session != null:
			var preload_result: GFAssetLoadSessionResult = preload_session.get_result()
			assert_true(
				preload_result != null and preload_result.is_successful(),
				"模式配置应在业务读取前由 GFAssetLoadSession 提交。"
			)

	return {
		"architecture": architecture,
		"asset_utility": asset_utility,
		"resolver": resolver,
		"catalog": catalog,
		"mode_catalog": mode_catalog,
	}


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = setup.get("architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	assert_true(false, "测试 setup 缺少 GFArchitecture。")
	return GFArchitecture.new()


func _get_asset_utility(setup: Dictionary) -> GFAssetUtility:
	var value: Variant = setup.get("asset_utility")
	if value is GFAssetUtility:
		var asset_utility: GFAssetUtility = value
		return asset_utility
	assert_true(false, "测试 setup 缺少 GFAssetUtility。")
	return GFAssetUtility.new()


func _get_resolver(setup: Dictionary) -> GFResourceResolverUtility:
	var value: Variant = setup.get("resolver")
	if value is GFResourceResolverUtility:
		var resolver: GFResourceResolverUtility = value
		return resolver
	assert_true(false, "测试 setup 缺少 GFResourceResolverUtility。")
	return GFResourceResolverUtility.new()


func _get_resource_catalog(setup: Dictionary) -> ProjectResourceCatalogUtility:
	var value: Variant = setup.get("catalog")
	if value is ProjectResourceCatalogUtility:
		var catalog: ProjectResourceCatalogUtility = value
		return catalog
	assert_true(false, "测试 setup 缺少 ProjectResourceCatalogUtility。")
	return ProjectResourceCatalogUtility.new()


func _get_mode_catalog(setup: Dictionary) -> GameModeCatalogUtility:
	var value: Variant = setup.get("mode_catalog")
	if value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = value
		return mode_catalog
	assert_true(false, "测试 setup 缺少 GameModeCatalogUtility。")
	return GameModeCatalogUtility.new()


func _packed_paths_to_array(paths: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for path: String in paths:
		result.append(path)
	return result


func _get_expected_target_for_mode(config_path: String) -> int:
	match config_path:
		"res://features/gameplay/resources/modes/classic_mode_config.tres":
			return 2048
		"res://features/gameplay/resources/modes/progressive_mode_config.tres":
			return 2048
		"res://features/gameplay/resources/modes/step_by_step_mode_config.tres":
			return 2048
		_:
			return 0


# --- 内部类 ---

class _DeferredAssetUtility extends GFAssetUtility:
	var _pending_requests: Array[Dictionary] = []


	## @param group_id: 记录 GFAssetLoadSession 的 staging group。
	## @param entries: 记录会话提交的资源条目。
	## @param on_completed: 延迟到测试显式收敛时调用的完成回调。
	## @param _options: 测试替身不解释加载选项。
	func preload_group_async(
		group_id: StringName,
		entries: Array,
		on_completed: Callable = Callable(),
		_options: Dictionary = {}
	) -> void:
		_pending_requests.append({
			"group_id": group_id,
			"entries": entries.duplicate(true),
			"completion": on_completed,
		})


	func settle_pending_success() -> void:
		if _pending_requests.is_empty():
			return
		var request: Dictionary = _pending_requests[0]
		_pending_requests.remove_at(0)
		var group_id: StringName = GFVariantData.get_option_string_name(request, "group_id")
		var pending_entries: Array = GFVariantData.get_option_array(request, "entries")
		var completion_value: Variant = request.get("completion")
		var completion: Callable = (
			completion_value if completion_value is Callable else Callable()
		)
		if not completion.is_valid():
			return
		var loaded_paths: PackedStringArray = PackedStringArray()
		for entry_value: Variant in pending_entries:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var path: String = GFVariantData.get_option_string(entry, "path")
			if path.is_empty():
				continue
			register_group_path(group_id, path, false)
			var _path_appended: bool = loaded_paths.append(path)
		var completed_count: int = pending_entries.size()
		completion.call({
			"ok": true,
			"group_id": group_id,
			"paths": loaded_paths,
			"failed_paths": PackedStringArray(),
			"total": completed_count,
			"completed": completed_count,
		})


class _CatalogReentryProbe extends RefCounted:
	var attempt_count: int = 0
	var attempted_session: GFAssetLoadSession = null
	var _catalog: ProjectResourceCatalogUtility = null


	func _init(catalog: ProjectResourceCatalogUtility) -> void:
		_catalog = catalog


	## @param _previous_state: 旧会话进入回滚前的状态。
	## @param current_state: 旧会话当前状态。
	func on_state_changed(
		_previous_state: GFAssetLoadSession.State,
		current_state: GFAssetLoadSession.State
	) -> void:
		if current_state != GFAssetLoadSession.State.ROLLBACK_PENDING:
			return
		attempt_count += 1
		attempted_session = _catalog.start_catalog_preload_session(&"game_modes")


class _CatalogReplacementReentryProbe extends RefCounted:
	var attempt_count: int = 0
	var replacement_report: GFValidationReport = null
	var _catalog: ProjectResourceCatalogUtility = null


	func _init(catalog: ProjectResourceCatalogUtility) -> void:
		_catalog = catalog


	## @param _previous_state: 被 supersede 会话进入回滚前的状态。
	## @param current_state: 被 supersede 会话当前状态。
	func on_state_changed(
		_previous_state: GFAssetLoadSession.State,
		current_state: GFAssetLoadSession.State
	) -> void:
		if current_state != GFAssetLoadSession.State.ROLLBACK_PENDING:
			return
		attempt_count += 1
		replacement_report = _catalog.register_catalog(
			&"game_modes",
			GameModeCatalogUtility.DEFAULT_MODE_REGISTRY,
			"game.mode_config.",
			"Resource",
			&"replacement_game_modes",
			{"registry": "reentrant_replacement"}
		)
