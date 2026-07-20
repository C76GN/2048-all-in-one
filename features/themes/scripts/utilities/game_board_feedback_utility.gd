## GameBoardFeedbackUtility: 编排方块、棋盘与背景的统一操作反馈。
##
## 表现数据交给常驻 BoardFeedbackCanvas 批量绘制；本 Utility 只负责编排 GF 震动、
## GF 触觉、棋盘方向形变和主题背景 uniform，避免在每次操作时构建临时场景节点。
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

const _MERGE_COLOR: Color = Color(0.8745098, 0.6901961, 0.3019608, 1.0)
const _SPAWN_COLOR: Color = Color(0.36078432, 0.7176471, 0.7254902, 1.0)
const _TRANSFORM_COLOR: Color = Color(0.827451, 0.38431373, 0.29411766, 1.0)
const _DEFAULT_COLOR: Color = Color(0.19215687, 0.2, 0.21568628, 1.0)
const _SHAKE_CHANNEL: StringName = &"board"
const _HAPTIC_CHANNEL: StringName = &"board"
const _BASE_POSITION_META: StringName = &"feedback_base_position"


# --- 私有变量 ---

var _shake_utility: GFShakeUtility = null
var _haptic_utility: GFHapticUtility = null
var _shader_parameter_utility: GFShaderParameterUtility = null
var _profile: GameBoardFeedbackProfile = null
var _root_tweens: Dictionary = {}
var _background_tweens: Dictionary = {}


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFShakeUtility, GFHapticUtility, GFShaderParameterUtility]


func ready() -> void:
	_shake_utility = _get_shake_utility()
	_haptic_utility = _get_haptic_utility()
	_shader_parameter_utility = _get_shader_parameter_utility()


func dispose() -> void:
	_kill_tweens(_root_tweens)
	_kill_tweens(_background_tweens)
	_shake_utility = null
	_haptic_utility = null
	_shader_parameter_utility = null
	_profile = null


# --- 公共方法 ---

## 应用当前视觉主题提供的棋盘反馈 Profile。
## @param profile: 已通过资源校验的主题反馈 Profile。
func apply_profile(profile: GameBoardFeedbackProfile) -> bool:
	if profile == null or not profile.get_validation_report().is_ok():
		return false
	_profile = profile
	return true


func get_profile() -> GameBoardFeedbackProfile:
	return _profile

## 根据一次有效操作的结果返回稳定反馈等级。
## @param merge_count: 本回合发生的合并次数。
## @param max_merge_value: 本回合生成的最大合并值。
## @param score_delta: 本回合增加的分数。
## @param is_record: 本回合是否打破记录。
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


## 播放一次有效移动对应的整屏反馈，返回常驻画布绘制的边缘碎片数。
## @param root: 承载棋盘视觉的根节点。
## @param canvas: 常驻批量反馈画布。
## @param background: 可接收交互 uniform 的主题背景。
## @param direction: 本次有效移动方向。
## @param tier: 已归类的反馈强度。
## @param board_rect: 棋盘在反馈画布本地坐标中的边界。
## @param accent_color: 当前主题提供的强调色。
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

	var direction_vector: Vector2 = Vector2(direction).normalized()
	_play_root_impulse(root, direction_vector, tier)
	_play_background_impulse(background, direction_vector, tier)
	_play_turn_shake(tier, direction)
	_play_turn_haptic(tier, direction)
	return canvas.play_turn_impact(
		board_rect,
		direction_vector,
		int(tier),
		_get_edge_fragment_count(tier),
		accent_color
	)


## 在常驻画布中播放单个方块反馈，不改变场景树结构。
## @param canvas: 常驻批量反馈画布。
## @param local_position: 方块中心在反馈画布中的本地坐标。
## @param feedback_type: `spawn`、`merge` 或 `transform` 反馈类型。
## @param label_text: 可选分数或状态文本。
## @param source_color: 当前方块底色；透明时使用反馈类型默认色。
func play_feedback(
	canvas: BoardFeedbackCanvas,
	local_position: Vector2,
	feedback_type: StringName,
	label_text: String = "",
	source_color: Color = Color.TRANSPARENT
) -> int:
	if not is_instance_valid(canvas) or not canvas.is_inside_tree():
		return 0
	return canvas.play_tile_burst(
		local_position,
		feedback_type,
		label_text,
		_resolve_feedback_color(feedback_type, source_color)
	)


# --- 私有/辅助方法 ---

func _play_root_impulse(root: Node2D, direction: Vector2, tier: FeedbackTier) -> void:
	var root_id: int = root.get_instance_id()
	_kill_tracked_tween(_root_tweens, root_id)
	var base_value: Variant = root.get_meta(_BASE_POSITION_META, root.position)
	var base_position: Vector2 = base_value if base_value is Vector2 else root.position
	var impulse: float = _get_root_impulse(tier)
	var rotation_degrees: float = _get_root_rotation(tier)
	var rotation_sign: float = _get_rotation_sign(direction)
	var impact_scale: Vector2 = _get_impact_scale(direction, tier)

	# 输入当帧先沿反方向压缩，随后越过中心，最后带轻微回弹归位。
	root.position = base_position - direction * impulse
	root.rotation_degrees = -rotation_sign * rotation_degrees
	root.scale = impact_scale
	root.skew = deg_to_rad(rotation_sign * rotation_degrees * 0.22)

	var tween: Tween = root.create_tween()
	var impact_position_tweener: PropertyTweener = tween.tween_property(
		root,
		"position",
		base_position + direction * impulse * 0.24,
		_get_impact_duration(tier)
	)
	var _impact_position_transition: Tweener = impact_position_tweener.set_trans(
		Tween.TRANS_CUBIC
	)
	var _impact_position_ease: Tweener = impact_position_tweener.set_ease(Tween.EASE_OUT)
	var impact_rotation_tweener: PropertyTweener = tween.parallel().tween_property(
		root,
		"rotation_degrees",
		rotation_sign * rotation_degrees * 0.30,
		_get_impact_duration(tier)
	)
	var _impact_rotation_transition: Tweener = impact_rotation_tweener.set_trans(
		Tween.TRANS_CUBIC
	)
	var _impact_rotation_ease: Tweener = impact_rotation_tweener.set_ease(Tween.EASE_OUT)
	var impact_scale_tweener: PropertyTweener = tween.parallel().tween_property(
		root,
		"scale",
		Vector2(2.0 - impact_scale.x, 2.0 - impact_scale.y),
		_get_impact_duration(tier)
	)
	var _impact_scale_transition: Tweener = impact_scale_tweener.set_trans(
		Tween.TRANS_CUBIC
	)
	var _impact_scale_ease: Tweener = impact_scale_tweener.set_ease(Tween.EASE_OUT)
	var impact_skew_tweener: PropertyTweener = tween.parallel().tween_property(
		root,
		"skew",
		deg_to_rad(-rotation_sign * rotation_degrees * 0.07),
		_get_impact_duration(tier)
	)
	var _impact_skew_transition: Tweener = impact_skew_tweener.set_trans(
		Tween.TRANS_CUBIC
	)
	var _impact_skew_ease: Tweener = impact_skew_tweener.set_ease(Tween.EASE_OUT)

	var settle_position_tweener: PropertyTweener = tween.chain().tween_property(
		root,
		"position",
		base_position,
		_get_settle_duration(tier)
	)
	var _settle_position_transition: Tweener = settle_position_tweener.set_trans(
		Tween.TRANS_BACK
	)
	var _settle_position_ease: Tweener = settle_position_tweener.set_ease(Tween.EASE_OUT)
	var settle_rotation_tweener: PropertyTweener = tween.parallel().tween_property(
		root,
		"rotation_degrees",
		0.0,
		_get_settle_duration(tier)
	)
	var _settle_rotation_transition: Tweener = settle_rotation_tweener.set_trans(
		Tween.TRANS_BACK
	)
	var _settle_rotation_ease: Tweener = settle_rotation_tweener.set_ease(Tween.EASE_OUT)
	var settle_scale_tweener: PropertyTweener = tween.parallel().tween_property(
		root,
		"scale",
		Vector2.ONE,
		_get_settle_duration(tier)
	)
	var _settle_scale_transition: Tweener = settle_scale_tweener.set_trans(
		Tween.TRANS_BACK
	)
	var _settle_scale_ease: Tweener = settle_scale_tweener.set_ease(Tween.EASE_OUT)
	var settle_skew_tweener: PropertyTweener = tween.parallel().tween_property(
		root,
		"skew",
		0.0,
		_get_settle_duration(tier)
	)
	var _settle_skew_transition: Tweener = settle_skew_tweener.set_trans(
		Tween.TRANS_BACK
	)
	var _settle_skew_ease: Tweener = settle_skew_tweener.set_ease(Tween.EASE_OUT)

	var _finished_connection: int = tween.finished.connect(
		_clear_tracked_tween.bind(_root_tweens, root_id, tween),
		CONNECT_ONE_SHOT
	)
	_root_tweens[root_id] = tween


func _play_background_impulse(
	background: ColorRect,
	direction: Vector2,
	tier: FeedbackTier
) -> void:
	if not is_instance_valid(background) or not background.is_inside_tree():
		return
	if not background.material is ShaderMaterial:
		return
	var material: ShaderMaterial = background.material
	var background_id: int = background.get_instance_id()
	_kill_tracked_tween(_background_tweens, background_id)

	var tier_energy: float = _get_tier_energy(tier)
	var shader_parameters: GFShaderParameterUtility = _get_cached_shader_parameter_utility()
	if is_instance_valid(shader_parameters):
		var _parameter_count: int = shader_parameters.apply_parameters(
			background,
			{
				&"interaction_offset": -direction * 0.018 * tier_energy,
				&"interaction_direction": direction,
				&"interaction_energy": tier_energy,
				&"interaction_phase": 0.0,
			},
			_get_shader_apply_options()
		)

	# GF 负责一次性契约校验，逐帧变化直接交给 Tween 操作已确认的材质属性。
	var duration: float = _get_background_duration(tier)
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


func _play_turn_shake(tier: FeedbackTier, direction: Vector2i) -> void:
	var shake: GFShakeUtility = _get_cached_shake_utility()
	if not is_instance_valid(shake):
		return
	var preset: GFShakePreset = _get_shake_preset(tier)
	if preset == null:
		return
	var _shake_id: int = shake.play_shake(
		_SHAKE_CHANNEL,
		preset,
		1.0,
		{
			"feedback_tier": tier,
			"direction": direction,
		}
	)


func _play_turn_haptic(tier: FeedbackTier, direction: Vector2i) -> void:
	var haptic: GFHapticUtility = _get_cached_haptic_utility()
	if not is_instance_valid(haptic):
		return
	var preset: GFHapticPreset = _get_haptic_preset(tier)
	if preset == null:
		return
	var _stopped_count: int = haptic.stop_channel(_HAPTIC_CHANNEL)
	var _haptic_id: int = haptic.play_haptic(
		_HAPTIC_CHANNEL,
		preset,
		-1,
		1.0,
		{
			"feedback_tier": tier,
			"direction": direction,
		}
	)


func _resolve_feedback_color(feedback_type: StringName, source_color: Color) -> Color:
	var semantic_color: Color = _get_feedback_color(feedback_type)
	if source_color.a <= 0.0:
		return semantic_color
	var resolved: Color = source_color.lerp(semantic_color, 0.42)
	resolved.a = 1.0
	return resolved


func _get_feedback_color(feedback_type: StringName) -> Color:
	match feedback_type:
		&"merge":
			return _MERGE_COLOR
		&"spawn":
			return _SPAWN_COLOR
		&"transform":
			return _TRANSFORM_COLOR
		_:
			return _DEFAULT_COLOR


func _get_root_impulse(tier: FeedbackTier) -> float:
	match tier:
		FeedbackTier.MERGE:
			return 14.0
		FeedbackTier.HIGH_MERGE:
			return 20.0
		FeedbackTier.RECORD:
			return 26.0
		_:
			return 8.0


func _get_root_rotation(tier: FeedbackTier) -> float:
	match tier:
		FeedbackTier.MERGE:
			return 2.6
		FeedbackTier.HIGH_MERGE:
			return 4.0
		FeedbackTier.RECORD:
			return 5.2
		_:
			return 1.6


func _get_impact_scale(direction: Vector2, tier: FeedbackTier) -> Vector2:
	var compression: float = 0.025 + float(int(tier)) * 0.011
	var expansion: float = compression * 0.52
	if absf(direction.x) >= absf(direction.y):
		return Vector2(1.0 - compression, 1.0 + expansion)
	return Vector2(1.0 + expansion, 1.0 - compression)


func _get_rotation_sign(direction: Vector2) -> float:
	var sign_value: float = direction.x - direction.y * 0.72
	return -1.0 if sign_value < 0.0 else 1.0


func _get_impact_duration(tier: FeedbackTier) -> float:
	return 0.055 + float(int(tier)) * 0.006


func _get_settle_duration(tier: FeedbackTier) -> float:
	return 0.15 + float(int(tier)) * 0.018


func _get_background_duration(tier: FeedbackTier) -> float:
	return _get_impact_duration(tier) + _get_settle_duration(tier) + 0.12


func _get_tier_energy(tier: FeedbackTier) -> float:
	match tier:
		FeedbackTier.MERGE:
			return 0.62
		FeedbackTier.HIGH_MERGE:
			return 0.84
		FeedbackTier.RECORD:
			return 1.0
		_:
			return 0.38


func _get_edge_fragment_count(tier: FeedbackTier) -> int:
	match tier:
		FeedbackTier.MERGE:
			return 8
		FeedbackTier.HIGH_MERGE:
			return 13
		FeedbackTier.RECORD:
			return 18
		_:
			return 5


func _get_cached_shake_utility() -> GFShakeUtility:
	if is_instance_valid(_shake_utility):
		return _shake_utility
	_shake_utility = _get_shake_utility()
	return _shake_utility


func _get_cached_haptic_utility() -> GFHapticUtility:
	if is_instance_valid(_haptic_utility):
		return _haptic_utility
	_haptic_utility = _get_haptic_utility()
	return _haptic_utility


func _get_cached_shader_parameter_utility() -> GFShaderParameterUtility:
	if is_instance_valid(_shader_parameter_utility):
		return _shader_parameter_utility
	_shader_parameter_utility = _get_shader_parameter_utility()
	return _shader_parameter_utility


func _get_shake_utility() -> GFShakeUtility:
	var utility_value: Object = get_utility(GFShakeUtility)
	if utility_value is GFShakeUtility:
		return utility_value
	return null


func _get_haptic_utility() -> GFHapticUtility:
	var utility_value: Object = get_utility(GFHapticUtility)
	if utility_value is GFHapticUtility:
		return utility_value
	return null


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		return utility_value
	return null


func _get_shake_preset(tier: FeedbackTier) -> GFShakePreset:
	if _profile == null:
		return null
	return _profile.get_shake_preset(_get_tier_id(tier))


func _get_haptic_preset(tier: FeedbackTier) -> GFHapticPreset:
	if _profile == null:
		return null
	return _profile.get_haptic_preset(_get_tier_id(tier))


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


func _get_shader_apply_options() -> Dictionary:
	return {
		"duplicate_material": false,
		"require_declared_parameters": true,
		"warn_on_invalid_target": false,
		"warn_on_missing_parameters": true,
		"copy_values": true,
	}


func _kill_tracked_tween(tweens: Dictionary, target_id: int) -> void:
	var tween_value: Variant = tweens.get(target_id)
	if tween_value is Tween:
		var tween: Tween = tween_value
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
	for tween_value: Variant in tweens.values():
		if tween_value is Tween:
			var tween: Tween = tween_value
			if tween.is_valid():
				tween.kill()
	tweens.clear()
