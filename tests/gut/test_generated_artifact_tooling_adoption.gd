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
