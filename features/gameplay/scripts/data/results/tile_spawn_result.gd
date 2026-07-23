## TileSpawnResult: 一次确定性生成提交后的强类型结果。
class_name TileSpawnResult
extends RefCounted


# --- 公共变量 ---

var tile: TileState
var to_cell: Vector2i = Vector2i.ZERO


# --- Godot 生命周期方法 ---

func _init(tile_state: TileState = null, target_cell: Vector2i = Vector2i.ZERO) -> void:
	tile = tile_state
	to_cell = target_cell


# --- 公共方法 ---

func is_valid_result() -> bool:
	return is_instance_valid(tile)
