## GameBoardFeedbackUtility: 统一生成棋盘上的短生命周期反馈特效。
##
## 作为项目级 GFUtility，它只负责视觉反馈节点的生成与自动释放；
## 具体何时触发由棋盘表现 Action 决定。
class_name GameBoardFeedbackUtility
extends GFUtility


# --- 常量 ---

const _FEEDBACK_NODE_NAME: String = "BoardFeedback"
const _FEEDBACK_Z_INDEX: int = 100
const _MERGE_COLOR: Color = Color(1.0, 0.78, 0.24, 1.0)
const _SPAWN_COLOR: Color = Color(0.74, 0.95, 1.0, 1.0)
const _TRANSFORM_COLOR: Color = Color(0.58, 0.82, 1.0, 1.0)
const _DEFAULT_COLOR: Color = Color.WHITE
const _SPARK_BASE_SIZE: float = 7.0
const _LABEL_SIZE: Vector2 = Vector2(120.0, 36.0)
const _LABEL_OFFSET: Vector2 = Vector2(-60.0, -58.0)
const _LABEL_RISE: Vector2 = Vector2(0.0, -20.0)
const _LABEL_DURATION: float = 0.42
const _ROOT_LIFETIME_PADDING: float = 0.08


# --- 公共方法 ---

## 在棋盘容器的局部坐标中播放反馈特效。
## @param parent: 承载反馈节点的棋盘容器。
## @param local_position: 特效出现的局部坐标。
## @param feedback_type: 反馈类型，如 merge、spawn、transform。
## @param label_text: 可选浮动文字。
## @return: 本次创建的可见反馈子节点数量。
func play_feedback(
	parent: Node2D,
	local_position: Vector2,
	feedback_type: StringName,
	label_text: String = ""
) -> int:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return 0

	var effect_root := Node2D.new()
	effect_root.name = _FEEDBACK_NODE_NAME
	effect_root.position = local_position
	effect_root.z_index = _FEEDBACK_Z_INDEX
	parent.add_child(effect_root)

	var color: Color = _get_feedback_color(feedback_type)
	var particle_count: int = _get_particle_count(feedback_type)
	var duration: float = _get_particle_duration(feedback_type)
	var created_count: int = 0

	for index in range(particle_count):
		_create_spark(effect_root, color, feedback_type, index, particle_count, duration)
		created_count += 1

	var resolved_label_text := _get_label_text(feedback_type, label_text)
	if not resolved_label_text.is_empty():
		_create_label(effect_root, resolved_label_text, color)
		created_count += 1

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
	var spark := Panel.new()
	var spark_size: float = _SPARK_BASE_SIZE + float(index % 3)
	spark.size = Vector2.ONE * spark_size
	spark.pivot_offset = spark.size * 0.5
	spark.position = -spark.size * 0.5
	spark.modulate = color
	spark.scale = Vector2.ONE
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.add_theme_stylebox_override("panel", _create_spark_style(color, spark_size))
	root.add_child(spark)

	var angle: float = _get_particle_phase(feedback_type) + TAU * float(index) / maxf(float(count), 1.0)
	var direction := Vector2.RIGHT.rotated(angle)
	var distance: float = _get_particle_distance(feedback_type) * (0.78 + float(index % 4) * 0.08)
	var tween := spark.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(spark, "position", direction * distance - spark.size * 0.5, duration)
	tween.tween_property(spark, "scale", Vector2.ONE * 0.22, duration)
	tween.tween_property(spark, "modulate:a", 0.0, duration)


func _create_label(root: Node2D, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.size = _LABEL_SIZE
	label.position = _LABEL_OFFSET
	label.pivot_offset = _LABEL_SIZE * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color.lightened(0.18))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.scale = Vector2.ONE * 0.76
	root.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position", _LABEL_OFFSET + _LABEL_RISE, _LABEL_DURATION)
	tween.tween_property(label, "scale", Vector2.ONE, _LABEL_DURATION * 0.55)
	tween.tween_property(label, "modulate:a", 0.0, _LABEL_DURATION).set_delay(_LABEL_DURATION * 0.25)


func _create_spark_style(color: Color, spark_size: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(spark_size))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	style.shadow_size = 3
	return style


func _queue_free_after(root: Node2D, lifetime: float) -> void:
	var tween := root.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_callback(root.queue_free)


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
			return "+" + label_text
		return label_text
	if feedback_type == &"transform":
		return "!"
	return ""
