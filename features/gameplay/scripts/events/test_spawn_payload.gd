## TestSpawnPayload: 在测试模式下从测试面板请求生成一个特定的方块。
class_name TestSpawnPayload
extends "res://addons/gf/kernel/base/gf_payload.gd"


# --- 公共变量 ---

## 目标网格坐标。
var grid_pos: Vector2i

## 方块值。
var value: int

## 诊断面板局部生成选项 ID。
var option_id: int


# --- Godot 生命周期方法 ---

func _init(p_grid_pos: Vector2i = Vector2i.ZERO, p_value: int = 2, p_option_id: int = 0) -> void:
	grid_pos = p_grid_pos
	value = p_value
	option_id = p_option_id
