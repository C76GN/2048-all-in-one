## GameBoardFeedbackUtility: 统一生成棋盘上的短生命周期反馈特效。
##
## 作为项目级 GFUtility，它只负责视觉反馈节点的生成与自动释放；
## 具体何时触发由棋盘表现 Action 决定。
class_name GameBoardFeedbackUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const _FEEDBACK_NODE_NAME: String = "BoardFeedback"
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


# --- 私有变量 ---

var _shake_utility: GFShakeUtility = null
var _shake_presets: Dictionary = {}


# --- GF 生命周期方法 ---

func init() -> void:
	_shake_presets = {
		&"merge": _make_shake_preset(0.16, 2.2, 34.0),
		&"spawn": _make_shake_preset(0.10, 0.9, 24.0),
		&"transform": _make_shake_preset(0.14, 1.5, 30.0),
	}


func get_required_utilities() -> Array[Script]:
	return [GFShakeUtility]


func ready() -> void:
	_shake_utility = _get_shake_utility()


func dispose() -> void:
	_shake_utility = null
	_shake_presets.clear()


# --- 公共方法 ---

## 在棋盘容器的局部坐标中播放反馈特效。
## @param parent: 承载反馈节点的棋盘容器。
## @param local_position: 特效出现的局部坐标。
## @param feedback_type: 反馈类型，如 merge、spawn、transform。
## @param label_text: 可选浮动文字。
## @param source_color: 可选的方块主题色；提供时会与语义反馈色混合。
## @return: 本次创建的可见反馈子节点数量。
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

	_play_feedback_shake(feedback_type)
	_queue_free_after(effect_root, maxf(duration, _LABEL_DURATION) + _ROOT_LIFETIME_PADDING)
	return created_count


# --- 私有/辅助方法 ---

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
	spark.scale = Vector2.ONE
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
	var _position_tweener: PropertyTweener = tween.tween_property(spark, "position", direction * distance - spark.size * 0.5, duration)
	var _scale_tweener: PropertyTweener = tween.tween_property(spark, "scale", Vector2.ONE * 0.22, duration)
	var _rotation_tweener: PropertyTweener = tween.tween_property(
		spark,
		"rotation",
		spark.rotation + (0.65 if index % 2 == 0 else -0.65),
		duration
	)
	var _fade_tweener: PropertyTweener = tween.tween_property(spark, "modulate:a", 0.0, duration)


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
	label.add_theme_color_override("font_outline_color", Color(1.0, 0.972549, 0.9098039, 0.72))
	label.add_theme_constant_override("outline_size", 2)
	label.scale = Vector2.ONE * 0.76
	root.add_child(label)

	var tween: Tween = label.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _position_tweener: PropertyTweener = tween.tween_property(label, "position", _LABEL_OFFSET + _LABEL_RISE, _LABEL_DURATION)
	var _scale_tweener: PropertyTweener = tween.tween_property(label, "scale", Vector2.ONE, _LABEL_DURATION * 0.55)
	var fade_tweener: PropertyTweener = tween.tween_property(label, "modulate:a", 0.0, _LABEL_DURATION)
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
			return 12
		&"transform":
			return 9
		&"spawn":
			return 6
		_:
			return 5


func _get_particle_distance(feedback_type: StringName) -> float:
	match feedback_type:
		&"merge":
			return 58.0
		&"transform":
			return 44.0
		&"spawn":
			return 30.0
		_:
			return 32.0


func _get_particle_duration(feedback_type: StringName) -> float:
	match feedback_type:
		&"merge":
			return 0.34
		&"transform":
			return 0.28
		&"spawn":
			return 0.24
		_:
			return 0.24


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
			return label_text if label_text.begins_with("-") or label_text.begins_with("+") else "+" + label_text
		return label_text
	if feedback_type == &"transform":
		return "!"
	return ""


func _play_feedback_shake(feedback_type: StringName) -> void:
	var shake: GFShakeUtility = _get_cached_shake_utility()
	if not is_instance_valid(shake):
		return

	var preset: GFShakePreset = _get_shake_preset(feedback_type)
	if preset == null:
		return

	var _shake_id: int = shake.play_shake(_SHAKE_CHANNEL, preset, 1.0, {
		"feedback_type": String(feedback_type),
	})


func _get_cached_shake_utility() -> GFShakeUtility:
	if is_instance_valid(_shake_utility):
		return _shake_utility

	_shake_utility = _get_shake_utility()
	return _shake_utility


func _get_shake_utility() -> GFShakeUtility:
	var utility_value: Object = get_utility(GFShakeUtility)
	if utility_value is GFShakeUtility:
		var shake_utility: GFShakeUtility = utility_value
		return shake_utility
	return null


func _get_shake_preset(feedback_type: StringName) -> GFShakePreset:
	var preset_value: Variant = _shake_presets.get(feedback_type)
	if preset_value is GFShakePreset:
		var preset: GFShakePreset = preset_value
		return preset
	return null


func _make_shake_preset(duration: float, amplitude: float, frequency: float) -> GFShakePreset:
	var preset: GFShakePreset = GFShakePreset.new()
	preset.duration_seconds = duration
	preset.amplitude = amplitude
	preset.frequency = frequency
	preset.waveform = GFShakePreset.Waveform.NOISE
	preset.position_axis = Vector3(1.0, 0.55, 0.0)
	return preset
