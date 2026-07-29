## BookmarkCatalogSaveData: bookmarks Feature 的严格 GFSaveProfile section。
class_name BookmarkCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 9


# --- 私有变量 ---

## 持有已经通过严格校验的规范持久化 envelope。
##
## 保留二进制历史原文可让 gather 与事务快照直接复制，不必把每个撤回快照
## 反复解码为 Resource，再在保存、回滚和读取时重新编码。
var _items: Array[Dictionary] = []
var _decoded_items_by_id: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.BOOKMARKS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: Dictionary in _items:
		serialized_items.append(item)
	return {
		"items": serialized_items,
	}


func _make_runtime_section_cache_snapshot() -> Dictionary:
	var decoded_items: Array[BookmarkData] = []
	for item: Dictionary in _items:
		var bookmark_id: String = GFVariantData.get_option_string(
			item,
			"bookmark_id"
		)
		var decoded_value: Variant = _decoded_items_by_id.get(
			bookmark_id
		)
		if decoded_value is BookmarkData:
			var decoded_item: BookmarkData = decoded_value
			var duplicate_value: Resource = decoded_item.duplicate(true)
			if duplicate_value is BookmarkData:
				var duplicate_item: BookmarkData = duplicate_value
				decoded_items.append(duplicate_item)
	return {&"items": decoded_items}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, "items")
	if not (items_value is Array):
		return ERR_INVALID_DATA

	var current_by_id: Dictionary = {}
	for current_item: Dictionary in _items:
		current_by_id[
			GFVariantData.get_option_string(
				current_item,
				"bookmark_id"
			)
		] = current_item

	var next_items: Array[Dictionary] = []
	var next_decoded_items_by_id: Dictionary = {}
	var seen_ids: Dictionary = {}
	for item_value: Variant in GFVariantData.as_array(items_value):
		if not (item_value is Dictionary):
			return ERR_INVALID_DATA
		var item_envelope: Dictionary = GFVariantData.as_dictionary(
			item_value
		)
		if not BookmarkData.is_persisted_envelope_lightweight_valid(
			item_envelope
		):
			return ERR_INVALID_DATA
		var bookmark_id: String = GFVariantData.get_option_string(
			item_envelope,
			"bookmark_id"
		)
		if seen_ids.has(bookmark_id):
			return ERR_INVALID_DATA
		seen_ids[bookmark_id] = true

		var current_value: Variant = current_by_id.get(bookmark_id)
		if current_value is Dictionary and current_value == item_envelope:
			next_items.append(GFVariantData.as_dictionary(current_value))
			var current_decoded_value: Variant = (
				_decoded_items_by_id.get(bookmark_id)
			)
			if not current_decoded_value is BookmarkData:
				return ERR_INVALID_DATA
			next_decoded_items_by_id[bookmark_id] = current_decoded_value
			continue

		# 初次 Profile load 以及新增/变化书签必须完整解码历史并校验命令语义。
		# 只有与当前已验证 envelope 完全相同的项才可走上面的稳定快路径。
		var decoded_item: BookmarkData = BookmarkData.from_dict(
			item_envelope
		)
		if decoded_item == null:
			return ERR_INVALID_DATA
		if (
			GFVariantData.get_option_int(
				item_envelope,
				"schema_version"
			) == BookmarkData.SCHEMA_VERSION
		):
			next_items.append(item_envelope)
		else:
			# v5 字典历史仅在初载时解码一次，并在下一次持久化时升级为 v6。
			next_items.append(decoded_item.to_dict())
		next_decoded_items_by_id[bookmark_id] = decoded_item

	next_items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return (
			GFVariantData.get_option_string(left, "bookmark_id")
			> GFVariantData.get_option_string(right, "bookmark_id")
		)
	)
	_items = next_items
	_decoded_items_by_id = next_decoded_items_by_id
	return OK
