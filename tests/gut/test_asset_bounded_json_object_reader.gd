## 验证素材工具只通过项目侧严格有界报告读取不受信任 JSON object。
extends GutTest


# --- 常量 ---

const READER_SCRIPT = preload(
	"res://features/asset_library/scripts/data/asset_bounded_json_object_reader.gd"
)


# --- 测试用例 ---

func test_reader_accepts_object_and_ignores_brackets_inside_strings() -> void:
	var fixture_path: String = _fixture_path("quote_aware")
	_assert_fixture_written(
		fixture_path,
		'{"label":"escaped \\\" [ { ] }","nested":{"values":[1,2]}}'
	)

	var report: Dictionary = READER_SCRIPT.read_object_report(
		fixture_path,
		{"max_depth": 3, "max_entries": 5}
	)

	assert_true(GFVariantData.get_option_bool(report, "ok"), "字符串内括号不得污染深度预算。")
	assert_true(GFVariantData.get_option_int(report, "observed_depth") == 3)
	assert_true(GFVariantData.get_option_int(report, "entry_count") == 5)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.get_option_dictionary(report, "data"),
			"label"
		) == 'escaped " [ { ] }'
	)
	_remove_fixture(fixture_path)


func test_reader_rejects_depth_before_json_materialization() -> void:
	var fixture_path: String = _fixture_path("depth")
	_assert_fixture_written(fixture_path, '{"one":{"two":{"value":1}}}')

	var report: Dictionary = READER_SCRIPT.read_object_report(
		fixture_path,
		{"max_depth": 2}
	)

	assert_false(GFVariantData.get_option_bool(report, "ok"))
	assert_true(
		GFVariantData.get_option_string_name(report, "error_kind")
		== READER_SCRIPT.ERROR_DEPTH_EXCEEDED
	)
	assert_true(GFVariantData.get_option_int(report, "observed_depth") == 3)
	assert_true(GFVariantData.get_option_dictionary(report, "data").is_empty())
	_remove_fixture(fixture_path)


func test_reader_rejects_non_object_root_and_malformed_json() -> void:
	var array_path: String = _fixture_path("array_root")
	var malformed_path: String = _fixture_path("malformed")
	_assert_fixture_written(array_path, '[1,2,3]')
	_assert_fixture_written(malformed_path, '{"value":]')

	var array_report: Dictionary = READER_SCRIPT.read_object_report(array_path)
	var malformed_report: Dictionary = READER_SCRIPT.read_object_report(
		malformed_path
	)

	assert_true(
		GFVariantData.get_option_string_name(array_report, "error_kind")
		== READER_SCRIPT.ERROR_INVALID_ROOT
	)
	assert_true(
		GFVariantData.get_option_string_name(malformed_report, "error_kind")
		== READER_SCRIPT.ERROR_INVALID_JSON
	)
	assert_true(
		GFVariantData.get_option_int(malformed_report, "error_code")
		== ERR_PARSE_ERROR
	)
	_remove_fixture(array_path)
	_remove_fixture(malformed_path)


func test_reader_rejects_byte_and_entry_budget_overflow() -> void:
	var bytes_path: String = _fixture_path("bytes")
	var entries_path: String = _fixture_path("entries")
	_assert_fixture_written(bytes_path, '{"value":"0123456789"}')
	_assert_fixture_written(entries_path, '{"a":1,"b":2}')

	var bytes_report: Dictionary = READER_SCRIPT.read_object_report(
		bytes_path,
		{"max_file_bytes": 8}
	)
	var entries_report: Dictionary = READER_SCRIPT.read_object_report(
		entries_path,
		{"max_entries": 1}
	)

	assert_true(
		GFVariantData.get_option_string_name(bytes_report, "error_kind")
		== READER_SCRIPT.ERROR_FILE_TOO_LARGE
	)
	assert_true(
		GFVariantData.get_option_string_name(entries_report, "error_kind")
		== READER_SCRIPT.ERROR_ENTRY_BUDGET_EXCEEDED
	)
	assert_gt(GFVariantData.get_option_int(entries_report, "entry_count"), 1)
	_remove_fixture(bytes_path)
	_remove_fixture(entries_path)


# --- 私有/辅助方法 ---

func _fixture_path(label: String) -> String:
	return "user://asset_bounded_json_%s_%d.json" % [
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
