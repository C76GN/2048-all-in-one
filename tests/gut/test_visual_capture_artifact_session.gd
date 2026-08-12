extends GutTest


const VisualCaptureArtifactSession = preload(
	"res://tools/visual_capture_artifact_session.gd"
)
const _OUTPUT_DIRECTORY: String = (
	"res://build/test_visual_capture_artifact_session"
)
const _LINK_OUTPUT_DIRECTORY: String = (
	"res://build/test_visual_capture_artifact_session_link"
)
const _LINK_TARGET_DIRECTORY: String = (
	"res://build/test_visual_capture_artifact_session_link_target"
)
const _LINKED_CHILD_DIRECTORY: String = (
	_OUTPUT_DIRECTORY + "/linked_child"
)


func before_each() -> void:
	_remove_link_fixtures()
	_remove_output_directory()


func after_each() -> void:
	_remove_link_fixtures()
	_remove_output_directory()


func test_begin_removes_stale_evidence_and_completed_manifest_is_traceable() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(
		_OUTPUT_DIRECTORY
	)
	assert_true(DirAccess.make_dir_recursive_absolute(absolute_directory) == OK)
	assert_true(_write_text("stale.png", "old run"))

	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_test",
		_OUTPUT_DIRECTORY,
		["fresh.png"]
	)
	assert_true(session.begin())
	assert_false(
		FileAccess.file_exists(_OUTPUT_DIRECTORY.path_join("stale.png")),
		"单次截图会话不得沿用上次截图。"
	)
	assert_true(_write_text("fresh.png", "current run"))
	session.record_screenshot("fresh.png")
	session.add_surface_contract_id(&"navigation/mode-selection")
	session.add_surface_contract_id(&"navigation/mode-selection")
	assert_true(session.finalize(OK, "capture completed") == OK)

	var manifest: Dictionary = _read_manifest()
	assert_false(manifest.is_empty())
	assert_true(
		GFVariantData.get_option_string(manifest, "suite")
		== "artifact_session_test"
	)
	assert_true(
		GFVariantData.get_option_array(
			manifest,
			"expected_screenshots"
		) == ["fresh.png"]
	)
	assert_true(
		GFVariantData.get_option_array(
			manifest,
			"actual_screenshots"
		) == ["fresh.png"]
	)
	assert_true(
		GFVariantData.get_option_array(
			manifest,
			"surface_contract_ids"
		) == ["navigation/mode-selection"],
		"manifest 必须绑定本次视觉证据所验证的页面意图合同。"
	)
	var git_identity: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"git"
	)
	assert_false(
		GFVariantData.get_option_string(git_identity, "head").is_empty(),
		"manifest 必须绑定当次 Git HEAD。"
	)
	assert_true(git_identity.has("dirty"))
	var vendor_identity: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"gf_vendor"
	)
	assert_false(
		GFVariantData.get_option_string(
			vendor_identity,
			"framework_version"
		).is_empty(),
		"manifest 必须绑定 GF vendor 版本。"
	)
	var terminal: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"terminal"
	)
	assert_true(
		GFVariantData.get_option_string(terminal, "state") == "completed"
	)
	assert_true(GFVariantData.get_option_int(terminal, "exit_code", -1) == OK)


func test_missing_expected_screenshot_converts_success_to_failed_terminal() -> void:
	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_missing_test",
		_OUTPUT_DIRECTORY,
		["missing.png"]
	)
	assert_true(session.begin())
	assert_true(session.finalize(OK, "capture completed") == 65)
	var manifest: Dictionary = _read_manifest()
	assert_true(
		GFVariantData.get_option_array(
			manifest,
			"missing_screenshots"
		) == ["missing.png"]
	)
	var terminal: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"terminal"
	)
	assert_true(
		GFVariantData.get_option_string(terminal, "state") == "failed"
	)
	assert_true(GFVariantData.get_option_int(terminal, "exit_code", -1) == 65)


func test_unexpected_screenshot_converts_success_to_failed_terminal() -> void:
	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_unexpected_test",
		_OUTPUT_DIRECTORY,
		[]
	)
	assert_true(session.begin())
	assert_true(_write_text("unexpected.png", "unexpected capture"))
	session.record_screenshot("unexpected.png")
	assert_true(session.finalize(OK, "capture completed") == 65)
	var manifest: Dictionary = _read_manifest()
	assert_true(
		GFVariantData.get_option_array(
			manifest,
			"unexpected_screenshots"
		) == ["unexpected.png"]
	)
	var terminal: Dictionary = GFVariantData.get_option_dictionary(
		manifest,
		"terminal"
	)
	assert_true(
		GFVariantData.get_option_string(terminal, "state") == "failed"
	)
	assert_true(GFVariantData.get_option_int(terminal, "exit_code", -1) == 65)


func test_finalize_rejects_manifest_created_after_begin_without_overwriting_it() -> void:
	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_manifest_conflict_test",
		_OUTPUT_DIRECTORY,
		[]
	)
	assert_true(session.begin())
	assert_true(_write_text("capture_manifest.json", "caller-owned"))

	assert_true(
		session.finalize(OK, "capture completed") == 74,
		"终态 manifest 必须以 begin 后不存在为提交基线。"
	)
	assert_push_error("目标文件已偏离调用方读取基线")
	assert_true(
		FileAccess.get_file_as_string(
			_OUTPUT_DIRECTORY.path_join("capture_manifest.json")
		) == "caller-owned",
		"并发出现的 manifest 不得被生成器覆盖。"
	)


func test_begin_rejects_linked_output_without_deleting_link_target() -> void:
	assert_true(_prepare_link_target())
	if not _try_create_directory_link(
		_LINK_OUTPUT_DIRECTORY,
		_LINK_TARGET_DIRECTORY
	):
		_assert_source_contains_link_guards()
		return

	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_linked_output_test",
		_LINK_OUTPUT_DIRECTORY,
		[]
	)
	assert_false(
		session.begin(),
		"截图清理不得沿输出目录 junction/symlink 进入其他目录。"
	)
	assert_true(
		FileAccess.file_exists(
			_LINK_TARGET_DIRECTORY.path_join("sentinel.txt")
		),
		"拒绝链接输出时不得删除链接目标中的文件。"
	)


func test_begin_rejects_linked_child_without_deleting_link_target() -> void:
	assert_true(_prepare_link_target())
	var absolute_output: String = ProjectSettings.globalize_path(
		_OUTPUT_DIRECTORY
	)
	assert_true(DirAccess.make_dir_recursive_absolute(absolute_output) == OK)
	if not _try_create_directory_link(
		_LINKED_CHILD_DIRECTORY,
		_LINK_TARGET_DIRECTORY
	):
		_assert_source_contains_link_guards()
		return

	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_linked_child_test",
		_OUTPUT_DIRECTORY,
		[]
	)
	assert_false(
		session.begin(),
		"截图清理不得递归进入子目录 junction/symlink。"
	)
	assert_true(
		FileAccess.file_exists(
			_LINK_TARGET_DIRECTORY.path_join("sentinel.txt")
		),
		"拒绝链接子目录时不得删除链接目标中的文件。"
	)


func test_finalize_rejects_link_inserted_after_begin() -> void:
	assert_true(_prepare_link_target())
	var session: VisualCaptureArtifactSession = VisualCaptureArtifactSession.new(
		"artifact_session_late_link_test",
		_OUTPUT_DIRECTORY,
		[]
	)
	assert_true(session.begin())
	if not _try_create_directory_link(
		_LINKED_CHILD_DIRECTORY,
		_LINK_TARGET_DIRECTORY
	):
		_assert_source_contains_link_guards()
		return

	assert_false(session.is_ready_for_artifact_write())
	assert_true(
		session.finalize(OK, "capture completed") == 74,
		"begin 后新出现的 junction/symlink 必须令终态写入失败关闭。"
	)
	assert_true(
		FileAccess.file_exists(
			_LINK_TARGET_DIRECTORY.path_join("sentinel.txt")
		),
		"终态防线不得写入或删除链接目标中的文件。"
	)
	assert_false(
		FileAccess.file_exists(
			_OUTPUT_DIRECTORY.path_join("capture_manifest.json")
		)
	)


# --- 私有/辅助方法 ---


func _write_text(file_name: String, contents: String) -> bool:
	var file: FileAccess = FileAccess.open(
		_OUTPUT_DIRECTORY.path_join(file_name),
		FileAccess.WRITE
	)
	if file == null:
		return false
	var wrote: bool = file.store_string(contents)
	file.close()
	return wrote


func _read_manifest() -> Dictionary:
	var path: String = _OUTPUT_DIRECTORY.path_join("capture_manifest.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return parsed_value if parsed_value is Dictionary else {}


func _prepare_link_target() -> bool:
	var absolute_target: String = ProjectSettings.globalize_path(
		_LINK_TARGET_DIRECTORY
	)
	if DirAccess.make_dir_recursive_absolute(absolute_target) != OK:
		return false
	var sentinel: FileAccess = FileAccess.open(
		_LINK_TARGET_DIRECTORY.path_join("sentinel.txt"),
		FileAccess.WRITE
	)
	if sentinel == null:
		return false
	var wrote: bool = sentinel.store_string("must survive guarded cleanup")
	sentinel.close()
	return wrote


func _try_create_directory_link(
	link_resource_path: String,
	target_resource_path: String
) -> bool:
	var link_path: String = ProjectSettings.globalize_path(link_resource_path)
	var target_path: String = ProjectSettings.globalize_path(target_resource_path)
	var output: Array = []
	var exit_code: int = FAILED
	if OS.get_name() == "Windows":
		exit_code = OS.execute(
			"cmd.exe",
			PackedStringArray(["/d", "/c", "mklink", "/J", link_path, target_path]),
			output,
			true,
			false
		)
	else:
		exit_code = OS.execute(
			"ln",
			PackedStringArray(["-s", target_path, link_path]),
			output,
			true,
			false
		)
	return exit_code == OK and _entry_is_link(link_resource_path)


func _entry_is_link(resource_path: String) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	var parent: DirAccess = DirAccess.open(absolute_path.get_base_dir())
	return parent != null and parent.is_link(absolute_path.get_file())


func _assert_source_contains_link_guards() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://tools/visual_capture_artifact_session.gd"
	)
	assert_true(source.contains("_path_has_link_component(absolute_directory)"))
	assert_true(source.contains("directory.is_link(child_name)"))
	assert_true(source.contains("func is_ready_for_artifact_write() -> bool:"))


func _remove_link_fixtures() -> void:
	_remove_link_entry(_LINKED_CHILD_DIRECTORY)
	_remove_link_entry(_LINK_OUTPUT_DIRECTORY)
	_remove_simple_directory(_LINK_TARGET_DIRECTORY)


func _remove_link_entry(resource_path: String) -> void:
	if not _entry_is_link(resource_path):
		return
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	var _remove_link_error: Error = DirAccess.remove_absolute(absolute_path)


func _remove_simple_directory(resource_path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	var directory: DirAccess = DirAccess.open(absolute_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		var _remove_file_error: Error = DirAccess.remove_absolute(
			absolute_path.path_join(file_name)
		)
	var _remove_directory_error: Error = DirAccess.remove_absolute(absolute_path)


func _remove_output_directory() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(
		_OUTPUT_DIRECTORY
	)
	var directory: DirAccess = DirAccess.open(absolute_directory)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		var _remove_file_error: Error = DirAccess.remove_absolute(
			absolute_directory.path_join(file_name)
		)
	var _remove_directory_error: Error = DirAccess.remove_absolute(
		absolute_directory
	)
