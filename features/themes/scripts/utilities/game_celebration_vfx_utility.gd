## GameCelebrationVfxUtility: 统一播放目标达成、新纪录等全屏庆祝反馈。
class_name GameCelebrationVfxUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const _LAYER_NAME: String = "GameCelebrationVfxLayer"
const _NODE_NAME_PREFIX: String = "CelebrationConfetti"
# GF UI 的默认 HUD/POPUP CanvasLayer 分别为 50/60。庆祝反馈应覆盖 HUD，
# 但绝不能遮挡结算、暂停等 POPUP 的摘要与操作按钮。
const _LAYER_INDEX: int = 55
const _STATIC_FALLBACK_META: StringName = &"celebration_static_fallback"
const _CLEANUP_QUEUED_META: StringName = &"celebration_cleanup_queued"


# --- 私有变量 ---

var _asset_library: GameAssetLibraryUtility = null
var _shader_parameters: GFShaderParameterUtility = null
var _accessibility: GameAccessibilityUtility = null
var _timer_utility: GFTimerUtility = null
var _theme: GameCelebrationVfxTheme = null
var _layer: CanvasLayer = null


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [
		GameAssetLibraryUtility,
		GFShaderParameterUtility,
		GameAccessibilityUtility,
		GFTimerUtility,
	]


func ready() -> void:
	_asset_library = _get_asset_library_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_accessibility = _get_accessibility_utility()
	_timer_utility = _get_timer_utility()
	if not is_instance_valid(_asset_library):
		push_error("[GameCelebrationVfxUtility] 缺少 GameAssetLibraryUtility。")
	if not is_instance_valid(_shader_parameters):
		push_error("[GameCelebrationVfxUtility] 缺少 GFShaderParameterUtility。")
	if not is_instance_valid(_timer_utility):
		push_error("[GameCelebrationVfxUtility] 缺少 GFTimerUtility。")


func dispose() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_asset_library = null
	_shader_parameters = null
	_accessibility = null
	_timer_utility = null
	_theme = null


func release_dependencies() -> void:
	_asset_library = null
	_shader_parameters = null
	_accessibility = null
	_timer_utility = null
	super.release_dependencies()


# --- 公共方法 ---

## 应用当前视觉主题提供的庆祝特效配置。
## @param theme: 已验证的庆祝特效主题资源。
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


func get_theme() -> GameCelebrationVfxTheme:
	return _theme


func play_target_reached_celebration() -> bool:
	return _play_confetti(GameCelebrationVfxTheme.EVENT_TARGET_REACHED)


func play_new_record_celebration() -> bool:
	return _play_confetti(GameCelebrationVfxTheme.EVENT_NEW_RECORD)


## 停止产生新纸屑，让已经生成的有界粒子自然落出屏幕后回收。
func drain_active_celebrations() -> void:
	if not is_instance_valid(_layer):
		return
	for child: Node in _layer.get_children():
		if not child.name.begins_with(_NODE_NAME_PREFIX):
			continue
		if child is GameCelebrationConfettiEmitter:
			var emitter: GameCelebrationConfettiEmitter = child
			if emitter.is_draining():
				continue
			emitter.begin_drain()
			_queue_emitter_cleanup(emitter)
		elif child is ColorRect:
			var static_rect: ColorRect = child
			static_rect.queue_free()


# --- 私有/辅助方法 ---

func _play_confetti(event_id: StringName) -> bool:
	if not is_instance_valid(_theme):
		push_error("[GameCelebrationVfxUtility] 尚未应用庆祝特效主题。")
		return false
	var preset: GameCelebrationVfxPreset = _theme.get_preset(event_id)
	if not is_instance_valid(preset):
		push_error(
			"[GameCelebrationVfxUtility] 主题缺少庆祝事件 preset：%s。"
			% String(event_id)
		)
		return false
	var state: GameAccessibilityState = _get_accessibility_state()
	var budget: GameFeedbackBudget = GameFeedbackPerformanceMatrix.resolve(state)
	var layer: CanvasLayer = _ensure_layer()
	if not is_instance_valid(layer):
		return false
	if (
		not budget.celebration_shader_enabled
		or budget.celebration_particle_count <= 0
	):
		return _play_static_celebration(layer, preset)
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

	var emitter: GameCelebrationConfettiEmitter = (
		GameCelebrationConfettiEmitter.new()
	)
	emitter.name = "%s%d" % [_NODE_NAME_PREFIX, layer.get_child_count()]
	layer.add_child(emitter)
	var configured: bool = emitter.configure(
		_get_viewport_size(layer),
		budget.celebration_particle_count,
		preset.get_shader_parameters(),
		confetti_shader,
		preset.opacity
	)
	if not configured:
		emitter.queue_free()
		return false

	var profile_count: int = _shader_parameters.apply_profile(
		emitter,
		_theme.shader_parameter_profile,
		_get_shader_apply_options()
	)
	if profile_count != _theme.shader_parameter_profile.get_parameter_names().size():
		emitter.queue_free()
		return false
	if not preset.loop_until_dismissed:
		_queue_emitter_drain(emitter, preset.duration)
	return true


func _play_static_celebration(
	layer: CanvasLayer,
	preset: GameCelebrationVfxPreset
) -> bool:
	var rect: ColorRect = ColorRect.new()
	rect.name = "%s%d" % [_NODE_NAME_PREFIX, layer.get_child_count()]
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.process_mode = Node.PROCESS_MODE_DISABLED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.set_meta(_STATIC_FALLBACK_META, true)
	rect.color = preset.fallback_color
	rect.modulate = Color(1.0, 1.0, 1.0, preset.opacity)
	layer.add_child(rect)
	if not preset.loop_until_dismissed:
		_queue_static_cleanup(rect, minf(preset.duration, 0.45))
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
		_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
		tree.root.add_child(_layer)
	return _layer


func _queue_emitter_drain(
	emitter: GameCelebrationConfettiEmitter,
	delay_seconds: float
) -> void:
	if not is_instance_valid(emitter) or not is_instance_valid(_timer_utility):
		return
	var _timer_handle: int = _timer_utility.execute_after_owned(
		emitter,
		maxf(delay_seconds, 0.0),
		_on_emitter_drain_timeout.bind(emitter)
	)


func _on_emitter_drain_timeout(
	emitter: GameCelebrationConfettiEmitter
) -> void:
	if not is_instance_valid(emitter):
		return
	emitter.begin_drain()
	_queue_emitter_cleanup(emitter)


func _queue_emitter_cleanup(emitter: GameCelebrationConfettiEmitter) -> void:
	if (
		not is_instance_valid(emitter)
		or GFVariantData.to_bool(
			emitter.get_meta(_CLEANUP_QUEUED_META, false),
			false
		)
	):
		return
	emitter.set_meta(_CLEANUP_QUEUED_META, true)
	if not is_instance_valid(_timer_utility):
		emitter.queue_free()
		return
	var _timer_handle: int = _timer_utility.execute_after_owned(
		emitter,
		emitter.get_drain_seconds(),
		_queue_free_if_valid.bind(emitter)
	)


func _queue_static_cleanup(rect: ColorRect, delay_seconds: float) -> void:
	if not is_instance_valid(rect) or not is_instance_valid(_timer_utility):
		return
	var _timer_handle: int = _timer_utility.execute_after_owned(
		rect,
		maxf(delay_seconds, 0.0),
		_queue_free_if_valid.bind(rect)
	)


func _queue_free_if_valid(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _get_viewport_size(layer: CanvasLayer) -> Vector2:
	if is_instance_valid(layer):
		var viewport: Viewport = layer.get_viewport()
		if is_instance_valid(viewport):
			var viewport_size: Vector2 = viewport.get_visible_rect().size
			if viewport_size.x > 0.0 and viewport_size.y > 0.0:
				return viewport_size
	return Vector2(1280.0, 720.0)


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


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		var shader_utility: GFShaderParameterUtility = utility_value
		return shader_utility
	return null


func _get_accessibility_state() -> GameAccessibilityState:
	if not is_instance_valid(_accessibility):
		_accessibility = _get_accessibility_utility()
	return (
		_accessibility.get_state()
		if is_instance_valid(_accessibility)
		else GameAccessibilityState.new()
	)


func _get_accessibility_utility() -> GameAccessibilityUtility:
	var utility_value: Object = get_utility(GameAccessibilityUtility)
	if utility_value is GameAccessibilityUtility:
		var utility: GameAccessibilityUtility = utility_value
		return utility
	return null


func _get_timer_utility() -> GFTimerUtility:
	var utility_value: Object = get_utility(GFTimerUtility)
	if utility_value is GFTimerUtility:
		var timer_utility: GFTimerUtility = utility_value
		return timer_utility
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
