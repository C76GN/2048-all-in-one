## TileDiscoverySystem: 观察方块组合与棋盘拓扑，并持久化最小发现进度。
class_name TileDiscoverySystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 信号 ---

signal tile_discovery_changed(composition_key: String)
signal board_discovery_changed(board_key: String)


# --- 私有变量 ---

var _catalog: TileCatalogUtility = null
var _clock: GameClockUtility = null
var _composition: TileCompositionUtility = null
var _save_graph: GameSaveGraphUtility = null
var _signal_utility: GFSignalUtility = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameClockUtility,
		GameSaveGraphUtility,
		GFSignalUtility,
		TileCatalogUtility,
		TileCompositionUtility,
	]


func ready() -> void:
	_catalog = _resolve_catalog_utility()
	_clock = _resolve_clock_utility()
	_composition = _resolve_composition_utility()
	_save_graph = _resolve_save_graph_utility()
	_signal_utility = _resolve_signal_utility()
	if is_instance_valid(_composition) and is_instance_valid(_signal_utility):
		var _composition_connection: GFSignalConnection = _signal_utility.connect_signal(
			_composition.tile_composition_observed,
			_on_tile_composition_observed,
			self
		)
	register_event(
		GameplayBoardReadyData,
		GFEventListener.from_method(self, &"_on_gameplay_board_ready", 1)
	)


func dispose() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_catalog = null
	_clock = null
	_composition = null
	_save_graph = null
	_signal_utility = null


# --- 公共方法 ---

## 记录一个有效方块组合；仅首次发现或最高值提升时提交 SaveGraph。
## @param tile: 当前有效的方块运行时状态。
func observe_tile(tile: TileState) -> Error:
	if tile == null or not tile.is_valid_state():
		return ERR_INVALID_PARAMETER
	var catalog: TileCatalogUtility = _get_catalog()
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var clock: GameClockUtility = _get_clock()
	if catalog == null or save_graph == null or clock == null:
		return ERR_UNCONFIGURED
	var descriptor: Dictionary = catalog.get_composition_descriptor(
		tile.definition_id,
		tile.capability_recipe_ids
	)
	if descriptor.is_empty():
		return ERR_INVALID_DATA

	var composition_key: String = GFVariantData.get_option_string(
		descriptor,
		&"composition_key"
	)
	var records: Array[TileDiscoveryRecord] = get_tile_discoveries()
	var existing_index: int = _find_tile_record(records, composition_key)
	if existing_index >= 0 and records[existing_index].max_observed_value >= tile.value:
		return OK

	var now: int = maxi(clock.get_unix_timestamp(), 1)
	var next_record: TileDiscoveryRecord = TileDiscoveryRecord.create(
		tile.definition_id,
		tile.capability_recipe_ids,
		now,
		tile.value
	)
	if next_record == null:
		return ERR_INVALID_DATA
	if existing_index >= 0:
		next_record.discovered_at = records[existing_index].discovered_at
		records[existing_index] = next_record
	else:
		records.append(next_record)

	var save_error: Error = _save_discoveries(records, get_board_discoveries())
	if save_error == OK:
		tile_discovery_changed.emit(composition_key)
		_publish_discovery_progress(
			DiscoveryProgressChangedData.KIND_TILE,
			composition_key
		)
	return save_error


## 记录一个稳定棋盘拓扑；同一内容键只提交一次。
## @param topology: 当前对局使用的棋盘拓扑。
func observe_board(topology: BoardTopology) -> Error:
	if not is_instance_valid(topology) or not topology.get_validation_report().is_ok():
		return ERR_INVALID_PARAMETER
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	var clock: GameClockUtility = _get_clock()
	if save_graph == null or clock == null:
		return ERR_UNCONFIGURED
	var board_key: String = topology.get_stable_key()
	var records: Array[BoardDiscoveryRecord] = get_board_discoveries()
	if _find_board_record(records, board_key) >= 0:
		return OK
	var record: BoardDiscoveryRecord = BoardDiscoveryRecord.create(
		topology,
		maxi(clock.get_unix_timestamp(), 1)
	)
	if record == null:
		return ERR_INVALID_DATA
	records.append(record)
	var save_error: Error = _save_discoveries(get_tile_discoveries(), records)
	if save_error == OK:
		board_discovery_changed.emit(board_key)
		_publish_discovery_progress(
			DiscoveryProgressChangedData.KIND_BOARD,
			board_key
		)
	return save_error


## 返回全部严格方块发现记录。
func get_tile_discoveries() -> Array[TileDiscoveryRecord]:
	var result: Array[TileDiscoveryRecord] = []
	var section_data: Dictionary = _get_discovery_section_data()
	for value: Variant in GFVariantData.get_option_array(section_data, "tile_compositions"):
		if not value is Dictionary:
			continue
		var record: TileDiscoveryRecord = TileDiscoveryRecord.from_dict(
			GFVariantData.as_dictionary(value)
		)
		if record != null:
			result.append(record)
	result.sort_custom(_is_tile_key_before)
	return result


## 返回全部严格棋盘发现记录。
func get_board_discoveries() -> Array[BoardDiscoveryRecord]:
	var result: Array[BoardDiscoveryRecord] = []
	var section_data: Dictionary = _get_discovery_section_data()
	for value: Variant in GFVariantData.get_option_array(section_data, "board_topologies"):
		if not value is Dictionary:
			continue
		var record: BoardDiscoveryRecord = BoardDiscoveryRecord.from_dict(
			GFVariantData.as_dictionary(value)
		)
		if record != null:
			result.append(record)
	result.sort_custom(_is_board_key_before)
	return result


## 合并注册定义与玩家进度，生成 UI 可消费的只读图鉴条目。
func get_catalog_entries() -> Array[Dictionary]:
	var catalog: TileCatalogUtility = _get_catalog()
	if catalog == null:
		return []
	var tile_records: Array[TileDiscoveryRecord] = get_tile_discoveries()
	var records_by_key: Dictionary = {}
	for record: TileDiscoveryRecord in tile_records:
		records_by_key[record.composition_key] = record

	var entries_by_key: Dictionary = {}
	var ordered_keys: Array[String] = []
	for definition: TileDefinition in catalog.get_definitions():
		var descriptor: Dictionary = catalog.get_composition_descriptor(
			definition.definition_id,
			definition.initial_recipe_ids
		)
		_append_catalog_entry(descriptor, records_by_key, entries_by_key, ordered_keys)
		for record: TileDiscoveryRecord in tile_records:
			if (
				record.definition_id != definition.definition_id
				or entries_by_key.has(record.composition_key)
			):
				continue
			var discovered_descriptor: Dictionary = catalog.get_composition_descriptor(
				record.definition_id,
				record.recipe_ids
			)
			_append_catalog_entry(
				discovered_descriptor,
				records_by_key,
				entries_by_key,
				ordered_keys
			)

	var result: Array[Dictionary] = []
	for composition_key: String in ordered_keys:
		var value: Variant = entries_by_key.get(composition_key)
		if value is Dictionary:
			var entry: Dictionary = value
			result.append(entry.duplicate(true))
	return result


## @param composition_key: 待查询的稳定组合键。
func is_tile_discovered(composition_key: String) -> bool:
	return _find_tile_record(get_tile_discoveries(), composition_key) >= 0


## 返回图鉴发现进度摘要。
func get_discovery_summary() -> Dictionary:
	var entries: Array[Dictionary] = get_catalog_entries()
	var discovered_count: int = 0
	var max_observed_tile_value: int = 0
	for entry: Dictionary in entries:
		if GFVariantData.get_option_bool(entry, &"discovered"):
			discovered_count += 1
			max_observed_tile_value = maxi(
				max_observed_tile_value,
				GFVariantData.get_option_int(
					GFVariantData.get_option_dictionary(entry, &"discovery"),
					&"max_observed_value",
					0
				)
			)
	return {
		"known_tile_composition_count": entries.size(),
		"discovered_tile_composition_count": discovered_count,
		"discovered_board_count": get_board_discoveries().size(),
		"max_observed_tile_value": max_observed_tile_value,
	}


# --- 私有/辅助方法 ---

func _append_catalog_entry(
	descriptor: Dictionary,
	records_by_key: Dictionary,
	entries_by_key: Dictionary,
	ordered_keys: Array[String]
) -> void:
	if descriptor.is_empty():
		return
	var composition_key: String = GFVariantData.get_option_string(
		descriptor,
		&"composition_key"
	)
	if composition_key.is_empty() or entries_by_key.has(composition_key):
		return
	var entry: Dictionary = descriptor.duplicate(true)
	var record_value: Variant = records_by_key.get(composition_key)
	entry[&"discovered"] = record_value is TileDiscoveryRecord
	var discovery: Dictionary = {}
	if record_value is TileDiscoveryRecord:
		var record: TileDiscoveryRecord = record_value
		discovery = record.to_dict()
	entry[&"discovery"] = discovery
	entries_by_key[composition_key] = entry
	ordered_keys.append(composition_key)


func _save_discoveries(
	tile_records: Array[TileDiscoveryRecord],
	board_records: Array[BoardDiscoveryRecord]
) -> Error:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return ERR_UNCONFIGURED
	var tile_items: Array[Dictionary] = []
	for record: TileDiscoveryRecord in tile_records:
		if record != null:
			tile_items.append(record.to_dict())
	var board_items: Array[Dictionary] = []
	for record: BoardDiscoveryRecord in board_records:
		if record != null:
			board_items.append(record.to_dict())
	return save_graph.queue_section_data(
		GameSaveGraphUtility.DISCOVERIES_SECTION_ID,
		{
			"tile_compositions": tile_items,
			"board_topologies": board_items,
		}
	)


func _get_discovery_section_data() -> Dictionary:
	var save_graph: GameSaveGraphUtility = _get_save_graph()
	if save_graph == null:
		return {}
	return save_graph.get_section_data(GameSaveGraphUtility.DISCOVERIES_SECTION_ID)


func _publish_discovery_progress(changed_kind: StringName, changed_key: String) -> void:
	var summary: Dictionary = get_discovery_summary()
	send_event(DiscoveryProgressChangedData.new(
		changed_kind,
		changed_key,
		GFVariantData.get_option_int(summary, "discovered_tile_composition_count", 0),
		GFVariantData.get_option_int(summary, "discovered_board_count", 0),
		GFVariantData.get_option_int(summary, "max_observed_tile_value", 0)
	))


func _get_catalog() -> TileCatalogUtility:
	if is_instance_valid(_catalog):
		return _catalog
	_catalog = _resolve_catalog_utility()
	return _catalog


func _get_save_graph() -> GameSaveGraphUtility:
	if is_instance_valid(_save_graph):
		return _save_graph
	_save_graph = _resolve_save_graph_utility()
	return _save_graph


func _get_clock() -> GameClockUtility:
	if is_instance_valid(_clock):
		return _clock
	_clock = _resolve_clock_utility()
	return _clock


func _resolve_catalog_utility() -> TileCatalogUtility:
	var value: Object = get_utility(TileCatalogUtility)
	if value is TileCatalogUtility:
		var utility: TileCatalogUtility = value
		return utility
	return null


func _resolve_clock_utility() -> GameClockUtility:
	var value: Object = get_utility(GameClockUtility)
	if value is GameClockUtility:
		var utility: GameClockUtility = value
		return utility
	return null


func _resolve_composition_utility() -> TileCompositionUtility:
	var value: Object = get_utility(TileCompositionUtility)
	if value is TileCompositionUtility:
		var utility: TileCompositionUtility = value
		return utility
	return null


func _resolve_save_graph_utility() -> GameSaveGraphUtility:
	var value: Object = get_utility(GameSaveGraphUtility)
	if value is GameSaveGraphUtility:
		var utility: GameSaveGraphUtility = value
		return utility
	return null


func _resolve_signal_utility() -> GFSignalUtility:
	var value: Object = get_utility(GFSignalUtility)
	if value is GFSignalUtility:
		var utility: GFSignalUtility = value
		return utility
	return null


static func _find_tile_record(records: Array[TileDiscoveryRecord], key: String) -> int:
	for index: int in range(records.size()):
		if records[index].composition_key == key:
			return index
	return -1


static func _find_board_record(records: Array[BoardDiscoveryRecord], key: String) -> int:
	for index: int in range(records.size()):
		if records[index].board_key == key:
			return index
	return -1


static func _is_tile_key_before(left: TileDiscoveryRecord, right: TileDiscoveryRecord) -> bool:
	return left.composition_key < right.composition_key


static func _is_board_key_before(left: BoardDiscoveryRecord, right: BoardDiscoveryRecord) -> bool:
	return left.board_key < right.board_key


# --- 信号处理函数 ---

func _on_tile_composition_observed(tile: TileState) -> void:
	var _observation_error: Error = observe_tile(tile)


func _on_gameplay_board_ready(payload: GameplayBoardReadyData) -> void:
	if (
		payload == null
		or not is_instance_valid(payload.board)
		or not is_instance_valid(payload.board.model)
		or not is_instance_valid(payload.board.model.topology)
	):
		return
	var _observation_error: Error = observe_board(payload.board.model.topology)
