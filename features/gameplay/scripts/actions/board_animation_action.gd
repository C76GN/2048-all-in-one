## BoardAnimationAction: 封装棋盘上方块合并、移动、生成的表现动作。
##
## 同一批棋盘 Tween 并行执行，GFActionQueueSystem 会等待整批完成后再消费下一动作。
class_name BoardAnimationAction
extends BoardTweenBatchAction


# --- 常量 ---

## 用于防止旧 Tween 回调释放已被复用的 Tile。
const RELEASE_TOKEN_META: StringName = &"_board_animation_release_token"


# --- 私有变量 ---

var _instructions: Array[Dictionary] = []
var _game_board: GameBoardController
var _pending_consumed_tiles: Dictionary = {}


# --- Godot 生命周期方法 ---

func _init(instructions: Array, game_board: GameBoardController) -> void:
	for instruction: Variant in instructions:
		if instruction is Dictionary:
			_instructions.append(instruction)
	_game_board = game_board


# --- 公共方法 ---

func execute() -> Variant:
	if not is_instance_valid(_game_board) or _instructions.is_empty():
		return null

	_pending_consumed_tiles.clear()
	var tweens: Array[Tween] = []
	for instruction: Dictionary in _instructions:
		var tile: Tile
		var target_pos: Vector2

		match _get_instruction_type(instruction):
			&"MOVE":
				tile = _get_tile(instruction, &"tile")
				
				target_pos = _get_vector2(instruction, &"to_pos", Vector2.ZERO)
				if is_instance_valid(tile):
					_append_tween(tweens, tile.animate_move(target_pos))
			
			&"MERGE":
				var consumed: Tile = _get_tile(instruction, &"consumed_tile")
				var merged: Tile = _get_tile(instruction, &"merged_tile")
				target_pos = _get_vector2(instruction, &"to_pos", Vector2.ZERO)
				var target_data: Dictionary = _get_dictionary(instruction, &"target_setup_data")

				if is_instance_valid(consumed):
					# 确保被消耗的方块平滑移动到目标点后再消失
					var release_token: RefCounted = RefCounted.new()
					consumed.set_meta(RELEASE_TOKEN_META, release_token)
					_pending_consumed_tiles[consumed] = release_token
					var consumed_tween: Tween = consumed.animate_move(target_pos)
					if is_instance_valid(consumed_tween) and consumed_tween.is_valid():
						_append_tween(tweens, consumed_tween)
						var _release_connected: Error = consumed_tween.finished.connect(
							_release_consumed_tile.bind(consumed, release_token),
							CONNECT_ONE_SHOT as Object.ConnectFlags
						) as Error
					else:
						_release_consumed_tile(consumed, release_token)

				if is_instance_valid(merged):
					# merged 方块可能在同一帧收到了 MOVE 指令（已在上面处理）
					# 如果它的目标位置已经改变，或者尚未开始移动动画，则触发移动。
					# animate_move 内部自带了 is_equal_approx 检查，所以这里直接调用是安全的。
					_append_tween(tweens, merged.animate_move(target_pos))
					
					if not target_data.is_empty():
						_apply_target_setup_data(merged, target_data)
						_append_tween(tweens, merged.animate_merge())
						_play_tile_feedback(merged, &"merge", str(_get_int(target_data, &"value", merged.value)))
						if _get_bool(target_data, &"do_transform", false):
							_append_tween(tweens, merged.animate_transform())
							_play_tile_feedback(merged, &"transform")
			
			&"SPAWN":
				var spawn_tile: Tile = _get_tile(instruction, &"tile")
				if is_instance_valid(spawn_tile):
					_append_tween(tweens, spawn_tile.animate_spawn())
					_play_tile_feedback(spawn_tile, &"spawn")

			&"TRANSFORM":
				tile = _get_tile(instruction, &"tile")
				var transform_data: Dictionary = _get_dictionary(instruction, &"target_setup_data")
				if is_instance_valid(tile) and not transform_data.is_empty():
					_apply_target_setup_data(tile, transform_data)
					if _get_bool(transform_data, &"do_merge", false):
						_append_tween(tweens, tile.animate_merge())
						_play_tile_feedback(tile, &"merge", str(_get_int(transform_data, &"value", tile.value)))
					if _get_bool(transform_data, &"do_transform", false):
						_append_tween(tweens, tile.animate_transform())
						_play_tile_feedback(tile, &"transform")

			_:
				continue

	return wait_for_tweens(tweens, _game_board)


func cancel() -> void:
	super.cancel()
	_release_all_pending_consumed_tiles()


func finish() -> void:
	super.finish()
	_release_all_pending_consumed_tiles()


# --- 私有/辅助方法 ---

func _release_consumed_tile(consumed: Tile, release_token: RefCounted) -> void:
	if not is_instance_valid(consumed):
		var _invalid_erased: bool = _pending_consumed_tiles.erase(consumed)
		return
	if not consumed.has_meta(RELEASE_TOKEN_META):
		return
	if consumed.get_meta(RELEASE_TOKEN_META) != release_token:
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


static func _append_tween(tweens: Array[Tween], tween: Tween) -> void:
	if is_instance_valid(tween) and tween.is_valid() and not tweens.has(tween):
		tweens.append(tween)


func _play_tile_feedback(tile: Tile, feedback_type: StringName, label_text: String = "") -> void:
	if not is_instance_valid(_game_board):
		return

	_game_board.play_tile_feedback(tile, feedback_type, label_text)


static func _get_instruction_type(instruction: Dictionary) -> StringName:
	return GFVariantData.get_option_string_name(instruction, &"type")


static func _get_tile(instruction: Dictionary, key: StringName) -> Tile:
	var value: Variant = instruction.get(key, null)
	if value is Tile:
		return value
	return null


static func _get_vector2(instruction: Dictionary, key: StringName, default_value: Vector2) -> Vector2:
	return GFVariantData.get_option_vector2(instruction, key, default_value)


static func _get_dictionary(instruction: Dictionary, key: StringName) -> Dictionary:
	return GFVariantData.get_option_dictionary(instruction, key)


static func _apply_target_setup_data(tile: Tile, target_data: Dictionary) -> void:
	tile.setup(
		_get_int(target_data, &"value", tile.value),
		_get_tile_type(target_data, &"type", tile.type),
		_get_color(target_data, &"bg", Color.WHITE),
		_get_color(target_data, &"font", Color.BLACK)
	)


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	return GFVariantData.get_option_int(data, key, default_value)


static func _get_bool(data: Dictionary, key: StringName, default_value: bool) -> bool:
	return GFVariantData.get_option_bool(data, key, default_value)


static func _get_tile_type(data: Dictionary, key: StringName, default_value: Tile.TileType) -> Tile.TileType:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is int:
		var enum_value: int = value
		match enum_value:
			Tile.TileType.PLAYER:
				return Tile.TileType.PLAYER
			Tile.TileType.MONSTER:
				return Tile.TileType.MONSTER
	return default_value


static func _get_color(data: Dictionary, key: StringName, default_value: Color) -> Color:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is Color:
		return value
	return default_value
