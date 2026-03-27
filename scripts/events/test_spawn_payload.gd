# scripts/events/test_spawn_payload.gd

## TestSpawnPayload: 在测试模式下从测试面板请求生成一个特定的方块。
class_name TestSpawnPayload
extends GFPayload

## 目标网格坐标。
var grid_pos: Vector2i

## 方块值。
var value: int

## 方块类型的整数ID。
var type_id: int


func _init(p_grid_pos: Vector2i = Vector2i.ZERO, p_value: int = 2, p_type_id: int = 0) -> void:
	grid_pos = p_grid_pos
	value = p_value
	type_id = p_type_id
