## BoardAnimationAction: 封装棋盘上方块合并、移动、生成的表现动作。
##
## 棋盘动画是非阻塞表现层：execute() 只启动 Tween 并立即返回，不等待动画完成。
class_name BoardAnimationAction
extends "res://addons/gf/extensions/action_queue/actions/gf_visual_action.gd"


# --- 常量 ---

## 用于防止旧 Tween 回调释放已被复用的 Tile。
const RELEASE_TOKEN_META: StringName = &"_board_animation_release_token"


# --- 私有变量 ---

var _instructions: Array[Dictionary] = []
var _game_board: GameBoardController


# --- Godot 生命周期方法 ---

func _init(instructions: Array, game_board: GameBoardController) -> void:
	for instruction: Variant in instructions:
		if instruction is Dictionary:
			_instructions.append(instruction)
	_game_board = game_board
	var _fire_and_forget_action: GFVisualAction = as_fire_and_forget()


# --- 公共方法 ---

func execute() -> Variant:
	if not is_instance_valid(_game_board) or _instructions.is_empty():
		return null

	for instruction: Dictionary in _instructions:
		var tile: Tile
		var target_pos: Vector2

		match _get_instruction_type(instruction):
			&"MOVE":
				tile = _get_tile(instruction, &"tile")
				
				target_pos = _get_vector2(instruction, &"to_pos", Vector2.ZERO)
				if is_instance_valid(tile):
					var _move_tween: Tween = tile.animate_move(target_pos)
			
			&"MERGE":
				var consumed: Tile = _get_tile(instruction, &"consumed_tile")
				var merged: Tile = _get_tile(instruction, &"merged_tile")
				target_pos = _get_vector2(instruction, &"to_pos", Vector2.ZERO)
				var target_data: Dictionary = _get_dictionary(instruction, &"target_setup_data")

				if is_instance_valid(consumed):
					# 确保被消耗的方块平滑移动到目标点后再消失
					var release_token: RefCounted = RefCounted.new()
					consumed.set_meta(RELEASE_TOKEN_META, release_token)
					var consumed_tween: Tween = consumed.animate_move(target_pos)
					if is_instance_valid(consumed_tween) and consumed_tween.is_valid():
						var _connect_result_58: int = consumed_tween.finished.connect(func() -> void: _release_consumed_tile(consumed, release_token))
					else:
						_release_consumed_tile(consumed, release_token)

				if is_instance_valid(merged):
					# merged 方块可能在同一帧收到了 MOVE 指令（已在上面处理）
					# 如果它的目标位置已经改变，或者尚未开始移动动画，则触发移动。
					# animate_move 内部自带了 is_equal_approx 检查，所以这里直接调用是安全的。
					var _merge_move_tween: Tween = merged.animate_move(target_pos)
					
					if not target_data.is_empty():
						_apply_target_setup_data(merged, target_data)
						var _merge_tween: Tween = merged.animate_merge()
						_play_tile_feedback(merged, &"merge", str(_get_int(target_data, &"value", merged.value)))
						if _get_bool(target_data, &"do_transform", false):
							var _transform_tween: Tween = merged.animate_transform()
							_play_tile_feedback(merged, &"transform")
			
			&"SPAWN":
				var spawn_tile: Tile = _get_tile(instruction, &"tile")
				if is_instance_valid(spawn_tile):
					var _spawn_tween: Tween = spawn_tile.animate_spawn()
					_play_tile_feedback(spawn_tile, &"spawn")

			&"TRANSFORM":
				tile = _get_tile(instruction, &"tile")
				var transform_data: Dictionary = _get_dictionary(instruction, &"target_setup_data")
				if is_instance_valid(tile) and not transform_data.is_empty():
					_apply_target_setup_data(tile, transform_data)
					if _get_bool(transform_data, &"do_merge", false):
						var _merge_tween: Tween = tile.animate_merge()
						_play_tile_feedback(tile, &"merge", str(_get_int(transform_data, &"value", tile.value)))
					if _get_bool(transform_data, &"do_transform", false):
						var _transform_tween: Tween = tile.animate_transform()
						_play_tile_feedback(tile, &"transform")

			_:
				continue

	return null


# --- 私有/辅助方法 ---

func _release_consumed_tile(consumed: Tile, release_token: RefCounted) -> void:
	if not is_instance_valid(consumed):
		return
	if not consumed.has_meta(RELEASE_TOKEN_META):
		return
	if consumed.get_meta(RELEASE_TOKEN_META) != release_token:
		return

	consumed.set_meta(RELEASE_TOKEN_META, 0)
	if is_instance_valid(_game_board):
		_game_board.release_visual_tile(consumed)
		return

	consumed.reset_animation_state()
	consumed.queue_free()


func _play_tile_feedback(tile: Tile, feedback_type: StringName, label_text: String = "") -> void:
	if not is_instance_valid(_game_board):
		return

	_game_board.play_tile_feedback(tile, feedback_type, label_text)


static func _get_instruction_type(instruction: Dictionary) -> StringName:
	var value: Variant = instruction.get(&"type", instruction.get("type", &""))
	if value is StringName:
		return value
	return StringName(str(value))


static func _get_tile(instruction: Dictionary, key: StringName) -> Tile:
	var value: Variant = instruction.get(key, null)
	if value is Tile:
		return value
	return null


static func _get_vector2(instruction: Dictionary, key: StringName, default_value: Vector2) -> Vector2:
	var value: Variant = instruction.get(key, default_value)
	if value is Vector2:
		return value
	return default_value


static func _get_dictionary(instruction: Dictionary, key: StringName) -> Dictionary:
	var value: Variant = instruction.get(key, {})
	if value is Dictionary:
		return value
	return {}


static func _apply_target_setup_data(tile: Tile, target_data: Dictionary) -> void:
	tile.setup(
		_get_int(target_data, &"value", tile.value),
		_get_tile_type(target_data, &"type", tile.type),
		_get_color(target_data, &"bg", Color.WHITE),
		_get_color(target_data, &"font", Color.BLACK)
	)


static func _get_int(data: Dictionary, key: StringName, default_value: int) -> int:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


static func _get_bool(data: Dictionary, key: StringName, default_value: bool) -> bool:
	var value: Variant = data.get(key, data.get(String(key), default_value))
	if value is bool:
		return value
	return default_value


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
