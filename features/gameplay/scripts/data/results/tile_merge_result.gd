## TileMergeResult: 一次交互在棋盘坐标中的强类型合并结果。
class_name TileMergeResult
extends RefCounted


# --- 公共变量 ---

var interaction: TileInteractionResult
var consumed_from_cell: Vector2i = Vector2i.ZERO
var survivor_from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO


# --- 公共方法 ---

func is_valid_result() -> bool:
	return is_instance_valid(interaction) and interaction.is_valid_result()
