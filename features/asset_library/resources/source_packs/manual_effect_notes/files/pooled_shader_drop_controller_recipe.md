# Pooled Shader Drop Controller Recipe

This is a review-only VFX controller recipe captured from chat.

It manages a fixed pool of shader-driven drops by writing two shader uniform arrays:

- `positions`: `PackedVector2Array`
- `scales`: `PackedFloat32Array`

Potential project uses:

- Tile merge residue or impact marks.
- Theme unlock ink, paint, water, dust, or sparkle drops.
- Reward reveal surface marks.
- Future 2.5D/3D board feedback effects.

Runtime promotion requirements:

- Pair with an approved shader whose array constant exactly matches `pool_size`.
- Decide whether positions are UV, local plane coordinates, or world-projected coordinates.
- Add guardrails for call frequency so the pool is not constantly saturated.
- Prefer theme-neutral naming in shared code; effect-specific names belong in theme resources.
- Add tests or diagnostics that assert shader array sizes match the exported pool size.
- Add a reduced-motion or instant-complete path when used in core UI flows.

```gdscript
extends MeshInstance3D
class_name PooledShaderDropPool

@export var pool_size: int = 64
@export var grow_time: float = 0.2
@export var fade_time: float = 4.0
@export var fade_delay: float = 0.2

@onready var shader_material: ShaderMaterial = get_active_material(0) as ShaderMaterial

var drop_pool: Array[DropHandle] = []

func _ready() -> void:
	if shader_material == null:
		return

	var positions: PackedVector2Array = PackedVector2Array()
	positions.resize(pool_size)
	shader_material.set_shader_parameter("positions", positions)

	var scales: PackedFloat32Array = PackedFloat32Array()
	scales.resize(pool_size)
	shader_material.set_shader_parameter("scales", scales)

	DropHandle.shader_material = shader_material
	for index in range(pool_size):
		drop_pool.append(DropHandle.new(index))

func drop_at(position: Vector2) -> void:
	if shader_material == null:
		return

	for drop: DropHandle in drop_pool:
		if drop.active:
			continue

		drop.start(position)
		var tween: Tween = create_tween()
		tween.tween_method(drop.animate, 0.0, 1.0, grow_time)
		tween.tween_method(drop.animate, 1.0, 0.0, fade_time).set_delay(fade_delay)
		tween.finished.connect(drop.end)
		return

class DropHandle:
	static var shader_material: ShaderMaterial

	var active: bool = false
	var index: int = -1

	func _init(drop_index: int) -> void:
		index = drop_index

	func start(position: Vector2) -> void:
		active = true
		var positions: PackedVector2Array = shader_material.get_shader_parameter("positions")
		if index < 0 or index >= positions.size():
			active = false
			return
		positions[index] = position
		shader_material.set_shader_parameter("positions", positions)

	func animate(value: float) -> void:
		var scales: PackedFloat32Array = shader_material.get_shader_parameter("scales")
		if index < 0 or index >= scales.size():
			return
		scales[index] = value
		shader_material.set_shader_parameter("scales", scales)

	func end() -> void:
		active = false
```
