## GameFeedbackBudget: 一个 VFX 性能档位解析后的硬预算。
class_name GameFeedbackBudget
extends RefCounted


# --- 公共变量 ---

var motion_scale: float = 1.0
var duration_scale: float = 1.0
var particle_scale: float = 1.0
var max_edge_fragments: int = 18
var max_tile_shards: int = 8
var max_active_bursts: int = 8
var celebration_particle_count: int = 88
var background_shader_enabled: bool = true
var celebration_shader_enabled: bool = true


# --- 公共方法 ---

func is_valid_budget() -> bool:
	return (
		motion_scale >= 0.0
		and duration_scale > 0.0
		and particle_scale >= 0.0
		and max_edge_fragments >= 0
		and max_tile_shards >= 0
		and max_active_bursts > 0
		and celebration_particle_count >= 0
	)
