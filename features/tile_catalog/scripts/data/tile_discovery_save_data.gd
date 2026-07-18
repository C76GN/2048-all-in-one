## TileDiscoverySaveData: tile_catalog Feature 的严格 SaveGraph section。
class_name TileDiscoverySaveData
extends GameSaveSectionData


# --- 常量 ---

const SCHEMA_VERSION: int = 1


# --- 私有变量 ---

var _tile_compositions: Array[TileDiscoveryRecord] = []
var _board_topologies: Array[BoardDiscoveryRecord] = []


# --- Godot 生命周期方法 ---

func _init() -> void:
	section_id = GameSaveGraphUtility.DISCOVERIES_SECTION_ID
	schema_version = SCHEMA_VERSION


# --- 可重写钩子 ---

func _gather_section_data() -> Dictionary:
	var tile_compositions: Array[Dictionary] = []
	for record: TileDiscoveryRecord in _tile_compositions:
		if record != null:
			tile_compositions.append(record.to_dict())
	var board_topologies: Array[Dictionary] = []
	for record: BoardDiscoveryRecord in _board_topologies:
		if record != null:
			board_topologies.append(record.to_dict())
	return {
		"tile_compositions": tile_compositions,
		"board_topologies": board_topologies,
	}


func _replace_section_data(data: Dictionary) -> Error:
	if data.size() != 2:
		return ERR_INVALID_DATA
	var tile_value: Variant = GFVariantData.get_option_value(data, "tile_compositions")
	var board_value: Variant = GFVariantData.get_option_value(data, "board_topologies")
	if not tile_value is Array or not board_value is Array:
		return ERR_INVALID_DATA

	var next_tiles: Array[TileDiscoveryRecord] = []
	var tile_keys: Dictionary = {}
	for record_value: Variant in GFVariantData.as_array(tile_value):
		if not record_value is Dictionary:
			return ERR_INVALID_DATA
		var tile_record: TileDiscoveryRecord = TileDiscoveryRecord.from_dict(
			GFVariantData.as_dictionary(record_value)
		)
		if tile_record == null or tile_keys.has(tile_record.composition_key):
			return ERR_INVALID_DATA
		tile_keys[tile_record.composition_key] = true
		next_tiles.append(tile_record)

	var next_boards: Array[BoardDiscoveryRecord] = []
	var board_keys: Dictionary = {}
	for record_value: Variant in GFVariantData.as_array(board_value):
		if not record_value is Dictionary:
			return ERR_INVALID_DATA
		var board_record: BoardDiscoveryRecord = BoardDiscoveryRecord.from_dict(
			GFVariantData.as_dictionary(record_value)
		)
		if board_record == null or board_keys.has(board_record.board_key):
			return ERR_INVALID_DATA
		board_keys[board_record.board_key] = true
		next_boards.append(board_record)

	next_tiles.sort_custom(_is_tile_key_before)
	next_boards.sort_custom(_is_board_key_before)
	_tile_compositions = next_tiles
	_board_topologies = next_boards
	return OK


# --- 私有/辅助方法 ---

static func _is_tile_key_before(left: TileDiscoveryRecord, right: TileDiscoveryRecord) -> bool:
	return left.composition_key < right.composition_key


static func _is_board_key_before(left: BoardDiscoveryRecord, right: BoardDiscoveryRecord) -> bool:
	return left.board_key < right.board_key
