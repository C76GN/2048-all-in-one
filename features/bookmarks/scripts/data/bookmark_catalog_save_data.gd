## BookmarkCatalogSaveData: bookmarks Feature 的严格 GFSaveProfile section。
class_name BookmarkCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 9
## 产品目录最多展示并保留的书签数；新增项按 UUID v7 时间顺序替换最旧项。
const MAX_BOOKMARK_COUNT: int = 16
## GFStorage 当前对完整文档执行 1,000,000 个 Variant 的物理预算；每个合法
## 书签根至少占 45 个值（22 个键值对和 Dictionary 本身）。20,000 因此覆盖
## 所有可由当前 GFStorage 产生的旧目录，同时拒绝绕过存储边界的异常调用。
## 产品上限以上的同 schema 数据会严格校验后安全收敛为最新 16 项。
const ABSOLUTE_MAX_BOOKMARK_COUNT: int = 20_000


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

func _begin_save_snapshot(
	_context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	return _BookmarkCatalogSnapshotOperation.new(
		section_id,
		schema_version,
		# Operation 必须拥有独立根；取消时清空其工作集不得触及 provider。
		# 嵌套 envelope 仍在各 work unit 内逐项隔离，避免 begin 同步遍历。
		_items.duplicate()
	)

func _validate_section_data_boundary(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, "items")
	if not items_value is Array:
		return ERR_INVALID_DATA
	var item_values: Array = GFVariantData.as_array(items_value)
	if item_values.size() > ABSOLUTE_MAX_BOOKMARK_COUNT:
		return ERR_INVALID_DATA
	for item_value: Variant in item_values:
		if (
			not item_value is Dictionary
			or not BookmarkData.is_persisted_envelope_copy_boundary_valid(
				GFVariantData.as_dictionary(item_value)
			)
		):
			return ERR_INVALID_DATA
	return OK

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: Dictionary in _items:
		serialized_items.append(item)
	return {
		"items": serialized_items,
	}


func _make_immutable_edit_candidate() -> Dictionary:
	# 已验证 envelope 进入 provider 后永不原地修改；编辑方只取得可重排的
	# 数组根，保存/删除完成后通过 ownership 入口立即放弃所有嵌套别名。
	return {&"items": _items.duplicate()}


func _make_transaction_rollback_data() -> Dictionary:
	# provider 只整体替换 _items；旧根中的规范 envelope 永不原地修改，
	# 因此回滚候选只需冻结数组根，失败时再由严格入口恢复。
	return {&"items": _items.duplicate()}


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
	var item_values: Array = GFVariantData.as_array(items_value)
	if item_values.size() > ABSOLUTE_MAX_BOOKMARK_COUNT:
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
	for item_value: Variant in item_values:
		if not (item_value is Dictionary):
			return ERR_INVALID_DATA
		var item_envelope: Dictionary = GFVariantData.as_dictionary(
			item_value
		)
		var bookmark_id: String = GFVariantData.get_option_string(
			item_envelope,
			"bookmark_id"
		)
		if seen_ids.has(bookmark_id):
			return ERR_INVALID_DATA
		seen_ids[bookmark_id] = true

		var current_value: Variant = current_by_id.get(bookmark_id)
		if current_value is Dictionary and is_same(
			current_value,
			item_envelope
		):
			next_items.append(GFVariantData.as_dictionary(current_value))
			var shared_decoded_value: Variant = (
				_decoded_items_by_id.get(bookmark_id)
			)
			if not shared_decoded_value is BookmarkData:
				return ERR_INVALID_DATA
			next_decoded_items_by_id[bookmark_id] = shared_decoded_value
			continue
		if not BookmarkData.is_persisted_envelope_lightweight_valid(
			item_envelope
		):
			return ERR_INVALID_DATA
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
	if next_items.size() > MAX_BOOKMARK_COUNT:
		var resize_error_code: int = next_items.resize(MAX_BOOKMARK_COUNT)
		if resize_error_code != OK:
			return ERR_OUT_OF_MEMORY
	_items = next_items
	_decoded_items_by_id = next_decoded_items_by_id
	for decoded_id_value: Variant in _decoded_items_by_id.keys():
		var decoded_id: String = GFVariantData.to_text(decoded_id_value)
		var retained: bool = false
		for retained_item: Dictionary in _items:
			if GFVariantData.get_option_string(
				retained_item,
				"bookmark_id"
			) == decoded_id:
				retained = true
				break
		if not retained:
			var _erased_decoded_item: bool = (
				_decoded_items_by_id.erase(decoded_id)
			)
	return OK


# --- 内部类 ---

class _BookmarkCatalogSnapshotOperation extends GFSaveSectionSnapshotOperation:
	var _snapshot_section_id: StringName = &""
	var _snapshot_schema_version: int = 0
	var _source_items: Array[Dictionary] = []
	var _source_index: int = 0
	var _snapshot_items: Array[Dictionary] = []

	func _init(
		snapshot_section_id: StringName,
		snapshot_schema_version: int,
		source_items: Array[Dictionary]
	) -> void:
		_snapshot_section_id = snapshot_section_id
		_snapshot_schema_version = snapshot_schema_version
		_source_items = source_items

	func _advance_snapshot(step_budget: int) -> int:
		var consumed_units: int = 0
		while consumed_units < step_budget and is_pending():
			if _source_index >= _source_items.size():
				_complete_catalog_snapshot()
				break
			# take_ownership() 要求 Snapshot 独占所有嵌套载荷；每个已受
			# 2 MiB 边界保护的 envelope 在独立 work unit 内完成深复制。
			var duplicate_value: Variant = GFVariantData.duplicate_variant(
				_source_items[_source_index],
				true,
				false
			)
			if not duplicate_value is Dictionary:
				var _failed_duplicate: bool = _fail_snapshot(
					ERR_INVALID_DATA,
					"Bookmark snapshot envelope duplication failed."
				)
				break
			_snapshot_items.append(
				GFVariantData.as_dictionary(duplicate_value)
			)
			_source_index += 1
			consumed_units += 1
		return maxi(consumed_units, 1)

	func _cancel_snapshot() -> void:
		_source_items.clear()
		_snapshot_items.clear()

	func _complete_catalog_snapshot() -> void:
		var owned_items: Array[Dictionary] = _snapshot_items
		_snapshot_items = []
		_source_items = []
		var snapshot: GFSaveSectionSnapshot = (
			GFSaveSectionSnapshot.take_ownership(
				_snapshot_section_id,
				_snapshot_schema_version,
				{&"items": owned_items}
			)
		)
		if snapshot == null:
			var _failed: bool = _fail_snapshot(
				ERR_INVALID_DATA,
				"Bookmark catalog snapshot identity is invalid."
			)
			return
		var _completed: bool = _complete_snapshot(snapshot)
