## 验证项目工具统一采用 GF 的原子文本产物报告边界。
extends GutTest


const _SINGLE_REPORT_TOOL_PATHS: Array[String] = [
	"res://features/platform_runtime/tools/platform_readiness_check.gd",
	"res://tools/validate_project_layout.gd",
	"res://tools/ui_route_performance_acceptance_harness.gd",
]
const _CAPTURE_SESSION_PATH: String = (
	"res://tools/visual_capture_artifact_session.gd"
)
const _CAPTURE_MATRIX_PATH: String = "res://tools/capture_ui_vfx_matrix.gd"
const _FEEDBACK_PROFILE_PATH: String = (
	"res://features/themes/resources/themes/game/feedback/"
	+ "halftone_atlas_board_feedback_profile.tres"
)


func test_single_report_tools_use_generated_artifact_contract() -> void:
	for path: String in _SINGLE_REPORT_TOOL_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		assert_false(source.is_empty(), "工具源码必须可读取：%s。" % path)
		assert_true(
			source.contains("GFGeneratedArtifactReport.save_text("),
			"工具必须采用 GF 原子文本产物边界：%s。" % path
		)
		assert_true(
			source.contains("GFGeneratedArtifactReport.get_error_code("),
			"工具必须保留 GF 产物错误码：%s。" % path
		)
		assert_true(source.contains('"allowed_roots":'))
		assert_true(
			source.contains(
				'"artifact_owner": GFGeneratedArtifactReport.OWNER_GENERATED'
			)
		)
		assert_true(source.contains('"generator_id":'))
		assert_true(source.contains('"source_id":'))
		assert_true(source.contains('"scan_filesystem": false'))
		assert_false(
			source.contains("FileAccess.WRITE"),
			"工具不得保留非原子的直写分支：%s。" % path
		)


func test_capture_reports_preserve_isolation_and_fail_closed_contracts() -> void:
	var session_source: String = FileAccess.get_file_as_string(
		_CAPTURE_SESSION_PATH
	)
	var matrix_source: String = FileAccess.get_file_as_string(
		_CAPTURE_MATRIX_PATH
	)

	for source: String in [session_source, matrix_source]:
		assert_true(source.contains("GFGeneratedArtifactReport.save_text("))
		assert_true(source.contains('"allowed_roots":'))
		assert_true(source.contains('"expected_previous_sha256": ""'))
		assert_true(source.contains('"scan_filesystem": false'))
		assert_false(source.contains("FileAccess.WRITE"))
	assert_true(
		session_source.contains("func is_ready_for_artifact_write() -> bool:")
	)
	assert_true(
		session_source.contains("not _tree_has_link(absolute_directory)")
	)
	assert_true(
		matrix_source.contains(
			"GFGeneratedArtifactReport.summarize_reports("
		)
	)
	assert_true(
		matrix_source.contains(
			"GFGeneratedArtifactReport.get_error_code("
		)
	)
	assert_true(
		matrix_source.contains(
			"if effective_exit_code == OK and report_write_error != OK:"
		)
		and matrix_source.contains("effective_exit_code = 74"),
		"报告生成失败必须把原成功终态收敛为 I/O 失败。"
	)


func test_stationary_capture_guard_preserves_clearance_and_rejects_board_overlap() -> void:
	var matrix_script: Script = load(_CAPTURE_MATRIX_PATH)
	var profile: GameBoardFeedbackProfile = load(_FEEDBACK_PROFILE_PATH)
	var margin: float = matrix_script.call(
		&"_resolve_gameplay_guard_margin",
		profile,
		GameFeedbackBudget.new()
	)
	var board_rect: Rect2 = Rect2(94.0, 118.0, 532.0, 532.0)
	var guard_rect: Rect2 = board_rect.grow(margin)
	assert_true(is_equal_approx(margin, 16.0))
	assert_false(
		guard_rect.intersects(Rect2(110.0, 676.0, 500.0, 78.0)),
		"实测竖屏字幕距静止棋盘 26px，不应因旧整盘震动预留误报。"
	)
	assert_true(
		guard_rect.intersects(Rect2(110.0, 649.0, 500.0, 78.0)),
		"关闭整盘运动后，实际覆盖棋盘的字幕仍必须失败。"
	)
	assert_true(
		guard_rect.intersects(Rect2(110.0, 658.0, 500.0, 78.0)),
		"仅 8px 间距也必须失败，仍需保留局部脉冲与软边空间。"
	)


func test_capture_guard_keeps_motion_reserve_until_profile_or_budget_disables_it() -> void:
	var matrix_script: Script = load(_CAPTURE_MATRIX_PATH)
	var source_profile: GameBoardFeedbackProfile = load(_FEEDBACK_PROFILE_PATH)
	var profile: GameBoardFeedbackProfile = source_profile.duplicate(true)
	var budget: GameFeedbackBudget = GameFeedbackBudget.new()
	var turn_recipes: Array[GameFeedbackRecipe] = [
		profile.move_recipe,
		profile.turn_merge_recipe,
		profile.high_merge_recipe,
		profile.record_recipe,
	]
	for recipe: GameFeedbackRecipe in turn_recipes:
		for property_name: StringName in [
			&"root_impulse",
			&"root_rotation_degrees",
			&"root_compression",
		]:
			recipe.set(property_name, 0.1)
			var margin: float = matrix_script.call(
				&"_resolve_gameplay_guard_margin", profile, budget
			)
			assert_true(is_equal_approx(margin, 50.0))
			recipe.set(property_name, 0.0)
	var missing_profile_margin: float = matrix_script.call(
		&"_resolve_gameplay_guard_margin", null, budget
	)
	assert_true(is_equal_approx(missing_profile_margin, 50.0))
	var missing_budget_margin: float = matrix_script.call(
		&"_resolve_gameplay_guard_margin", profile, null
	)
	assert_true(is_equal_approx(missing_budget_margin, 50.0))
	profile.record_recipe.root_impulse = 20.0
	budget.motion_scale = 0.0
	var reduced_motion_margin: float = matrix_script.call(
		&"_resolve_gameplay_guard_margin", profile, budget
	)
	assert_true(is_equal_approx(reduced_motion_margin, 16.0))
