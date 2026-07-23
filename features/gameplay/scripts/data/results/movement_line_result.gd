## MovementLineResult: 单条连续拓扑 lane 的强类型解析结果。
class_name MovementLineResult
extends RefCounted


# --- 公共变量 ---

var line: Array[TileState] = []
var moved: bool = false
var interactions: Array[TileInteractionResult] = []


# --- Godot 生命周期方法 ---

func _init(
	resolved_line: Array[TileState] = [],
	did_move: bool = false,
	resolved_interactions: Array[TileInteractionResult] = []
) -> void:
	line = resolved_line
	moved = did_move
	interactions = resolved_interactions
