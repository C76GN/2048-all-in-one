## Runtime smoke test for GF setup and deterministic gameplay state restore.
extends Node


# --- Constants ---

const CLASSIC_CONFIG_PATH: String = "res://resources/modes/classic_mode_config.tres"
const GRID_SIZE: int = 4
const TEST_SEED: int = 24_681_357
const MOVE_CANDIDATES: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
]


# --- Private Variables ---

var _errors: Array[String] = []


# --- Godot Lifecycle Methods ---

func _ready() -> void:
	_run.call_deferred()


# --- Private Methods ---

func _run() -> void:
	await _setup_runtime()

	_assert(is_instance_valid(Gf.get_utility(GFLevelUtility) as GFLevelUtility), "GFLevelUtility is registered.")
	_assert(is_instance_valid(Gf.get_utility(GFSignalUtility) as GFSignalUtility), "GFSignalUtility is registered.")

	var grid := Gf.get_model(GridModel) as GridModel
	var status := Gf.get_model(GameStatusModel) as GameStatusModel
	var state_system := Gf.get_system(GameStateSystem) as GameStateSystem
	var history := Gf.get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility

	_assert(is_instance_valid(grid), "GridModel is available.")
	_assert(is_instance_valid(status), "GameStatusModel is available.")
	_assert(is_instance_valid(state_system), "GameStateSystem is available.")
	_assert(is_instance_valid(history), "GFCommandHistoryUtility is available.")
	if not _errors.is_empty():
		_finish()
		return

	_assert(status.highest_tile.get_value() == grid.get_max_player_value(), "highest_tile matches initial board.")
	_assert(status.highest_tile.get_value() > 0, "initial board spawned a player tile.")

	await _execute_valid_move(history, MOVE_CANDIDATES)
	await _execute_valid_move(history, MOVE_CANDIDATES)

	var saved_state := state_system.get_full_game_state(GRID_SIZE)
	var replay_direction := await _execute_valid_move(history, MOVE_CANDIDATES)
	var expected_state := state_system.get_full_game_state(GRID_SIZE)

	state_system.restore_state(saved_state)
	await history.execute_command(MoveCommand.new(replay_direction))
	var actual_state := state_system.get_full_game_state(GRID_SIZE)

	_assert(
		JSON.stringify(actual_state) == JSON.stringify(expected_state),
		"restored state remains deterministic after replaying the same move."
	)
	_assert(
		status.highest_tile.get_value() == grid.get_max_player_value(),
		"highest_tile matches board after restore and move."
	)

	_finish()


func _setup_runtime() -> void:
	var architecture := GFArchitecture.new()
	await Gf.set_architecture(architecture)

	var mode_config := load(CLASSIC_CONFIG_PATH) as GameModeConfig
	_assert(is_instance_valid(mode_config), "classic mode config loads.")
	if not is_instance_valid(mode_config):
		return

	var interaction_rule := mode_config.interaction_rule.duplicate() as InteractionRule
	var movement_rule := mode_config.movement_rule.duplicate() as MovementRule
	var game_over_rule := mode_config.game_over_rule.duplicate() as GameOverRule
	var spawn_rules: Array[SpawnRule] = []
	for rule_resource in mode_config.spawn_rules:
		var rule_instance := rule_resource.duplicate() as SpawnRule
		if is_instance_valid(rule_instance):
			spawn_rules.append(rule_instance)

	var seed_utility := Gf.get_utility(GFSeedUtility) as GFSeedUtility
	var grid := Gf.get_model(GridModel) as GridModel
	var status := Gf.get_model(GameStatusModel) as GameStatusModel
	var current_game := Gf.get_model(CurrentGameModel) as CurrentGameModel
	var rule_system := Gf.get_system(RuleSystem) as RuleSystem
	var game_flow := Gf.get_system(GameFlowSystem) as GameFlowSystem
	var history := Gf.get_utility(GFCommandHistoryUtility) as GFCommandHistoryUtility

	_assert(is_instance_valid(seed_utility), "GFSeedUtility is available.")
	_assert(is_instance_valid(grid), "GridModel is available during setup.")
	_assert(is_instance_valid(status), "GameStatusModel is available during setup.")
	_assert(is_instance_valid(current_game), "CurrentGameModel is available during setup.")
	_assert(is_instance_valid(rule_system), "RuleSystem is available during setup.")
	_assert(is_instance_valid(game_flow), "GameFlowSystem is available during setup.")
	if not _errors.is_empty():
		return

	seed_utility.set_global_seed(TEST_SEED)
	grid.initialize(GRID_SIZE, interaction_rule, movement_rule)
	rule_system.register_rules(spawn_rules)
	game_flow.setup(rule_system, game_over_rule)

	status.score.set_value(0)
	status.move_count.set_value(0)
	status.highest_tile.set_value(0)
	status.monsters_killed.set_value(0)
	status.status_message.set_value("")
	status.extra_stats.set_value({})

	current_game.mode_config.set_value(mode_config)
	current_game.current_grid_size.set_value(GRID_SIZE)
	current_game.initial_seed.set_value(TEST_SEED)
	current_game.initial_high_score.set_value(0)
	current_game.is_replay_mode.set_value(false)

	if is_instance_valid(history):
		history.clear()

	game_flow.trigger_initial_rules()


func _execute_valid_move(history: GFCommandHistoryUtility, directions: Array[Vector2i]) -> Vector2i:
	for direction in directions:
		var result: Variant = await history.execute_command(MoveCommand.new(direction))
		if result is MoveData:
			return direction

	_assert(false, "at least one candidate move is valid.")
	return Vector2i.ZERO


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return

	_errors.append(message)
	push_error("[FAIL] %s" % message)


func _finish() -> void:
	if _errors.is_empty():
		print("[PASS] runtime smoke test completed.")
		get_tree().quit(0)
		return

	for error in _errors:
		printerr("[FAIL] %s" % error)
	get_tree().quit(1)
