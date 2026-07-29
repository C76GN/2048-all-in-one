## 跨模式、拓扑、性能档位与平台边界的可重复优化验收矩阵。
extends GutTest


# --- 常量 ---

const DeterministicHintQueryType = preload(
	"res://features/gameplay/scripts/queries/deterministic_hint_query.gd"
)
const GameHintResultType = preload(
	"res://features/gameplay/scripts/data/game_hint_result.gd"
)
const _EXPORT_CONFIG_PATH: String = "res://export_presets.cfg"
const _LOCAL_ADAPTER_SCRIPT_PATH: String = (
	"res://features/platform_runtime/scripts/adapters/local_platform_adapter.gd"
)
const _WEB_PRESET_NAME: String = "Web Compatibility Smoke"
const _LARGE_BOARD_SIZE: Vector2i = Vector2i(512, 256)
const _VISIBLE_CELL_RECT: Rect2i = Rect2i(247, 101, 13, 9)
const _GOLDEN_SAMPLE_COUNT: int = 4

const _MODE_ROWS: Array[Dictionary] = [
	{
		&"id": &"gameplay.classic",
		&"path": "res://features/gameplay/resources/modes/classic_mode_config.tres",
		&"seed": 2048,
	},
	{
		&"id": &"gameplay.step_by_step",
		&"path": "res://features/gameplay/resources/modes/step_by_step_mode_config.tres",
		&"seed": 4096,
	},
	{
		&"id": &"gameplay.ratio",
		&"path": "res://features/gameplay/resources/modes/ratio_mode_config.tres",
		&"seed": 8192,
	},
	{
		&"id": &"gameplay.progressive",
		&"path": "res://features/gameplay/resources/modes/progressive_mode_config.tres",
		&"seed": 16384,
	},
	{
		&"id": &"gameplay.fibonacci",
		&"path": "res://features/gameplay/resources/modes/fibonacci_mode_config.tres",
		&"seed": 32768,
	},
	{
		&"id": &"gameplay.lucas_fibonacci",
		&"path": "res://features/gameplay/resources/modes/lucas_fibonacci_mode_config.tres",
		&"seed": 65536,
	},
]

const _EXPECTED_GOLDEN_SUMMARIES: Dictionary = {
	"gameplay.classic|rectangle": "aeec590bb2bda57bc75ecd61b27752456c1958fbd7648e56c0e174896164bc25",
	"gameplay.classic|sparse_cross": "1692275e72b083d532604edf193afe01b4da77063ad60f1ab7fa65a4ebc3c354",
	"gameplay.step_by_step|rectangle": "9fe9bff4664adbba18f64ce6338f724bc309fe73a79de37a2d640a3b0550c226",
	"gameplay.step_by_step|sparse_cross": "c6513ea2b491a93300c7ceae9317246c312be9f9d0cfa50072eee14ef3ff2267",
	"gameplay.ratio|rectangle": "b7fb4e1a46bafc25cc9c05d5ead3e1baa3166dc037cf0334dfcc69e871331eac",
	"gameplay.ratio|sparse_cross": "9126dbaccef7f8d6153258494205e50ca94c3ed6333f1cba29e4938c624d30b6",
	"gameplay.progressive|rectangle": "875bf6f75ed536afc6f55ad45c08940aa156bc5bf8da64d9721b715b28494b0c",
	"gameplay.progressive|sparse_cross": "61ea0dcbb2fc11d7302536591179b07fd9ae98545e0d71660d22b500d6ab553e",
	"gameplay.fibonacci|rectangle": "30cc2a0beae267fc5d0b28e1cae922ce7cbb14ccd68224fc9fce11abf78a40d4",
	"gameplay.fibonacci|sparse_cross": "cf465f341624526489e8a4209d3e3f97873057c6655a930c80e95ef9afeb8608",
	"gameplay.lucas_fibonacci|rectangle": "6230fcd7dfd21c6e7483813bc6c9e647b8b5a5779befdd424c6f4cf123caed58",
	"gameplay.lucas_fibonacci|sparse_cross": "740e995578bc0b59fc8526814952d0ba80f04ef6af878c433de7b1b75c48d5a9",
}


# --- 测试用例 ---

func test_six_modes_and_two_topologies_match_fixed_golden_summaries() -> void:
	var topology_rows: Array[Dictionary] = _make_topology_rows()
	var observed_summaries: Dictionary = {}
	var determinism: GameDeterminismUtility = GameDeterminismUtility.new()

	assert_true(
		topology_rows.size() == 2,
		"确定性验收必须同时覆盖矩形和稀疏拓扑。"
	)
	for mode_row: Dictionary in _MODE_ROWS:
		var mode_path: String = GFVariantData.get_option_string(mode_row, &"path")
		var mode_value: Resource = load(mode_path)
		assert_true(mode_value is GameModeConfig, "模式资源必须可加载：%s" % mode_path)
		if not mode_value is GameModeConfig:
			continue
		var mode_config: GameModeConfig = mode_value
		var expected_mode_id: StringName = GFVariantData.get_option_string_name(
			mode_row,
			&"id"
		)
		assert_true(
			mode_config.ruleset_id == expected_mode_id,
			"模式资源的 ruleset_id 必须与验收矩阵一致：%s" % mode_path
		)
		assert_true(
			mode_config.get_validation_report().is_ok(),
			"模式资源必须通过完整规则校验：%s" % mode_path
		)
		var ruleset_fingerprint: String = determinism.calculate_ruleset_fingerprint(
			mode_config
		)
		assert_true(
			ruleset_fingerprint.length() == 64,
			"每种模式必须提供稳定规则集指纹：%s" % expected_mode_id
		)

		for topology_row: Dictionary in topology_rows:
			var topology_value: Variant = topology_row.get(&"topology")
			assert_true(
				topology_value is BoardTopology,
				"验收矩阵拓扑必须是 BoardTopology。"
			)
			if not topology_value is BoardTopology:
				continue
			var topology: BoardTopology = topology_value
			var topology_id: StringName = GFVariantData.get_option_string_name(
				topology_row,
				&"id"
			)
			var summary_key: String = "%s|%s" % [
				String(expected_mode_id),
				String(topology_id),
			]
			var summary: String = _make_golden_summary(
				mode_config,
				topology,
				GFVariantData.get_option_int(mode_row, &"seed"),
				ruleset_fingerprint
			)
			observed_summaries[summary_key] = summary
			var expected_summary: String = GFVariantData.get_option_string(
				_EXPECTED_GOLDEN_SUMMARIES,
				summary_key
			)
			assert_true(
				summary == expected_summary,
				"%s 的固定 seed 摘要漂移：%s" % [summary_key, summary]
			)

	assert_true(
		observed_summaries.size() == _MODE_ROWS.size() * topology_rows.size(),
		"6 种模式 × 2 种拓扑必须产生完整的 12 项确定性摘要。"
	)


func test_large_board_visible_query_and_hint_deadline_are_operation_bounded() -> void:
	var topology: CountingBoardTopology = _make_large_counting_topology()
	assert_true(
		topology.get_cell_count() == _LARGE_BOARD_SIZE.x * _LARGE_BOARD_SIZE.y,
		"大棋盘夹具必须覆盖 131072 个活跃单元。"
	)
	assert_true(
		topology.get_bounds_size() == _LARGE_BOARD_SIZE,
		"大棋盘包围盒必须与夹具尺寸一致。"
	)

	var _warmed_cells: Array[Vector2i] = topology.get_cells_in_rect(
		_VISIBLE_CELL_RECT
	)
	topology.lower_bound_call_count = 0
	var visible_cells: Array[Vector2i] = topology.get_cells_in_rect(
		_VISIBLE_CELL_RECT
	)
	assert_true(
		visible_cells.size() == _VISIBLE_CELL_RECT.size.x * _VISIBLE_CELL_RECT.size.y,
		"矩形大棋盘可见区查询只应返回窗口内单元。"
	)
	var first_visible_cell: Vector2i = visible_cells.front()
	var last_visible_cell: Vector2i = visible_cells.back()
	assert_true(
		first_visible_cell == _VISIBLE_CELL_RECT.position
		and last_visible_cell == _VISIBLE_CELL_RECT.end - Vector2i.ONE,
		"可见区查询必须保持行优先且边界准确。"
	)
	assert_true(
		topology.lower_bound_call_count == _VISIBLE_CELL_RECT.size.y,
		"热查询每个可见行只允许一次二分入口，不得按整张大棋盘重复定位。"
	)

	var deadline_budget: GFExecutionBudget = GFExecutionBudget.new(
		{
			&"max_steps": BoardTopology.MAX_CELL_COUNT,
			&"max_elapsed_msec": 16,
			&"metadata": {&"operation": &"optimization_acceptance_hint"},
		},
		AdvancingClock.new(1)
	)
	var hint_result: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		{
			&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
			&"topology": topology.to_dict(),
			&"tiles": [],
		},
		"optimization-acceptance-large-board",
		deadline_budget
	)
	assert_true(
		hint_result.termination_reason == GameHintResultType.TERMINATION_TIME_LIMIT,
		"超大棋盘提示必须响应 GFExecutionBudget 的确定性 deadline。"
	)
	assert_true(
		deadline_budget.get_steps() > 0 and deadline_budget.get_steps() <= 64,
		"deadline 退出前的操作数必须保持有界，而不是扫描全部 131072 个单元。"
	)
	assert_true(
		hint_result.nodes_evaluated < topology.get_cell_count(),
		"预算退出不得进入整盘四向评分。"
	)
	assert_true(
		hint_result.can_display_for("optimization-acceptance-large-board"),
		"deadline 降级仍应提供带 freshness 的可显示结果。"
	)


func test_minimal_vfx_budget_disables_continuous_shader_work() -> void:
	var minimal_state: GameAccessibilityState = GameAccessibilityState.new()
	minimal_state.vfx_quality = GameAccessibilityState.VfxQuality.MINIMAL
	var budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(
		minimal_state
	)

	assert_false(budget.background_shader_enabled, "低 VFX 档必须关闭背景 Shader。")
	assert_false(budget.celebration_shader_enabled, "低 VFX 档必须关闭庆祝 Shader。")
	assert_true(
		budget.celebration_particle_count == 0,
		"低 VFX 档不得保留持续庆祝粒子。"
	)

	var background: ColorRect = ColorRect.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = (
		"shader_type canvas_item;\n"
		+ "uniform float animation_time = 0.0;\n"
		+ "void fragment() { COLOR = vec4(animation_time * 0.0); }\n"
	)
	material.shader = shader
	background.material = material
	add_child_autoqfree(background)
	var driver: GameShaderAnimationDriver = GameShaderAnimationDriver.new()
	background.add_child(driver)
	var _configured_driver: GameShaderAnimationDriver = driver.configure(background)
	await get_tree().process_frame

	driver.set_animation_enabled(budget.background_shader_enabled, true)
	assert_true(
		background.material == null,
		"低 VFX 预算应用后必须卸载背景 ShaderMaterial。"
	)
	assert_true(
		background.process_mode == Node.PROCESS_MODE_DISABLED,
		"低 VFX 背景节点必须禁用持续处理。"
	)
	assert_false(driver.is_processing(), "低 VFX 档的 Shader 时间驱动不得逐帧运行。")


func test_local_and_web_platform_capability_rows_are_ready() -> void:
	var adapter: LocalPlatformAdapter = LocalPlatformAdapter.new()
	assert_true(adapter.prepare(), "本地 Godot 平台 adapter 必须可冻结 GF 契约。")
	var context: GFPlatformRuntimeContext = adapter.get_context()
	assert_not_null(context, "本地平台 adapter 必须提供 GF 运行时上下文。")
	if context != null:
		assert_true(
			context.adapter_id == LocalPlatformAdapter.ADAPTER_ID,
			"本地平台上下文必须保留稳定 adapter ID。"
		)
		assert_true(context.platform_id != &"", "本地平台上下文必须识别当前平台。")
		for capability_id: StringName in [
			GamePlatformAdapter.CAPABILITY_STORAGE_LOCAL,
			GamePlatformAdapter.CAPABILITY_HTTP,
			GamePlatformAdapter.CAPABILITY_AUDIO,
			GamePlatformAdapter.CAPABILITY_LIFECYCLE,
			GamePlatformAdapter.CAPABILITY_SAFE_AREA,
			GamePlatformAdapter.CAPABILITY_WINDOW_RESIZE,
			GamePlatformAdapter.CAPABILITY_POINTER,
		]:
			assert_true(
				context.has_capability(capability_id),
				"本地平台缺少基础能力：%s" % capability_id
			)

	var config: ConfigFile = ConfigFile.new()
	assert_true(config.load(_EXPORT_CONFIG_PATH) == OK, "Web 验收必须能读取导出预设。")
	var web_section: String = _find_preset_section(config)
	assert_false(web_section.is_empty(), "必须保留 Web Compatibility Smoke 预设。")
	if not web_section.is_empty():
		var options_section: String = "%s.options" % web_section
		assert_false(
			GFVariantData.to_bool(
				config.get_value(options_section, "variant/thread_support", true),
				true
			),
			"Web 验收预设必须关闭线程。"
		)
		assert_false(
			GFVariantData.to_bool(
				config.get_value(options_section, "variant/extensions_support", true),
				true
			),
			"Web 验收预设必须关闭扩展。"
		)
		assert_true(
			GFVariantData.to_bool(
				config.get_value(
					options_section,
					"vram_texture_compression/for_mobile",
					false
				)
			),
			"Web 验收预设必须包含移动纹理压缩。"
		)
		assert_true(
			str(config.get_value(web_section, "custom_features", "")).contains(
				"platform_smoke"
			),
			"Web 验收预设必须进入平台 smoke 启动路径。"
		)
	assert_true(
		str(ProjectSettings.get_setting(
			"rendering/renderer/rendering_method.web",
			""
		)) == "gl_compatibility",
		"Web 平台必须固定 Compatibility 渲染器。"
	)

	var adapter_source: String = FileAccess.get_file_as_string(
		_LOCAL_ADAPTER_SCRIPT_PATH
	)
	assert_true(
		adapter_source.contains('OS.has_feature("web")')
		and adapter_source.contains("PLATFORM_WEB"),
		"生产 adapter 必须把 Web 映射为稳定平台 ID。"
	)
	assert_true(
		adapter_source.contains("CAPABILITY_TOUCH"),
		"生产 adapter 必须为 Web/移动运行时声明触摸能力。"
	)


# --- 私有/辅助方法 ---

func _make_topology_rows() -> Array[Dictionary]:
	var rectangle: BoardTopology = BoardTopology.create_rectangle(
		Vector2i(4, 4),
		&"board.acceptance.rectangle"
	)
	var sparse_cross: BoardTopology = BoardTopology.create_cross(
		2,
		1,
		&"board.acceptance.sparse_cross"
	)
	assert_true(rectangle.is_rectangle(), "矩形验收夹具必须是完整矩形。")
	assert_false(sparse_cross.is_rectangle(), "稀疏验收夹具必须包含空洞。")
	return [
		{
			&"id": &"rectangle",
			&"topology": rectangle,
		},
		{
			&"id": &"sparse_cross",
			&"topology": sparse_cross,
		},
	]


func _make_golden_summary(
	mode_config: GameModeConfig,
	topology: BoardTopology,
	root_seed: int,
	ruleset_fingerprint: String
) -> String:
	var seed_result: Dictionary = GFSeedUtility.try_make_stable_seed([
		"optimization_acceptance.v1",
		root_seed,
		String(mode_config.ruleset_id),
		mode_config.ruleset_version,
		ruleset_fingerprint,
		topology.get_stable_key(),
	])
	if not GFVariantData.get_option_bool(seed_result, &"ok", false):
		return ""
	var derived_seed: int = GFVariantData.get_option_int(seed_result, &"seed")
	var seed_utility: GFSeedUtility = GFSeedUtility.new()
	seed_utility.init()
	seed_utility.set_global_seed(derived_seed)
	var random_stream: GFDeterministicRandom = (
		seed_utility.get_branched_deterministic_random(
			"optimization_acceptance.golden"
		)
	)
	var samples: Array[int] = []
	for _sample_index: int in range(_GOLDEN_SAMPLE_COUNT):
		samples.append(random_stream.next_u32())
	seed_utility.dispose()
	return GFDeterministicVariantSerializer.sha256({
		&"mode_id": String(mode_config.ruleset_id),
		&"ruleset_version": mode_config.ruleset_version,
		&"ruleset_fingerprint": ruleset_fingerprint,
		&"topology_key": topology.get_stable_key(),
		&"root_seed": root_seed,
		&"derived_seed": derived_seed,
		&"rng_samples": samples,
	})


func _make_large_counting_topology() -> CountingBoardTopology:
	var cells: Array[Vector2i] = []
	var _resize_error: int = cells.resize(
		_LARGE_BOARD_SIZE.x * _LARGE_BOARD_SIZE.y
	)
	var cell_index: int = 0
	for y: int in range(_LARGE_BOARD_SIZE.y):
		for x: int in range(_LARGE_BOARD_SIZE.x):
			cells[cell_index] = Vector2i(x, y)
			cell_index += 1
	var topology: CountingBoardTopology = CountingBoardTopology.new()
	topology.topology_id = &"board.acceptance.large_rectangle"
	topology.active_cells = cells
	return topology


func _find_preset_section(config: ConfigFile) -> String:
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		if str(config.get_value(section, "name", "")) == _WEB_PRESET_NAME:
			return section
	return ""


# --- 内部类 ---

class CountingBoardTopology extends BoardTopology:
	var lower_bound_call_count: int = 0


	func _lower_bound_row_x(row_start: int, row_end: int, target_x: int) -> int:
		lower_bound_call_count += 1
		return super._lower_bound_row_x(row_start, row_end, target_x)


class AdvancingClock extends GFClock:
	var _current_msec: int = 0
	var _advance_per_read: int = 1


	func _init(advance_per_read: int = 1) -> void:
		_advance_per_read = maxi(advance_per_read, 1)


	func get_monotonic_msec() -> int:
		var result: int = _current_msec
		_current_msec += _advance_per_read
		return result
