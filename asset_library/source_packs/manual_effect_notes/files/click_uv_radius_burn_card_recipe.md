# Click UV Radius Burn Card Recipe

This is a review-only interaction recipe captured from chat.

It converts a click on a `Sprite2D` into local UV coordinates, writes that UV into a shader parameter named `position`, then tweens a shader parameter named `radius`.

Potential project uses:

- Delete bookmark card feedback.
- Delete replay card feedback.
- Mode card rejection or reroll feedback.
- Future card-like collectible or theme preview UI.

Runtime promotion requirements:

- Pair with an approved burn or dissolve shader that exposes `position` and `radius`.
- Adapt from `Sprite2D` to `Control`/`TextureRect` for UI cards.
- Verify it does not obscure important text or buttons.
- Add reduced-motion or instant-complete fallback if used on core workflows.

```gdscript
extends Sprite2D

var texture_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	if texture:
		texture_size = texture.get_size()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var world_pos: Vector2 = get_global_mouse_position()
		var local_pos: Vector2 = to_local(world_pos)
		if get_rect().has_point(local_pos):
			var uv: Vector2 = get_uv_from_click(local_pos)
			burn_card(uv)

func get_uv_from_click(local_click_pos: Vector2) -> Vector2:
	var top_left_pos: Vector2 = local_click_pos + texture_size / 2.0
	return top_left_pos / texture_size

func burn_card(uv: Vector2) -> void:
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material
		var tween: Tween = create_tween()
		shader_material.set_shader_parameter("position", uv)
		var _radius_tweener: MethodTweener = tween.tween_method(update_radius, 0.0, 2.0, 1.5)

func update_radius(value: float) -> void:
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material
		shader_material.set_shader_parameter("radius", value)
```
