## TileTransformResult: 棋盘已存在方块的一次重组或强化结果。
class_name TileTransformResult
extends RefCounted


# --- 枚举 ---

enum Kind {
	RECOMPOSE,
	EMPOWER,
}


# --- 公共变量 ---

var tile: TileState
var kind: Kind = Kind.RECOMPOSE


# --- Godot 生命周期方法 ---

func _init(tile_state: TileState = null, transform_kind: Kind = Kind.RECOMPOSE) -> void:
	tile = tile_state
	kind = transform_kind


# --- 公共方法 ---

func is_valid_result() -> bool:
	return is_instance_valid(tile)
