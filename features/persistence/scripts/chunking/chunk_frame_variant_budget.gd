## manifest-backed framed-record codec 共用的严格 Variant 结构预算。
##
## 本类只判断一个待编码/已解码 frame 是否能在固定 work/memory 上限内安全
## 递归处理；不拥有任何 Feature schema。Object、Callable、RID、Signal、循环
## 引用与非有限数一律拒绝。
class_name ChunkFrameVariantBudget
extends RefCounted


# --- 常量 ---

const MAX_VARIANT_DEPTH: int = 8
const MAX_VARIANT_NODES: int = 4096
const MAX_CONTAINER_COUNT: int = 256
const MAX_CONTAINER_ITEMS: int = 2048
const MAX_PACKED_BYTES: int = 64 * 1024
const MAX_TEXT_CHARACTERS: int = 16 * 1024
const MAX_APPROX_BYTES: int = 96 * 1024


# --- 公共方法 ---

## 使用 persistence 默认预算扫描单个 Variant frame。
## @param value: 待执行结构与资源预算校验的 Variant frame。
static func is_value_within_default_budget(value: Variant) -> bool:
	var state: Dictionary = {
		&"node_count": 0,
		&"container_count": 0,
		&"container_items": 0,
		&"packed_bytes": 0,
		&"approx_bytes": 0,
	}
	return _scan_value(value, state, 0, [])


# --- 私有/辅助方法 ---

static func _scan_value(
	value: Variant,
	state: Dictionary,
	depth: int,
	active_containers: Array
) -> bool:
	if depth > MAX_VARIANT_DEPTH or not _consume_node(state):
		return false
	match typeof(value):
		TYPE_NIL:
			return _consume_approx_bytes(state, 1)
		TYPE_BOOL:
			return _consume_approx_bytes(state, 1)
		TYPE_INT:
			return _consume_approx_bytes(state, 8)
		TYPE_FLOAT:
			var number: float = value
			return is_finite(number) and _consume_approx_bytes(state, 8)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return _consume_text(state, str(value))
		TYPE_VECTOR2:
			var vector_2: Vector2 = value
			return (
				_are_finite([vector_2.x, vector_2.y])
				and _consume_approx_bytes(state, 16)
			)
		TYPE_VECTOR2I:
			return _consume_approx_bytes(state, 16)
		TYPE_RECT2:
			var rect_2: Rect2 = value
			return (
				_are_finite([
					rect_2.position.x,
					rect_2.position.y,
					rect_2.size.x,
					rect_2.size.y,
				])
				and _consume_approx_bytes(state, 32)
			)
		TYPE_RECT2I, TYPE_VECTOR3I:
			return _consume_approx_bytes(state, 32)
		TYPE_VECTOR3:
			var vector_3: Vector3 = value
			return (
				_are_finite([vector_3.x, vector_3.y, vector_3.z])
				and _consume_approx_bytes(state, 32)
			)
		TYPE_TRANSFORM2D:
			var transform_2d: Transform2D = value
			return (
				_are_finite([
					transform_2d.x.x,
					transform_2d.x.y,
					transform_2d.y.x,
					transform_2d.y.y,
					transform_2d.origin.x,
					transform_2d.origin.y,
				])
				and _consume_approx_bytes(state, 64)
			)
		TYPE_VECTOR4:
			var vector_4: Vector4 = value
			return (
				_are_finite([
					vector_4.x,
					vector_4.y,
					vector_4.z,
					vector_4.w,
				])
				and _consume_approx_bytes(state, 64)
			)
		TYPE_VECTOR4I:
			return _consume_approx_bytes(state, 64)
		TYPE_PLANE:
			var plane: Plane = value
			return (
				_are_finite([
					plane.normal.x,
					plane.normal.y,
					plane.normal.z,
					plane.d,
				])
				and _consume_approx_bytes(state, 64)
			)
		TYPE_QUATERNION:
			var quaternion: Quaternion = value
			return (
				_are_finite([
					quaternion.x,
					quaternion.y,
					quaternion.z,
					quaternion.w,
				])
				and _consume_approx_bytes(state, 32)
			)
		TYPE_COLOR:
			var color: Color = value
			return (
				_are_finite([color.r, color.g, color.b, color.a])
				and _consume_approx_bytes(state, 32)
			)
		TYPE_AABB:
			var box: AABB = value
			return (
				_are_finite([
					box.position.x,
					box.position.y,
					box.position.z,
					box.size.x,
					box.size.y,
					box.size.z,
				])
				and _consume_approx_bytes(state, 128)
			)
		TYPE_BASIS:
			var basis: Basis = value
			return (
				_are_finite([
					basis.x.x, basis.x.y, basis.x.z,
					basis.y.x, basis.y.y, basis.y.z,
					basis.z.x, basis.z.y, basis.z.z,
				])
				and _consume_approx_bytes(state, 128)
			)
		TYPE_TRANSFORM3D:
			var transform_3d: Transform3D = value
			return (
				_are_finite([
					transform_3d.basis.x.x,
					transform_3d.basis.x.y,
					transform_3d.basis.x.z,
					transform_3d.basis.y.x,
					transform_3d.basis.y.y,
					transform_3d.basis.y.z,
					transform_3d.basis.z.x,
					transform_3d.basis.z.y,
					transform_3d.basis.z.z,
					transform_3d.origin.x,
					transform_3d.origin.y,
					transform_3d.origin.z,
				])
				and _consume_approx_bytes(state, 192)
			)
		TYPE_PROJECTION:
			var projection: Projection = value
			return (
				_are_finite([
					projection.x.x, projection.x.y,
					projection.x.z, projection.x.w,
					projection.y.x, projection.y.y,
					projection.y.z, projection.y.w,
					projection.z.x, projection.z.y,
					projection.z.z, projection.z.w,
					projection.w.x, projection.w.y,
					projection.w.z, projection.w.w,
				])
				and _consume_approx_bytes(state, 256)
			)
		TYPE_ARRAY:
			return _scan_array(
				GFVariantData.as_array(value),
				state,
				depth,
				active_containers
			)
		TYPE_DICTIONARY:
			return _scan_dictionary(
				GFVariantData.as_dictionary(value),
				state,
				depth,
				active_containers
			)
		TYPE_PACKED_BYTE_ARRAY:
			var bytes: PackedByteArray = value
			return _consume_packed_array(state, bytes.size(), 1)
		TYPE_PACKED_INT32_ARRAY:
			return _consume_packed_array(state, len(value), 4)
		TYPE_PACKED_INT64_ARRAY:
			return _consume_packed_array(state, len(value), 8)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return (
				_consume_packed_array(
					state,
					len(value),
					4 if typeof(value) == TYPE_PACKED_FLOAT32_ARRAY else 8
				)
				and _are_finite(value)
			)
		TYPE_PACKED_VECTOR2_ARRAY:
			return (
				_consume_packed_array(state, len(value), 8)
				and _packed_vectors_are_finite(value)
			)
		TYPE_PACKED_VECTOR3_ARRAY:
			return (
				_consume_packed_array(state, len(value), 12)
				and _packed_vectors_are_finite(value)
			)
		TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return (
				_consume_packed_array(state, len(value), 16)
				and _packed_vectors_are_finite(value)
			)
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = value
			if not _consume_container(state, strings.size()):
				return false
			for text_value: String in strings:
				if not _consume_text(state, text_value):
					return false
			return true
		_:
			return false


static func _scan_array(
	value: Array,
	state: Dictionary,
	depth: int,
	active_containers: Array
) -> bool:
	if (
		not _consume_container(state, value.size())
		or _contains_same_container(active_containers, value)
		or not _consume_approx_bytes(state, 16 + value.size() * 8)
	):
		return false
	active_containers.append(value)
	for child: Variant in value:
		if not _scan_value(child, state, depth + 1, active_containers):
			var _removed_on_failure: Variant = active_containers.pop_back()
			return false
	var _removed: Variant = active_containers.pop_back()
	return true


static func _scan_dictionary(
	value: Dictionary,
	state: Dictionary,
	depth: int,
	active_containers: Array
) -> bool:
	if (
		not _consume_container(state, value.size() * 2)
		or _contains_same_container(active_containers, value)
		or not _consume_approx_bytes(state, 32 + value.size() * 16)
	):
		return false
	active_containers.append(value)
	for key: Variant in value.keys():
		if (
			not _scan_value(key, state, depth + 1, active_containers)
			or not _scan_value(
				value[key],
				state,
				depth + 1,
				active_containers
			)
		):
			var _removed_on_failure: Variant = active_containers.pop_back()
			return false
	var _removed: Variant = active_containers.pop_back()
	return true


static func _consume_node(state: Dictionary) -> bool:
	state[&"node_count"] = GFVariantData.get_option_int(
		state,
		&"node_count"
	) + 1
	return (
		GFVariantData.get_option_int(state, &"node_count")
		<= MAX_VARIANT_NODES
	)


static func _consume_container(state: Dictionary, item_count: int) -> bool:
	if item_count < 0 or item_count > MAX_CONTAINER_ITEMS:
		return false
	state[&"container_count"] = GFVariantData.get_option_int(
		state,
		&"container_count"
	) + 1
	state[&"container_items"] = GFVariantData.get_option_int(
		state,
		&"container_items"
	) + item_count
	return (
		GFVariantData.get_option_int(state, &"container_count")
		<= MAX_CONTAINER_COUNT
		and GFVariantData.get_option_int(state, &"container_items")
		<= MAX_CONTAINER_ITEMS
	)


static func _consume_packed_array(
	state: Dictionary,
	element_count: int,
	element_bytes: int
) -> bool:
	if not _consume_container(state, element_count):
		return false
	var byte_count: int = element_count * element_bytes
	state[&"packed_bytes"] = GFVariantData.get_option_int(
		state,
		&"packed_bytes"
	) + byte_count
	return (
		GFVariantData.get_option_int(state, &"packed_bytes")
		<= MAX_PACKED_BYTES
		and _consume_approx_bytes(state, byte_count)
	)


static func _consume_text(state: Dictionary, value: String) -> bool:
	if value.length() > MAX_TEXT_CHARACTERS:
		return false
	# 字符上限先约束临时 UTF-8 分配，最长编码仍不超过 64 KiB。
	return _consume_approx_bytes(state, value.to_utf8_buffer().size())


static func _consume_approx_bytes(state: Dictionary, byte_count: int) -> bool:
	state[&"approx_bytes"] = GFVariantData.get_option_int(
		state,
		&"approx_bytes"
	) + maxi(byte_count, 0)
	return (
		GFVariantData.get_option_int(state, &"approx_bytes")
		<= MAX_APPROX_BYTES
	)


static func _contains_same_container(
	active_containers: Array,
	value: Variant
) -> bool:
	for active_value: Variant in active_containers:
		if is_same(active_value, value):
			return true
	return false


static func _are_finite(values: Variant) -> bool:
	for value: Variant in values:
		if value is float:
			var number: float = value
			if not is_finite(number):
				return false
	return true


static func _packed_vectors_are_finite(values: Variant) -> bool:
	for value: Variant in values:
		match typeof(value):
			TYPE_VECTOR2:
				var vector_2: Vector2 = value
				if not _are_finite([vector_2.x, vector_2.y]):
					return false
			TYPE_VECTOR3:
				var vector_3: Vector3 = value
				if not _are_finite([vector_3.x, vector_3.y, vector_3.z]):
					return false
			TYPE_VECTOR4:
				var vector_4: Vector4 = value
				if not _are_finite([
					vector_4.x,
					vector_4.y,
					vector_4.z,
					vector_4.w,
				]):
					return false
			TYPE_COLOR:
				var color: Color = value
				if not _are_finite([color.r, color.g, color.b, color.a]):
					return false
			_:
				return false
	return true
