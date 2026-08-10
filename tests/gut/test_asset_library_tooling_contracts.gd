## 验证素材维护工具统一采用 GF 校验报告与原子文本产物边界。
extends GutTest


# --- 常量 ---

const VALIDATION_TOOL_PATHS: PackedStringArray = [
	"res://features/asset_library/tools/asset_library_audit.gd",
	"res://features/asset_library/tools/import_asset_sources.gd",
	"res://features/asset_library/tools/sync_audio_review_variants.gd",
	"res://tools/purge_rejected_assets.gd",
]
const GENERATED_TEXT_TOOL_PATHS: PackedStringArray = [
	"res://features/asset_library/tools/asset_library_audit.gd",
	"res://features/asset_library/tools/import_asset_sources.gd",
	"res://tools/purge_rejected_assets.gd",
]


# --- 测试用例 ---

func test_asset_tools_use_gf_validation_report_dictionary() -> void:
	for path: String in VALIDATION_TOOL_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		assert_false(source.is_empty(), "素材工具源码必须可读取：%s。" % path)
		assert_true(
			source.contains("GFValidationReportDictionary.append_issue("),
			"素材工具必须通过 GF 追加规范 issue：%s。" % path
		)
		assert_true(
			source.contains("GFValidationReportDictionary.finalize_report("),
			"素材工具必须通过 GF 重算校验统计：%s。" % path
		)


func test_asset_text_outputs_use_generated_artifact_reports() -> void:
	for path: String in GENERATED_TEXT_TOOL_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		assert_true(source.contains("GFGeneratedArtifactReport.save_text("))
		assert_true(source.contains("GFGeneratedArtifactReport.get_error_code("))
		assert_true(source.contains('"allowed_roots":'))
		assert_true(
			source.contains(
				'"artifact_owner": GFGeneratedArtifactReport.OWNER_GENERATED'
			)
		)
		assert_true(source.contains('"generator_id":'))
		assert_true(source.contains('"source_id":'))
		assert_true(source.contains('"scan_filesystem": false'))
		assert_true(
			source.contains('save_options["expected_previous_sha256"]'),
			"覆盖已有产物前必须绑定调用方读取基线：%s。" % path
		)

	var purge_source: String = FileAccess.get_file_as_string(
		"res://tools/purge_rejected_assets.gd"
	)
	assert_true(
		purge_source.contains(
			'"allowed_roots": PackedStringArray(["res://build/asset_library"])'
		),
		"拒绝素材清理报告只能写入固定 generated_artifacts 根。"
	)
	assert_false(
		purge_source.contains("FileAccess.open(REPORT_PATH, FileAccess.WRITE)"),
		"拒绝素材清理不得保留报告直写分支。"
	)
