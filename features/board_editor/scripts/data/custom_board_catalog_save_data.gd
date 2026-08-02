## CustomBoardCatalogSaveData: board_editor Feature 的严格 GFSaveProfile section。
class_name CustomBoardCatalogSaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const MAX_CUSTOM_BOARD_COUNT: int = 32
## 合法棋盘 envelope 至少占 18 个 GFStorage Variant；50,000 覆盖当前
## 1,000,000-value 物理文档预算内的全部旧目录，并隔离绕过 Storage 的异常输入。
const ABSOLUTE_MAX_CUSTOM_BOARD_COUNT: int = 50_000


# --- 私有变量 ---

var _items: Array[CustomBoardData] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.CUSTOM_BOARDS_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _begin_save_snapshot(
	_context: Dictionary = {}
) -> GFSaveSectionSnapshotOperation:
	return _CustomBoardCatalogSnapshotOperation.new(
		section_id,
		schema_version,
		_items.duplicate()
	)


func _validate_section_data_boundary(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, &"items")
	if not items_value is Array:
		return ERR_INVALID_DATA
	var item_values: Array = GFVariantData.as_array(items_value)
	if item_values.size() > ABSOLUTE_MAX_CUSTOM_BOARD_COUNT:
		return ERR_INVALID_DATA
	for item_value: Variant in item_values:
		if (
			not item_value is Dictionary
			or not CustomBoardData.is_persisted_envelope_copy_boundary_valid(
				GFVariantData.as_dictionary(item_value)
			)
		):
			return ERR_INVALID_DATA
	return OK

func _gather_section_data() -> Dictionary:
	var serialized_items: Array[Dictionary] = []
	for item: CustomBoardData in _items:
		if item != null:
			serialized_items.append(item.to_dict())
	return {
		"items": serialized_items,
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 1:
		return ERR_INVALID_DATA
	var items_value: Variant = GFVariantData.get_option_value(data, "items")
	if not items_value is Array:
		return ERR_INVALID_DATA
	var item_values: Array = GFVariantData.as_array(items_value)
	if item_values.size() > ABSOLUTE_MAX_CUSTOM_BOARD_COUNT:
		return ERR_INVALID_DATA

	var next_items: Array[CustomBoardData] = []
	var seen_ids: Dictionary = {}
	for item_value: Variant in item_values:
		if not item_value is Dictionary:
			return ERR_INVALID_DATA
		var item: CustomBoardData = CustomBoardData.from_dict(GFVariantData.as_dictionary(item_value))
		if item == null or seen_ids.has(item.custom_board_id):
			return ERR_INVALID_DATA
		seen_ids[item.custom_board_id] = true
		next_items.append(item)

	next_items.sort_custom(_is_newer_board)
	if next_items.size() > MAX_CUSTOM_BOARD_COUNT:
		var resize_error_code: int = next_items.resize(MAX_CUSTOM_BOARD_COUNT)
		if resize_error_code != OK:
			return ERR_OUT_OF_MEMORY
	_items = next_items
	return OK


# --- 私有/辅助方法 ---

static func _is_newer_board(left: CustomBoardData, right: CustomBoardData) -> bool:
	if left.updated_at != right.updated_at:
		return left.updated_at > right.updated_at
	return left.custom_board_id > right.custom_board_id


# --- 内部类 ---

class _CustomBoardCatalogSnapshotOperation extends GFSaveSectionSnapshotOperation:
	var _snapshot_section_id: StringName = &""
	var _snapshot_schema_version: int = 0
	var _source_items: Array[CustomBoardData] = []
	var _source_index: int = 0
	var _snapshot_items: Array[Dictionary] = []

	func _init(
		snapshot_section_id: StringName,
		snapshot_schema_version: int,
		source_items: Array[CustomBoardData]
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
			var item: CustomBoardData = _source_items[_source_index]
			_source_index += 1
			if item != null:
				_snapshot_items.append(item.to_dict())
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
				"Custom board catalog snapshot identity is invalid."
			)
			return
		var _completed: bool = _complete_snapshot(snapshot)
