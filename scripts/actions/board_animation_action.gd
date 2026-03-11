# scripts/actions/board_animation_action.gd

## BoardAnimationAction: 封装棋盘上方块合并、移动、生成的表现动作。
##
## 该动作将一帧内所有方块动画组合在一起执行。由于使用了 Tween，它会在
## 所有动画结束后完成，通知 GFActionQueueSystem 继续下一个动作。
class_name BoardAnimationAction
extends GFVisualAction


# --- 私有变量 ---

var _instructions: Array
var _game_board: Node


# --- Godot 生命周期方法 ---

func _init(instructions: Array, game_board: Node) -> void:
	_instructions = instructions
	_game_board = game_board


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
					var c_t: Tween = consumed.animate_move(target_pos)
					if c_t and c_t.is_valid():
						c_t.finished.connect(func():
							if is_instance_valid(consumed):
								var pool
								if _game_board.has_method("get_utility"):
									pool = _game_board.get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
								if pool and _game_board.get("TileScene") != null:
									pool.release(consumed, _game_board.TileScene)
									consumed.visible = false
								else:
									consumed.queue_free()
						)
					else:
						var pool
						if _game_board.has_method("get_utility"):
							pool = _game_board.get_utility(GFObjectPoolUtility) as GFObjectPoolUtility
						if pool and _game_board.get("TileScene") != null:
							pool.release(consumed, _game_board.TileScene)
							consumed.visible = false
						else:
							consumed.queue_free()

				if is_instance_valid(merged):
					# merged 方块可能在同一帧收到了 MOVE 指令（已在上面处理）
					# 如果它的目标位置已经改变，或者尚未开始移动动画，则触发移动。
					# animate_move 内部自带了 is_equal_approx 检查，所以这里直接调用是安全的。
					merged.animate_move(target_pos)
					
					if not target_data.is_empty():
						merged.setup(target_data[&"value"], target_data[&"bg"], target_data[&"font"])
						merged.animate_merge()
						if target_data.get(&"do_transform", false):
							merged.animate_transform()
			
			&"SPAWN":
				var spawn_tile: Tile = instruction[&"tile"]
				if is_instance_valid(spawn_tile):
					spawn_tile.animate_spawn()

			_:
				continue

	return null
