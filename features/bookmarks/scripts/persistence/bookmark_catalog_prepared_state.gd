## 已逐帧严格物化、可一次性交给 BookmarkCatalogSaveData 的目录根。
##
## 持久化 envelope 与对应 BookmarkData cache 在 decoder 中同时构造；apply
## 只交换两个有限根，不再同步调用 BookmarkData.from_dict() 扫描完整流。
class_name BookmarkCatalogPreparedState
extends RefCounted


# --- 私有变量 ---

var _items: Array[Dictionary] = []
var _decoded_items_by_id: Dictionary = {}
var _available: bool = false


# --- 公共方法 ---

## 接管 decoder 已完整验证的不可变 envelope 与 Resource cache 根。
## @param items: 已验证、具有唯一书签 ID 的持久化 envelope 根。
## @param decoded_items_by_id: 书签 ID 到对应 BookmarkData 缓存的映射。
static func take_ownership_of_validated_roots(
	items: Array[Dictionary],
	decoded_items_by_id: Dictionary
) -> BookmarkCatalogPreparedState:
	if (
		items.size() > BookmarkCatalogSaveData.MAX_BOOKMARK_COUNT
		or decoded_items_by_id.size() != items.size()
	):
		return null
	var seen_ids: Dictionary = {}
	for item: Dictionary in items:
		var bookmark_id: String = GFVariantData.get_option_string(
			item,
			&"bookmark_id"
		)
		var decoded_value: Variant = decoded_items_by_id.get(bookmark_id)
		if (
			bookmark_id.is_empty()
			or seen_ids.has(bookmark_id)
			or not decoded_value is BookmarkData
		):
			return null
		var decoded: BookmarkData = decoded_value
		if decoded.bookmark_id != bookmark_id:
			return null
		seen_ids[bookmark_id] = true
	items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return GFVariantData.get_option_string(
			left,
			&"bookmark_id"
		) > GFVariantData.get_option_string(right, &"bookmark_id")
	)
	var state: BookmarkCatalogPreparedState = BookmarkCatalogPreparedState.new()
	state._items = items
	state._decoded_items_by_id = decoded_items_by_id
	state._available = true
	return state


func get_item_count() -> int:
	return _items.size() if _available else 0


## 返回稳定 Resource 身份，仅供 rollback/回归测试；不暴露对象 alias。
func get_item_instance_ids() -> PackedInt64Array:
	var identities: PackedInt64Array = PackedInt64Array()
	if not _available:
		return identities
	for item: Dictionary in _items:
		var bookmark_id: String = GFVariantData.get_option_string(
			item,
			&"bookmark_id"
		)
		var decoded_value: Variant = _decoded_items_by_id.get(bookmark_id)
		if decoded_value is BookmarkData:
			var decoded: BookmarkData = decoded_value
			var _appended: bool = identities.append(decoded.get_instance_id())
	return identities


## 一次性移出两个根；重复调用返回空字典。
func take_roots_taking_ownership() -> Dictionary:
	if not _available:
		return {}
	var roots: Dictionary = {
		&"items": _items,
		&"decoded_items_by_id": _decoded_items_by_id,
	}
	_items = []
	_decoded_items_by_id = {}
	_available = false
	return roots


## 仅供同步 codec 单元测试恢复旧 `{items}` 断言。
func make_serialized_payload_for_tests() -> Dictionary:
	return {&"items": _items} if _available else {}
