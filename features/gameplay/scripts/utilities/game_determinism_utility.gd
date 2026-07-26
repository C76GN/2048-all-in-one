## GameDeterminismUtility: 统一规则集指纹与回放语义状态校验。
class_name GameDeterminismUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 私有变量 ---

var _codec: GFStorageCodec = GFStorageCodec.new()


# --- 公共方法 ---

## 计算稳定规则集身份的内容指纹。
## @param mode_config: 已验证且声明规则集 ID/版本的模式资源。
func calculate_ruleset_fingerprint(mode_config: GameModeConfig) -> String:
	if not is_instance_valid(mode_config):
		return ""
	return _checksum({
		&"ruleset_id": String(mode_config.ruleset_id),
		&"ruleset_version": mode_config.ruleset_version,
		&"interaction_rule": _normalize_ruleset_value(mode_config.interaction_rule, {}),
		&"movement_rule": _normalize_ruleset_value(mode_config.movement_rule, {}),
		&"spawn_rules": _normalize_ruleset_value(mode_config.spawn_rules, {}),
		&"game_over_rule": _normalize_ruleset_value(mode_config.game_over_rule, {}),
		&"board_topology_template": _normalize_ruleset_value(
			mode_config.board_topology_template,
			{}
		),
		&"target_tile_value": mode_config.target_tile_value,
	})


## 为一个已结算回合生成可持久化 checkpoint。
## @param step_index: 从 1 开始的有效回合序号。
## @param full_state: 当前完整玩法状态快照。
## @param mode_config: 当前权威模式资源。
## @param turn_result: 可选的当前回合结算结果。
func create_checkpoint(
	step_index: int,
	full_state: Dictionary,
	mode_config: GameModeConfig,
	turn_result: TurnResult = null
) -> ReplayCheckpoint:
	if step_index <= 0 or full_state.is_empty() or not is_instance_valid(mode_config):
		return null
	return create_checkpoint_for_session(
		step_index,
		full_state,
		calculate_ruleset_fingerprint(mode_config),
		turn_result
	)


## 使用对局开始时冻结的规则集指纹生成 checkpoint。
##
## 该入口是运行时热路径：同一份棋盘快照只规范化一次，且不会递归重算规则资源指纹。
## @param step_index: 从 1 开始的有效回合序号。
## @param full_state: 当前完整玩法状态快照。
## @param ruleset_fingerprint: 对局开始时冻结的规则集内容指纹。
## @param turn_result: 可选的当前回合结算结果。
func create_checkpoint_for_session(
	step_index: int,
	full_state: Dictionary,
	ruleset_fingerprint: String,
	turn_result: TurnResult = null
) -> ReplayCheckpoint:
	if (
		step_index <= 0
		or full_state.is_empty()
		or ruleset_fingerprint.is_empty()
	):
		return null
	var board_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		full_state,
		&"board_snapshot"
	)
	var normalized_board: Dictionary = normalize_board_snapshot(board_snapshot)
	if normalized_board.is_empty():
		return null
	var rng_state: Dictionary = GFVariantData.get_option_dictionary(
		full_state,
		&"rng_full_state"
	)
	var result: ReplayCheckpoint = ReplayCheckpoint.new()
	result.step_index = step_index
	result.board_checksum = _checksum(normalized_board)
	result.rng_checksum = _checksum(rng_state)
	result.score = GFVariantData.get_option_int(full_state, &"score", 0)
	result.state_checksum = _calculate_state_checksum_from_normalized(
		full_state,
		ruleset_fingerprint,
		normalized_board
	)
	result.highest_tile = GFVariantData.get_option_int(full_state, &"highest_tile", 0)
	var target_tile_value: int = GFVariantData.get_option_int(
		full_state,
		&"target_tile_value",
		0
	)
	result.target_reached = (
		GFVariantData.get_option_bool(full_state, &"target_reached", false)
		or (
			target_tile_value > 0
			and result.highest_tile >= target_tile_value
		)
	)
	if is_instance_valid(turn_result):
		result.metadata_available = true
		result.merge_count = turn_result.merges.size()
		result.transform_count = turn_result.transforms.size()
		result.ratio_resolution_count = turn_result.ratio_resolution_count
		result.max_merge_value = turn_result.max_merge_value
	return result if result.is_valid_checkpoint() else null


## 计算包含棋盘、玩法 RNG、统计与规则集的完整状态摘要。
## @param full_state: 当前完整玩法状态快照。
## @param mode_config: 当前权威模式资源。
func calculate_state_checksum(
	full_state: Dictionary,
	mode_config: GameModeConfig
) -> String:
	if full_state.is_empty() or not is_instance_valid(mode_config):
		return ""
	return calculate_state_checksum_for_session(
		full_state,
		calculate_ruleset_fingerprint(mode_config)
	)


## 使用对局冻结的规则集指纹计算完整状态摘要。
## @param full_state: 当前完整玩法状态快照。
## @param ruleset_fingerprint: 对局开始时冻结的规则集内容指纹。
func calculate_state_checksum_for_session(
	full_state: Dictionary,
	ruleset_fingerprint: String
) -> String:
	if full_state.is_empty() or ruleset_fingerprint.is_empty():
		return ""
	var normalized_board: Dictionary = normalize_board_snapshot(
		GFVariantData.get_option_dictionary(full_state, &"board_snapshot")
	)
	return _calculate_state_checksum_from_normalized(
		full_state,
		ruleset_fingerprint,
		normalized_board
	)


## 计算排除运行时方块 UUID 的棋盘语义摘要。
## @param board_snapshot: `GridModel` 当前严格快照。
func calculate_board_checksum(board_snapshot: Dictionary) -> String:
	var normalized: Dictionary = normalize_board_snapshot(board_snapshot)
	return _checksum(normalized) if not normalized.is_empty() else ""


## 移除运行时 UUID，只保留决定玩法状态的方块语义，并稳定排序。
## @param board_snapshot: `GridModel` 当前严格快照。
func normalize_board_snapshot(board_snapshot: Dictionary) -> Dictionary:
	if not GridModel.is_snapshot_envelope_valid(board_snapshot):
		return {}
	var semantic_tiles: Array[Dictionary] = []
	for tile_value: Variant in GFVariantData.get_option_array(board_snapshot, &"tiles"):
		if not tile_value is Dictionary:
			return {}
		var tile: Dictionary = tile_value
		var position_value: Variant = GFVariantData.get_option_value(tile, &"pos")
		if not position_value is Vector2i:
			return {}
		var position: Vector2i = position_value
		var recipe_ids: Array[String] = []
		for recipe_value: Variant in GFVariantData.get_option_array(
			tile,
			&"capability_recipe_ids"
		):
			recipe_ids.append(String(GFVariantData.to_string_name(recipe_value)))
		semantic_tiles.append({
			&"x": position.x,
			&"y": position.y,
			&"definition_id": String(
				GFVariantData.get_option_string_name(tile, &"definition_id")
			),
			&"value": GFVariantData.get_option_int(tile, &"value", 0),
			&"capability_recipe_ids": recipe_ids,
			&"capability_state": GFVariantData.get_option_dictionary(
				tile,
				&"capability_state"
			),
		})
	semantic_tiles.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_y: int = GFVariantData.get_option_int(left, &"y", 0)
		var right_y: int = GFVariantData.get_option_int(right, &"y", 0)
		if left_y != right_y:
			return left_y < right_y
		return GFVariantData.get_option_int(left, &"x", 0) < GFVariantData.get_option_int(
			right,
			&"x",
			0
		)
	)
	return {
		&"schema_version": GFVariantData.get_option_int(
			board_snapshot,
			&"schema_version",
			0
		),
		&"topology": GFVariantData.get_option_dictionary(board_snapshot, &"topology"),
		&"tiles": semantic_tiles,
	}


# --- 私有/辅助方法 ---

func _calculate_state_checksum_from_normalized(
	full_state: Dictionary,
	ruleset_fingerprint: String,
	normalized_board: Dictionary
) -> String:
	return _checksum({
		&"ruleset_fingerprint": ruleset_fingerprint,
		&"board": normalized_board,
		&"rng": GFVariantData.get_option_dictionary(full_state, &"rng_full_state"),
		&"score": GFVariantData.get_option_int(full_state, &"score", 0),
		&"move_count": GFVariantData.get_option_int(full_state, &"move_count", 0),
		&"highest_tile": GFVariantData.get_option_int(full_state, &"highest_tile", 0),
		&"ratio_resolutions": GFVariantData.get_option_int(
			full_state,
			&"ratio_resolutions",
			0
		),
		&"target_tile_value": GFVariantData.get_option_int(
			full_state,
			&"target_tile_value",
			0
		),
		&"target_reached": GFVariantData.get_option_bool(
			full_state,
			&"target_reached",
			false
		),
		&"extra_stats": GFVariantData.get_option_dictionary(full_state, &"extra_stats"),
		&"rules_states": GFVariantData.get_option_dictionary(full_state, &"rules_states"),
	})


func _checksum(data: Dictionary) -> String:
	return _codec.calculate_checksum(data, GFStorageCodec.Format.JSON)


func _normalize_ruleset_value(value: Variant, visited_resources: Dictionary) -> Variant:
	if value is Resource:
		var resource: Resource = value
		var instance_id: int = resource.get_instance_id()
		if visited_resources.has(instance_id):
			return {
				&"resource_ref": GFVariantData.get_option_int(
					visited_resources,
					instance_id,
					0
				),
			}

		var reference_index: int = visited_resources.size()
		visited_resources[instance_id] = reference_index
		var properties: Dictionary = {}
		for property_value: Variant in resource.get_property_list():
			if not property_value is Dictionary:
				continue
			var property_info: Dictionary = property_value
			var usage: int = GFVariantData.get_option_int(property_info, &"usage", 0)
			if (usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var property_name: StringName = GFVariantData.get_option_string_name(
				property_info,
				&"name"
			)
			if property_name in [&"script", &"resource_name", &"resource_local_to_scene"]:
				continue
			properties[property_name] = _normalize_ruleset_value(
				resource.get(property_name),
				visited_resources
			)

		var script_path: String = ""
		var script_value: Variant = resource.get_script()
		if script_value is Script:
			var resource_script: Script = script_value
			script_path = resource_script.resource_path
		return {
			&"resource_ref": reference_index,
			&"class": resource.get_class(),
			&"script_path": script_path,
			&"properties": properties,
		}

	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value:
			normalized_array.append(_normalize_ruleset_value(item, visited_resources))
		return normalized_array

	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		var source_dictionary: Dictionary = value
		for key: Variant in source_dictionary:
			normalized_dictionary[key] = _normalize_ruleset_value(
				source_dictionary[key],
				visited_resources
			)
		return normalized_dictionary

	return GFVariantData.duplicate_variant(value, true, false)
