## GameBoardFeedbackUtility: 使用主题配方、无障碍状态和性能预算编排反馈。
class_name GameBoardFeedbackUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 枚举 ---

enum FeedbackTier {
	MOVE,
	MERGE,
	HIGH_MERGE,
	RECORD,
}


# --- 常量 ---

const _SHAKE_CHANNEL: StringName = &"board"
const _HAPTIC_CHANNEL: StringName = &"board"
const _BASE_POSITION_META: StringName = &"feedback_base_position"


# --- 私有变量 ---

var _shake_utility: GFShakeUtility = null
var _haptic_utility: GFHapticUtility = null
var _shader_parameter_utility: GFShaderParameterUtility = null
var _accessibility_utility: GameAccessibilityUtility = null
var _profile: GameBoardFeedbackProfile = null
var _root_tweens: Dictionary = {}
var _background_tweens: Dictionary = {}


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GFShakeUtility,
		GFHapticUtility,
		GFShaderParameterUtility,
		GameAccessibilityUtility,
	]


func ready() -> void:
	_shake_utility = _get_shake_utility()
	_haptic_utility = _get_haptic_utility()
	_shader_parameter_utility = _get_shader_parameter_utility()
	_accessibility_utility = _get_accessibility_utility()


func dispose() -> void:
	_kill_tweens(_root_tweens)
	_kill_tweens(_background_tweens)
	_shake_utility = null
	_haptic_utility = null
	_shader_parameter_utility = null
	_accessibility_utility = null
	_profile = null
# --- 公共方法 ---

## 应用经过完整校验的主题反馈 Profile。
## @param profile: 当前主题拥有的反馈 recipe 集合。
func apply_profile(profile: GameBoardFeedbackProfile) -> bool:
	if profile == null or not profile.get_validation_report().is_ok():
		return false
	_profile = profile
	return true


func get_profile() -> GameBoardFeedbackProfile:
	return _profile


func get_current_budget() -> GameFeedbackBudget:
	return GameFeedbackPerformanceMatrix.resolve(_get_accessibility_state())


## 按合并语义把回合映射到唯一反馈等级。
## @param merge_count: 本回合合并次数。
## @param max_merge_value: 本回合最大合并结果值。
## @param score_delta: 本回合分数增量。
## @param is_record: 是否明确发生实时破纪录事件。
func classify_turn(
	merge_count: int,
	max_merge_value: int,
	score_delta: int,
	is_record: bool = false
) -> FeedbackTier:
	if is_record:
		return FeedbackTier.RECORD
	if merge_count <= 0:
		return FeedbackTier.MOVE
	if merge_count >= 2 or max_merge_value >= 64 or score_delta >= 128:
		return FeedbackTier.HIGH_MERGE
	return FeedbackTier.MERGE


## 播放一次完整回合的棋盘、背景、Shake 与 Haptic 配方。
## @param root: 接收方向冲量的棋盘表现根节点。
## @param canvas: 绘制边缘碎片的反馈画布。
## @param background: 可选的交互背景材质载体。
## @param direction: 当前有效移动方向。
## @param tier: 已分类的回合反馈等级。
## @param board_rect: 棋盘在反馈画布中的边界。
## @param accent_color: 方块或主题提供的附加强调色。
func play_turn_feedback(
	root: Node2D,
	canvas: BoardFeedbackCanvas,
	background: ColorRect,
	direction: Vector2i,
	tier: FeedbackTier,
	board_rect: Rect2,
	accent_color: Color = Color.WHITE
) -> int:
	if (
		not is_instance_valid(root)
		or not root.is_inside_tree()
		or not is_instance_valid(canvas)
		or direction == Vector2i.ZERO
	):
		return 0
	var recipe: GameFeedbackRecipe = _get_turn_recipe(tier)
	if recipe == null:
		return 0
	var state: GameAccessibilityState = _get_accessibility_state()
	var budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(state)
	var direction_vector: Vector2 = Vector2(direction).normalized()
	_play_root_impulse(root, direction_vector, recipe, budget)
	_play_background_impulse(background, direction_vector, recipe, budget)
	_play_turn_shake(recipe, direction, state, budget)
	_play_turn_haptic(recipe, direction, state)
	var fragment_count: int = mini(
		roundi(float(recipe.edge_fragment_count) * budget.particle_scale),
		budget.max_edge_fragments
	)
	var resolved_color: Color = accent_color.lerp(
		recipe.get_color(state.high_contrast_feedback),
		0.48
	)
	return canvas.play_turn_impact(
		board_rect,
		direction_vector,
		int(tier),
		fragment_count,
		resolved_color,
		(recipe.impact_duration + recipe.settle_duration + 0.07) * budget.duration_scale,
		budget.motion_scale
	)


## 播放单方块生成、合并或转化配方。
## @param canvas: 方块反馈画布。
## @param local_position: 反馈在画布内的中心。
## @param feedback_type: `spawn`、`merge` 或 `transform`。
## @param label_text: 可选分数或状态文字。
## @param source_color: 可选的方块来源色。
func play_feedback(
	canvas: BoardFeedbackCanvas,
	local_position: Vector2,
	feedback_type: StringName,
	label_text: String = "",
	source_color: Color = Color.TRANSPARENT
) -> int:
	if not is_instance_valid(canvas) or not canvas.is_inside_tree():
		return 0
	var recipe: GameFeedbackRecipe = _get_tile_recipe(feedback_type)
	if recipe == null:
		return 0
	var state: GameAccessibilityState = _get_accessibility_state()
	var budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(state)
	var shard_count: int = mini(
		roundi(float(recipe.tile_shard_count) * budget.particle_scale),
		budget.max_tile_shards
	)
	return canvas.play_tile_burst(
		local_position,
		feedback_type,
		label_text,
		_resolve_feedback_color(recipe, state, source_color),
		shard_count,
		recipe.tile_burst_duration * budget.duration_scale,
		budget.motion_scale,
		budget.max_active_bursts
	)


# --- 私有/辅助方法 ---

func _play_root_impulse(
	root: Node2D,
	direction: Vector2,
	recipe: GameFeedbackRecipe,
	budget: GameFeedbackBudget
) -> void:
	var root_id: int = root.get_instance_id()
	_kill_tracked_tween(_root_tweens, root_id)
	var base_value: Variant = root.get_meta(_BASE_POSITION_META, root.position)
	var base_position: Vector2 = base_value if base_value is Vector2 else root.position
	if budget.motion_scale <= 0.0:
		root.position = base_position
		root.rotation_degrees = 0.0
		root.scale = Vector2.ONE
		root.skew = 0.0
		return

	var impulse: float = recipe.root_impulse * budget.motion_scale
	var rotation_degrees: float = recipe.root_rotation_degrees * budget.motion_scale
	var rotation_sign: float = _get_rotation_sign(direction)
	var impact_scale: Vector2 = _get_impact_scale(
		direction,
		recipe.root_compression * budget.motion_scale
	)
	var impact_duration: float = maxf(
		recipe.impact_duration * budget.duration_scale,
		0.01
	)
	var settle_duration: float = maxf(
		recipe.settle_duration * budget.duration_scale,
		0.01
	)

	root.position = base_position - direction * impulse
	root.rotation_degrees = -rotation_sign * rotation_degrees
	root.scale = impact_scale
	root.skew = deg_to_rad(rotation_sign * rotation_degrees * 0.22)

	var tween: Tween = root.create_tween()
	var impact_position: PropertyTweener = tween.tween_property(
		root,
		"position",
		base_position + direction * impulse * 0.24,
		impact_duration
	)
	var _impact_position_curve: Tweener = impact_position.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var impact_rotation: PropertyTweener = tween.parallel().tween_property(
		root,
		"rotation_degrees",
		rotation_sign * rotation_degrees * 0.30,
		impact_duration
	)
	var _impact_rotation_curve: Tweener = impact_rotation.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var impact_scale_tween: PropertyTweener = tween.parallel().tween_property(
		root,
		"scale",
		Vector2(2.0 - impact_scale.x, 2.0 - impact_scale.y),
		impact_duration
	)
	var _impact_scale_curve: Tweener = impact_scale_tween.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var impact_skew: PropertyTweener = tween.parallel().tween_property(
		root,
		"skew",
		deg_to_rad(-rotation_sign * rotation_degrees * 0.07),
		impact_duration
	)
	var _impact_skew_curve: Tweener = impact_skew.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	var settle_position: PropertyTweener = tween.chain().tween_property(
		root,
		"position",
		base_position,
		settle_duration
	)
	var _settle_position_curve: Tweener = settle_position.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var settle_rotation: PropertyTweener = tween.parallel().tween_property(
		root,
		"rotation_degrees",
		0.0,
		settle_duration
	)
	var _settle_rotation_curve: Tweener = settle_rotation.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var settle_scale: PropertyTweener = tween.parallel().tween_property(
		root,
		"scale",
		Vector2.ONE,
		settle_duration
	)
	var _settle_scale_curve: Tweener = settle_scale.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var settle_skew: PropertyTweener = tween.parallel().tween_property(
		root,
		"skew",
		0.0,
		settle_duration
	)
	var _settle_skew_curve: Tweener = settle_skew.set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	var _finished_connection: int = tween.finished.connect(
		_clear_tracked_tween.bind(_root_tweens, root_id, tween),
		CONNECT_ONE_SHOT
	)
	_root_tweens[root_id] = tween


func _play_background_impulse(
	background: ColorRect,
	direction: Vector2,
	recipe: GameFeedbackRecipe,
	budget: GameFeedbackBudget
) -> void:
	if not is_instance_valid(background) or not background.is_inside_tree():
		return
	if not background.material is ShaderMaterial:
		return
	var material: ShaderMaterial = background.material
	var background_id: int = background.get_instance_id()
	_kill_tracked_tween(_background_tweens, background_id)
	if not budget.background_shader_enabled:
		material.set_shader_parameter(&"interaction_energy", 0.0)
		material.set_shader_parameter(&"interaction_offset", Vector2.ZERO)
		return

	var energy: float = recipe.background_energy * budget.motion_scale
	var shader_parameters: GFShaderParameterUtility = _get_cached_shader_parameter_utility()
	if is_instance_valid(shader_parameters):
		var _parameter_count: int = shader_parameters.apply_parameters(
			background,
			{
				&"interaction_offset": -direction * 0.018 * energy,
				&"interaction_direction": direction,
				&"interaction_energy": energy,
				&"interaction_phase": 0.0,
			},
			_get_shader_apply_options()
		)

	var duration: float = maxf(recipe.background_duration * budget.duration_scale, 0.01)
	var tween: Tween = background.create_tween()
	var energy_tweener: PropertyTweener = tween.tween_property(
		material,
		"shader_parameter/interaction_energy",
		0.0,
		duration
	)
	var _energy_curve: Tweener = energy_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var offset_tweener: PropertyTweener = tween.parallel().tween_property(
		material,
		"shader_parameter/interaction_offset",
		Vector2.ZERO,
		duration
	)
	var _offset_curve: Tweener = offset_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var phase_tweener: PropertyTweener = tween.parallel().tween_property(
		material,
		"shader_parameter/interaction_phase",
		1.0,
		duration
	)
	var _phase_curve: Tweener = phase_tweener.set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	var _finished_connection: int = tween.finished.connect(
		_clear_tracked_tween.bind(_background_tweens, background_id, tween),
		CONNECT_ONE_SHOT
	)
	_background_tweens[background_id] = tween


func _play_turn_shake(
	recipe: GameFeedbackRecipe,
	direction: Vector2i,
	state: GameAccessibilityState,
	budget: GameFeedbackBudget
) -> void:
	if state.reduced_motion or budget.motion_scale <= 0.0:
		return
	var shake: GFShakeUtility = _get_cached_shake_utility()
	if not is_instance_valid(shake) or recipe.shake_preset == null:
		return
	var _shake_id: int = shake.play_shake(
		_SHAKE_CHANNEL,
		recipe.shake_preset,
		budget.motion_scale,
		{&"feedback_recipe_id": recipe.recipe_id, &"direction": direction}
	)


func _play_turn_haptic(
	recipe: GameFeedbackRecipe,
	direction: Vector2i,
	state: GameAccessibilityState
) -> void:
	if not state.haptics_enabled:
		return
	var haptic: GFHapticUtility = _get_cached_haptic_utility()
	if not is_instance_valid(haptic) or recipe.haptic_preset == null:
		return
	var _stopped_count: int = haptic.stop_channel(_HAPTIC_CHANNEL)
	var _haptic_id: int = haptic.play_haptic(
		_HAPTIC_CHANNEL,
		recipe.haptic_preset,
		-1,
		1.0,
		{&"feedback_recipe_id": recipe.recipe_id, &"direction": direction}
	)


func _resolve_feedback_color(
	recipe: GameFeedbackRecipe,
	state: GameAccessibilityState,
	source_color: Color
) -> Color:
	var semantic_color: Color = recipe.get_color(state.high_contrast_feedback)
	if source_color.a <= 0.0:
		return semantic_color
	var resolved: Color = source_color.lerp(semantic_color, 0.42)
	resolved.a = 1.0
	return resolved


func _get_impact_scale(direction: Vector2, compression: float) -> Vector2:
	var expansion: float = compression * 0.52
	if absf(direction.x) >= absf(direction.y):
		return Vector2(1.0 - compression, 1.0 + expansion)
	return Vector2(1.0 + expansion, 1.0 - compression)


func _get_rotation_sign(direction: Vector2) -> float:
	return -1.0 if direction.x - direction.y * 0.72 < 0.0 else 1.0


func _get_turn_recipe(tier: FeedbackTier) -> GameFeedbackRecipe:
	if _profile == null:
		return null
	return _profile.get_turn_recipe(_get_tier_id(tier))


func _get_tile_recipe(feedback_type: StringName) -> GameFeedbackRecipe:
	return _profile.get_tile_recipe(feedback_type) if _profile != null else null


func _get_tier_id(tier: FeedbackTier) -> StringName:
	match tier:
		FeedbackTier.MERGE:
			return GameBoardFeedbackProfile.TIER_MERGE
		FeedbackTier.HIGH_MERGE:
			return GameBoardFeedbackProfile.TIER_HIGH_MERGE
		FeedbackTier.RECORD:
			return GameBoardFeedbackProfile.TIER_RECORD
		_:
			return GameBoardFeedbackProfile.TIER_MOVE


func _get_accessibility_state() -> GameAccessibilityState:
	if not is_instance_valid(_accessibility_utility):
		_accessibility_utility = _get_accessibility_utility()
	return (
		_accessibility_utility.get_state()
		if is_instance_valid(_accessibility_utility)
		else GameAccessibilityState.new()
	)


func _get_cached_shake_utility() -> GFShakeUtility:
	if not is_instance_valid(_shake_utility):
		_shake_utility = _get_shake_utility()
	return _shake_utility


func _get_cached_haptic_utility() -> GFHapticUtility:
	if not is_instance_valid(_haptic_utility):
		_haptic_utility = _get_haptic_utility()
	return _haptic_utility


func _get_cached_shader_parameter_utility() -> GFShaderParameterUtility:
	if not is_instance_valid(_shader_parameter_utility):
		_shader_parameter_utility = _get_shader_parameter_utility()
	return _shader_parameter_utility


func _get_shake_utility() -> GFShakeUtility:
	var value: Object = get_utility(GFShakeUtility)
	return value if value is GFShakeUtility else null


func _get_haptic_utility() -> GFHapticUtility:
	var value: Object = get_utility(GFHapticUtility)
	return value if value is GFHapticUtility else null


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var value: Object = get_utility(GFShaderParameterUtility)
	return value if value is GFShaderParameterUtility else null


func _get_accessibility_utility() -> GameAccessibilityUtility:
	var value: Object = get_utility(GameAccessibilityUtility)
	return value if value is GameAccessibilityUtility else null


func _get_shader_apply_options() -> Dictionary:
	return {
		"duplicate_material": false,
		"require_declared_parameters": true,
		"warn_on_invalid_target": false,
		"warn_on_missing_parameters": true,
		"copy_values": true,
	}


func _kill_tracked_tween(tweens: Dictionary, target_id: int) -> void:
	var value: Variant = tweens.get(target_id)
	if value is Tween:
		var tween: Tween = value
		if tween.is_valid():
			tween.kill()
	var _erased: bool = tweens.erase(target_id)


func _clear_tracked_tween(
	tweens: Dictionary,
	target_id: int,
	completed_tween: Tween
) -> void:
	if tweens.get(target_id) == completed_tween:
		var _erased: bool = tweens.erase(target_id)


func _kill_tweens(tweens: Dictionary) -> void:
	for value: Variant in tweens.values():
		if value is Tween:
			var tween: Tween = value
			if tween.is_valid():
				tween.kill()
	tweens.clear()
