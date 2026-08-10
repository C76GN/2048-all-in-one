## 验证源素材排除索引只保留防止重新导入所需的最小身份信息。
extends GutTest


# --- 常量 ---

const EXCLUSION_INDEX_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_source_exclusion_index.gd"
)


# --- 测试用例 ---

func test_exclusion_index_round_trips_exact_source_identity() -> void:
	var fixture_path: String = "user://asset_source_exclusions_%d.json" % Time.get_ticks_usec()
	var index: AssetSourceExclusionIndex = EXCLUSION_INDEX_SCRIPT.new()
	var original_sha256: String = "a".repeat(64)
	var changed_sha256: String = "b".repeat(64)

	var add_result: Error = index.add_exclusion(
		"fixture_pack",
		"Audio/rejected.wav",
		original_sha256
	)
	var save_report: Dictionary = index.save_report_to_path(fixture_path)
	var save_result: Error = GFGeneratedArtifactReport.get_error_code(save_report)
	var compatible_save_result: Error = index.save_to_path(fixture_path)
	var loaded: AssetSourceExclusionIndex = EXCLUSION_INDEX_SCRIPT.new()
	var load_result: Error = loaded.load_from_path(fixture_path)

	assert_true(add_result == OK, "有效源素材身份应能加入排除索引。")
	assert_true(save_result == OK, "排除索引应能保存。")
	assert_true(compatible_save_result == OK, "原 Error 保存入口应保持兼容。")
	assert_true(
		GFVariantData.get_option_string(save_report, "artifact_owner")
		== String(GFGeneratedArtifactReport.OWNER_GENERATED)
	)
	assert_true(
		GFVariantData.get_option_string(save_report, "generator_id")
		== "asset_library.source_exclusion_index"
	)
	assert_true(
		GFVariantData.get_option_string(save_report, "source_id")
		== "asset_library.source_exclusions"
	)
	assert_true(load_result == OK, "排除索引应能重新加载。")
	assert_true(
		loaded.is_excluded("fixture_pack", "Audio/rejected.wav", original_sha256),
		"相同源包、路径和哈希应保持排除。"
	)
	assert_false(
		loaded.is_excluded("fixture_pack", "Audio/rejected.wav", changed_sha256),
		"内容哈希变化后应作为新素材重新进入评审。"
	)
	assert_true(loaded.size() == 1, "索引只应包含一个最小排除项。")
	_remove_fixture(fixture_path)


func test_exclusion_index_rejects_invalid_identity() -> void:
	var index: AssetSourceExclusionIndex = EXCLUSION_INDEX_SCRIPT.new()
	var valid_sha256: String = "a".repeat(64)

	assert_true(
		index.add_exclusion("fixture_pack", "../outside.wav", valid_sha256)
			== ERR_INVALID_PARAMETER,
		"排除索引不得接受逃逸源包目录的路径。"
	)
	assert_true(
		index.add_exclusion("", "Audio/rejected.wav", valid_sha256)
			== ERR_INVALID_PARAMETER,
		"排除索引不得接受空源包 ID。"
	)
	assert_true(
		index.add_exclusion("fixture_pack", "Audio/rejected.wav", "not_sha256")
			== ERR_INVALID_PARAMETER,
		"排除索引不得接受非 SHA-256 内容身份。"
	)
	assert_true(index.size() == 0, "无效身份不得写入索引。")


func test_exclusion_index_reports_invalid_persisted_entry_and_clears_partial_state() -> void:
	var fixture_path: String = "user://asset_source_exclusions_invalid_%d.json" % Time.get_ticks_usec()
	var index: AssetSourceExclusionIndex = EXCLUSION_INDEX_SCRIPT.new()
	var valid_sha256: String = "a".repeat(64)
	var file: FileAccess = FileAccess.open(fixture_path, FileAccess.WRITE)
	assert_not_null(file, "无效排除索引夹具应可写入。")
	if file == null:
		return
	var stored: bool = file.store_string(JSON.stringify({
		"schema_version": AssetSourceExclusionIndex.SCHEMA_VERSION,
		"entries": [
			{
				"source_pack_id": "fixture_pack",
				"relative_path": "Audio/valid.wav",
				"sha256": valid_sha256,
			},
			{
				"source_pack_id": "",
				"relative_path": "Audio/invalid.wav",
				"sha256": valid_sha256,
			},
		],
	}))
	file.close()
	assert_true(stored, "无效排除索引夹具内容应完整写入。")

	var report: Dictionary = index.load_report_from_path(fixture_path)

	assert_false(GFVariantData.get_option_bool(report, "ok"))
	assert_true(
		GFVariantData.get_option_string_name(report, "error_kind")
		== &"invalid_entry"
	)
	assert_true(GFVariantData.get_option_int(report, "entry_index") == 1)
	assert_true(index.size() == 0, "任一持久化身份无效时不得保留部分加载状态。")
	_remove_fixture(fixture_path)


# --- 私有/辅助方法 ---

func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		var _remove_result: Error = DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		)
