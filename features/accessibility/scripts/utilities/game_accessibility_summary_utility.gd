## GameAccessibilitySummaryUtility: 生成并发布唯一的棋盘/回合无障碍语义。
##
## HUD 字幕、复制文本和未来的平台屏幕阅读器适配层都消费同一个
## GameAccessibilitySummary，避免视觉文案与辅助技术描述分别推导后漂移。
class_name GameAccessibilitySummaryUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal summary_published(summary: GameAccessibilitySummary)


# --- 常量 ---

const _DIRECTION_KEYS: Dictionary = {
	Vector2i.LEFT: &"HINT_DIRECTION_LEFT",
	Vector2i.RIGHT: &"HINT_DIRECTION_RIGHT",
	Vector2i.UP: &"HINT_DIRECTION_UP",
	Vector2i.DOWN: &"HINT_DIRECTION_DOWN",
}
const _DIRECTION_FALLBACKS: Dictionary = {
	Vector2i.LEFT: "左",
	Vector2i.RIGHT: "右",
	Vector2i.UP: "上",
	Vector2i.DOWN: "下",
}
const _BOARD_HEADER_FALLBACK: String = (
	"棋盘 %d×%d，%d 个有效格，%d 个方块，最大方块 %d。"
)
const _BOARD_ROW_FALLBACK: String = "第 %d 行：%s。"
const _TURN_FALLBACK: String = (
	"向%s移动：%d 个方块位移，合并 %d 次，生成 %d 个，变化 %d 个，得分 %+d。"
)


# --- 私有变量 ---

var _determinism: GameDeterminismUtility = null
var _platform: GamePlatformUtility = null
var _latest_summary: GameAccessibilitySummary = null
var _sequence: int = 0


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameDeterminismUtility,
		GamePlatformUtility,
	]


func ready() -> void:
	var utility_value: Object = get_utility(GameDeterminismUtility)
	if utility_value is GameDeterminismUtility:
		_determinism = utility_value
	var platform_value: Object = get_utility(GamePlatformUtility)
	if platform_value is GamePlatformUtility:
		_platform = platform_value


func dispose() -> void:
	_determinism = null
	_platform = null
	_latest_summary = null
	_sequence = 0


# --- 公共方法 ---

## 只构建棋盘摘要，不发布信号或修改序号。
## @param board_snapshot: 当前严格棋盘快照。
func build_board_summary(board_snapshot: Dictionary) -> GameAccessibilitySummary:
	var board_payload: Dictionary = _build_board_payload(board_snapshot)
	if board_payload.is_empty():
		return null
	return _compose_summary(
		GameAccessibilitySummary.KIND_BOARD,
		board_payload,
		{},
		0
	)


## 只构建回合摘要，不发布信号或修改序号。
## @param turn_result: 已完成回合的权威结算结果。
## @param board_snapshot: 结算后的当前严格棋盘快照。
func build_turn_summary(
	turn_result: TurnResult,
	board_snapshot: Dictionary
) -> GameAccessibilitySummary:
	if not is_instance_valid(turn_result) or not turn_result.is_effective():
		return null
	var board_payload: Dictionary = _build_board_payload(board_snapshot)
	if board_payload.is_empty():
		return null
	var turn_payload: Dictionary = _build_turn_payload(turn_result)
	if turn_payload.is_empty():
		return null
	return _compose_summary(
		GameAccessibilitySummary.KIND_TURN,
		board_payload,
		turn_payload,
		0
	)


## 构建并发布当前棋盘摘要。
## @param board_snapshot: 当前严格棋盘快照。
func publish_board_summary(board_snapshot: Dictionary) -> GameAccessibilitySummary:
	var summary: GameAccessibilitySummary = build_board_summary(board_snapshot)
	return _publish(summary)


## 构建并发布已完成回合的摘要。
## @param turn_result: 已完成回合的权威结算结果。
## @param board_snapshot: 结算后的当前严格棋盘快照。
func publish_turn_summary(
	turn_result: TurnResult,
	board_snapshot: Dictionary
) -> GameAccessibilitySummary:
	var summary: GameAccessibilitySummary = build_turn_summary(
		turn_result,
		board_snapshot
	)
	return _publish(summary)


func get_latest_summary() -> GameAccessibilitySummary:
	return (
		_latest_summary.duplicate_summary()
		if is_instance_valid(_latest_summary)
		else null
	)


## 把与字幕完全同源的完整棋盘摘要复制到系统剪贴板。
func copy_latest_board_text() -> bool:
	if (
		not is_instance_valid(_latest_summary)
		or _latest_summary.board_text.is_empty()
		or not is_instance_valid(_platform)
	):
		return false
	return _platform.copy_text_to_clipboard(_latest_summary.board_text)


# --- 私有/辅助方法 ---

func _build_board_payload(board_snapshot: Dictionary) -> Dictionary:
	if not GridModel.is_snapshot_envelope_valid(board_snapshot):
		return {}
	var topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(board_snapshot, &"topology")
	)
	if not is_instance_valid(topology):
		return {}
	var tiles_by_cell: Dictionary = {}
	var highest_tile: int = 0
	for tile_value: Variant in GFVariantData.get_option_array(board_snapshot, &"tiles"):
		if not tile_value is Dictionary:
			return {}
		var tile: Dictionary = tile_value
		var position_value: Variant = GFVariantData.get_option_value(tile, &"pos")
		if not position_value is Vector2i:
			return {}
		var position: Vector2i = position_value
		var value: int = GFVariantData.get_option_int(tile, &"value", 0)
		highest_tile = maxi(highest_tile, value)
		tiles_by_cell[position] = {
			&"state": &"tile",
			&"value": value,
			&"definition_id": GFVariantData.get_option_string_name(
				tile,
				&"definition_id"
			),
		}

	var rows: Array[Dictionary] = []
	var bounds_size: Vector2i = topology.get_bounds_size()
	for y: int in range(bounds_size.y):
		var cells: Array[Dictionary] = []
		for x: int in range(bounds_size.x):
			var cell: Vector2i = Vector2i(x, y)
			var cell_payload: Dictionary
			if not topology.contains_cell(cell):
				cell_payload = {&"state": &"inactive"}
			elif tiles_by_cell.has(cell):
				cell_payload = GFVariantData.get_option_dictionary(
					tiles_by_cell,
					cell
				).duplicate(true)
			else:
				cell_payload = {&"state": &"empty"}
			cell_payload[&"x"] = x
			cell_payload[&"y"] = y
			cells.append(cell_payload)
		rows.append({&"row": y, &"cells": cells})

	return {
		&"schema_version": GameAccessibilitySummary.SCHEMA_VERSION,
		&"kind": GameAccessibilitySummary.KIND_BOARD,
		&"board_checksum": _calculate_board_checksum(board_snapshot),
		&"topology_key": topology.get_stable_key(),
		&"width": bounds_size.x,
		&"height": bounds_size.y,
		&"active_cell_count": topology.get_cell_count(),
		&"occupied_tile_count": tiles_by_cell.size(),
		&"highest_tile": highest_tile,
		&"rows": rows,
	}


func _build_turn_payload(turn_result: TurnResult) -> Dictionary:
	var direction_key: StringName = GFVariantData.to_string_name(
		_DIRECTION_KEYS.get(turn_result.direction, &"")
	)
	if direction_key == &"":
		return {}
	var merges: Array[Dictionary] = []
	for merge: TileMergeResult in turn_result.merges:
		if merge == null or not merge.is_valid_result():
			continue
		merges.append({
			&"from_a": merge.consumed_from_cell,
			&"from_b": merge.survivor_from_cell,
			&"to": merge.to_cell,
			&"result_value": merge.interaction.survivor.value,
			&"rule_id": merge.interaction.interaction_rule_id,
		})
	var spawns: Array[Dictionary] = []
	for spawn: TileSpawnResult in turn_result.spawns:
		if spawn == null or not spawn.is_valid_result():
			continue
		spawns.append({
			&"to": spawn.to_cell,
			&"value": spawn.tile.value,
			&"definition_id": spawn.tile.definition_id,
		})
	var transforms: Array[Dictionary] = []
	for transform: TileTransformResult in turn_result.transforms:
		if transform == null or not transform.is_valid_result():
			continue
		transforms.append({
			&"kind": transform.kind,
			&"value": transform.tile.value,
			&"definition_id": transform.tile.definition_id,
		})
	return {
		&"direction": turn_result.direction,
		&"direction_key": direction_key,
		&"movement_count": turn_result.movements.size(),
		&"merge_count": merges.size(),
		&"spawn_count": spawns.size(),
		&"transform_count": transforms.size(),
		&"score_delta": turn_result.score_delta,
		&"max_merge_value": turn_result.max_merge_value,
		&"merges": merges,
		&"spawns": spawns,
		&"transforms": transforms,
	}


func _compose_summary(
	kind: StringName,
	board_payload: Dictionary,
	turn_payload: Dictionary,
	sequence: int
) -> GameAccessibilitySummary:
	var board_text: String = _format_board_text(board_payload)
	if board_text.is_empty():
		return null
	var summary: GameAccessibilitySummary = GameAccessibilitySummary.new()
	summary.sequence = sequence
	summary.kind = kind
	summary.board_checksum = GFVariantData.get_option_string(
		board_payload,
		&"board_checksum"
	)
	summary.board_text = board_text
	summary.canonical_payload = board_payload.duplicate(true)
	if kind == GameAccessibilitySummary.KIND_TURN:
		summary.canonical_payload[&"kind"] = kind
		summary.canonical_payload[&"turn"] = turn_payload.duplicate(true)
		summary.subtitle_text = _format_turn_text(turn_payload)
		summary.announcement_text = "%s %s" % [
			summary.subtitle_text,
			_format_board_header(board_payload),
		]
	else:
		summary.subtitle_text = _format_board_header(board_payload)
		summary.announcement_text = board_text
	return summary if summary.is_valid_summary() else null


func _publish(
	summary: GameAccessibilitySummary
) -> GameAccessibilitySummary:
	if not is_instance_valid(summary):
		return null
	_sequence += 1
	summary.sequence = _sequence
	if not summary.is_valid_summary():
		return null
	_latest_summary = summary.duplicate_summary()
	summary_published.emit(_latest_summary.duplicate_summary())
	return _latest_summary.duplicate_summary()


func _format_board_text(board_payload: Dictionary) -> String:
	var lines: PackedStringArray = [_format_board_header(board_payload)]
	for row_value: Variant in GFVariantData.get_option_array(board_payload, &"rows"):
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var cell_tokens: PackedStringArray = []
		for cell_value: Variant in GFVariantData.get_option_array(row, &"cells"):
			if not cell_value is Dictionary:
				continue
			var cell: Dictionary = cell_value
			match GFVariantData.get_option_string_name(cell, &"state"):
				&"tile":
					var _tile_token_added: bool = cell_tokens.append(
						str(GFVariantData.get_option_int(cell, &"value", 0))
					)
				&"empty":
					var _empty_token_added: bool = cell_tokens.append(
						_translated(&"ACCESSIBILITY_CELL_EMPTY", "空")
					)
				_:
					var _inactive_token_added: bool = cell_tokens.append(
						_translated(&"ACCESSIBILITY_CELL_INACTIVE", "不可用")
					)
		var row_text: String = GameTextFormatUtility.format_template(
			_translated(&"ACCESSIBILITY_BOARD_ROW_FORMAT", _BOARD_ROW_FALLBACK),
			_BOARD_ROW_FALLBACK,
			[
				GFVariantData.get_option_int(row, &"row", 0) + 1,
				"，".join(cell_tokens),
			]
		)
		var _row_added: bool = lines.append(row_text)
	return "\n".join(lines)


func _format_board_header(board_payload: Dictionary) -> String:
	return GameTextFormatUtility.format_template(
		_translated(
			&"ACCESSIBILITY_BOARD_HEADER_FORMAT",
			_BOARD_HEADER_FALLBACK
		),
		_BOARD_HEADER_FALLBACK,
		[
			GFVariantData.get_option_int(board_payload, &"width", 0),
			GFVariantData.get_option_int(board_payload, &"height", 0),
			GFVariantData.get_option_int(
				board_payload,
				&"active_cell_count",
				0
			),
			GFVariantData.get_option_int(
				board_payload,
				&"occupied_tile_count",
				0
			),
			GFVariantData.get_option_int(board_payload, &"highest_tile", 0),
		]
	)


func _format_turn_text(turn_payload: Dictionary) -> String:
	var direction_value: Variant = GFVariantData.get_option_value(
		turn_payload,
		&"direction"
	)
	var direction: Vector2i = (
		direction_value
		if direction_value is Vector2i
		else Vector2i.ZERO
	)
	var direction_fallback: String = GFVariantData.to_text(
		_DIRECTION_FALLBACKS.get(direction, "?")
	)
	var direction_text: String = _translated(
		GFVariantData.get_option_string_name(turn_payload, &"direction_key"),
		direction_fallback
	)
	return GameTextFormatUtility.format_template(
		_translated(&"ACCESSIBILITY_TURN_FORMAT", _TURN_FALLBACK),
		_TURN_FALLBACK,
		[
			direction_text,
			GFVariantData.get_option_int(turn_payload, &"movement_count", 0),
			GFVariantData.get_option_int(turn_payload, &"merge_count", 0),
			GFVariantData.get_option_int(turn_payload, &"spawn_count", 0),
			GFVariantData.get_option_int(turn_payload, &"transform_count", 0),
			GFVariantData.get_option_int(turn_payload, &"score_delta", 0),
		]
	)


func _calculate_board_checksum(board_snapshot: Dictionary) -> String:
	if is_instance_valid(_determinism):
		return _determinism.calculate_board_checksum(board_snapshot)
	var fallback: GameDeterminismUtility = GameDeterminismUtility.new()
	return fallback.calculate_board_checksum(board_snapshot)


func _translated(key: StringName, fallback: String) -> String:
	if key == &"":
		return fallback
	var translated: String = tr(key)
	return fallback if translated == String(key) else translated
