## GameTileData: 方块数据模型，纯数据，不依赖 Node。
class_name GameTileData
extends RefCounted


# --- 公共变量 ---

var value: int = 0
var type: Tile.TileType = Tile.TileType.PLAYER


# --- Godot 生命周期方法 ---

func _init(p_value: int, p_type: Tile.TileType) -> void:
	value = p_value
	type = p_type
