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
	var save_result: Error = index.save_to_path(fixture_path)
	var loaded: AssetSourceExclusionIndex = EXCLUSION_INDEX_SCRIPT.new()
	var load_result: Error = loaded.load_from_path(fixture_path)

	assert_true(add_result == OK, "有效源素材身份应能加入排除索引。")
	assert_true(save_result == OK, "排除索引应能保存。")
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


# --- 私有/辅助方法 ---

func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		var _remove_result: Error = DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		)
