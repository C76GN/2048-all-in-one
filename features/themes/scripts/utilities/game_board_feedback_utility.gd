## GameBoardFeedbackUtility: 编排方块、棋盘与背景的统一操作反馈。
##
## 局部火花、方向冲量、GF 震动和背景 shader 使用同一批次语义，避免各组件各自
## 播放互不相关的动画。强度由有效操作的合并数量与结果值分级。
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

const _FEEDBACK_NODE_NAME: String = "BoardFeedback"
const _TURN_FEEDBACK_NODE_NAME: String = "TurnEdgeFeedback"
const _FEEDBACK_Z_INDEX: int = 100
const _MERGE_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _SPAWN_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
const _TRANSFORM_COLOR: Color = Color(0.8745098, 0.29411766, 0.6039216, 1.0)
const _DEFAULT_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _SPARK_BASE_SIZE: float = 5.0
const _LABEL_SIZE: Vector2 = Vector2(120.0, 36.0)
const _LABEL_OFFSET: Vector2 = Vector2(-60.0, -58.0)
const _LABEL_RISE: Vector2 = Vector2(0.0, -20.0)
const _LABEL_DURATION: float = 0.34
const _ROOT_LIFETIME_PADDING: float = 0.08
const _SHAKE_CHANNEL: StringName = &"board"
const _BASE_POSITION_META: StringName = &"feedback_base_position"


# --- 私有变量 ---

var _shake_utility: GFShakeUtility = null
var _shader_parameter_utility: GFShaderParameterUtility = null
var _shake_presets: Dictionary = {}
var _root_tweens: Dictionary = {}
var _background_tweens: Dictionary = {}


# --- GF 生命周期方法 ---

func init() -> void:
	_shake_presets = {
		FeedbackTier.MOVE: _make_shake_preset(0.08, 0.28, 24.0, 0.04),
		FeedbackTier.MERGE: _make_shake_preset(0.12, 0.72, 30.0, 0.08),
		FeedbackTier.HIGH_MERGE: _make_shake_preset(0.16, 1.28, 34.0, 0.14),
		FeedbackTier.RECORD: _make_shake_preset(0.20, 1.75, 38.0, 0.20),
	}


func get_required_utilities() -> Array[Script]:
	return [GFShakeUtility, GFShaderParameterUtility]


func ready() -> void:
	_shake_utility = _get_shake_utility()
	_shader_parameter_utility = _get_shader_parameter_utility()


func dispose() -> void:
	_kill_tweens(_root_tweens)
	_kill_tweens(_background_tweens)
	_shake_utility = null
	_shader_parameter_utility = null
	_shake_presets.clear()


# --- 公共方法 ---

## 根据一次有效操作的结果返回稳定反馈等级。
## @param merge_count: 本次操作产生的合并数量。
## @param max_merge_value: 本次操作产生的最大合并结果值。
## @param score_delta: 本次操作增加的分数。
## @param is_record: 本次操作是否创造纪录。
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


## 播放一次有效移动对应的整屏反馈，返回创建的边缘碎片数。
## @param root: 承载整批方向冲量和边缘反馈的棋盘根节点。
## @param background: 承载操作响应 uniform 的全屏背景。
## @param direction: 本次有效移动的棋盘方向。
## @param tier: 已分类的整批反馈等级。
## @param board_rect: 以反馈根节点为坐标系的棋盘矩形。
## @param accent_color: 当前主题用于反馈碎片的强调色。
func play_turn_feedback(
	root: Node2D,
	background: ColorRect,
	direction: Vector2i,
	tier: FeedbackTier,
	board_rect: Rect2,
	accent_color: Color = Color.WHITE
) -> int:
	if not is_instance_valid(root) or not root.is_inside_tree() or direction == Vector2i.ZERO:
		return 0

	var direction_vector: Vector2 = Vector2(direction).normalized()
	_play_root_impulse(root, direction_vector, tier)
	_play_background_impulse(background, direction_vector, tier)
	_play_turn_shake(tier, direction)
	return _create_edge_fragments(root, board_rect, direction_vector, tier, accent_color)


## 在棋盘容器的局部坐标中播放单个方块反馈。
## @param parent: 承载单方块反馈的棋盘容器。
## @param local_position: 反馈在棋盘容器中的局部位置。
## @param feedback_type: 合并、生成或变换等稳定反馈类型。
## @param label_text: 可选的短反馈文字。
## @param source_color: 可选的方块来源色，用于派生反馈色。
func play_feedback(
	parent: Node2D,
	local_position: Vector2,
	feedback_type: StringName,
	label_text: String = "",
	source_color: Color = Color.TRANSPARENT
) -> int:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return 0

	var effect_root: Node2D = Node2D.new()
	effect_root.name = _FEEDBACK_NODE_NAME
	effect_root.position = local_position
	effect_root.z_index = _FEEDBACK_Z_INDEX
	parent.add_child(effect_root)

	var color: Color = _resolve_feedback_color(feedback_type, source_color)
	var particle_count: int = _get_particle_count(feedback_type)
	var duration: float = _get_particle_duration(feedback_type)
	var created_count: int = 0

	for index: int in range(particle_count):
		_create_spark(effect_root, color, feedback_type, index, particle_count, duration)
		created_count += 1

	var resolved_label_text: String = _get_label_text(feedback_type, label_text)
	if not resolved_label_text.is_empty():
		_create_label(effect_root, resolved_label_text, color)
		created_count += 1

	_queue_free_after(effect_root, maxf(duration, _LABEL_DURATION) + _ROOT_LIFETIME_PADDING)
	return created_count


# --- 私有/辅助方法 ---

func _play_root_impulse(root: Node2D, direction: Vector2, tier: FeedbackTier) -> void:
	var root_id: int = root.get_instance_id()
	_kill_tracked_tween(_root_tweens, root_id)
	var base_value: Variant = root.get_meta(_BASE_POSITION_META, root.position)
	var base_position: Vector2 = base_value if base_value is Vector2 else root.position
	var impulse: float = _get_root_impulse(tier)
	var rotation_sign: float = direction.x - direction.y * 0.55

	root.position = base_position - direction * impulse
	root.rotation_degrees = -rotation_sign * impulse * 0.045
	root.scale = Vector2.ONE * (1.0 - impulse * 0.0009)

	var tween: Tween = root.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_BACK)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = tween.tween_property(
		root,
		"position",
		base_position,
		_get_turn_duration(tier)
	)
	var _rotation_tweener: PropertyTweener = tween.tween_property(
		root,
		"rotation_degrees",
		0.0,
		_get_turn_duration(tier)
	)
	var _scale_tweener: PropertyTweener = tween.tween_property(
		root,
		"scale",
		Vector2.ONE,
		_get_turn_duration(tier)
	)
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
	var background_id: int = background.get_instance_id()
	_kill_tracked_tween(_background_tweens, background_id)
	_set_background_feedback(1.0, background, direction, tier)

	var tween: Tween = background.create_tween()
	var energy_tweener: MethodTweener = tween.tween_method(
		_set_background_feedback.bind(background, direction, tier),
		1.0,
		0.0,
		_get_background_duration(tier)
	)
	var _energy_curve: Tweener = energy_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	var _finished_connection: int = tween.finished.connect(
		_clear_tracked_tween.bind(_background_tweens, background_id, tween),
		CONNECT_ONE_SHOT
	)
	_background_tweens[background_id] = tween


func _set_background_feedback(
	progress: float,
	background: ColorRect,
	direction: Vector2,
	tier: FeedbackTier
) -> void:
	var shader_parameters: GFShaderParameterUtility = _get_cached_shader_parameter_utility()
	if not is_instance_valid(shader_parameters) or not is_instance_valid(background):
		return
	var safe_progress: float = clampf(progress, 0.0, 1.0)
	var tier_energy: float = _get_tier_energy(tier)
	var _parameter_count: int = shader_parameters.apply_parameters(
		background,
		{
			&"interaction_offset": -direction * 0.012 * tier_energy * safe_progress,
			&"interaction_direction": direction,
			&"interaction_energy": tier_energy * safe_progress,
		},
		_get_shader_apply_options()
	)


func _create_edge_fragments(
	root: Node2D,
	board_rect: Rect2,
	direction: Vector2,
	tier: FeedbackTier,
	accent_color: Color
) -> int:
	var fragment_root: Node2D = Node2D.new()
	fragment_root.name = _TURN_FEEDBACK_NODE_NAME
	fragment_root.z_index = _FEEDBACK_Z_INDEX + 4
	root.add_child(fragment_root)

	var count: int = _get_edge_fragment_count(tier)
	var tangent: Vector2 = Vector2(-direction.y, direction.x)
	var edge_center: Vector2 = board_rect.get_center()
	var span: float
	if absf(direction.x) >= absf(direction.y):
		edge_center.x = board_rect.end.x if direction.x > 0.0 else board_rect.position.x
		span = board_rect.size.y * 0.72
	else:
		edge_center.y = board_rect.end.y if direction.y > 0.0 else board_rect.position.y
		span = board_rect.size.x * 0.72

	var color: Color = accent_color.lerp(_get_tier_color(tier), 0.42)
	color.a = 1.0
	for index: int in range(count):
		var normalized: float = (
			0.0 if count <= 1 else float(index) / float(count - 1) - 0.5
		)
		var fragment: Panel = _create_edge_fragment(color, index)
		fragment.position = edge_center + tangent * normalized * span - fragment.size * 0.5
		fragment_root.add_child(fragment)
		_animate_edge_fragment(fragment, direction, tangent, index, tier)

	_queue_free_after(fragment_root, _get_background_duration(tier) + 0.12)
	return count


func _create_edge_fragment(color: Color, index: int) -> Panel:
	var fragment: Panel = Panel.new()
	fragment.size = Vector2(9.0 + float(index % 3) * 4.0, 3.0 + float(index % 2) * 3.0)
	fragment.pivot_offset = fragment.size * 0.5
	fragment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fragment.modulate = color
	fragment.add_theme_stylebox_override("panel", _create_spark_style(color, 0.0))
	return fragment


func _animate_edge_fragment(
	fragment: Panel,
	direction: Vector2,
	tangent: Vector2,
	index: int,
	tier: FeedbackTier
) -> void:
	var drift_sign: float = -1.0 if index % 2 == 0 else 1.0
	var distance: float = 14.0 + _get_tier_energy(tier) * 11.0 + float(index % 4) * 3.0
	var target_position: Vector2 = (
		fragment.position
		+ direction * distance
		+ tangent * drift_sign * (4.0 + float(index % 3) * 2.0)
	)
	var duration: float = _get_turn_duration(tier) + 0.08
	var tween: Tween = fragment.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = tween.tween_property(
		fragment,
		"position",
		target_position,
		duration
	)
	var _rotation_tweener: PropertyTweener = tween.tween_property(
		fragment,
		"rotation",
		drift_sign * 0.55,
		duration
	)
	var _fade_tweener: PropertyTweener = tween.tween_property(
		fragment,
		"modulate:a",
		0.0,
		duration
	)


func _create_spark(
	root: Node2D,
	color: Color,
	feedback_type: StringName,
	index: int,
	count: int,
	duration: float
) -> void:
	var spark: Panel = Panel.new()
	var spark_size: float = _SPARK_BASE_SIZE + float(index % 3)
	var is_print_chip: bool = index % 2 == 0
	spark.size = (
		Vector2(spark_size * 1.45, maxf(spark_size * 0.52, 2.0))
		if is_print_chip
		else Vector2.ONE * spark_size
	)
	spark.pivot_offset = spark.size * 0.5
	spark.position = -spark.size * 0.5
	spark.modulate = color
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.add_theme_stylebox_override("panel", _create_spark_style(color, spark_size))
	root.add_child(spark)

	var angle: float = _get_particle_phase(feedback_type) + TAU * float(index) / maxf(float(count), 1.0)
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	spark.rotation = angle + (PI * 0.25 if is_print_chip else 0.0)
	var distance: float = _get_particle_distance(feedback_type) * (0.78 + float(index % 4) * 0.08)
	var tween: Tween = spark.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = tween.tween_property(
		spark,
		"position",
		direction * distance - spark.size * 0.5,
		duration
	)
	var _scale_tweener: PropertyTweener = tween.tween_property(
		spark,
		"scale",
		Vector2.ONE * 0.22,
		duration
	)
	var _rotation_tweener: PropertyTweener = tween.tween_property(
		spark,
		"rotation",
		spark.rotation + (0.65 if index % 2 == 0 else -0.65),
		duration
	)
	var _fade_tweener: PropertyTweener = tween.tween_property(
		spark,
		"modulate:a",
		0.0,
		duration
	)


func _create_label(root: Node2D, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.size = _LABEL_SIZE
	label.position = _LABEL_OFFSET
	label.pivot_offset = _LABEL_SIZE * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override(
		"font_outline_color",
		Color(1.0, 0.972549, 0.9098039, 0.72)
	)
	label.add_theme_constant_override("outline_size", 2)
	label.scale = Vector2.ONE * 0.76
	root.add_child(label)

	var tween: Tween = label.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = tween.tween_property(
		label,
		"position",
		_LABEL_OFFSET + _LABEL_RISE,
		_LABEL_DURATION
	)
	var _scale_tweener: PropertyTweener = tween.tween_property(
		label,
		"scale",
		Vector2.ONE,
		_LABEL_DURATION * 0.55
	)
	var fade_tweener: PropertyTweener = tween.tween_property(
		label,
		"modulate:a",
		0.0,
		_LABEL_DURATION
	)
	var _fade_delay_result: Tweener = fade_tweener.set_delay(_LABEL_DURATION * 0.25)


func _create_spark_style(color: Color, _spark_size: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	return style


func _queue_free_after(root: Node2D, lifetime: float) -> void:
	var tween: Tween = root.create_tween()
	var _interval_tweener: IntervalTweener = tween.tween_interval(lifetime)
	var _callback_tweener: CallbackTweener = tween.tween_callback(root.queue_free)


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


func _resolve_feedback_color(feedback_type: StringName, source_color: Color) -> Color:
	var semantic_color: Color = _get_feedback_color(feedback_type)
	if source_color.a <= 0.0:
		return semantic_color
	var resolved: Color = source_color.lerp(semantic_color, 0.24)
	resolved.a = 1.0
	return resolved


func _get_particle_count(feedback_type: StringName) -> int:
	match feedback_type:
		&"merge":
			return 10
		&"transform":
			return 7
		&"spawn":
			return 4
		_:
			return 4


func _get_particle_distance(feedback_type: StringName) -> float:
	match feedback_type:
		&"merge":
			return 52.0
		&"transform":
			return 42.0
		&"spawn":
			return 26.0
		_:
			return 30.0


func _get_particle_duration(feedback_type: StringName) -> float:
	match feedback_type:
		&"merge":
			return 0.30
		&"transform":
			return 0.26
		&"spawn":
			return 0.22
		_:
			return 0.22


func _get_particle_phase(feedback_type: StringName) -> float:
	match feedback_type:
		&"transform":
			return TAU * 0.08
		&"spawn":
			return TAU * 0.04
		_:
			return 0.0


func _get_label_text(feedback_type: StringName, label_text: String) -> String:
	if not label_text.is_empty():
		if feedback_type == &"merge":
			return (
				label_text
				if label_text.begins_with("-") or label_text.begins_with("+")
				else "+" + label_text
			)
		return label_text
	if feedback_type == &"transform":
		return "!"
	return ""


func _get_root_impulse(tier: FeedbackTier) -> float:
	match tier:
		FeedbackTier.MERGE:
			return 5.0
		FeedbackTier.HIGH_MERGE:
			return 8.0
		FeedbackTier.RECORD:
			return 11.0
		_:
			return 2.8


func _get_turn_duration(tier: FeedbackTier) -> float:
	match tier:
		FeedbackTier.HIGH_MERGE, FeedbackTier.RECORD:
			return 0.20
		FeedbackTier.MERGE:
			return 0.17
		_:
			return 0.13


func _get_background_duration(tier: FeedbackTier) -> float:
	return _get_turn_duration(tier) + 0.10


func _get_tier_energy(tier: FeedbackTier) -> float:
	match tier:
		FeedbackTier.MERGE:
			return 0.58
		FeedbackTier.HIGH_MERGE:
			return 0.82
		FeedbackTier.RECORD:
			return 1.0
		_:
			return 0.30


func _get_edge_fragment_count(tier: FeedbackTier) -> int:
	match tier:
		FeedbackTier.MERGE:
			return 5
		FeedbackTier.HIGH_MERGE:
			return 8
		FeedbackTier.RECORD:
			return 11
		_:
			return 3


func _get_tier_color(tier: FeedbackTier) -> Color:
	match tier:
		FeedbackTier.MERGE:
			return _MERGE_COLOR
		FeedbackTier.HIGH_MERGE, FeedbackTier.RECORD:
			return _TRANSFORM_COLOR
		_:
			return _SPAWN_COLOR


func _get_cached_shake_utility() -> GFShakeUtility:
	if is_instance_valid(_shake_utility):
		return _shake_utility
	_shake_utility = _get_shake_utility()
	return _shake_utility


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


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		return utility_value
	return null


func _get_shake_preset(tier: FeedbackTier) -> GFShakePreset:
	var preset_value: Variant = _shake_presets.get(tier)
	if preset_value is GFShakePreset:
		return preset_value
	return null


func _make_shake_preset(
	duration: float,
	amplitude: float,
	frequency: float,
	rotation_degrees: float
) -> GFShakePreset:
	var preset: GFShakePreset = GFShakePreset.new()
	preset.duration_seconds = duration
	preset.amplitude = amplitude
	preset.frequency = frequency
	preset.waveform = GFShakePreset.Waveform.NOISE
	preset.position_axis = Vector3(1.0, 0.55, 0.0)
	preset.rotation_axis_degrees = Vector3(0.0, 0.0, rotation_degrees)
	return preset


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
