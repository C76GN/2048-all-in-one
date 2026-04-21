# scripts/actions/board_animation_action.gd

## BoardAnimationAction: 封装棋盘上方块合并、移动、生成的表现动作。
##
## 棋盘动画是非阻塞表现层：execute() 只启动 Tween 并立即返回，不等待动画完成。
class_name BoardAnimationAction
extends GFVisualAction


# --- 常量 ---

## 用于防止旧 Tween 回调释放已被复用的 Tile。
const RELEASE_TOKEN_META: StringName = &"_board_animation_release_token"


# --- 私有变量 ---

var _instructions: Array
var _game_board: Node


# --- Godot 生命周期方法 ---

func _init(instructions: Array, game_board: Node) -> void:
	_instructions = instructions
	_game_board = game_board
	as_fire_and_forget()


# --- 公共方法 ---

func execute() -> Variant:
	if not is_instance_valid(_game_board) or _instructions.is_empty():
		return null

	for instruction in _instructions:
		var tile: Tile
		var target_pos: Vector2

		match instruction[&"type"]:
			&"MOVE":
				tile = instruction[&"tile"]
				
				target_pos = instruction[&"to_pos"]
				if is_instance_valid(tile):
					tile.animate_move(target_pos)
			
			&"MERGE":
				var consumed: Tile = instruction[&"consumed_tile"]
				var merged: Tile = instruction[&"merged_tile"]
				target_pos = instruction[&"to_pos"]
				var target_data: Dictionary = instruction.get(&"target_setup_data", {})

				if is_instance_valid(consumed):
					# 确保被消耗的方块平滑移动到目标点后再消失
					var release_token := RefCounted.new()
					consumed.set_meta(RELEASE_TOKEN_META, release_token)
					var consumed_tween: Tween = consumed.animate_move(target_pos)
					if consumed_tween and consumed_tween.is_valid():
						consumed_tween.finished.connect(func(): _release_consumed_tile(consumed, release_token))
					else:
						_release_consumed_tile(consumed, release_token)

				if is_instance_valid(merged):
					# merged 方块可能在同一帧收到了 MOVE 指令（已在上面处理）
					# 如果它的目标位置已经改变，或者尚未开始移动动画，则触发移动。
					# animate_move 内部自带了 is_equal_approx 检查，所以这里直接调用是安全的。
					merged.animate_move(target_pos)
					
					if not target_data.is_empty():
						merged.setup(target_data[&"value"], target_data.get(&"type", merged.type), target_data[&"bg"], target_data[&"font"])
						merged.animate_merge()
						if target_data.get(&"do_transform", false):
							merged.animate_transform()
			
			&"SPAWN":
				var spawn_tile: Tile = instruction[&"tile"]
				if is_instance_valid(spawn_tile):
					spawn_tile.animate_spawn()

			&"TRANSFORM":
				tile = instruction[&"tile"]
				var transform_data: Dictionary = instruction.get(&"target_setup_data", {})
				if is_instance_valid(tile) and not transform_data.is_empty():
					tile.setup(transform_data[&"value"], transform_data.get(&"type", tile.type), transform_data[&"bg"], transform_data[&"font"])
					if transform_data.get(&"do_merge", false):
						tile.animate_merge()
					if transform_data.get(&"do_transform", false):
						tile.animate_transform()

			_:
				continue

	return null


func _release_consumed_tile(consumed: Tile, release_token: RefCounted) -> void:
	if not is_instance_valid(consumed):
		return
	if consumed.get_meta(RELEASE_TOKEN_META, "") != release_token:
		return

	consumed.set_meta(RELEASE_TOKEN_META, 0)
	if _game_board.has_method(&"release_visual_tile"):
		_game_board.release_visual_tile(consumed)
	else:
		consumed.reset_animation_state()
		consumed.queue_free()
