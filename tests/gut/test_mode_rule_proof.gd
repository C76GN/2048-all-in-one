## 验证模式选择页以导航层数据驱动的规则样张解释玩法，而不污染确定性配置。
extends GutTest


# --- 常量 ---

const _MODE_SELECTION_SCENE: PackedScene = preload(
	"res://features/navigation/scenes/menus/mode_selection.tscn"
)
const _STEP_BY_STEP_MODE_CONFIG: GameModeConfig = preload(
	"res://features/gameplay/resources/modes/step_by_step_mode_config.tres"
)
const _RATIO_MODE_CONFIG: GameModeConfig = preload(
	"res://features/gameplay/resources/modes/ratio_mode_config.tres"
)


# --- 测试用例 ---

func test_every_registered_mode_has_one_valid_proof_descriptor() -> void:
	var seen_rulesets: Dictionary = {}
	for descriptor: ModeRuleProofDescriptor in ModeSelection.MODE_RULE_PROOF_DESCRIPTORS:
		assert_not_null(descriptor)
		if descriptor == null:
			continue
		assert_true(descriptor.is_valid_descriptor())
		assert_false(
			seen_rulesets.has(descriptor.ruleset_id),
			"每个 ruleset_id 只能拥有一张导航层规则样张。"
		)
		seen_rulesets[descriptor.ruleset_id] = true

	for ruleset_id: StringName in [
		&"gameplay.classic",
		&"gameplay.fibonacci",
		&"gameplay.lucas_fibonacci",
		&"gameplay.progressive",
		&"gameplay.step_by_step",
		&"gameplay.ratio",
	]:
		assert_not_null(ModeSelection._get_rule_proof_descriptor(ruleset_id))
	assert_true(seen_rulesets.size() == 6)


func test_proofs_match_canonical_rule_examples() -> void:
	_assert_proof(&"gameplay.classic", "2", "+", "2", "4")
	_assert_proof(&"gameplay.fibonacci", "2", "+", "3", "5")
	_assert_proof(&"gameplay.lucas_fibonacci", "1", "+", "3", "4")
	_assert_proof(&"gameplay.progressive", "1024", "+", "1024", "2048")
	_assert_proof(&"gameplay.step_by_step", "2", "←", "1", "2")
	_assert_proof(&"gameplay.ratio", "8", "÷", "2", "4")


func test_every_proof_notation_stays_inside_the_compact_job_sheet_contract() -> void:
	var scene: PackedScene = preload(
		"res://features/navigation/scenes/ui/mode_rule_proof.tscn"
	)
	var proof: ModeRuleProof = scene.instantiate() as ModeRuleProof
	assert_not_null(proof)
	if proof == null:
		return
	add_child_autoqfree(proof)
	await get_tree().process_frame

	for descriptor: ModeRuleProofDescriptor in ModeSelection.MODE_RULE_PROOF_DESCRIPTORS:
		proof.present(descriptor, null, null)
		await get_tree().process_frame
		assert_lte(
			proof.get_combined_minimum_size().x,
			340.0,
			"紧凑规则示例不得撑破右侧任务单：%s。" %
			String(descriptor.ruleset_id)
		)
		assert_lte(
			proof.get_combined_minimum_size().y,
			150.0,
			"紧凑规则示例不得重新演变为整块说明面板：%s。" %
			String(descriptor.ruleset_id)
		)


func test_step_and_ratio_spawn_claims_are_bound_to_production_mode_rules() -> void:
	assert_true(_STEP_BY_STEP_MODE_CONFIG.movement_rule is StepByStepMovementRule)
	assert_true(
		_has_spawn_rule_type(_STEP_BY_STEP_MODE_CONFIG, ClassicSpawnRule),
		"步进模式生产配置必须沿用经典空位生成。"
	)
	assert_false(
		_has_spawn_rule_type(_STEP_BY_STEP_MODE_CONFIG, OppositeEdgeSpawnRule),
		"步进模式样张不得宣称相反边缘生成。"
	)
	assert_true(
		_has_spawn_rule_type(_RATIO_MODE_CONFIG, OppositeEdgeSpawnRule),
		"相反边缘生成只属于实际挂载该规则的比值模式。"
	)
	var translated_step_name: String = tr(_STEP_BY_STEP_MODE_CONFIG.mode_name)
	var translated_step_description: String = tr(
		_STEP_BY_STEP_MODE_CONFIG.mode_description
	)
	assert_false(
		translated_step_name.contains("对边")
		or translated_step_description.contains("相反边缘")
		or translated_step_description.to_lower().contains("opposite edge"),
		"玩家可见的模式名称与详情也必须服从生产 SpawnRule 真值。"
	)


func test_proof_is_a_compact_child_of_the_start_job_sheet() -> void:
	var selection_node: Node = _MODE_SELECTION_SCENE.instantiate()
	selection_node.set_script(_ModeSelectionProbe)
	var selection: _ModeSelectionProbe = selection_node as _ModeSelectionProbe
	assert_not_null(selection)
	if selection == null:
		selection_node.free()
		return
	add_child_autoqfree(selection)
	await get_tree().process_frame
	selection._apply_responsive_layout()

	assert_true(selection._mode_rule_proof is ModeRuleProof)
	assert_same(
		selection._mode_rule_proof.get_parent(),
		selection._right_panel_container,
		"规则示例必须从永久第三栏降级为开始任务单内的紧凑提示。"
	)
	assert_false(selection._left_panel_container.visible, "旧左侧样张栏必须保持隐藏。")


func test_proof_explanation_does_not_depend_on_motion() -> void:
	var scene: PackedScene = preload(
		"res://features/navigation/scenes/ui/mode_rule_proof.tscn"
	)
	var proof: ModeRuleProof = scene.instantiate() as ModeRuleProof
	assert_not_null(proof)
	if proof == null:
		return
	add_child_autoqfree(proof)
	await get_tree().process_frame

	var descriptor: ModeRuleProofDescriptor = ModeSelection._get_rule_proof_descriptor(
		&"gameplay.fibonacci"
	)
	proof.present(descriptor, null, null)
	assert_true(proof._source_a_value.text == "2")
	assert_true(proof._source_b_value.text == "3")
	assert_true(proof._result_value.text == "5")
	assert_false(proof.is_processing(), "静态样张不得靠逐帧动画承载规则解释。")


func test_compact_proof_contains_no_repeated_prose_fields() -> void:
	var scene: PackedScene = preload(
		"res://features/navigation/scenes/ui/mode_rule_proof.tscn"
	)
	var proof: ModeRuleProof = scene.instantiate() as ModeRuleProof
	assert_not_null(proof)
	if proof == null:
		return
	add_child_autoqfree(proof)
	await get_tree().process_frame

	for removed_node_name: String in [
		"ProofKickerLabel",
		"ProofNumberLabel",
		"ProofModeNameLabel",
		"ProofFormulaLabel",
		"OutcomeLabel",
	]:
		assert_null(
			proof.find_child(removed_node_name, true, false),
			"紧凑示例不得恢复重复文案节点：%s。" % removed_node_name
		)


# --- 测试辅助方法 ---

func _has_spawn_rule_type(mode_config: GameModeConfig, rule_type: Script) -> bool:
	for spawn_rule: SpawnRule in mode_config.spawn_rules:
		if is_instance_valid(spawn_rule) and is_instance_of(spawn_rule, rule_type):
			return true
	return false

func _assert_proof(
	ruleset_id: StringName,
	source_a: String,
	operator_symbol: String,
	source_b: String,
	result: String
) -> void:
	var descriptor: ModeRuleProofDescriptor = ModeSelection._get_rule_proof_descriptor(ruleset_id)
	assert_not_null(descriptor)
	if descriptor == null:
		return
	assert_true(descriptor.source_a == source_a)
	assert_true(descriptor.operator_symbol == operator_symbol)
	assert_true(descriptor.source_b == source_b)
	assert_true(descriptor.result == result)


# --- 内部类 ---

class _ModeSelectionProbe extends ModeSelection:
	func _ready() -> void:
		_viewport_utility = null
		_page_scroll = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
			_columns_container,
			&"ModeSelectionScroll"
		)
		_apply_responsive_layout()


	func _get_layout_reference_size() -> Vector2:
		return Vector2(1280.0, 720.0)
