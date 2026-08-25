## 验证素材 JSON 由 GF 持有文件/解析信任边界，项目只追加条目预算。
extends GutTest


# --- 常量 ---

const ENTRY_BUDGET_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_json_entry_budget.gd"
)
const CURRENT_ASSET_JSON_POLICIES: Array[Dictionary] = [
	{
		"path": "res://features/asset_library/resources/import_sources.json",
		"max_depth": 16,
		"max_entries": 50_000,
	},
	{
		"path": "res://features/asset_library/resources/source_exclusions.json",
		"max_depth": 8,
		"max_entries": 500_000,
	},
]


# --- 测试用例 ---

func test_gf_reader_accepts_object_and_project_policy_counts_entries() -> void:
	var fixture_path: String = _fixture_path("quote_aware")
	_assert_fixture_written(
		fixture_path,
		'{"label":"escaped \\\" [ { ] }","nested":{"values":[1,2]}}'
	)

	var report: Dictionary = _read_with_asset_policy(fixture_path, 1024, 3, 5)

	assert_true(
		GFVariantData.get_option_bool(report, "ok"),
		"字符串内括号不得污染 GF 深度预算。"
	)
	assert_true(GFVariantData.get_option_int(report, "entry_count") == 5)
	assert_true(GFVariantData.get_option_int(report, "max_file_bytes") == 1024)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.get_option_dictionary(report, "data"),
			"label"
		) == 'escaped " [ { ] }'
	)
	_remove_fixture(fixture_path)


func test_gf_reader_rejects_depth_before_project_entry_policy() -> void:
	var fixture_path: String = _fixture_path("depth")
	_assert_fixture_written(fixture_path, '{"one":{"two":{"value":1}}}')

	var report: Dictionary = _read_with_asset_policy(fixture_path, 1024, 2, 100)

	assert_false(GFVariantData.get_option_bool(report, "ok"))
	assert_true(
		GFVariantData.get_option_string_name(report, "error_kind")
		== &"nesting_too_deep"
	)
	assert_true(GFVariantData.get_option_int(report, "entry_count") == 0)
	assert_true(GFVariantData.get_option_dictionary(report, "data").is_empty())
	_remove_fixture(fixture_path)


func test_gf_reader_rejects_non_object_root_and_malformed_json() -> void:
	var array_path: String = _fixture_path("array_root")
	var malformed_path: String = _fixture_path("malformed")
	_assert_fixture_written(array_path, '[1,2,3]')
	_assert_fixture_written(malformed_path, '{"value":]')

	var array_report: Dictionary = _read_with_asset_policy(
		array_path,
		1024,
		8,
		100
	)
	var malformed_report: Dictionary = _read_with_asset_policy(
		malformed_path,
		1024,
		8,
		100
	)

	assert_true(
		GFVariantData.get_option_string_name(array_report, "error_kind")
		== &"invalid_root_type"
	)
	assert_true(
		GFVariantData.get_option_string_name(malformed_report, "error_kind")
		== &"parse_failed"
	)
	assert_true(
		GFVariantData.get_option_int(malformed_report, "error_code")
		== ERR_PARSE_ERROR
	)
	_remove_fixture(array_path)
	_remove_fixture(malformed_path)


func test_gf_reader_owns_byte_budget_and_project_owns_entry_budget() -> void:
	var bytes_path: String = _fixture_path("bytes")
	var entries_path: String = _fixture_path("entries")
	_assert_fixture_written(bytes_path, '{"value":"0123456789"}')
	_assert_fixture_written(entries_path, '{"a":1,"b":2}')

	var bytes_report: Dictionary = _read_with_asset_policy(bytes_path, 8, 8, 100)
	var entries_report: Dictionary = _read_with_asset_policy(
		entries_path,
		1024,
		8,
		1
	)

	assert_true(
		GFVariantData.get_option_string_name(bytes_report, "error_kind")
		== &"payload_too_large"
	)
	assert_true(
		GFVariantData.get_option_string_name(entries_report, "error_kind")
		== ENTRY_BUDGET_SCRIPT.ERROR_ENTRY_BUDGET_EXCEEDED
	)
	assert_gt(GFVariantData.get_option_int(entries_report, "entry_count"), 1)
	assert_true(GFVariantData.get_option_dictionary(entries_report, "data").is_empty())
	_remove_fixture(bytes_path)
	_remove_fixture(entries_path)


func test_gf_reader_clamps_requested_bytes_to_one_mib() -> void:
	var fixture_path: String = _fixture_path("absolute_limit")
	_assert_fixture_written(fixture_path, '{"value":1}')

	var report: Dictionary = _read_with_asset_policy(
		fixture_path,
		4 * 1024 * 1024,
		8,
		100
	)

	assert_true(GFVariantData.get_option_bool(report, "ok"))
	assert_true(
		GFVariantData.get_option_int(report, "max_bytes")
		== GFBoundedJsonObjectReader.ABSOLUTE_MAX_BYTES
	)
	assert_true(
		GFVariantData.get_option_int(report, "max_file_bytes")
		== GFBoundedJsonObjectReader.ABSOLUTE_MAX_BYTES
	)
	_remove_fixture(fixture_path)


func test_current_asset_json_inputs_fit_gf_one_mib_boundary() -> void:
	for policy: Dictionary in CURRENT_ASSET_JSON_POLICIES:
		var path: String = GFVariantData.get_option_string(policy, "path")
		var report: Dictionary = _read_with_asset_policy(
			path,
			GFBoundedJsonObjectReader.ABSOLUTE_MAX_BYTES,
			GFVariantData.get_option_int(policy, "max_depth"),
			GFVariantData.get_option_int(policy, "max_entries")
		)
		assert_true(
			GFVariantData.get_option_bool(report, "ok"),
			"当前素材 JSON 必须适配 GF 的 1 MiB 信任边界：%s；%s" % [
				path,
				GFVariantData.get_option_string(report, "message"),
			]
		)


# --- 私有/辅助方法 ---

func _read_with_asset_policy(
	path: String,
	max_bytes: int,
	max_depth: int,
	max_entries: int
) -> Dictionary:
	var read_report: Dictionary = GFBoundedJsonObjectReader.read_object(
		path,
		max_bytes,
		max_depth
	)
	return ENTRY_BUDGET_SCRIPT.apply_to_read_report(read_report, max_entries)


func _fixture_path(label: String) -> String:
	return "user://asset_json_entry_budget_%s_%d.json" % [
		label,
		Time.get_ticks_usec(),
	]


func _assert_fixture_written(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "测试夹具应可写入：%s" % path)
	if file == null:
		return
	var stored: bool = file.store_string(text)
	file.close()
	assert_true(stored, "测试夹具内容应完整写入。")


func _remove_fixture(path: String) -> void:
	if FileAccess.file_exists(path):
		var _remove_result: Error = DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		)
