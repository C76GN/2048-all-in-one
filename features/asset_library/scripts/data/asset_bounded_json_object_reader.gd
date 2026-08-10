## AssetBoundedJsonObjectReader: 素材工具侧严格有界的 JSON object 读取报告。
##
## GF 当前公开 API 尚未提供通用 bounded JSON object reader；本类只拥有项目素材
## 工具的信任边界。它在解析前限制文件字节数并以识别字符串/转义的扫描限制嵌套
## 深度，解析后再限制 object 成员与 array 元素总数，避免不受信任素材配置无界展开。
class_name AssetBoundedJsonObjectReader
extends RefCounted


# --- 常量 ---

const DEFAULT_MAX_FILE_BYTES: int = 1024 * 1024
const DEFAULT_MAX_DEPTH: int = 32
const DEFAULT_MAX_ENTRIES: int = 100_000
const HARD_MAX_FILE_BYTES: int = 4 * 1024 * 1024
const HARD_MAX_DEPTH: int = 64
const HARD_MAX_ENTRIES: int = 1_000_000

const ERROR_NONE: StringName = &""
const ERROR_EMPTY_PATH: StringName = &"empty_path"
const ERROR_OPEN_FAILED: StringName = &"open_failed"
const ERROR_FILE_TOO_LARGE: StringName = &"file_too_large"
const ERROR_READ_FAILED: StringName = &"read_failed"
const ERROR_DEPTH_EXCEEDED: StringName = &"max_depth_exceeded"
const ERROR_INVALID_JSON: StringName = &"invalid_json"
const ERROR_INVALID_ROOT: StringName = &"invalid_root"
const ERROR_ENTRY_BUDGET_EXCEEDED: StringName = &"entry_budget_exceeded"


# --- 公共方法 ---

## 读取 JSON object 并返回结构化终态；预算只能收紧项目硬上限。
## @param path: res://、user:// 或绝对文件路径。
## @param options: max_file_bytes、max_depth、max_entries。
## @return: 包含 ok、error_code、error_kind、message、data 和预算证据的报告。
static func read_object_report(path: String, options: Dictionary = {}) -> Dictionary:
	var source_path: String = path.strip_edges()
	var max_file_bytes: int = _get_bounded_limit(
		options,
		"max_file_bytes",
		DEFAULT_MAX_FILE_BYTES,
		HARD_MAX_FILE_BYTES
	)
	var max_depth: int = _get_bounded_limit(
		options,
		"max_depth",
		DEFAULT_MAX_DEPTH,
		HARD_MAX_DEPTH
	)
	var max_entries: int = _get_bounded_limit(
		options,
		"max_entries",
		DEFAULT_MAX_ENTRIES,
		HARD_MAX_ENTRIES
	)
	var limits: Dictionary = {
		"max_file_bytes": max_file_bytes,
		"max_depth": max_depth,
		"max_entries": max_entries,
	}
	if source_path.is_empty():
		return _make_failure(
			source_path,
			ERR_INVALID_PARAMETER,
			ERROR_EMPTY_PATH,
			"JSON 路径为空。",
			limits
		)

	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		return _make_failure(
			source_path,
			open_error,
			ERROR_OPEN_FAILED,
			"无法打开 JSON：%s。" % error_string(open_error),
			limits
		)

	var size_bytes: int = file.get_length()
	if size_bytes > max_file_bytes:
		file.close()
		return _make_failure(
			source_path,
			ERR_INVALID_DATA,
			ERROR_FILE_TOO_LARGE,
			"JSON 超过字节预算 %d：%d bytes。" % [max_file_bytes, size_bytes],
			limits,
			{"size_bytes": size_bytes}
		)

	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return _make_failure(
			source_path,
			read_error,
			ERROR_READ_FAILED,
			"无法读取 JSON：%s。" % error_string(read_error),
			limits,
			{"size_bytes": size_bytes}
		)

	var depth_report: Dictionary = _scan_json_depth(text, max_depth)
	if GFVariantData.get_option_bool(depth_report, "exceeded"):
		return _make_failure(
			source_path,
			ERR_INVALID_DATA,
			ERROR_DEPTH_EXCEEDED,
			"JSON 嵌套深度超过预算 %d。" % max_depth,
			limits,
			{
				"size_bytes": size_bytes,
				"observed_depth": GFVariantData.get_option_int(depth_report, "observed_depth"),
			}
		)

	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return _make_failure(
			source_path,
			ERR_PARSE_ERROR,
			ERROR_INVALID_JSON,
			"JSON 解析失败（第 %d 行）：%s。" % [
				parser.get_error_line(),
				parser.get_error_message(),
			],
			limits,
			{
				"size_bytes": size_bytes,
				"observed_depth": GFVariantData.get_option_int(depth_report, "observed_depth"),
			}
		)

	if not (parser.data is Dictionary):
		return _make_failure(
			source_path,
			ERR_INVALID_DATA,
			ERROR_INVALID_ROOT,
			"JSON 根节点必须是 object。",
			limits,
			{
				"size_bytes": size_bytes,
				"observed_depth": GFVariantData.get_option_int(depth_report, "observed_depth"),
			}
		)

	var data: Dictionary = GFVariantData.as_dictionary(parser.data)
	var entry_report: Dictionary = _measure_entries(data, max_entries)
	if GFVariantData.get_option_bool(entry_report, "exceeded"):
		return _make_failure(
			source_path,
			ERR_INVALID_DATA,
			ERROR_ENTRY_BUDGET_EXCEEDED,
			"JSON object/array 条目超过预算 %d。" % max_entries,
			limits,
			{
				"size_bytes": size_bytes,
				"observed_depth": GFVariantData.get_option_int(depth_report, "observed_depth"),
				"entry_count": GFVariantData.get_option_int(entry_report, "entry_count"),
			}
		)

	return {
		"ok": true,
		"error_code": OK,
		"error_kind": ERROR_NONE,
		"message": "",
		"source_path": source_path,
		"data": data.duplicate(true),
		"size_bytes": size_bytes,
		"observed_depth": GFVariantData.get_option_int(depth_report, "observed_depth"),
		"entry_count": GFVariantData.get_option_int(entry_report, "entry_count"),
		"max_file_bytes": max_file_bytes,
		"max_depth": max_depth,
		"max_entries": max_entries,
	}


# --- 私有/辅助方法 ---

static func _get_bounded_limit(
	options: Dictionary,
	key: String,
	default_value: int,
	hard_limit: int
) -> int:
	var requested: int = GFVariantData.get_option_int(options, key, default_value)
	if requested <= 0:
		requested = default_value
	return mini(requested, hard_limit)


## 只把非字符串中的 `{` / `[` 计为嵌套；反斜杠转义不会误结束字符串。
static func _scan_json_depth(text: String, max_depth: int) -> Dictionary:
	var depth: int = 0
	var observed_depth: int = 0
	var in_string: bool = false
	var escaped: bool = false
	for index: int in text.length():
		var codepoint: int = text.unicode_at(index)
		if in_string:
			if escaped:
				escaped = false
			elif codepoint == 92:
				escaped = true
			elif codepoint == 34:
				in_string = false
			continue
		if codepoint == 34:
			in_string = true
		elif codepoint == 123 or codepoint == 91:
			depth += 1
			observed_depth = maxi(observed_depth, depth)
			if depth > max_depth:
				return {"exceeded": true, "observed_depth": observed_depth}
		elif codepoint == 125 or codepoint == 93:
			depth = maxi(depth - 1, 0)
	return {"exceeded": false, "observed_depth": observed_depth}


## 条目定义为每个 object 成员和 array 元素；标量不额外重复计数。
static func _measure_entries(root: Dictionary, max_entries: int) -> Dictionary:
	var pending: Array[Dictionary] = [{"value": root}]
	var entry_count: int = 0
	while not pending.is_empty():
		var frame: Dictionary = pending.pop_back()
		var value: Variant = frame.get("value")
		if value is Dictionary:
			var object_value: Dictionary = value
			entry_count += object_value.size()
			if entry_count > max_entries:
				return {"exceeded": true, "entry_count": entry_count}
			for key: Variant in object_value.keys():
				var object_child: Variant = object_value[key]
				if object_child is Dictionary or object_child is Array:
					pending.append({"value": object_child})
		elif value is Array:
			var array_value: Array = value
			entry_count += array_value.size()
			if entry_count > max_entries:
				return {"exceeded": true, "entry_count": entry_count}
			for array_child: Variant in array_value:
				if array_child is Dictionary or array_child is Array:
					pending.append({"value": array_child})
	return {"exceeded": false, "entry_count": entry_count}


static func _make_failure(
	source_path: String,
	error_code: Error,
	error_kind: StringName,
	message: String,
	limits: Dictionary,
	evidence: Dictionary = {}
) -> Dictionary:
	var report: Dictionary = {
		"ok": false,
		"error_code": error_code,
		"error_kind": error_kind,
		"message": message,
		"source_path": source_path,
		"data": {},
		"size_bytes": 0,
		"observed_depth": 0,
		"entry_count": 0,
		"max_file_bytes": GFVariantData.get_option_int(limits, "max_file_bytes"),
		"max_depth": GFVariantData.get_option_int(limits, "max_depth"),
		"max_entries": GFVariantData.get_option_int(limits, "max_entries"),
	}
	for key: Variant in evidence.keys():
		report[key] = evidence[key]
	return report
