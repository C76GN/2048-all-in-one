## ReplayJumpRequestData: ReplaySystem 发给命令历史执行边界的确定性跳转请求。
class_name ReplayJumpRequestData
extends "res://addons/gf/kernel/base/gf_payload.gd"


# --- 公共变量 ---

var request_id: int = 0
var target_step: int = 0


# --- Godot 生命周期方法 ---

func _init(p_request_id: int = 0, p_target_step: int = 0) -> void:
	request_id = maxi(p_request_id, 0)
	target_step = maxi(p_target_step, 0)
