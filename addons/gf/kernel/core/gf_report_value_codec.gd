## GFReportValueCodec: 报告与诊断快照的 JSON-safe 值编码器。
##
## 用于把公开报告、调试快照和诊断事件中的任意 Variant 收束为
## JSON.stringify() 可安全处理的结构。Object、Callable、Signal 和 RID
## 会被结构化脱敏，不会把运行时对象直接泄漏到报告边界。
## [br]
## @api public
## [br]
## @category runtime_service
## [br]
## @since unreleased
class_name GFReportValueCodec
extends RefCounted


const _GF_VARIANT_ACCESS_SCRIPT = preload("res://addons/gf/kernel/core/gf_variant_access.gd")

const _REPORT_MARKER_KEY: String = "__gf_report_value__"
const _REPORT_SCHEMA_VERSION: int = 1
const _VARIANT_MARKER_KEY: String = "__gf_variant__"
const _VARIANT_SCHEMA_VERSION: int = 1
const _JSON_SAFE_INTEGER_MAX: int = 9_007_199_254_740_991
const _JSON_SAFE_INTEGER_MIN: int = -9_007_199_254_740_991
const _FLOAT_TYPE_NAME: String = "Float"
const _FLOAT_NAN_TEXT: String = "NaN"
const _FLOAT_POSITIVE_INF_TEXT: String = "INF"
const _FLOAT_NEGATIVE_INF_TEXT: String = "-INF"
const _DEFAULT_MAX_DEPTH: int = 32
const _DEFAULT_MAX_STRING_LENGTH: int = 8192
const _DEFAULT_SUMMARY_SAMPLE_COUNT: int = 16


# --- 常量 ---

## 本地调试报告配置，保留对象 id、Node 名称和路径，路径不脱敏。
## [br]
## @api public
## [br]
## @since unreleased
const REDACTION_PROFILE_DEBUG: String = "debug"

## 支持排障报告配置，保留对象 id 和 Node 名称，但默认隐藏路径。
## [br]
## @api public
## [br]
## @since unreleased
const REDACTION_PROFILE_SUPPORT: String = "support"

## 对外报告配置，隐藏对象 id、Node 名称和路径，只保留类型和有效性。
## [br]
## @api public
## [br]
## @since unreleased
const REDACTION_PROFILE_PUBLIC: String = "public"

## 隐私优先报告配置，隐藏对象 id、Node 名称、路径和 Resource 路径。
## [br]
## @api public
## [br]
## @since unreleased
const REDACTION_PROFILE_PRIVACY: String = "privacy"


# --- 公共方法 ---

## 根据内置脱敏 profile 构建报告编码选项。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param profile: REDACTION_PROFILE_* 常量之一。
## [br]
## @param overrides: 覆盖默认 profile 的选项。
## [br]
## @return 编码选项字典。
## [br]
## @schema overrides: Dictionary，可覆盖 redaction_profile、path_redaction、include_node_name、include_node_path、include_object_instance_id 和 include_resource_path。
## [br]
## @schema return: Dictionary，可直接传给 GFReportValueCodec 的编码选项。
static func make_redaction_options(profile: String, overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _get_profile_defaults(profile)
	for key: Variant in overrides.keys():
		result[key] = _duplicate_variant(overrides[key])
	result["redaction_profile"] = profile
	return result


## 将任意 Variant 转为报告边界可安全 JSON.stringify() 的值。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param value: 待转换的报告值。
## [br]
## @param options: 可选项；支持 redaction_profile、circular_reference、include_resource_path、include_node_name、include_node_path、include_object_instance_id、max_depth、max_string_length 和 path_redaction；路径默认脱敏。
## [br]
## @return JSON 兼容值；不支持的运行时类型会写入脱敏 marker。
## [br]
## @schema value: Variant report value to encode.
## [br]
## @schema options: Dictionary with redaction_profile, circular_reference, include_resource_path, include_node_name, include_node_path, include_object_instance_id, max_depth, max_string_length, path_redaction, and encode_dictionary_keys options; path_redaction defaults to redacted.
## [br]
## @schema return: Variant made only from JSON-compatible values, GF variant markers, and GF report redaction markers.
static func to_json_compatible(value: Variant, options: Dictionary = {}) -> Variant:
	var effective_options: Dictionary = _normalize_options(options)
	var sanitized: Variant = _sanitize_report_value(value, effective_options, [], 0)
	return _variant_to_json_compatible(sanitized, _make_variant_json_options(effective_options), [])


## 将任意报告值转为 JSON-safe Dictionary。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param value: 待转换的报告值。
## [br]
## @param options: 传给 to_json_compatible() 的编码选项。
## [br]
## @return JSON-safe 字典；转换结果不是 Dictionary 时返回空字典。
## [br]
## @schema value: Variant report value to encode before narrowing to Dictionary.
## [br]
## @schema options: Dictionary with redaction_profile, circular_reference, include_resource_path, include_node_name, include_node_path, include_object_instance_id, max_depth, max_string_length, path_redaction, and encode_dictionary_keys options; path_redaction defaults to redacted.
## [br]
## @schema return: Dictionary made only from JSON-compatible values, GF variant markers, and GF report redaction markers.
static func to_report_dictionary(value: Variant, options: Dictionary = {}) -> Dictionary:
	var encoded: Variant = to_json_compatible(value, options)
	if encoded is Dictionary:
		var encoded_dictionary: Dictionary = encoded
		return encoded_dictionary.duplicate(true)
	return {}


## 将报告值转为 JSON-safe 后序列化为文本。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param value: 待序列化的报告值。
## [br]
## @param indent: 缩进字符串；空字符串表示压缩输出。
## [br]
## @param sort_keys: 是否按键名排序 Dictionary。
## [br]
## @param options: 传给 to_json_compatible() 的编码选项。
## [br]
## @return JSON 文本。
## [br]
## @schema value: Variant report value to encode before JSON.stringify().
## [br]
## @schema options: Dictionary with redaction_profile, circular_reference, include_resource_path, include_node_name, include_node_path, include_object_instance_id, max_depth, max_string_length, path_redaction, and encode_dictionary_keys options; path_redaction defaults to redacted.
static func stringify_json_compatible(
	value: Variant,
	indent: String = "",
	sort_keys: bool = false,
	options: Dictionary = {}
) -> String:
	var encoded: Variant = to_json_compatible(value, options)
	return JSON.stringify(encoded, indent, sort_keys)


## 为报告中的大型集合生成稳定摘要。
## [br]
## @api public
## [br]
## @since unreleased
## [br]
## @param value: 待摘要的集合值。
## [br]
## @param options: 可选项；支持 sample_count 和传给 stringify_json_compatible() 的编码选项。
## [br]
## @return 摘要字典。
## [br]
## @schema value: Variant collection value to summarize.
## [br]
## @schema options: Dictionary with sample_count and GFReportValueCodec encoding options.
## [br]
## @schema return: Dictionary with ok, collection_type, count, sample, truncated, and hash.
static func make_collection_summary(value: Variant, options: Dictionary = {}) -> Dictionary:
	var values: Array = _collection_to_array(value)
	if values.is_empty() and not _is_empty_collection(value):
		return {
			"ok": false,
			"collection_type": type_string(typeof(value)),
			"count": 0,
			"sample": [],
			"truncated": false,
			"hash": "",
		}

	var effective_options: Dictionary = _normalize_options(options)
	var sample_count: int = maxi(_option_int(effective_options, "sample_count", _DEFAULT_SUMMARY_SAMPLE_COUNT), 0)
	var sample: Array = []
	var limit: int = mini(sample_count, values.size())
	for index: int in range(limit):
		sample.append(_sanitize_report_value(values[index], effective_options, [], 0))

	var full_text: String = stringify_json_compatible(values, "", true, effective_options)
	return {
		"ok": true,
		"collection_type": type_string(typeof(value)),
		"count": values.size(),
		"sample": to_json_compatible(sample, effective_options),
		"truncated": values.size() > sample.size(),
		"hash": full_text.sha256_text(),
	}


# --- 私有/辅助方法 ---

static func _sanitize_report_value(value: Variant, options: Dictionary, visited: Array, depth: int) -> Variant:
	var max_depth: int = _option_int(options, "max_depth", _DEFAULT_MAX_DEPTH)
	if max_depth >= 0 and depth > max_depth:
		return _make_marker("MaxDepth", {
			"depth": depth,
			"max_depth": max_depth,
		})

	match typeof(value):
		TYPE_STRING:
			var text_value: String = value
			return _sanitize_string_value(text_value, options)
		TYPE_ARRAY:
			if _visited_contains_reference(visited, value):
				return _make_marker("CircularReference", {
					"value": _option_value(options, "circular_reference", "<circular_reference>"),
				})
			visited.append(value)
			var array_value: Array = value
			var array_result: Array = []
			for item: Variant in array_value:
				array_result.append(_sanitize_report_value(item, options, visited, depth + 1))
			var _removed_array_reference: Variant = visited.pop_back()
			return array_result
		TYPE_DICTIONARY:
			if _visited_contains_reference(visited, value):
				return _make_marker("CircularReference", {
					"value": _option_value(options, "circular_reference", "<circular_reference>"),
				})
			visited.append(value)
			var dictionary_value: Dictionary = value
			var dictionary_result: Dictionary = {}
			for key: Variant in dictionary_value.keys():
				dictionary_result[key] = _sanitize_report_value(dictionary_value[key], options, visited, depth + 1)
			var _removed_dictionary_reference: Variant = visited.pop_back()
			return dictionary_result
		TYPE_OBJECT:
			return _object_to_marker(value, options)
		TYPE_CALLABLE:
			var callable_value: Callable = value
			return _make_marker("Callable", {
				"valid": callable_value.is_valid(),
			})
		TYPE_SIGNAL:
			return _make_marker("Signal", {})
		TYPE_RID:
			return _make_marker("RID", {})
		_:
			return value


static func _object_to_marker(value: Variant, options: Dictionary) -> Dictionary:
	if value == null:
		return _make_marker("Object", {
			"valid": false,
		})
	var object: Object = value
	if not is_instance_valid(object):
		return _make_marker("Object", {
			"valid": false,
		})

	var payload: Dictionary = {
		"valid": true,
		"class": object.get_class(),
		"class_name": object.get_class(),
	}
	if _option_bool(options, "include_object_instance_id", true):
		payload["instance_id"] = object.get_instance_id()
	if object is Node:
		var node: Node = object
		if _option_bool(options, "include_node_name", true):
			payload["node_name"] = String(node.name)
		if _option_bool(options, "include_node_path", false):
			payload["node_path"] = _redact_path(String(node.get_path()) if node.is_inside_tree() else String(node.name), options)
	if object is Resource and _option_bool(options, "include_resource_path", true):
		var resource: Resource = object
		if not resource.resource_path.is_empty():
			payload["resource_path"] = _redact_path(resource.resource_path, options)
	return _make_marker("Object", payload)


static func _variant_to_json_compatible(value: Variant, options: Dictionary, visited: Array) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_FLOAT:
			var float_value: float = value
			return _float_to_json_compatible(float_value)
		TYPE_INT:
			var int_value: int = _number_to_int(value)
			if _option_bool(options, "encode_unsafe_ints", true) and _is_unsafe_json_integer(int_value):
				return _make_json_typed_value("Int64", str(int_value))
			return int_value
		TYPE_STRING_NAME:
			return _make_json_typed_value("StringName", str(value))
		TYPE_NODE_PATH:
			return _make_json_typed_value("NodePath", str(value))
		TYPE_VECTOR2:
			var vector_2: Vector2 = value
			return _make_json_typed_value("Vector2", _float_array_to_json_compatible([vector_2.x, vector_2.y]))
		TYPE_VECTOR2I:
			var vector_2i: Vector2i = value
			return _make_json_typed_value("Vector2i", [vector_2i.x, vector_2i.y])
		TYPE_VECTOR3:
			var vector_3: Vector3 = value
			return _make_json_typed_value("Vector3", _float_array_to_json_compatible([vector_3.x, vector_3.y, vector_3.z]))
		TYPE_VECTOR3I:
			var vector_3i: Vector3i = value
			return _make_json_typed_value("Vector3i", [vector_3i.x, vector_3i.y, vector_3i.z])
		TYPE_VECTOR4:
			var vector_4: Vector4 = value
			return _make_json_typed_value("Vector4", _float_array_to_json_compatible([vector_4.x, vector_4.y, vector_4.z, vector_4.w]))
		TYPE_VECTOR4I:
			var vector_4i: Vector4i = value
			return _make_json_typed_value("Vector4i", [vector_4i.x, vector_4i.y, vector_4i.z, vector_4i.w])
		TYPE_RECT2:
			var rect_2: Rect2 = value
			return _make_json_typed_value("Rect2", _float_array_to_json_compatible([rect_2.position.x, rect_2.position.y, rect_2.size.x, rect_2.size.y]))
		TYPE_RECT2I:
			var rect_2i: Rect2i = value
			return _make_json_typed_value("Rect2i", [rect_2i.position.x, rect_2i.position.y, rect_2i.size.x, rect_2i.size.y])
		TYPE_COLOR:
			var color: Color = value
			return _make_json_typed_value("Color", _float_array_to_json_compatible([color.r, color.g, color.b, color.a]))
		TYPE_PLANE:
			var plane: Plane = value
			return _make_json_typed_value("Plane", _float_array_to_json_compatible([plane.normal.x, plane.normal.y, plane.normal.z, plane.d]))
		TYPE_QUATERNION:
			var quaternion: Quaternion = value
			return _make_json_typed_value("Quaternion", _float_array_to_json_compatible([quaternion.x, quaternion.y, quaternion.z, quaternion.w]))
		TYPE_AABB:
			var aabb: AABB = value
			return _make_json_typed_value("AABB", _float_array_to_json_compatible([aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z]))
		TYPE_BASIS:
			var basis: Basis = value
			return _make_json_typed_value("Basis", _basis_to_array(basis))
		TYPE_TRANSFORM2D:
			var transform_2d: Transform2D = value
			return _make_json_typed_value("Transform2D", _transform_2d_to_array(transform_2d))
		TYPE_TRANSFORM3D:
			var transform_3d: Transform3D = value
			return _make_json_typed_value("Transform3D", {
				"basis": _basis_to_array(transform_3d.basis),
				"origin": _float_array_to_json_compatible([transform_3d.origin.x, transform_3d.origin.y, transform_3d.origin.z]),
			})
		TYPE_ARRAY:
			if _visited_contains_reference(visited, value):
				return _make_circular_reference_value(options)
			visited.append(value)
			var array_value: Array = value
			var result_array: Array = []
			for item: Variant in array_value:
				result_array.append(_variant_to_json_compatible(item, options, visited))
			var _removed_array_reference: Variant = visited.pop_back()
			return result_array
		TYPE_DICTIONARY:
			if _visited_contains_reference(visited, value):
				return _make_circular_reference_value(options)
			visited.append(value)
			var dictionary_value: Dictionary = value
			var result_dictionary: Variant = _dictionary_to_json_compatible(dictionary_value, options, visited)
			var _removed_dictionary_reference: Variant = visited.pop_back()
			return result_dictionary
		TYPE_PACKED_BYTE_ARRAY:
			var byte_array: PackedByteArray = value
			return _make_json_typed_value("PackedByteArray", _packed_byte_array_to_array(byte_array))
		TYPE_PACKED_INT32_ARRAY:
			var int_32_array: PackedInt32Array = value
			return _make_json_typed_value("PackedInt32Array", Array(int_32_array))
		TYPE_PACKED_INT64_ARRAY:
			var int_64_array: PackedInt64Array = value
			return _make_json_typed_value("PackedInt64Array", Array(int_64_array))
		TYPE_PACKED_FLOAT32_ARRAY:
			var float_32_array: PackedFloat32Array = value
			return _make_json_typed_value("PackedFloat32Array", _float_array_to_json_compatible(Array(float_32_array)))
		TYPE_PACKED_FLOAT64_ARRAY:
			var float_64_array: PackedFloat64Array = value
			return _make_json_typed_value("PackedFloat64Array", _float_array_to_json_compatible(Array(float_64_array)))
		TYPE_PACKED_STRING_ARRAY:
			var string_array: PackedStringArray = value
			return _make_json_typed_value("PackedStringArray", Array(string_array))
		TYPE_PACKED_VECTOR2_ARRAY:
			var vector_2_array: PackedVector2Array = value
			return _make_json_typed_value("PackedVector2Array", _vector_2_array_to_array(vector_2_array))
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector_3_array: PackedVector3Array = value
			return _make_json_typed_value("PackedVector3Array", _vector_3_array_to_array(vector_3_array))
		TYPE_PACKED_COLOR_ARRAY:
			var color_array: PackedColorArray = value
			return _make_json_typed_value("PackedColorArray", _color_array_to_array(color_array))
		TYPE_PACKED_VECTOR4_ARRAY:
			var vector_4_array: PackedVector4Array = value
			return _make_json_typed_value("PackedVector4Array", _vector_4_array_to_array(vector_4_array))
		_:
			if _option_string(options, "unsupported", "null") == "string":
				return str(value)
	return null


static func _dictionary_to_json_compatible(value: Dictionary, options: Dictionary, visited: Array) -> Variant:
	if _option_bool(options, "encode_dictionary_keys", false):
		return _make_json_typed_value("Dictionary", _dictionary_entries_to_json_compatible(value, options, visited))

	var result: Dictionary = {}
	var seen_json_keys: Dictionary = {}
	for key: Variant in value.keys():
		var json_key: String = _json_key_to_string(key)
		if seen_json_keys.has(json_key):
			return _make_json_typed_value("Dictionary", _dictionary_entries_to_json_compatible(value, options, visited))
		seen_json_keys[json_key] = true
		result[json_key] = _variant_to_json_compatible(value[key], options, visited)
	if _has_reserved_variant_marker_shape(result):
		return _make_json_typed_value("Dictionary", _dictionary_entries_to_json_compatible(value, options, visited))
	return result


static func _dictionary_entries_to_json_compatible(value: Dictionary, options: Dictionary, visited: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: Variant in value.keys():
		entries.append({
			"key": _dictionary_key_to_json_compatible(key, options, visited),
			"value": _variant_to_json_compatible(value[key], options, visited),
		})
	return entries


static func _dictionary_key_to_json_compatible(key: Variant, options: Dictionary, visited: Array) -> Variant:
	if typeof(key) == TYPE_INT:
		return _make_json_typed_value("Int64", str(_number_to_int(key)))
	return _variant_to_json_compatible(key, options, visited)


static func _make_marker(marker_type: String, payload: Dictionary) -> Dictionary:
	var marker: Dictionary = {
		"version": _REPORT_SCHEMA_VERSION,
		"type": marker_type,
		"redacted": true,
	}
	for key: Variant in payload.keys():
		marker[key] = _duplicate_variant(payload[key])
	return {
		_REPORT_MARKER_KEY: marker,
	}


static func _make_json_typed_value(type_name: String, typed_value: Variant) -> Dictionary:
	return {
		_VARIANT_MARKER_KEY: {
			"version": _VARIANT_SCHEMA_VERSION,
			"type": type_name,
			"value": typed_value,
		},
	}


static func _make_variant_json_options(options: Dictionary) -> Dictionary:
	return {
		"encode_dictionary_keys": _option_bool(options, "encode_dictionary_keys", false),
		"encode_unsafe_ints": true,
		"unsupported": "string",
		"circular_reference": _option_value(options, "circular_reference", "<circular_reference>"),
	}


static func _make_circular_reference_value(options: Dictionary) -> Variant:
	return _make_json_typed_value(
		"CircularReference",
		_option_value(options, "circular_reference", "<circular_reference>")
	)


static func _sanitize_string_value(value: String, options: Dictionary) -> String:
	var result: String = _redact_path(value, options)
	var max_length: int = _option_int(options, "max_string_length", _DEFAULT_MAX_STRING_LENGTH)
	if max_length >= 0 and result.length() > max_length:
		return "%s..." % result.substr(0, max_length)
	return result


static func _redact_path(value: String, options: Dictionary) -> String:
	var path_redaction: String = _option_string(options, "path_redaction", "redact")
	if path_redaction == "none" or not _looks_like_path(value):
		return value
	if path_redaction == "basename":
		return value.get_file()
	if path_redaction == "hash":
		return value.sha256_text()
	return "<redacted_path>"


static func _looks_like_path(value: String) -> bool:
	return (
		value.begins_with("res://")
		or value.begins_with("user://")
		or value.begins_with("uid://")
		or value.contains(":/")
		or value.contains(":\\")
	)


static func _collection_to_array(value: Variant) -> Array:
	match typeof(value):
		TYPE_ARRAY:
			var array_value: Array = value
			return array_value.duplicate(true)
		TYPE_PACKED_BYTE_ARRAY:
			var byte_array: PackedByteArray = value
			return _packed_byte_array_to_array(byte_array)
		TYPE_PACKED_INT32_ARRAY:
			var int_32_array: PackedInt32Array = value
			return Array(int_32_array)
		TYPE_PACKED_INT64_ARRAY:
			var int_64_array: PackedInt64Array = value
			return Array(int_64_array)
		TYPE_PACKED_FLOAT32_ARRAY:
			var float_32_array: PackedFloat32Array = value
			return Array(float_32_array)
		TYPE_PACKED_FLOAT64_ARRAY:
			var float_64_array: PackedFloat64Array = value
			return Array(float_64_array)
		TYPE_PACKED_STRING_ARRAY:
			var string_array: PackedStringArray = value
			return Array(string_array)
		TYPE_PACKED_VECTOR2_ARRAY:
			var vector_2_array: PackedVector2Array = value
			return Array(vector_2_array)
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector_3_array: PackedVector3Array = value
			return Array(vector_3_array)
		TYPE_PACKED_COLOR_ARRAY:
			var color_array: PackedColorArray = value
			return Array(color_array)
		TYPE_PACKED_VECTOR4_ARRAY:
			var vector_4_array: PackedVector4Array = value
			return Array(vector_4_array)
		TYPE_DICTIONARY:
			var dictionary_value: Dictionary = value
			var entries: Array = []
			for key: Variant in dictionary_value.keys():
				entries.append({
					"key": key,
					"value": dictionary_value[key],
				})
			return entries
		_:
			return []


static func _is_empty_collection(value: Variant) -> bool:
	match typeof(value):
		TYPE_ARRAY:
			var array_value: Array = value
			return array_value.is_empty()
		TYPE_DICTIONARY:
			var dictionary_value: Dictionary = value
			return dictionary_value.is_empty()
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return _collection_to_array(value).is_empty()
		_:
			return false


static func _has_reserved_variant_marker_shape(value: Dictionary) -> bool:
	if value.size() != 1 or not value.has(_VARIANT_MARKER_KEY):
		return false
	var marker: Dictionary = _as_dictionary(_option_value(value, _VARIANT_MARKER_KEY))
	return marker.has("type") and marker.has("value")


static func _visited_contains_reference(visited: Array, value: Variant) -> bool:
	for item: Variant in visited:
		if is_same(item, value):
			return true
	return false


static func _json_key_to_string(key: Variant) -> String:
	if key is StringName:
		var string_name_key: StringName = key
		return String(string_name_key)
	return str(key)


static func _is_unsafe_json_integer(value: int) -> bool:
	return value < _JSON_SAFE_INTEGER_MIN or value > _JSON_SAFE_INTEGER_MAX


static func _float_to_json_compatible(value: float) -> Variant:
	if is_nan(value):
		return _make_json_typed_value(_FLOAT_TYPE_NAME, _FLOAT_NAN_TEXT)
	if is_inf(value):
		return _make_json_typed_value(_FLOAT_TYPE_NAME, _FLOAT_POSITIVE_INF_TEXT if value > 0.0 else _FLOAT_NEGATIVE_INF_TEXT)
	return value


static func _float_array_to_json_compatible(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		if value is float:
			var float_value: float = value
			result.append(_float_to_json_compatible(float_value))
		elif value is int:
			var int_value: int = value
			result.append(float(int_value))
		else:
			result.append(0.0)
	return result


static func _basis_to_array(value: Basis) -> Array:
	return [
		_float_array_to_json_compatible([value.x.x, value.x.y, value.x.z]),
		_float_array_to_json_compatible([value.y.x, value.y.y, value.y.z]),
		_float_array_to_json_compatible([value.z.x, value.z.y, value.z.z]),
	]


static func _transform_2d_to_array(value: Transform2D) -> Array:
	return [
		_float_array_to_json_compatible([value.x.x, value.x.y]),
		_float_array_to_json_compatible([value.y.x, value.y.y]),
		_float_array_to_json_compatible([value.origin.x, value.origin.y]),
	]


static func _packed_byte_array_to_array(value: PackedByteArray) -> Array:
	var result: Array = []
	for item: int in value:
		result.append(item)
	return result


static func _vector_2_array_to_array(value: PackedVector2Array) -> Array:
	var result: Array = []
	for item: Vector2 in value:
		result.append(_float_array_to_json_compatible([item.x, item.y]))
	return result


static func _vector_3_array_to_array(value: PackedVector3Array) -> Array:
	var result: Array = []
	for item: Vector3 in value:
		result.append(_float_array_to_json_compatible([item.x, item.y, item.z]))
	return result


static func _vector_4_array_to_array(value: PackedVector4Array) -> Array:
	var result: Array = []
	for item: Vector4 in value:
		result.append(_float_array_to_json_compatible([item.x, item.y, item.z, item.w]))
	return result


static func _color_array_to_array(value: PackedColorArray) -> Array:
	var result: Array = []
	for item: Color in value:
		result.append(_float_array_to_json_compatible([item.r, item.g, item.b, item.a]))
	return result


static func _number_to_int(value: Variant) -> int:
	if value is int:
		var int_value: int = value
		return int_value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return 0


static func _duplicate_variant(value: Variant) -> Variant:
	return _GF_VARIANT_ACCESS_SCRIPT.duplicate_variant(value)


static func _as_dictionary(value: Variant, default_value: Variant = null) -> Dictionary:
	return _GF_VARIANT_ACCESS_SCRIPT.as_dictionary(value, default_value)


static func _option_value(options: Dictionary, key: Variant, default_value: Variant = null) -> Variant:
	return _GF_VARIANT_ACCESS_SCRIPT.get_option_value(options, key, default_value)


static func _option_bool(options: Dictionary, key: Variant, default_value: bool = false) -> bool:
	return _GF_VARIANT_ACCESS_SCRIPT.get_option_bool(options, key, default_value)


static func _option_int(options: Dictionary, key: Variant, default_value: int = 0) -> int:
	return _GF_VARIANT_ACCESS_SCRIPT.get_option_int(options, key, default_value)


static func _option_string(options: Dictionary, key: Variant, default_value: String = "") -> String:
	return _GF_VARIANT_ACCESS_SCRIPT.get_option_string(options, key, default_value)


static func _normalize_options(options: Dictionary) -> Dictionary:
	var profile: String = _option_string(options, "redaction_profile", REDACTION_PROFILE_SUPPORT)
	var result: Dictionary = _get_profile_defaults(profile)
	for key: Variant in options.keys():
		result[key] = options[key]
	return result


static func _get_profile_defaults(profile: String) -> Dictionary:
	match profile:
		REDACTION_PROFILE_DEBUG:
			return {
				"redaction_profile": REDACTION_PROFILE_DEBUG,
				"path_redaction": "none",
				"include_node_name": true,
				"include_node_path": true,
				"include_object_instance_id": true,
				"include_resource_path": true,
			}
		REDACTION_PROFILE_PUBLIC:
			return {
				"redaction_profile": REDACTION_PROFILE_PUBLIC,
				"path_redaction": "redact",
				"include_node_name": false,
				"include_node_path": false,
				"include_object_instance_id": false,
				"include_resource_path": false,
			}
		REDACTION_PROFILE_PRIVACY:
			return {
				"redaction_profile": REDACTION_PROFILE_PRIVACY,
				"path_redaction": "redact",
				"include_node_name": false,
				"include_node_path": false,
				"include_object_instance_id": false,
				"include_resource_path": false,
			}
		_:
			return {
				"redaction_profile": REDACTION_PROFILE_SUPPORT,
				"path_redaction": "redact",
				"include_node_name": true,
				"include_node_path": false,
				"include_object_instance_id": true,
				"include_resource_path": true,
			}
