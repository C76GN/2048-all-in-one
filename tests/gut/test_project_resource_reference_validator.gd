extends GutTest


# --- 常量 ---

const _FIXTURE_ROOT: String = "user://test_project_resource_reference_validator"
const _TARGET_SCRIPT_PATH: String = "res://shared/scripts/ui/surface_vbox_container.gd"
const _TARGET_SCRIPT_UID: String = "uid://oyvormqr2bhb"


# --- GUT 生命周期方法 ---

func before_each() -> void:
	_remove_fixture_root()
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_FIXTURE_ROOT)
	)
	assert_true(make_error == OK)


func after_each() -> void:
	_remove_fixture_root()


# --- 测试用例 ---

func test_matching_uid_and_existing_path_are_accepted() -> void:
	var report: Dictionary = _validate_fixture(
		"matching_uid.tres",
		_make_ext_resource_text(_TARGET_SCRIPT_PATH, _TARGET_SCRIPT_UID)
	)
	assert_true(GFVariantData.get_option_bool(report, "success"))
	assert_true(GFVariantData.get_option_int(report, "reference_count") == 1)


func test_stale_uid_is_rejected_with_target_evidence() -> void:
	var report: Dictionary = _validate_fixture(
		"stale_uid.tres",
		_make_ext_resource_text(_TARGET_SCRIPT_PATH, "uid://d7m4q9v2k1xcp")
	)
	assert_false(GFVariantData.get_option_bool(report, "success"))
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	assert_true(issues.size() == 1)
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.as_dictionary(issues[0]),
			"kind"
		) == "ext_resource_uid_mismatch"
	)


func test_existing_path_without_declared_uid_is_accepted() -> void:
	var report: Dictionary = _validate_fixture(
		"path_only.tres",
		_make_ext_resource_text(_TARGET_SCRIPT_PATH)
	)
	assert_true(GFVariantData.get_option_bool(report, "success"))


func test_missing_path_is_rejected_even_without_uid() -> void:
	# 运行时拼出不存在的项目路径，避免 GF 契约扫描把负向 fixture 当成真实依赖边。
	var missing_path: String = "res:/" + "/features/missing/not_a_resource.gd"
	var report: Dictionary = _validate_fixture(
		"missing_path.tres",
		_make_ext_resource_text(missing_path)
	)
	assert_false(GFVariantData.get_option_bool(report, "success"))
	var issues: Array = GFVariantData.get_option_array(report, "issues")
	assert_true(
		GFVariantData.get_option_string(
			GFVariantData.as_dictionary(issues[0]),
			"kind"
		) == "ext_resource_path_missing"
	)


func test_subresources_and_builtin_values_are_not_treated_as_external_paths() -> void:
	var report: Dictionary = _validate_fixture(
		"subresource_only.tres",
		"[gd_resource format=3]\n\n[sub_resource type=\"Resource\" id=\"Local\"]\n\n"
		+ "[resource]\nvalue = SubResource(\"Local\")\n"
	)
	assert_true(GFVariantData.get_option_bool(report, "success"))
	assert_true(GFVariantData.get_option_int(report, "reference_count") == 0)


func test_target_without_canonical_uid_keeps_path_only_validation() -> void:
	var report: Dictionary = _validate_fixture(
		"canonical_uid_unavailable.tres",
		_make_ext_resource_text(
			"res://features/navigation/scenes/ui/game_modal_route_panel.tscn",
			"uid://d7m4q9v2k1xcp"
		)
	)
	assert_true(GFVariantData.get_option_bool(report, "success"))


# --- 私有/辅助方法 ---

func _validate_fixture(file_name: String, content: String) -> Dictionary:
	var path: String = _FIXTURE_ROOT.path_join(file_name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return {}
	var stored: bool = file.store_string(content)
	assert_true(stored)
	file.close()
	return ProjectResourceReferenceValidator.validate_text_resource_file(path)


func _make_ext_resource_text(path: String, uid: String = "") -> String:
	var uid_attribute: String = "" if uid.is_empty() else " uid=\"%s\"" % uid
	return (
		"[gd_resource format=3]\n\n"
		+ "[ext_resource type=\"Script\"%s path=\"%s\" id=\"1_target\"]\n\n" % [
			uid_attribute,
			path,
		]
		+ "[resource]\n"
	)


func _remove_fixture_root() -> void:
	var absolute_root: String = ProjectSettings.globalize_path(_FIXTURE_ROOT)
	if not DirAccess.dir_exists_absolute(absolute_root):
		return
	var directory: DirAccess = DirAccess.open(absolute_root)
	if directory != null:
		var _list_error: Error = directory.list_dir_begin()
		var entry: String = directory.get_next()
		while not entry.is_empty():
			if not directory.current_is_dir():
				var _remove_file_error: Error = DirAccess.remove_absolute(
					absolute_root.path_join(entry)
				)
			entry = directory.get_next()
		directory.list_dir_end()
	var _remove_directory_error: Error = DirAccess.remove_absolute(absolute_root)
