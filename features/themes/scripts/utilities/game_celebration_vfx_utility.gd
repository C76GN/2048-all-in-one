## GameCelebrationVfxUtility: 统一播放目标达成、新纪录等全屏庆祝反馈。
class_name GameCelebrationVfxUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const _LAYER_NAME: String = "GameCelebrationVfxLayer"
const _RECT_NAME_PREFIX: String = "CelebrationConfetti"
const _LAYER_INDEX: int = 960
const _DRAINING_META: StringName = &"celebration_draining"
const _MIN_DRAIN_SECONDS: float = 1.5
const _MAX_DRAIN_SECONDS: float = 14.0


# --- 私有变量 ---

var _asset_library: GameAssetLibraryUtility = null
var _clock_utility: GameClockUtility = null
var _shader_parameters: GFShaderParameterUtility = null
var _theme: GameCelebrationVfxTheme = null
var _layer: CanvasLayer = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameAssetLibraryUtility, GameClockUtility, GFShaderParameterUtility]


func ready() -> void:
	_asset_library = _get_asset_library_utility()
	_clock_utility = _get_clock_utility()
	_shader_parameters = _get_shader_parameter_utility()
	if not is_instance_valid(_asset_library):
		push_error("[GameCelebrationVfxUtility] 缺少 GameAssetLibraryUtility。")
	if not is_instance_valid(_clock_utility):
		push_error("[GameCelebrationVfxUtility] 缺少 GameClockUtility。")
	if not is_instance_valid(_shader_parameters):
		push_error("[GameCelebrationVfxUtility] 缺少 GFShaderParameterUtility。")


func dispose() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_asset_library = null
	_clock_utility = null
	_shader_parameters = null
	_theme = null


func release_dependencies() -> void:
	_asset_library = null
	_clock_utility = null
	_shader_parameters = null
	super.release_dependencies()


# --- 公共方法 ---

## 应用当前视觉主题提供的庆祝特效配置。
## @param theme: 要应用的庆祝特效主题。
func apply_theme(theme: GameCelebrationVfxTheme) -> bool:
	if not is_instance_valid(theme):
		push_error("[GameCelebrationVfxUtility] 庆祝特效主题无效。")
		return false
	var report: GFValidationReport = theme.get_validation_report()
	if not report.is_ok():
		for issue: GFValidationIssue in report.issues:
			if issue != null and issue.is_error():
				push_error("[GameCelebrationVfxUtility] %s" % issue.message)
		return false
	_theme = theme
	return true


## 获取当前生效的庆祝特效主题。
func get_theme() -> GameCelebrationVfxTheme:
	return _theme


func play_target_reached_celebration() -> bool:
	return _play_confetti(GameCelebrationVfxTheme.EVENT_TARGET_REACHED)


func play_new_record_celebration() -> bool:
	return _play_confetti(GameCelebrationVfxTheme.EVENT_NEW_RECORD)


## 停止产生新的纸屑周期，并让当前纸屑自然落出屏幕后回收。
func drain_active_celebrations() -> void:
	if not is_instance_valid(_layer):
		return
	for child: Node in _layer.get_children():
		if not child is ColorRect or not child.name.begins_with(_RECT_NAME_PREFIX):
			continue
		var rect: ColorRect = child
		if GFVariantData.to_bool(rect.get_meta(_DRAINING_META, false), false):
			continue
		_begin_rect_drain(rect)
		_queue_rect_cleanup(rect, _get_rect_drain_seconds(rect))


# --- 私有/辅助方法 ---

func _play_confetti(event_id: StringName) -> bool:
	if not is_instance_valid(_theme):
		push_error("[GameCelebrationVfxUtility] 尚未应用庆祝特效主题。")
		return false
	var preset: GameCelebrationVfxPreset = _theme.get_preset(event_id)
	if not is_instance_valid(preset):
		push_error("[GameCelebrationVfxUtility] 主题缺少庆祝事件 preset：%s。" % String(event_id))
		return false
	if not is_instance_valid(_shader_parameters):
		_shader_parameters = _get_shader_parameter_utility()
	if not is_instance_valid(_shader_parameters):
		push_error("[GameCelebrationVfxUtility] 缺少 GFShaderParameterUtility。")
		return false
	var confetti_shader: Shader = _load_confetti_shader(_theme.shader_asset_key)
	if not is_instance_valid(confetti_shader):
		push_error(
			"[GameCelebrationVfxUtility] 无法通过素材键加载庆祝 shader：%s。"
			% String(_theme.shader_asset_key)
		)
		return false

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
	rect.modulate = Color(1.0, 1.0, 1.0, preset.opacity)
	layer.add_child(rect)

	var viewport_size: Vector2 = _sync_rect_to_viewport(rect)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = confetti_shader
	rect.material = material
	var profile_count: int = _shader_parameters.apply_profile(
		material,
		_theme.shader_parameter_profile,
		_get_shader_apply_options()
	)
	if profile_count != _theme.shader_parameter_profile.get_parameter_names().size():
		rect.queue_free()
		return false

	var event_parameters: Dictionary = preset.get_shader_parameters()
	event_parameters[&"resolution"] = viewport_size
	event_parameters[&"drain_started_at"] = -1.0
	var event_parameter_count: int = _shader_parameters.apply_parameters(
		material,
		event_parameters,
		_get_shader_apply_options()
	)
	if event_parameter_count != event_parameters.size():
		rect.queue_free()
		return false

	if not preset.loop_until_dismissed:
		_queue_rect_drain(rect, preset.duration)
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


func _queue_rect_drain(rect: ColorRect, duration: float) -> void:
	var tween: Tween = rect.create_tween()
	var _interval_tweener: IntervalTweener = tween.tween_interval(maxf(duration, 0.0))
	var _drain_callback: CallbackTweener = tween.tween_callback(_begin_rect_drain.bind(rect))
	var _drain_interval: IntervalTweener = tween.tween_interval(_get_rect_drain_seconds(rect))
	var _callback_tweener: CallbackTweener = tween.tween_callback(rect.queue_free)


func _begin_rect_drain(rect: ColorRect) -> void:
	if not is_instance_valid(rect):
		return
	if GFVariantData.to_bool(rect.get_meta(_DRAINING_META, false), false):
		return
	if not is_instance_valid(_clock_utility):
		_clock_utility = _get_clock_utility()
	if not is_instance_valid(_clock_utility):
		push_error("[GameCelebrationVfxUtility] 缺少 GameClockUtility，无法开始纸屑清退。")
		return
	rect.set_meta(_DRAINING_META, true)
	if rect.material is ShaderMaterial:
		var material: ShaderMaterial = rect.material
		material.set_shader_parameter(
			&"drain_started_at",
			float(_clock_utility.get_tick_msec()) / 1000.0
		)


func _queue_rect_cleanup(rect: ColorRect, delay_seconds: float) -> void:
	if not is_instance_valid(rect):
		return
	var tween: Tween = rect.create_tween()
	var _interval_tweener: IntervalTweener = tween.tween_interval(delay_seconds)
	var _callback_tweener: CallbackTweener = tween.tween_callback(rect.queue_free)


func _get_rect_drain_seconds(rect: ColorRect) -> float:
	var viewport_height: float = _sync_rect_to_viewport(rect).y
	var speed: float = 105.0
	var piece_size: float = 7.0
	if is_instance_valid(rect) and rect.material is ShaderMaterial:
		var material: ShaderMaterial = rect.material
		speed = GFVariantData.to_float(material.get_shader_parameter(&"speed"), speed)
		piece_size = GFVariantData.to_float(
			material.get_shader_parameter(&"piece_size"),
			piece_size
		)
	var slowest_particle_speed: float = maxf(speed * 0.5, 1.0)
	var drain_seconds: float = (viewport_height + piece_size * 4.0) / slowest_particle_speed
	return clampf(drain_seconds + 0.25, _MIN_DRAIN_SECONDS, _MAX_DRAIN_SECONDS)


func _load_confetti_shader(asset_key: StringName) -> Shader:
	var asset_library: GameAssetLibraryUtility = _get_cached_asset_library_utility()
	if not is_instance_valid(asset_library):
		return null
	var resource: Resource = asset_library.load_asset(asset_key, "Shader")
	if resource is Shader:
		var shader: Shader = resource
		return shader
	return null


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


func _get_clock_utility() -> GameClockUtility:
	var utility_value: Object = get_utility(GameClockUtility)
	if utility_value is GameClockUtility:
		var clock_utility: GameClockUtility = utility_value
		return clock_utility
	return null


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		var shader_utility: GFShaderParameterUtility = utility_value
		return shader_utility
	return null


func _get_shader_apply_options() -> Dictionary:
	return {
		"duplicate_material": false,
		"require_declared_parameters": true,
		"warn_on_invalid_target": true,
		"warn_on_missing_parameters": true,
		"copy_values": true,
	}


func _get_scene_tree() -> SceneTree:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		return tree
	return null
