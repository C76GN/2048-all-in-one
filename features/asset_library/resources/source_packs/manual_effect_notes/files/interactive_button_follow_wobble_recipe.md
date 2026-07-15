# Interactive Button Follow Wobble Recipe

This is a review-only UI motion recipe captured from chat.

It combines four reusable interaction ideas:

- Drag-follow motion for card-like buttons.
- Inertial rotation based on pointer velocity or return velocity.
- Subtle idle floating after the control returns to its anchor.
- Shader parameter feedback for hover, especially `hovering` and `mouse_screen_pos`.

Potential project uses:

- Main menu buttons with richer pointer feedback.
- Mode selection cards.
- Theme preview cards.
- Bookmark and replay list items.
- Future collectible, reward, or card-like UI.

Runtime promotion requirements:

- Convert this into a reusable component or utility instead of embedding it in every button script.
- Replace scene-specific `$Chip` and `$Chip/Suit` paths with exported `NodePath` values.
- Ensure keyboard/gamepad focus receives equivalent feedback, not mouse-only behavior.
- Clamp motion so text stays readable and hit boxes remain predictable.
- Add reduced-motion fallback if used in core navigation.
- Pair with an approved hover shader exposing `hovering` and `mouse_screen_pos`.

```gdscript
extends Button

@export var anchor: Marker2D
@export var interaction_enabled: bool = true
@export var chip_path: NodePath = ^"Chip"
@export var suit_path: NodePath = ^"Chip/Suit"
@export var pointer_offset_scale: float = 2.0
@export var pointer_offset_limit: float = 2000.0
@export var follow_weight: float = 0.25
@export var hover_scale: Vector2 = Vector2(1.05, 1.05)
@export var idle_float_amplitude: float = 0.4375
@export var idle_rotation_amplitude: float = 0.0018125

var elapsed_time: float = 0.0
var is_dragging: bool = false
var target_mouse_position: Vector2 = Vector2.ZERO
var drag_velocity: Vector2 = Vector2.ZERO
var previous_return_position: Vector2 = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not interaction_enabled:
		return

	if event is InputEventMouseMotion:
		target_mouse_position = event.position - size * 0.5
		drag_velocity = (event.velocity / 4000.0).clamp(Vector2(-0.3, -0.3), Vector2(0.3, 0.3))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			is_dragging = false

func _process(delta: float) -> void:
	if anchor == null:
		return

	if not interaction_enabled:
		position = anchor.position
		rotation = 0.0
		visible = false
		return

	visible = true
	elapsed_time += delta

	if is_dragging:
		_update_drag_motion()
	else:
		_update_idle_motion()

	_update_hover_shader()

func _update_drag_motion() -> void:
	position = position.lerp(target_mouse_position, follow_weight)
	rotation += clamp(drag_velocity.x, -0.3, 0.3)
	rotation *= 0.8
	scale = scale.lerp(hover_scale, follow_weight)
	drag_velocity = Vector2.ZERO

func _update_idle_motion() -> void:
	position = position.lerp(anchor.position, follow_weight)
	var return_velocity: Vector2 = (position - previous_return_position) * 0.01532
	previous_return_position = position

	rotation += clamp(return_velocity.x, -0.3, 0.25)
	rotation *= 0.8
	rotation += sin(elapsed_time + 1321.0) * idle_rotation_amplitude
	position.x += cos(elapsed_time + 1501.0) * idle_float_amplitude
	position.y += sin(elapsed_time + 1591.0) * idle_float_amplitude

func _update_hover_shader() -> void:
	var shader_material: ShaderMaterial = _get_chip_shader_material()
	if shader_material == null:
		return

	var hovering: bool = get_global_rect().has_point(get_global_mouse_position())
	scale = scale.lerp(hover_scale if hovering else Vector2.ONE, follow_weight)
	shader_material.set_shader_parameter("hovering", 1.0 if hovering else 0.0)

	if hovering:
		var local_offset: Vector2 = get_global_mouse_position() - (global_position + size * 0.5)
		var shader_offset: Vector2 = Vector2(
			clampf(local_offset.x * pointer_offset_scale, -pointer_offset_limit, pointer_offset_limit),
			clampf(local_offset.y * pointer_offset_scale, -pointer_offset_limit, pointer_offset_limit)
		)
		shader_material.set_shader_parameter("mouse_screen_pos", shader_offset)

	var suit_node: CanvasItem = get_node_or_null(suit_path) as CanvasItem
	if suit_node != null:
		suit_node.material = shader_material

func _get_chip_shader_material() -> ShaderMaterial:
	var chip_node: CanvasItem = get_node_or_null(chip_path) as CanvasItem
	if chip_node == null:
		return null
	return chip_node.material as ShaderMaterial

func _on_button_down() -> void:
	if interaction_enabled:
		is_dragging = true
```
