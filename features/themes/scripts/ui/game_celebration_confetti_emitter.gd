## GameCelebrationConfettiEmitter: 有界、按粒子执行的庆祝纸屑发射器。
##
## 用最多几十个 GPUParticles2D 实例替代全屏片元 shader 中的粒子循环，
## 复杂度从“屏幕像素数 × 粒子数”降为“粒子数 + 可见纸片像素数”。
class_name GameCelebrationConfettiEmitter
extends GPUParticles2D


# --- 常量 ---

const _DRAINING_META: StringName = &"celebration_draining"
const _MIN_DRAIN_SECONDS: float = 1.5
const _MAX_DRAIN_SECONDS: float = 14.0
const _DEFAULT_ASPECT_RATIO: float = 1.85
const _DEFAULT_SPIN_SPEED: float = 2.8


# --- 公共只读配置 ---

var configured_speed: float = 105.0
var configured_sway_strength: float = 38.0
var configured_piece_size: float = 7.0
var configured_particle_count: int = 0


# --- 私有变量 ---

var _application_focused: bool = true
var _drain_seconds: float = _MIN_DRAIN_SECONDS


# --- 生命周期方法 ---

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_refresh_speed_scale()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_application_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_application_focused(true)


# --- 公共方法 ---

## 配置并启动一次主题化纸屑发射。
## @param viewport_size: 当前逻辑视口尺寸。
## @param particle_count: 本次庆祝使用的粒子数量。
## @param event_parameters: 当前庆祝事件的规范表现参数。
## @param draw_shader: 用于绘制纸屑图元的已加载 Shader。
## @param opacity: 纸屑层的整体不透明度。
func configure(
	viewport_size: Vector2,
	particle_count: int,
	event_parameters: Dictionary,
	draw_shader: Shader,
	opacity: float
) -> bool:
	if particle_count <= 0 or not is_instance_valid(draw_shader):
		return false

	configured_particle_count = particle_count
	configured_speed = maxf(
		GFVariantData.get_option_float(event_parameters, "speed", 105.0),
		1.0
	)
	configured_sway_strength = maxf(
		GFVariantData.get_option_float(event_parameters, "sway_strength", 38.0),
		0.0
	)
	configured_piece_size = maxf(
		GFVariantData.get_option_float(event_parameters, "piece_size", 7.0),
		2.0
	)
	var aspect_ratio: float = maxf(
		GFVariantData.get_option_float(
			event_parameters,
			"aspect_ratio",
			_DEFAULT_ASPECT_RATIO
		),
		0.2
	)
	var spin_speed: float = maxf(
		GFVariantData.get_option_float(
			event_parameters,
			"spin_speed",
			_DEFAULT_SPIN_SPEED
		),
		0.0
	)
	var safe_viewport_size: Vector2 = Vector2(
		maxf(viewport_size.x, 1.0),
		maxf(viewport_size.y, 1.0)
	)

	amount = particle_count
	lifetime = _calculate_drain_seconds(safe_viewport_size.y)
	_drain_seconds = lifetime
	preprocess = lifetime
	randomness = 1.0
	fixed_fps = 30
	interpolate = true
	fract_delta = true
	local_coords = true
	draw_order = GPUParticles2D.DRAW_ORDER_LIFETIME
	visibility_rect = Rect2(
		-safe_viewport_size.x * 0.5 - configured_piece_size * 4.0,
		-configured_piece_size * 4.0,
		safe_viewport_size.x + configured_piece_size * 8.0,
		safe_viewport_size.y + configured_piece_size * 8.0
	)
	position = Vector2(safe_viewport_size.x * 0.5, -configured_piece_size * 2.0)
	texture = _create_piece_texture(configured_piece_size, aspect_ratio)
	process_material = _create_process_material(
		safe_viewport_size,
		spin_speed
	)
	var draw_material: ShaderMaterial = ShaderMaterial.new()
	draw_material.shader = draw_shader
	material = draw_material
	modulate = Color(1.0, 1.0, 1.0, clampf(opacity, 0.0, 1.0))
	set_meta(_DRAINING_META, false)
	restart()
	emitting = true
	_refresh_speed_scale()
	return true


func begin_drain() -> void:
	if GFVariantData.to_bool(get_meta(_DRAINING_META, false), false):
		return
	set_meta(_DRAINING_META, true)
	emitting = false


func is_draining() -> bool:
	return GFVariantData.to_bool(get_meta(_DRAINING_META, false), false)


func get_drain_seconds() -> float:
	return _drain_seconds


## 显式同步应用聚焦状态，确保恢复焦点时不会跳过纸屑生命周期。
## @param focused: 应用当前是否拥有输入焦点。
func set_application_focused(focused: bool) -> void:
	_application_focused = focused
	_refresh_speed_scale()


func is_application_focused() -> bool:
	return _application_focused


# --- 私有/辅助方法 ---

func _create_process_material(
	viewport_size: Vector2,
	spin_speed: float
) -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.particle_flag_disable_z = true
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = clampf(
		rad_to_deg(atan(configured_sway_strength / configured_speed)),
		3.0,
		28.0
	)
	process.gravity = Vector3(0.0, configured_speed * 0.08, 0.0)
	process.initial_velocity_min = configured_speed * 0.65
	process.initial_velocity_max = configured_speed * 1.15
	process.angular_velocity_min = -spin_speed * 57.2958
	process.angular_velocity_max = spin_speed * 57.2958
	process.scale_min = 0.70
	process.scale_max = 1.25
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		viewport_size.x * 0.5,
		configured_piece_size,
		1.0
	)
	process.color_initial_ramp = _create_palette_selector_texture()
	return process


func _create_palette_selector_texture() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	for index: int in range(8):
		var coordinate: float = (float(index) + 0.5) / 8.0
		var _offset_appended: bool = offsets.append(float(index) / 7.0)
		var _color_appended: bool = colors.append(
			Color(coordinate, 0.0, 0.0, 1.0)
		)
	gradient.offsets = offsets
	gradient.colors = colors
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var texture_1d: GradientTexture1D = GradientTexture1D.new()
	texture_1d.gradient = gradient
	texture_1d.width = 64
	return texture_1d


func _create_piece_texture(piece_size: float, aspect_ratio: float) -> ImageTexture:
	var width: int = maxi(roundi(piece_size * aspect_ratio * 2.0), 2)
	var height: int = maxi(roundi(piece_size * 2.0), 2)
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _calculate_drain_seconds(viewport_height: float) -> float:
	var slowest_particle_speed: float = maxf(configured_speed * 0.65, 1.0)
	var travel_distance: float = viewport_height + configured_piece_size * 4.0
	return clampf(
		travel_distance / slowest_particle_speed + 0.25,
		_MIN_DRAIN_SECONDS,
		_MAX_DRAIN_SECONDS
	)


func _refresh_speed_scale() -> void:
	speed_scale = 1.0 if _application_focused else 0.0
