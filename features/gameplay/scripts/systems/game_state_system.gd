## GameStateSystem: 负责采集与恢复一局游戏的完整逻辑状态。
class_name GameStateSystem
extends "res://addons/gf/kernel/base/gf_system.gd"


# --- 常量 ---

const _CANONICAL_OPTIONS: Dictionary = {"allow_floats": true}
const STATE_SCHEMA_VERSION: int = 2
const _RNG_STATE_SCHEMA_VERSION: int = 3
const _STATE_FIELD_COUNT: int = 12


# --- 公共方法 ---

func get_required_models() -> Array[Script]:
	return [GameStatusModel, GridModel]


func get_required_systems() -> Array[Script]:
	return [RuleSystem]


func get_required_utilities() -> Array[Script]:
	return [GFSeedUtility]


## 提取完整快照。
## @return: 可用于撤销、书签比较和恢复的完整状态字典。
func get_full_game_state() -> Dictionary:
	var rule_sys: RuleSystem = _get_rule_system()
	var status: GameStatusModel = _get_status_model()
	var grid: GridModel = _get_grid_model()
	var seed_util: GFSeedUtility = _get_seed_utility()
	var highest_tile: int = 0
	var score: int = 0
	var move_count: int = 0
	var ratio_resolutions: int = 0
	var target_tile_value: int = 0
	var target_reached: bool = false
	var extra_stats: Dictionary = {}

	if is_instance_valid(grid):
		highest_tile = grid.get_max_tile_value()

	if is_instance_valid(status):
		score = GFVariantData.to_int(status.score.get_value(), 0)
		move_count = GFVariantData.to_int(status.move_count.get_value(), 0)
		ratio_resolutions = GFVariantData.to_int(status.ratio_resolutions.get_value(), 0)
		target_tile_value = GFVariantData.to_int(status.target_tile_value.get_value(), 0)
		target_reached = GFVariantData.to_bool(status.target_reached.get_value(), false)
		var extra_stats_value: Variant = status.extra_stats.get_value()
		if extra_stats_value is Dictionary:
			var typed_extra_stats: Dictionary = extra_stats_value
			extra_stats = typed_extra_stats.duplicate(true)

	var rules_states: Dictionary = {}
	if is_instance_valid(rule_sys):
		rules_states = RuleSystem.capture_rule_states(rule_sys.get_all_spawn_rules())

	return {
		&"schema_version": STATE_SCHEMA_VERSION,
		&"board_key": grid.get_board_key() if is_instance_valid(grid) else "",
		&"board_snapshot": grid.get_snapshot() if is_instance_valid(grid) else {},
		&"rng_full_state": seed_util.get_full_state() if is_instance_valid(seed_util) else {},
		&"score": score,
		&"move_count": move_count,
		&"highest_tile": highest_tile,
		&"ratio_resolutions": ratio_resolutions,
		&"target_tile_value": target_tile_value,
		&"target_reached": target_reached,
		&"extra_stats": extra_stats,
		&"rules_states": rules_states,
	}


## 在不访问运行时对象的前提下校验完整状态的当前严格 envelope。
## @param state: 待校验的完整游戏状态字典。
static func is_state_envelope_valid(state: Dictionary) -> bool:
	if not (
		state.size() == _STATE_FIELD_COUNT
		and GFVariantData.get_option_value(state, &"schema_version") is int
		and GFVariantData.get_option_value(state, &"board_key") is String
		and GFVariantData.get_option_value(state, &"board_snapshot") is Dictionary
		and GFVariantData.get_option_value(state, &"rng_full_state") is Dictionary
		and GFVariantData.get_option_value(state, &"score") is int
		and GFVariantData.get_option_value(state, &"move_count") is int
		and GFVariantData.get_option_value(state, &"highest_tile") is int
		and GFVariantData.get_option_value(state, &"ratio_resolutions") is int
		and GFVariantData.get_option_value(state, &"target_tile_value") is int
		and GFVariantData.get_option_value(state, &"target_reached") is bool
		and GFVariantData.get_option_value(state, &"extra_stats") is Dictionary
		and GFVariantData.get_option_value(state, &"rules_states") is Dictionary
	):
		return false
	if GFVariantData.get_option_int(state, &"schema_version", 0) != STATE_SCHEMA_VERSION:
		return false

	var board_snapshot: Dictionary = GFVariantData.get_option_dictionary(
		state,
		&"board_snapshot"
	)
	if not GridModel.is_snapshot_envelope_valid(board_snapshot):
		return false
	var topology: BoardTopology = BoardTopology.from_dict(
		GFVariantData.get_option_dictionary(board_snapshot, &"topology")
	)
	if (
		topology == null
		or GFVariantData.get_option_string(state, &"board_key")
		!= topology.get_stable_key()
	):
		return false

	var score: int = GFVariantData.get_option_int(state, &"score", -1)
	var move_count: int = GFVariantData.get_option_int(state, &"move_count", -1)
	var highest_tile: int = GFVariantData.get_option_int(state, &"highest_tile", -1)
	var ratio_resolutions: int = GFVariantData.get_option_int(
		state,
		&"ratio_resolutions",
		-1
	)
	var target_tile_value: int = GFVariantData.get_option_int(
		state,
		&"target_tile_value",
		-1
	)
	if (
		score < 0
		or move_count < 0
		or highest_tile < 0
		or ratio_resolutions < 0
		or target_tile_value < 0
		or highest_tile != _get_snapshot_max_tile_value(board_snapshot)
	):
		return false
	var target_reached: bool = GFVariantData.get_option_bool(
		state,
		&"target_reached",
		false
	)
	if target_tile_value == 0:
		if target_reached:
			return false
	elif highest_tile >= target_tile_value and not target_reached:
		return false

	if not _is_rng_full_state_valid(
		GFVariantData.get_option_dictionary(state, &"rng_full_state")
	):
		return false
	if not _is_rules_state_envelope_valid(
		GFVariantData.get_option_dictionary(state, &"rules_states")
	):
		return false
	return not GFDeterministicVariantSerializer.to_canonical_bytes(
		GFVariantData.get_option_dictionary(state, &"extra_stats"),
		_CANONICAL_OPTIONS
	).is_empty()


## 完整预演一次恢复；不会修改棋盘、统计、RNG 或规则状态。
## @param state_to_restore: 要预演恢复的完整游戏状态。
## @param interaction_rule_override: 可选的交互规则目标；省略时使用当前规则。
## @param rules_override: 可选的生成规则目标；空数组时使用当前规则集合。
func can_restore_state(
	state_to_restore: Dictionary,
	interaction_rule_override: InteractionRule = null,
	rules_override: Array[SpawnRule] = []
) -> bool:
	if not is_state_envelope_valid(state_to_restore):
		return false

	var rule_sys: RuleSystem = _get_rule_system()
	var status: GameStatusModel = _get_status_model()
	var grid: GridModel = _get_grid_model()
	var seed_util: GFSeedUtility = _get_seed_utility()
	if (
		not is_instance_valid(rule_sys)
		or not is_instance_valid(status)
		or not is_instance_valid(grid)
		or not is_instance_valid(seed_util)
	):
		return false

	var rules: Array[SpawnRule] = (
		rules_override
		if not rules_override.is_empty()
		else rule_sys.get_all_spawn_rules()
	)
	if not RuleSystem.are_rule_states_valid(
		GFVariantData.get_option_dictionary(state_to_restore, &"rules_states"),
		rules
	):
		return false
	var restore_interaction_rule: InteractionRule = (
		interaction_rule_override
		if is_instance_valid(interaction_rule_override)
		else grid.interaction_rule
	)
	return grid.can_restore_snapshot(
		GFVariantData.get_option_dictionary(state_to_restore, &"board_snapshot"),
		restore_interaction_rule
	)


## 对比两个完整游戏状态是否等价。
## @param left: 左侧完整游戏状态。
## @param right: 右侧完整游戏状态。
func are_states_equal(left: Dictionary, right: Dictionary) -> bool:
	var left_bytes: PackedByteArray = GFDeterministicVariantSerializer.to_canonical_bytes(
		left,
		_CANONICAL_OPTIONS
	)
	if left_bytes.is_empty():
		return false
	var right_bytes: PackedByteArray = GFDeterministicVariantSerializer.to_canonical_bytes(
		right,
		_CANONICAL_OPTIONS
	)
	return not right_bytes.is_empty() and left_bytes == right_bytes


## 根据快照恢复模型和系统的状态。
## @param state_to_restore: get_full_game_state() 产生的完整游戏状态。
## @remark 该方法只恢复逻辑状态，表现层刷新由调用方决定。
## @return: 所有逻辑状态均已提交时返回 true；失败时保留原状态。
func restore_state(state_to_restore: Dictionary) -> bool:
	if not can_restore_state(state_to_restore):
		return false

	var previous_state: Dictionary = get_full_game_state()
	var rule_sys: RuleSystem = _get_rule_system()
	var status: GameStatusModel = _get_status_model()
	var grid: GridModel = _get_grid_model()
	var seed_util: GFSeedUtility = _get_seed_utility()
	var all_rules: Array[SpawnRule] = rule_sys.get_all_spawn_rules()
	if (
		_apply_validated_state(
			state_to_restore,
			status,
			grid,
			seed_util,
			all_rules
		)
		and are_states_equal(get_full_game_state(), state_to_restore)
	):
		return true

	if is_state_envelope_valid(previous_state):
		var _rolled_back: bool = _apply_validated_state(
			previous_state,
			status,
			grid,
			seed_util,
			all_rules
		)
	return false


# --- 私有/辅助方法 ---

func _apply_validated_state(
	state: Dictionary,
	status: GameStatusModel,
	grid: GridModel,
	seed_util: GFSeedUtility,
	rules: Array[SpawnRule]
) -> bool:
	if not grid.restore_from_snapshot(
		GFVariantData.get_option_dictionary(state, &"board_snapshot")
	):
		return false

	status.score.set_value(GFVariantData.get_option_int(state, &"score", 0))
	status.move_count.set_value(GFVariantData.get_option_int(state, &"move_count", 0))
	status.ratio_resolutions.set_value(
		GFVariantData.get_option_int(state, &"ratio_resolutions", 0)
	)
	status.highest_tile.set_value(GFVariantData.get_option_int(state, &"highest_tile", 0))
	status.set_target_state(
		GFVariantData.get_option_int(state, &"target_tile_value", 0),
		GFVariantData.get_option_bool(state, &"target_reached", false)
	)
	status.extra_stats.set_value(
		GFVariantData.get_option_dictionary(state, &"extra_stats").duplicate(true)
	)
	seed_util.set_full_state(
		GFVariantData.get_option_dictionary(state, &"rng_full_state")
	)
	return RuleSystem.restore_rule_states(
		GFVariantData.get_option_dictionary(state, &"rules_states"),
		rules
	)


static func _is_rules_state_envelope_valid(rules_states: Dictionary) -> bool:
	for state_key: Variant in rules_states.keys():
		if not state_key is String or String(state_key).is_empty():
			return false
		var entry_value: Variant = rules_states[state_key]
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		if not (
			entry.size() == 3
			and GFVariantData.get_option_value(entry, &"rule_state_id") is StringName
			and GFVariantData.get_option_value(entry, &"schema_version") is int
			and entry.has(&"state")
		):
			return false
		if (
			String(GFVariantData.get_option_string_name(entry, &"rule_state_id"))
			!= String(state_key)
			or GFVariantData.get_option_int(entry, &"schema_version", 0) <= 0
		):
			return false
		if GFDeterministicVariantSerializer.to_canonical_bytes(
			{&"state": entry[&"state"]},
			_CANONICAL_OPTIONS
		).is_empty():
			return false
	return true


static func _is_rng_full_state_valid(state: Dictionary) -> bool:
	if not (
		state.size() == 5
		and GFVariantData.get_option_value(state, &"state_schema_version") is int
		and GFVariantData.get_option_value(state, &"global_seed") is String
		and GFVariantData.get_option_value(state, &"rng_state") is String
		and GFVariantData.get_option_value(state, &"branch_counters") is Dictionary
		and GFVariantData.get_option_value(
			state,
			&"deterministic_branch_counters"
		) is Dictionary
	):
		return false
	if (
		GFVariantData.get_option_int(state, &"state_schema_version", 0)
		!= _RNG_STATE_SCHEMA_VERSION
		or not GFVariantData.get_option_string(state, &"global_seed").is_valid_int()
		or not GFVariantData.get_option_string(state, &"rng_state").is_valid_int()
	):
		return false
	return (
		_are_rng_counters_valid(
			GFVariantData.get_option_dictionary(state, &"branch_counters")
		)
		and _are_rng_counters_valid(
			GFVariantData.get_option_dictionary(
				state,
				&"deterministic_branch_counters"
			)
		)
	)


static func _are_rng_counters_valid(counters: Dictionary) -> bool:
	for counter_key: Variant in counters.keys():
		if not counter_key is String:
			return false
		var counter_value: Variant = counters[counter_key]
		if (
			not counter_value is String
			or not String(counter_value).is_valid_int()
			or String(counter_value).begins_with("-")
		):
			return false
	return true


static func _get_snapshot_max_tile_value(board_snapshot: Dictionary) -> int:
	var result: int = 0
	for tile_value: Variant in GFVariantData.get_option_array(board_snapshot, &"tiles"):
		if tile_value is Dictionary:
			result = maxi(
				result,
				GFVariantData.get_option_int(tile_value, &"value", 0)
			)
	return result


func _get_rule_system() -> RuleSystem:
	var system_value: Object = get_system(RuleSystem)
	if system_value is RuleSystem:
		var rule_system: RuleSystem = system_value
		return rule_system
	return null


func _get_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_seed_utility() -> GFSeedUtility:
	var utility_value: Object = get_utility(GFSeedUtility)
	if utility_value is GFSeedUtility:
		var seed_utility: GFSeedUtility = utility_value
		return seed_utility
	return null
