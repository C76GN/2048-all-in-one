## TileMovementResult: 单个方块在一次回合中的位移。
class_name TileMovementResult
extends RefCounted


# --- 公共变量 ---

var tile: TileState
var from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO


# --- Godot 生命周期方法 ---

func _init(
	tile_state: TileState = null,
	start_cell: Vector2i = Vector2i.ZERO,
	target_cell: Vector2i = Vector2i.ZERO
) -> void:
	tile = tile_state
	from_cell = start_cell
	to_cell = target_cell


# --- 公共方法 ---

func is_valid_result() -> bool:
	return is_instance_valid(tile) and from_cell != to_cell
