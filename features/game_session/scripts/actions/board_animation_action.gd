## BoardAnimationAction: 封装棋盘上方块合并、移动、生成的表现动作。
##
## 位移与碰撞提交保持队列顺序；方块拥有的生成、脉冲尾效不占用下一输入的准入。
class_name BoardAnimationAction
extends BoardTweenBatchAction


# --- 常量 ---

## 用于防止旧 Tween 回调释放已被复用的 Tile。
const RELEASE_TOKEN_META: StringName = &"_board_animation_release_token"


# --- 私有变量 ---

var _instructions: Array[Dictionary] = []
var _game_board: GameBoardController
var _pending_consumed_tiles: Dictionary = {}
var _pending_merge_impacts: Dictionary = {}
var _turn_result: TurnResult
var _performance_trace_utility: GamePerformanceTraceUtility
var _primary_feedback_attempt_id: int = 0


# --- Godot 生命周期方法 ---

func _init(
	instructions: Array,
	game_board: GameBoardController,
	turn_result: TurnResult = null
) -> void:
	for instruction: Variant in instructions:
		if instruction is Dictionary:
			_instructions.append(instruction)
	_game_board = game_board
	_turn_result = turn_result


# --- 公共方法 ---

## 注入本次动作真正开始表现时的性能轨迹。
##
## 轨迹只承载短期性能观测，不参与领域状态或动画时序。
## @param performance_trace_utility: 接收真实首反馈时刻的强类型 Utility。
## @param attempt_id: 与本次棋盘表现绑定的移动尝试标识。
func configure_primary_feedback_trace(
	performance_trace_utility: GamePerformanceTraceUtility,
	attempt_id: int
) -> void:
	_performance_trace_utility = performance_trace_utility
	_primary_feedback_attempt_id = attempt_id


func execute() -> Variant:
	if not is_instance_valid(_game_board) or _instructions.is_empty():
		return null

	_pending_consumed_tiles.clear()
	_pending_merge_impacts.clear()
	_play_turn_feedback()
	var travel_tweens: Array[Tween] = []
	var visible_feedback_state_committed: bool = false
	for instruction: Dictionary in _instructions:
		match _get_instruction_type(instruction):
			&"MOVE":
				var tile: Tile = _get_tile(instruction, &"tile")
				if is_instance_valid(tile):
					visible_feedback_state_committed = true
					_append_tween(travel_tweens, tile.animate_move(
						_get_vector2(instruction, &"to_pos", Vector2.ZERO),
						_tile_motion_profile, _feedback_budget
					))
			&"MERGE":
				var consumed: Tile = _get_tile(instruction, &"consumed_tile")
				var merged: Tile = _get_tile(instruction, &"merged_tile")
				var target_pos: Vector2 = _get_vector2(instruction, &"to_pos", Vector2.ZERO)
				var consumed_travel: Tween
				if is_instance_valid(consumed):
					visible_feedback_state_committed = true
					var release_token: RefCounted = RefCounted.new()
					consumed.set_meta(RELEASE_TOKEN_META, release_token)
					_pending_consumed_tiles[consumed] = release_token
					consumed_travel = consumed.animate_move(
						target_pos, _tile_motion_profile, _feedback_budget
					)
					if is_instance_valid(consumed_travel) and consumed_travel.is_valid():
						_append_tween(travel_tweens, consumed_travel)
						var _release_connection: int = consumed_travel.finished.connect(
							_release_consumed_tile.bind(consumed, release_token), CONNECT_ONE_SHOT
						)
					else:
						_release_consumed_tile(consumed, release_token)
				if is_instance_valid(merged):
					visible_feedback_state_committed = true
					var merged_travel: Tween = merged.animate_move(
						target_pos, _tile_motion_profile, _feedback_budget
					)
					_append_tween(travel_tweens, merged_travel)
					var target_data: Dictionary = _get_dictionary(instruction, &"target_setup_data")
					if not target_data.is_empty():
						# A stationary survivor still waits for the incoming tile's collision.
						var arrival: Tween = (
							merged_travel
							if is_instance_valid(merged_travel) and merged_travel.is_valid()
							else consumed_travel
						)
						var impact_token: RefCounted = RefCounted.new()
						_pending_merge_impacts[merged] = {
							&"token": impact_token, &"target_data": target_data,
						}
						if is_instance_valid(arrival) and arrival.is_valid():
							var _impact_connection: int = arrival.finished.connect(
								_complete_merge_impact.bind(merged, impact_token), CONNECT_ONE_SHOT
							)
						else:
							_complete_merge_impact(merged, impact_token)
			&"SPAWN":
				var spawn_tile: Tile = _get_tile(instruction, &"tile")
				if is_instance_valid(spawn_tile):
					visible_feedback_state_committed = true
					# The tile owns this short decoration; it does not block the next input.
					var _spawn: Tween = spawn_tile.animate_spawn(_tile_motion_profile, _feedback_budget)
					_play_tile_feedback(spawn_tile, &"spawn")
			&"TRANSFORM":
				var transform_tile: Tile = _get_tile(instruction, &"tile")
				var transform_data: Dictionary = _get_dictionary(instruction, &"target_setup_data")
				if is_instance_valid(transform_tile) and not transform_data.is_empty():
					visible_feedback_state_committed = true
					_apply_target_setup_data(transform_tile, transform_data)
					_play_merge_decorations(transform_tile, transform_data)

	if visible_feedback_state_committed:
		_notify_primary_feedback_state_committed()
	# Only displacement/collision gates FIFO admission. Pulse, spawn and color tails are local.
	return _wait_for_tweens(travel_tweens, _game_board)


func cancel() -> void:
	_pending_merge_impacts.clear()
	_release_all_pending_consumed_tiles()
	super.cancel()
	_defer_visible_region_sync()


func finish() -> void:
	super.finish()
	_release_all_pending_consumed_tiles()
	_defer_visible_region_sync()


# --- 私有/辅助方法 ---

func _notify_primary_feedback_state_committed() -> void:
	var performance_trace_utility: GamePerformanceTraceUtility = (
		_performance_trace_utility
	)
	var attempt_id: int = _primary_feedback_attempt_id
	_performance_trace_utility = null
	_primary_feedback_attempt_id = 0
	if is_instance_valid(performance_trace_utility) and attempt_id > 0:
		performance_trace_utility.mark_primary_feedback_state_committed(attempt_id)

func _release_consumed_tile(consumed: Tile, release_token: RefCounted) -> void:
	if not is_instance_valid(consumed):
		var _invalid_erased: bool = _pending_consumed_tiles.erase(consumed)
		return
	if not consumed.has_meta(RELEASE_TOKEN_META):
		return
	var current_token: Variant = consumed.get_meta(RELEASE_TOKEN_META)
	if not current_token is RefCounted or not is_same(current_token, release_token):
		return

	var _erased: bool = _pending_consumed_tiles.erase(consumed)
	consumed.set_meta(RELEASE_TOKEN_META, 0)
	if is_instance_valid(_game_board):
		_game_board.release_visual_tile(consumed)
		return

	consumed.reset_animation_state()
	consumed.queue_free()


func _release_all_pending_consumed_tiles() -> void:
	var pending_tiles: Array = _pending_consumed_tiles.keys()
	for tile_value: Variant in pending_tiles:
		if not (tile_value is Tile):
			continue
		var tile: Tile = tile_value
		var token_value: Variant = _pending_consumed_tiles.get(tile)
		if token_value is RefCounted:
			var release_token: RefCounted = token_value
			_release_consumed_tile(tile, release_token)
	_pending_consumed_tiles.clear()


func _defer_visible_region_sync() -> void:
	if is_instance_valid(_game_board):
		_game_board.call_deferred(&"sync_visible_region")


static func _append_tween(tweens: Array[Tween], tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_valid() and not tweens.has(tween):
		tweens.append(tween)


func _play_tile_feedback(tile: Tile, feedback_type: StringName, label_text: String = "") -> void:
	if not is_instance_valid(_game_board):
		return

	_game_board.play_tile_feedback(
		tile,
		feedback_type,
		label_text,
		not is_instance_valid(_turn_result)
	)


func _play_turn_feedback() -> void:
	if not is_instance_valid(_game_board) or not is_instance_valid(_turn_result):
		return
	_game_board.play_turn_feedback(_turn_result)


func _complete_merge_impact(tile: Tile, token: RefCounted) -> void:
	var pending: Dictionary = GFVariantData.get_option_dictionary(_pending_merge_impacts, tile)
	var current_token: Variant = pending.get(&"token")
	if not current_token is RefCounted or not is_same(current_token, token) or not is_instance_valid(tile):
		return
	var _erased: bool = _pending_merge_impacts.erase(tile)
	var target_data: Dictionary = _get_dictionary(pending, &"target_data")
	_apply_merge_impact(tile, target_data)
	_play_merge_decorations(tile, target_data)


func _apply_merge_impact(tile: Tile, target_data: Dictionary) -> void:
	if not is_instance_valid(tile):
		return
	# Tile numbers represent committed values; only the local surface pulses at collision.
	_apply_target_setup_data(tile, target_data)
	_play_tile_feedback(tile, &"merge", "")


func _play_merge_decorations(tile: Tile, target_data: Dictionary) -> void:
	if _get_bool(target_data, &"do_merge", true):
		var _merge_pulse: Tween = tile.animate_merge(
			Callable(), 0.0, _tile_motion_profile, _feedback_budget
		)
	if _get_bool(target_data, &"do_transform", false):
		var _transform: Tween = tile.animate_transform(
			Callable(), 0.0, _tile_motion_profile, _feedback_budget
		)


static func _get_instruction_type(instruction: Dictionary) -> StringName:
	return GFVariantData.get_option_string_name(instruction, &"type")


static func _get_tile(instruction: Dictionary, key: StringName) -> Tile:
	var value: Variant = instruction.get(key, null)
	if value is Tile:
		return value
	return null


static func _get_vector2(instruction: Dictionary, key: StringName, default_value: Vector2) -> Vector2:
	return GFVariantData.get_option_vector2(instruction, key, default_value)


static func _get_vector2i(
	instruction: Dictionary,
	key: StringName,
	default_value: Vector2i
) -> Vector2i:
	var value: Variant = instruction.get(key, instruction.get(String(key), default_value))
	if value is Vector2i:
		return value
	if value is Vector2:
		var vector_value: Vector2 = value
		return Vector2i(roundi(vector_value.x), roundi(vector_value.y))
	return default_value


static func _get_dictionary(instruction: Dictionary, key: StringName) -> Dictionary:
	return GFVariantData.get_option_dictionary(instruction, key)


static func _apply_target_setup_data(tile: Tile, target_data: Dictionary) -> void:
	tile.setup(
		_get_int(target_data, &"value", tile.value),
		GFVariantData.get_option_string_name(
			target_data,
			&"definition_id",
			tile.definition_id
		),
		_get_color(target_data, &"bg", Color.WHITE),
		_get_color(target_data, &"font", Color.BLACK),
		GFVariantData.get_option_string_name(target_data, &"visual_family_id"),
		_get_string_name_array(target_data, &"visual_layer_ids"),
		_get_tile_visual_style(target_data, &"visual_style")
	)


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	return GFVariantData.get_option_int(data, key, default_value)


static func _get_bool(data: Dictionary, key: StringName, default_value: bool) -> bool:
	return GFVariantData.get_option_bool(data, key, default_value)


static func _get_string_name_array(data: Dictionary, key: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in GFVariantData.get_option_array(data, key):
		result.append(GFVariantData.to_string_name(value))
	return result


static func _get_color(data: Dictionary, key: StringName, default_value: Color) -> Color:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is Color:
		return value
	return default_value


static func _get_tile_visual_style(
	data: Dictionary,
	key: StringName
) -> TileVisualFamilyStyle:
	var value: Variant = data.get(key, data.get(String(key), null))
	if value is TileVisualFamilyStyle:
		return value
	return null
