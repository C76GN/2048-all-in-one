## GameFeedbackPerformanceMatrix: 将设置档位解析为可测试的表现预算。
class_name GameFeedbackPerformanceMatrix
extends RefCounted


# --- 公共方法 ---

## 将 VFX 档位和无障碍开关解析为统一硬预算。
## @param state: 当前只读无障碍状态；为空时使用默认完整档。
static func resolve(state: GameAccessibilityState) -> GameFeedbackBudget:
	var effective_state: GameAccessibilityState = (
		state if state != null else GameAccessibilityState.new()
	)
	var budget: GameFeedbackBudget = GameFeedbackBudget.new()
	match effective_state.vfx_quality:
		GameAccessibilityState.VfxQuality.MINIMAL:
			budget.motion_scale = 0.25
			budget.duration_scale = 0.65
			budget.particle_scale = 0.20
			budget.max_edge_fragments = 3
			budget.max_tile_shards = 2
			budget.max_active_bursts = 2
			budget.celebration_particle_count = 0
			budget.background_shader_enabled = false
			budget.celebration_shader_enabled = false
		GameAccessibilityState.VfxQuality.REDUCED:
			budget.motion_scale = 0.70
			budget.duration_scale = 0.85
			budget.particle_scale = 0.55
			budget.max_edge_fragments = 10
			budget.max_tile_shards = 5
			budget.max_active_bursts = 5
			budget.celebration_particle_count = 44
		_:
			pass

	if effective_state.reduced_motion:
		budget.motion_scale = 0.0
		budget.duration_scale = minf(budget.duration_scale, 0.55)
		budget.max_edge_fragments = 0
		budget.max_tile_shards = mini(budget.max_tile_shards, 1)
		budget.celebration_particle_count = 0
		budget.background_shader_enabled = false
		budget.celebration_shader_enabled = false
	if not effective_state.shader_effects_enabled:
		budget.background_shader_enabled = false
		budget.celebration_shader_enabled = false
		budget.celebration_particle_count = 0
	return budget
