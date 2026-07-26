## LimitedMoveLevelDefinition: 项目层原创限步关卡的稳定资产定义。
##
## GFLevelCatalog 负责目录、顺序和解锁关系；本资源只负责 2048 关卡规则、
## 初始棋盘和完成条件，避免把项目玩法语义写入 GF Framework。
class_name LimitedMoveLevelDefinition
extends Resource


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const PACK_ID: StringName = &"gameplay.limited_moves"
const PACK_VERSION: int = 1
const LEVEL_ID_PREFIX: String = "level.limited."


# --- 导出变量 ---

@export_group("Identity")
## 关卡稳定 ID，必须以 level.limited. 开头。
@export var level_id: StringName = &""

## 当前原创关卡包的版本。改变关卡语义时必须递增。
@export_range(1, 2147483647, 1) var pack_version: int = PACK_VERSION

## 本地化标题键。
@export var title_key: StringName = &""

## 本地化目标说明键。
@export var description_key: StringName = &""

@export_group("Rules")
## 使用的完整模式配置。
@export_file("*.tres") var mode_config_path: String = ""

## 关卡使用的固定棋盘拓扑。
@export var board_topology: BoardTopology

## 行优先初始棋盘。0 表示空格，正数表示默认 TileDefinition 的方块值。
@export var initial_rows: Array[PackedInt32Array] = []

## 达到该方块值即完成关卡。
@export_range(1, 2147483647, 1) var target_tile_value: int = 2

## 最多允许的有效移动次数。
@export_range(1, 100000, 1) var move_limit: int = 1

## 关卡固定随机种子；即使当前包禁用额外生成，也冻结后续扩展的确定性。
@export_range(1, 2147483647, 1) var fixed_seed: int = 1

## 为 false 时只使用手工棋盘，不执行模式中的 ON_MOVE 生成规则。
@export var spawn_after_move: bool = false


# --- 公共方法 ---

## 加载并返回此关卡绑定的模式配置。
func get_mode_config() -> GameModeConfig:
	if mode_config_path.is_empty() or not ResourceLoader.exists(mode_config_path, "Resource"):
		return null
	var resource: Resource = load(mode_config_path)
	if resource is GameModeConfig:
		return resource
	return null


## 生成可由 GridModel 原子恢复的严格初始棋盘快照。
func build_initial_board_snapshot() -> Dictionary:
	var mode_config: GameModeConfig = get_mode_config()
	if (
		not is_instance_valid(mode_config)
		or not is_instance_valid(board_topology)
		or not get_validation_report().is_ok()
	):
		return {}

	var definition: TileDefinition = mode_config.interaction_rule.get_default_tile_definition()
	if not is_instance_valid(definition):
		return {}

	var tiles: Array[Dictionary] = []
	for cell: Vector2i in board_topology.get_active_cells():
		var value: int = get_initial_value(cell)
		if value <= 0:
			continue
		var tile: TileState = TileState.new(value, definition.definition_id)
		tile.capability_recipe_ids = definition.initial_recipe_ids.duplicate()
		var tile_snapshot: Dictionary = tile.to_dict()
		tile_snapshot[&"pos"] = cell
		tiles.append(tile_snapshot)

	return {
		&"schema_version": GridModel.SNAPSHOT_SCHEMA_VERSION,
		&"topology": board_topology.to_dict(),
		&"tiles": tiles,
	}


## 获取指定棋盘坐标的初始数值；越界返回 0。
func get_initial_value(cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= initial_rows.size():
		return 0
	var row: PackedInt32Array = initial_rows[cell.y]
	if cell.x < 0 or cell.x >= row.size():
		return 0
	return row[cell.x]


## 返回初始棋盘中的方块数量。
func get_initial_tile_count() -> int:
	var count: int = 0
	for row: PackedInt32Array in initial_rows:
		for value: int in row:
			if value > 0:
				count += 1
	return count


## 返回当前剩余有效移动次数。
func get_moves_remaining(move_count: int) -> int:
	return maxi(move_limit - maxi(move_count, 0), 0)


## 判断关卡是否已经完成。
func is_completed(highest_tile: int) -> bool:
	return highest_tile >= target_tile_value


## 判断关卡是否因耗尽步数而失败。
func is_failed(highest_tile: int, move_count: int) -> bool:
	return not is_completed(highest_tile) and move_count >= move_limit


## 生成关卡内容指纹，供回放、结果和存档拒绝静默规则漂移。
func get_content_fingerprint() -> String:
	var row_parts: PackedStringArray = []
	for row: PackedInt32Array in initial_rows:
		var value_parts: PackedStringArray = []
		for value: int in row:
			var _value_added: bool = value_parts.append(str(value))
		var _row_added: bool = row_parts.append(",".join(value_parts))
	var topology_key: String = (
		board_topology.get_stable_key()
		if is_instance_valid(board_topology)
		else ""
	)
	return "|".join([
		str(SCHEMA_VERSION),
		String(level_id),
		String(PACK_ID),
		str(pack_version),
		mode_config_path,
		topology_key,
		str(target_tile_value),
		str(move_limit),
		str(fixed_seed),
		str(spawn_after_move),
		";".join(row_parts),
	]).sha256_text()


## 转换为 GFLevelEntry metadata 使用的稳定项目层字典。
func to_level_data() -> Dictionary:
	return {
		&"kind": &"2048_limited_move_level",
		&"schema_version": SCHEMA_VERSION,
		&"level_id": level_id,
		&"pack_id": PACK_ID,
		&"pack_version": pack_version,
		&"title_key": title_key,
		&"description_key": description_key,
		&"mode_config_path": mode_config_path,
		&"board_key": (
			board_topology.get_stable_key()
			if is_instance_valid(board_topology)
			else ""
		),
		&"target_tile_value": target_tile_value,
		&"move_limit": move_limit,
		&"fixed_seed": fixed_seed,
		&"spawn_after_move": spawn_after_move,
		&"content_fingerprint": get_content_fingerprint(),
	}


## 返回完整 GF 校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"LimitedMoveLevelDefinition:%s" % String(level_id),
		{
			&"level_id": level_id,
			&"resource_path": resource_path,
		}
	)
	_validate_identity(report)
	var mode_config: GameModeConfig = _validate_mode(report)
	_validate_topology_and_rows(report, mode_config)
	_validate_goal(report, mode_config)
	return report


# --- 私有/辅助方法 ---

func _validate_identity(report: GFValidationReport) -> void:
	if level_id == &"" or not String(level_id).begins_with(LEVEL_ID_PREFIX):
		_add_error(
			report,
			&"invalid_level_id",
			"level_id 必须使用 level.limited. 前缀。",
			&"level_id"
		)
	if pack_version != PACK_VERSION:
		_add_error(
			report,
			&"unsupported_pack_version",
			"当前运行时只支持原创限步关卡包版本 %d。" % PACK_VERSION,
			&"pack_version"
		)
	if title_key == &"":
		_add_error(report, &"missing_title_key", "title_key 不能为空。", &"title_key")
	if description_key == &"":
		_add_error(
			report,
			&"missing_description_key",
			"description_key 不能为空。",
			&"description_key"
		)
	if fixed_seed <= 0:
		_add_error(report, &"invalid_fixed_seed", "fixed_seed 必须大于 0。", &"fixed_seed")


func _validate_mode(report: GFValidationReport) -> GameModeConfig:
	var mode_config: GameModeConfig = get_mode_config()
	if not is_instance_valid(mode_config):
		_add_error(
			report,
			&"invalid_mode_config",
			"mode_config_path 必须指向有效 GameModeConfig。",
			&"mode_config_path"
		)
		return null
	if not mode_config.get_validation_report().is_ok():
		_add_error(
			report,
			&"invalid_mode_contract",
			"关卡引用的 GameModeConfig 校验失败。",
			&"mode_config_path"
		)
	return mode_config


func _validate_topology_and_rows(
	report: GFValidationReport,
	mode_config: GameModeConfig
) -> void:
	if (
		not is_instance_valid(board_topology)
		or not board_topology.get_validation_report().is_ok()
	):
		_add_error(
			report,
			&"invalid_board_topology",
			"board_topology 必须是有效的规范化拓扑。",
			&"board_topology"
		)
		return

	var bounds_size: Vector2i = board_topology.get_bounds_size()
	if initial_rows.size() != bounds_size.y:
		_add_error(
			report,
			&"invalid_row_count",
			"initial_rows 行数必须等于棋盘高度 %d。" % bounds_size.y,
			&"initial_rows"
		)
		return

	var allowed_values: Array[int] = _get_allowed_values(mode_config)
	var occupied_count: int = 0
	var max_initial_value: int = 0
	for y: int in range(initial_rows.size()):
		var row: PackedInt32Array = initial_rows[y]
		if row.size() != bounds_size.x:
			_add_error(
				report,
				&"invalid_column_count",
				"initial_rows[%d] 列数必须等于棋盘宽度 %d。" % [y, bounds_size.x],
				y
			)
			continue
		for x: int in range(row.size()):
			var cell: Vector2i = Vector2i(x, y)
			var value: int = row[x]
			if not board_topology.contains_cell(cell):
				if value != 0:
					_add_error(
						report,
						&"tile_on_inactive_cell",
						"非活跃单元 %s 必须保持为 0。" % cell,
						cell
					)
				continue
			if value < 0:
				_add_error(
					report,
					&"negative_tile_value",
					"初始方块值不能为负数：%s。" % cell,
					cell
				)
			elif value > 0:
				occupied_count += 1
				max_initial_value = maxi(max_initial_value, value)
				if not allowed_values.is_empty() and not allowed_values.has(value):
					_add_error(
						report,
						&"unsupported_tile_value",
						"初始方块值 %d 不属于当前模式默认定义。" % value,
						cell
					)

	if occupied_count <= 0:
		_add_error(
			report,
			&"empty_initial_board",
			"初始棋盘至少需要一个方块。",
			&"initial_rows"
		)
	if occupied_count >= board_topology.get_cell_count() and not _has_adjacent_equal_pair():
		_add_error(
			report,
			&"initial_board_has_no_move",
			"满棋盘初始状态必须至少包含一组相邻相同方块。",
			&"initial_rows"
		)
	if max_initial_value >= target_tile_value:
		_add_error(
			report,
			&"goal_already_completed",
			"目标方块必须高于初始棋盘最大值。",
			&"target_tile_value"
		)


func _validate_goal(report: GFValidationReport, mode_config: GameModeConfig) -> void:
	if target_tile_value <= 1:
		_add_error(
			report,
			&"invalid_target_tile_value",
			"target_tile_value 必须大于 1。",
			&"target_tile_value"
		)
	var allowed_values: Array[int] = _get_allowed_values(mode_config)
	if not allowed_values.is_empty() and not allowed_values.has(target_tile_value):
		_add_error(
			report,
			&"unsupported_target_tile_value",
			"目标方块不属于当前模式默认定义。",
			&"target_tile_value"
		)
	if move_limit <= 0:
		_add_error(report, &"invalid_move_limit", "move_limit 必须大于 0。", &"move_limit")


func _get_allowed_values(mode_config: GameModeConfig) -> Array[int]:
	if (
		not is_instance_valid(mode_config)
		or not is_instance_valid(mode_config.interaction_rule)
	):
		return []
	var definition: TileDefinition = mode_config.interaction_rule.get_default_tile_definition()
	if not is_instance_valid(definition):
		return []
	var definition_index: int = mode_config.interaction_rule.tile_definitions.find(definition)
	if definition_index < 0:
		return []
	return mode_config.interaction_rule.get_spawnable_values(definition_index)


func _has_adjacent_equal_pair() -> bool:
	if not is_instance_valid(board_topology):
		return false
	for cell: Vector2i in board_topology.get_active_cells():
		var value: int = get_initial_value(cell)
		if value <= 0:
			continue
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + direction
			if board_topology.contains_cell(neighbor) and get_initial_value(neighbor) == value:
				return true
	return false


func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
