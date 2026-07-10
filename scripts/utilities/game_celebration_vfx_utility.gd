## GameCelebrationVfxUtility: 统一播放目标达成、新纪录等全屏庆祝反馈。
class_name GameCelebrationVfxUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const CELEBRATION_CONFETTI_ASSET_KEY: StringName = &"asset.vfx.celebration.confetti_canvas"

const _FALLBACK_CONFETTI_SHADER: Shader = preload("res://asset_library/vfx/celebration_confetti_canvas.gdshader")
const _LAYER_NAME: String = "GameCelebrationVfxLayer"
const _RECT_NAME_PREFIX: String = "CelebrationConfetti"
const _LAYER_INDEX: int = 960
const _TARGET_REACHED_DURATION: float = 1.45
const _NEW_RECORD_DURATION: float = 2.05
const _FADE_OUT_SECONDS: float = 0.34


# --- 私有变量 ---

var _asset_library: GameAssetLibraryUtility = null
var _layer: CanvasLayer = null


# --- GF 生命周期方法 ---

func ready() -> void:
	_asset_library = _get_asset_library_utility()


func dispose() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_asset_library = null


func release_dependencies() -> void:
	_asset_library = null
	super.release_dependencies()


# --- 公共方法 ---

func play_target_reached_celebration() -> bool:
	return _play_confetti(_TARGET_REACHED_DURATION, 0.74, 94.0, 34.0, 6.2)


func play_new_record_celebration() -> bool:
	return _play_confetti(_NEW_RECORD_DURATION, 0.86, 118.0, 46.0, 7.5)


# --- 私有/辅助方法 ---

func _play_confetti(
	duration: float,
	opacity: float,
	speed: float,
	sway_strength: float,
	piece_size: float
) -> bool:
	var layer: CanvasLayer = _ensure_layer()
	if not is_instance_valid(layer):
		return false

	var rect: ColorRect = ColorRect.new()
	rect.name = "%s%d" % [_RECT_NAME_PREFIX, layer.get_child_count()]
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.process_mode = Node.PROCESS_MODE_ALWAYS
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.color = Color.WHITE
	rect.modulate = Color(1.0, 1.0, 1.0, opacity)
	layer.add_child(rect)

	var viewport_size: Vector2 = _sync_rect_to_viewport(rect)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _load_confetti_shader()
	material.set_shader_parameter("resolution", viewport_size)
	material.set_shader_parameter("speed", speed)
	material.set_shader_parameter("sway_strength", sway_strength)
	material.set_shader_parameter("piece_size", piece_size)
	rect.material = material

	_queue_rect_fade_out(rect, duration)
	return true


func _ensure_layer() -> CanvasLayer:
	if is_instance_valid(_layer):
		return _layer

	var tree: SceneTree = _get_scene_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return null

	var existing: Node = tree.root.get_node_or_null(_LAYER_NAME)
	if existing is CanvasLayer:
		_layer = existing
	else:
		_layer = CanvasLayer.new()
		_layer.name = _LAYER_NAME
		_layer.layer = _LAYER_INDEX
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_layer)

	return _layer


func _sync_rect_to_viewport(rect: ColorRect) -> Vector2:
	var viewport_size: Vector2 = Vector2(1280.0, 720.0)
	if is_instance_valid(rect):
		var viewport_rect: Rect2 = rect.get_viewport_rect()
		if viewport_rect.size.x > 0.0 and viewport_rect.size.y > 0.0:
			viewport_size = viewport_rect.size
	return viewport_size


func _queue_rect_fade_out(rect: ColorRect, duration: float) -> void:
	var tween: Tween = rect.create_tween()
	var _parallel_result: Tween = tween.set_parallel(false)
	var _interval_tweener: IntervalTweener = tween.tween_interval(maxf(duration - _FADE_OUT_SECONDS, 0.0))
	var _fade_tweener: PropertyTweener = tween.tween_property(rect, "modulate:a", 0.0, _FADE_OUT_SECONDS)
	var _callback_tweener: CallbackTweener = tween.tween_callback(rect.queue_free)


func _load_confetti_shader() -> Shader:
	var asset_library: GameAssetLibraryUtility = _get_cached_asset_library_utility()
	if is_instance_valid(asset_library):
		var resource: Resource = asset_library.load_asset(CELEBRATION_CONFETTI_ASSET_KEY, "Shader")
		if resource is Shader:
			var shader: Shader = resource
			return shader
	return _FALLBACK_CONFETTI_SHADER


func _get_cached_asset_library_utility() -> GameAssetLibraryUtility:
	if is_instance_valid(_asset_library):
		return _asset_library
	_asset_library = _get_asset_library_utility()
	return _asset_library


func _get_asset_library_utility() -> GameAssetLibraryUtility:
	var utility_value: Object = get_utility(GameAssetLibraryUtility)
	if utility_value is GameAssetLibraryUtility:
		var asset_library: GameAssetLibraryUtility = utility_value
		return asset_library
	return null


func _get_scene_tree() -> SceneTree:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		return tree
	return null
