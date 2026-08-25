## AssetJsonEntryBudget: 素材 JSON object 解析后的条目预算策略。
##
## 文件读取、UTF-8、字节数、词法深度和 JSON object 信任边界由公开的
## GFBoundedJsonObjectReader 独占；本类只保留素材工具自己的 object 成员与
## array 元素总量政策，并把 GF 报告补充为项目工具使用的结构化终态。
class_name AssetJsonEntryBudget
extends RefCounted


# --- 常量 ---

const DEFAULT_MAX_ENTRIES: int = 100_000
const ABSOLUTE_MAX_ENTRIES: int = 1_000_000
const ERROR_ENTRY_BUDGET_EXCEEDED: StringName = &"entry_budget_exceeded"


# --- 公共方法 ---

## 对 GF 已验证的 JSON object 读取报告追加素材条目预算。
## @param read_report: GFBoundedJsonObjectReader.read_object() 的公开报告。
## @param max_entries: object 成员与 array 元素总量预算，只能收紧项目绝对上限。
## @return: 保留 GF 证据并追加 error_code、message、entry_count 与 max_entries。
static func apply_to_read_report(
	read_report: Dictionary,
	max_entries: int = DEFAULT_MAX_ENTRIES
) -> Dictionary:
	var effective_max_entries: int = _effective_max_entries(max_entries)
	var report: Dictionary = read_report.duplicate(true)
	var successful: bool = GFVariantData.get_option_bool(report, "ok")
	var error_kind: StringName = GFVariantData.get_option_string_name(
		report,
		"error_kind"
	)
	report["error_code"] = OK if successful else _map_gf_error_code(error_kind)
	report["message"] = GFVariantData.get_option_string(report, "error")
	report["max_file_bytes"] = GFVariantData.get_option_int(report, "max_bytes")
	report["max_entries"] = effective_max_entries
	report["entry_count"] = 0
	if not successful:
		report["data"] = {}
		return report

	var data: Dictionary = GFVariantData.get_option_dictionary(report, "data")
	var measurement: Dictionary = _measure_entries(data, effective_max_entries)
	var entry_count: int = GFVariantData.get_option_int(measurement, "entry_count")
	report["entry_count"] = entry_count
	if not GFVariantData.get_option_bool(measurement, "exceeded"):
		return report

	var message: String = "JSON object/array 条目超过预算 %d。" % effective_max_entries
	report["ok"] = false
	report["error_code"] = ERR_INVALID_DATA
	report["error_kind"] = ERROR_ENTRY_BUDGET_EXCEEDED
	report["error"] = message
	report["message"] = message
	report["data"] = {}
	return report


# --- 私有/辅助方法 ---

static func _effective_max_entries(requested: int) -> int:
	if requested <= 0:
		return DEFAULT_MAX_ENTRIES
	return mini(requested, ABSOLUTE_MAX_ENTRIES)


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


static func _map_gf_error_code(error_kind: StringName) -> Error:
	match error_kind:
		&"open_failed":
			return ERR_CANT_OPEN
		&"parse_failed":
			return ERR_PARSE_ERROR
		_:
			return ERR_INVALID_DATA
