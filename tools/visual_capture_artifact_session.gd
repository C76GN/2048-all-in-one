## VisualCaptureArtifactSession: 为渲染验收工具管理单次、可追溯的截图产物。
##
## 每次运行先清理自己的 build 输出目录，再在终态 manifest 中记录
## Git/GF 身份、预期截图、实际截图与失败原因。上次运行的截图不得
## 被当作本次运行的验收证据。
extends RefCounted


const _MANIFEST_FILE_NAME: String = "capture_manifest.json"
const _VENDOR_LOCK_PATH: String = "res://.gf/vendor.lock.json"


var _suite_id: String = ""
var _output_directory: String = ""
var _expected_screenshots: PackedStringArray = PackedStringArray()
var _recorded_screenshots: PackedStringArray = PackedStringArray()
var _surface_contract_ids: PackedStringArray = PackedStringArray()
var _began: bool = false


func _init(
	suite_id: String,
	output_directory: String,
	expected_screenshots: Array[String] = []
) -> void:
	_suite_id = suite_id.strip_edges()
	_output_directory = output_directory.simplify_path()
	for file_name: String in expected_screenshots:
		expect_screenshot(file_name)


func begin() -> bool:
	if _suite_id.is_empty() or not _output_directory.begins_with("res://build/"):
		return false
	var absolute_directory: String = ProjectSettings.globalize_path(
		_output_directory
	).replace("\\", "/").simplify_path()
	if _path_has_link_component(absolute_directory):
		return false
	if DirAccess.dir_exists_absolute(absolute_directory):
		if _tree_has_link(absolute_directory):
			return false
		if not _remove_directory_contents(absolute_directory):
			return false
	else:
		var create_error: Error = DirAccess.make_dir_recursive_absolute(
			absolute_directory
		)
		if create_error != OK:
			return false
		# 创建后再次验证，避免通过既有父级联接把输出目录落到项目外。
		if _path_has_link_component(absolute_directory):
			return false
	_began = true
	return true


func get_output_directory() -> String:
	return _output_directory


## 返回本次会话是否仍可在隔离目录中安全写入产物。
##
## 会在每次终态写入前重新检查目录本身和整棵现有输出树，避免 begin() 后
## 新出现的 junction/symlink 把生成物或清理操作引向项目外。
func is_ready_for_artifact_write() -> bool:
	if not _began:
		return false
	var absolute_directory: String = ProjectSettings.globalize_path(
		_output_directory
	).replace("\\", "/").simplify_path()
	return (
		DirAccess.dir_exists_absolute(absolute_directory)
		and not _path_has_link_component(absolute_directory)
		and not _tree_has_link(absolute_directory)
	)


func expect_screenshot(file_name: String) -> void:
	var normalized_name: String = file_name.get_file()
	if (
		normalized_name.get_extension().to_lower() == "png"
		and normalized_name not in _expected_screenshots
	):
		var _expected_appended: bool = _expected_screenshots.append(
			normalized_name
		)


func record_screenshot(file_name: String) -> void:
	var normalized_name: String = file_name.get_file()
	if (
		normalized_name.get_extension().to_lower() == "png"
		and normalized_name not in _recorded_screenshots
	):
		var _recorded_appended: bool = _recorded_screenshots.append(
			normalized_name
		)


## 声明本次截图套件验证的玩家界面意图合同。
##
## 这里只记录稳定的 Feature/page contract ID，不读取或执行外部文档。
## @param contract_id: 例如 navigation/mode-selection。
func add_surface_contract_id(contract_id: StringName) -> void:
	var normalized_id: String = String(contract_id).strip_edges()
	if normalized_id.is_empty() or normalized_id in _surface_contract_ids:
		return
	var _contract_appended: bool = _surface_contract_ids.append(normalized_id)


## 写入终态 manifest，并在声明成功但产物与固定计划不一致时返回非零错误码。
func finalize(
	exit_code: int,
	terminal_message: String = "",
	details: Dictionary = {}
) -> int:
	if not _began:
		return exit_code if exit_code != 0 else 74
	if not is_ready_for_artifact_write():
		return exit_code if exit_code != 0 else 74

	var actual_screenshots: PackedStringArray = _scan_actual_screenshots()
	var expected: PackedStringArray = _expected_screenshots.duplicate()
	var recorded: PackedStringArray = _recorded_screenshots.duplicate()
	expected.sort()
	recorded.sort()
	actual_screenshots.sort()
	var surface_contract_ids: PackedStringArray = _surface_contract_ids.duplicate()
	surface_contract_ids.sort()
	var missing: PackedStringArray = PackedStringArray()
	for file_name: String in expected:
		if file_name not in actual_screenshots:
			var _missing_appended: bool = missing.append(file_name)
	var unexpected: PackedStringArray = PackedStringArray()
	for file_name: String in actual_screenshots:
		if file_name not in expected:
			var _unexpected_appended: bool = unexpected.append(file_name)

	var effective_exit_code: int = exit_code
	if (
		effective_exit_code == 0
		and (not missing.is_empty() or not unexpected.is_empty())
	):
		effective_exit_code = 65
	var terminal_state: String = (
		"completed" if effective_exit_code == 0 else "failed"
	)
	var manifest: Dictionary = {
		"schema_version": 1,
		"suite": _suite_id,
		"git": _read_git_identity(),
		"gf_vendor": _read_vendor_identity(),
		"expected_screenshots": Array(expected),
		"actual_screenshots": Array(actual_screenshots),
		"recorded_screenshots": Array(recorded),
		"missing_screenshots": Array(missing),
		"unexpected_screenshots": Array(unexpected),
		"surface_contract_ids": Array(surface_contract_ids),
		"terminal": {
			"state": terminal_state,
			"exit_code": effective_exit_code,
			"message": terminal_message,
		},
		"details": details.duplicate(true),
	}
	var manifest_path: String = _output_directory.path_join(
		_MANIFEST_FILE_NAME
	)
	var artifact_report: Dictionary = GFGeneratedArtifactReport.save_text(
		manifest_path,
		JSON.stringify(manifest, "\t") + "\n",
		{
			"allowed_roots": PackedStringArray([_output_directory]),
			"artifact_owner": GFGeneratedArtifactReport.OWNER_GENERATED,
			"generator_id": "VisualCaptureArtifactSession",
			"source_id": _suite_id,
			"expected_previous_sha256": "",
			"scan_filesystem": false,
			"label": "VisualCaptureArtifactSession",
		}
	)
	if GFGeneratedArtifactReport.get_error_code(artifact_report) != OK:
		return effective_exit_code if effective_exit_code != 0 else 74
	return effective_exit_code


func _scan_actual_screenshots() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var directory: DirAccess = DirAccess.open(_output_directory)
	if directory == null:
		return result
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() == "png":
			var _actual_appended: bool = result.append(file_name)
	return result


func _read_git_identity() -> Dictionary:
	var project_root: String = ProjectSettings.globalize_path("res://")
	var head_result: Dictionary = _execute_text(
		"git",
		PackedStringArray(["-C", project_root, "rev-parse", "HEAD"])
	)
	var status_result: Dictionary = _execute_text(
		"git",
		PackedStringArray(["-C", project_root, "status", "--porcelain=v1"])
	)
	var head_text: String = GFVariantData.get_option_string(
		head_result,
		"text"
	).strip_edges()
	var status_text: String = GFVariantData.get_option_string(
		status_result,
		"text"
	).strip_edges()
	var head_exit_code: int = GFVariantData.get_option_int(
		head_result,
		"exit_code",
		FAILED
	)
	var status_exit_code: int = GFVariantData.get_option_int(
		status_result,
		"exit_code",
		FAILED
	)
	return {
		"head": head_text,
		"dirty": (
			status_exit_code != OK
			or not status_text.is_empty()
		),
		"query_ok": (
			head_exit_code == OK
			and status_exit_code == OK
		),
	}


func _read_vendor_identity() -> Dictionary:
	if not FileAccess.file_exists(_VENDOR_LOCK_PATH):
		return {
			"framework_version": "",
			"source_commit": "",
			"query_ok": false,
		}
	var parsed_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(_VENDOR_LOCK_PATH)
	)
	if not parsed_value is Dictionary:
		return {
			"framework_version": "",
			"source_commit": "",
			"query_ok": false,
		}
	var vendor_lock: Dictionary = parsed_value
	return {
		"framework_version": GFVariantData.get_option_string(
			vendor_lock,
			"framework_version"
		),
		"source_commit": GFVariantData.get_option_string(
			vendor_lock,
			"source_commit"
		),
		"query_ok": true,
	}


func _execute_text(executable: String, arguments: PackedStringArray) -> Dictionary:
	var output: Array = []
	var exit_code: int = OS.execute(executable, arguments, output, true, false)
	return {
		"exit_code": exit_code,
		"text": "\n".join(PackedStringArray(output)),
	}


func _path_has_link_component(path: String) -> bool:
	var current: String = _trim_trailing_separators(
		path.replace("\\", "/").simplify_path()
	)
	if current.is_empty():
		return true
	while not current.is_empty():
		if _path_component_is_link(current):
			return true
		var parent: String = _trim_trailing_separators(
			current.get_base_dir().replace("\\", "/")
		)
		if parent.is_empty() or parent == current:
			break
		current = parent
	return false


func _path_component_is_link(path: String) -> bool:
	var normalized: String = _trim_trailing_separators(
		path.replace("\\", "/")
	)
	var parent: String = normalized.get_base_dir()
	var component_name: String = normalized.get_file()
	if parent.is_empty() or component_name.is_empty():
		return false
	var directory: DirAccess = DirAccess.open(parent)
	if directory == null:
		# 父级声明存在却无法打开时采取失败关闭，避免在不透明边界内清理。
		return DirAccess.dir_exists_absolute(parent)
	return directory.is_link(component_name)


func _tree_has_link(path: String) -> bool:
	if _path_has_link_component(path):
		return true
	if FileAccess.file_exists(path) or not DirAccess.dir_exists_absolute(path):
		return false
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return true
	directory.include_hidden = true
	if directory.list_dir_begin() != OK:
		return true
	var result: bool = false
	var child_name: String = directory.get_next()
	while not child_name.is_empty():
		if child_name != "." and child_name != "..":
			if directory.is_link(child_name):
				result = true
				break
			if directory.current_is_dir() and _tree_has_link(
				path.path_join(child_name)
			):
				result = true
				break
		child_name = directory.get_next()
	directory.list_dir_end()
	return result


func _remove_directory_contents(absolute_directory: String) -> bool:
	var directory: DirAccess = DirAccess.open(absolute_directory)
	if directory == null:
		return false
	directory.include_hidden = true
	for file_name: String in directory.get_files():
		if directory.is_link(file_name):
			return false
		var file_error: Error = DirAccess.remove_absolute(
			absolute_directory.path_join(file_name)
		)
		if file_error != OK:
			return false
	for child_name: String in directory.get_directories():
		if directory.is_link(child_name):
			return false
		var child_path: String = absolute_directory.path_join(child_name)
		if not _remove_directory_contents(child_path):
			return false
		var directory_error: Error = DirAccess.remove_absolute(child_path)
		if directory_error != OK:
			return false
	return true


func _trim_trailing_separators(path: String) -> String:
	var result: String = path
	while (
		result.length() > 1
		and result.ends_with("/")
		and not (result.length() == 3 and result.substr(1, 1) == ":")
	):
		result = result.substr(0, result.length() - 1)
	return result
