## GameUiMotionUtility: 统一处理项目 UI 控件的轻量交互动效。
##
## 作为项目级 GFUtility，它负责按钮 hover、focus、press、面板入场和列表刷新表现，
## 不接管菜单业务、路由或输入语义。
class_name GameUiMotionUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal interactive_control_selected(control: Control)
signal interactive_control_confirmed(control: Control)


# --- 常量 ---

const _BOUND_META: StringName = &"_game_ui_motion_bound"
const _HOVERED_META: StringName = &"_game_ui_motion_hovered"
const _FOCUSED_META: StringName = &"_game_ui_motion_focused"
const _BASE_SCALE_META: StringName = &"_game_ui_motion_base_scale"
const _TWEEN_META: StringName = &"_game_ui_motion_tween"
const _CONTROL_BASE_POSITION_META: StringName = &"_game_ui_motion_control_base_position"
const _CONTROL_BASE_SCALE_META: StringName = &"_game_ui_motion_control_base_scale"
const _CONTROL_BASE_MODULATE_META: StringName = &"_game_ui_motion_control_base_modulate"
const _CONTROL_TWEEN_META: StringName = &"_game_ui_motion_control_tween"
const _STATIC_STYLE_META: StringName = &"_game_ui_motion_static_style"
const _BUTTON_FOCUS_RING_NODE_NAME: String = "ButtonFocusRing"
const _BUTTON_FOCUS_RING_SHADER: Shader = preload("res://asset_library/shaders/ui/button_focus_dash.gdshader")

const _REST_MODULATE: Color = Color.WHITE
const _HOVER_MODULATE: Color = Color(0.98, 1.0, 0.99, 1.0)
const _FOCUS_MODULATE: Color = Color(1.0, 0.98, 1.0, 1.0)
const _PRESS_MODULATE: Color = Color(0.96, 0.94, 0.84, 1.0)
const _BUTTON_NORMAL_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.96)
const _BUTTON_HOVER_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
const _BUTTON_PRESSED_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _BUTTON_FOCUS_BORDER_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _BUTTON_DISABLED_COLOR: Color = Color(0.95686275, 0.92941177, 0.8666667, 0.46)
const _BUTTON_FONT_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _BUTTON_FONT_DISABLED_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.42)
const _TEXT_PRIMARY_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _TEXT_SECONDARY_COLOR: Color = Color(0.4, 0.35686275, 0.32156864, 0.96)
const _FIELD_SURFACE_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.94)
const _FIELD_FOCUS_SURFACE_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.88)
const _FIELD_BORDER_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.72)
const _FIELD_FOCUS_BORDER_COLOR: Color = Color(0.8745098, 0.29411766, 0.6039216, 1.0)
const _PANEL_SURFACE_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.88)
const _HOVER_SCALE: float = 1.012
const _PRESS_SCALE: float = 0.980
const _HOVER_DURATION: float = 0.11
const _PRESS_DURATION: float = 0.055
const _PANEL_INTRO_OFFSET: Vector2 = Vector2(0.0, 10.0)
const _PANEL_INTRO_SCALE: float = 0.992
const _PANEL_INTRO_DURATION: float = 0.18
const _CHILD_REVEAL_OFFSET: Vector2 = Vector2(8.0, 0.0)
const _CHILD_REVEAL_DURATION: float = 0.14
const _CHILD_REVEAL_STAGGER: float = 0.025
const _FOCUS_RING_MARGIN: float = 3.0


# --- 私有变量 ---

var _button_normal_color: Color = _BUTTON_NORMAL_COLOR
var _button_hover_color: Color = _BUTTON_HOVER_COLOR
var _button_pressed_color: Color = _BUTTON_PRESSED_COLOR
var _button_focus_border_color: Color = _BUTTON_FOCUS_BORDER_COLOR
var _button_disabled_color: Color = _BUTTON_DISABLED_COLOR
var _button_font_color: Color = _BUTTON_FONT_COLOR
var _button_font_disabled_color: Color = _BUTTON_FONT_DISABLED_COLOR
var _text_primary_color: Color = _TEXT_PRIMARY_COLOR
var _text_secondary_color: Color = _TEXT_SECONDARY_COLOR
var _field_surface_color: Color = _FIELD_SURFACE_COLOR
var _field_focus_surface_color: Color = _FIELD_FOCUS_SURFACE_COLOR
var _field_border_color: Color = _FIELD_BORDER_COLOR
var _field_focus_border_color: Color = _FIELD_FOCUS_BORDER_COLOR
var _panel_surface_color: Color = _PANEL_SURFACE_COLOR
var _slider_track_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 0.42)
var _slider_grabber_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.92)
var _slider_grabber_highlight_color: Color = Color(0.8745098, 0.29411766, 0.6039216, 0.88)
var _button_focus_shader_profile: GFShaderParameterProfile
var _shader_parameters: GFShaderParameterUtility


# --- GF 生命周期方法 ---

func ready() -> void:
	_shader_parameters = _get_shader_parameter_utility()


func dispose() -> void:
	_button_focus_shader_profile = null
	_shader_parameters = null


func release_dependencies() -> void:
	_shader_parameters = null
	super.release_dependencies()


# --- 公共方法 ---

## 应用一套 UI 色板，后续绑定的控件会使用该色板。
## @param palette: 当前视觉主题提供的 UI 色板。
func apply_palette(palette: GameUiPalette) -> void:
	if not is_instance_valid(palette):
		_reset_palette()
		return

	_button_normal_color = palette.button_normal_color
	_button_hover_color = palette.button_hover_color
	_button_pressed_color = palette.button_pressed_color
	_button_focus_border_color = palette.button_focus_border_color
	_button_disabled_color = palette.button_disabled_color
	_button_font_color = palette.button_font_color
	_button_font_disabled_color = palette.button_font_disabled_color
	_text_primary_color = palette.text_primary_color
	_text_secondary_color = palette.text_secondary_color
	_field_surface_color = palette.field_surface_color
	_field_focus_surface_color = palette.field_focus_surface_color
	_field_border_color = palette.field_border_color
	_field_focus_border_color = palette.field_focus_border_color
	_panel_surface_color = palette.panel_surface_color
	_slider_track_color = palette.slider_track_color
	_slider_grabber_color = palette.slider_grabber_color
	_slider_grabber_highlight_color = palette.slider_grabber_highlight_color
	_button_focus_shader_profile = palette.button_focus_shader_profile


## 应用色板并刷新根节点下已存在的控件样式。
## @param root: 要扫描的 UI 根节点。
## @param palette: 当前视觉主题提供的 UI 色板。
## @return: 本次刷新的 Control 数量。
func apply_palette_to_tree(root: Node, palette: GameUiPalette) -> int:
	apply_palette(palette)
	return _refresh_palette_tree(root)


## 递归绑定根节点下所有 BaseButton 控件。
## @param root: 要扫描的 UI 根节点。
## @return: 本次新绑定的按钮数量。
func bind_interactive_controls(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	if root is Control:
		var root_control: Control = root
		_apply_support_control_style(root_control)

	var bound_count: int = 0
	if root is BaseButton:
		var root_button: BaseButton = root
		if _bind_button(root_button):
			bound_count += 1

	for child: Node in root.get_children():
		bound_count += bind_interactive_controls(child)

	return bound_count


## 绑定单个按钮控件。
## @param button: 要绑定交互动效的按钮。
## @return: 本次完成新绑定时返回 true。
func bind_button(button: BaseButton) -> bool:
	return _bind_button(button)


## 播放单个面板的入场动画。
## @param panel: 要播放入场动效的面板控件。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_panel_intro(panel: Control) -> Tween:
	return play_control_reveal(
		panel,
		_PANEL_INTRO_OFFSET,
		_PANEL_INTRO_DURATION,
		0.0,
		_PANEL_INTRO_SCALE
	)


## 播放单个控件的出现动画。
## @param control: 要播放出现动效的控件。
## @param offset: 动画起点相对于原始位置的偏移。
## @param duration: 动画持续时间。
## @param delay: 动画开始前的延迟时间。
## @param start_scale: 动画起点相对于原始缩放的倍率。
## @return: 创建成功时返回 Tween，否则返回 null。
func play_control_reveal(
	control: Control,
	offset: Vector2 = _CHILD_REVEAL_OFFSET,
	duration: float = _CHILD_REVEAL_DURATION,
	delay: float = 0.0,
	start_scale: float = 1.0
) -> Tween:
	return _play_control_reveal(control, offset, duration, delay, start_scale, true)


## 错峰播放容器直接子控件的出现动画。
## @param container: 要扫描直接子节点的容器。
## @param offset: 每个子控件动画起点相对于原始位置的偏移。
## @param stagger: 相邻子控件之间的延迟时间。
## @return: 本次播放动效的子控件数量。
func play_children_reveal(
	container: Node,
	offset: Vector2 = _CHILD_REVEAL_OFFSET,
	stagger: float = _CHILD_REVEAL_STAGGER
) -> int:
	if not is_instance_valid(container):
		return 0

	var animated_count: int = 0
	var animate_position: bool = not container is Container
	var reveal_offset: Vector2 = offset if animate_position else Vector2.ZERO
	for child: Node in container.get_children():
		if child is Control:
			var child_control: Control = child
			if not child_control.visible:
				continue
			var _reveal_tween: Tween = _play_control_reveal(
				child_control,
				reveal_offset,
				_CHILD_REVEAL_DURATION,
				float(animated_count) * stagger,
				1.0,
				animate_position
			)
			animated_count += 1

	return animated_count


# --- 私有/辅助方法 ---

func _bind_button(button: BaseButton) -> bool:
	if not is_instance_valid(button):
		return false
	if GFVariantData.to_bool(_get_button_meta(button, _BOUND_META, false)):
		return false

	button.set_meta(_BOUND_META, true)
	button.set_meta(_HOVERED_META, false)
	button.set_meta(_FOCUSED_META, false)
	button.set_meta(_BASE_SCALE_META, button.scale)
	button.call_deferred("set", "pivot_offset", button.size * 0.5)
	_apply_button_visual_style(button)
	var _focus_ring: ColorRect = _ensure_button_focus_ring(button)

	var _connect_result_157: int = button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
	var _connect_result_158: int = button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	var _connect_result_159: int = button.focus_entered.connect(_on_button_focus_entered.bind(button))
	var _connect_result_160: int = button.focus_exited.connect(_on_button_focus_exited.bind(button))
	var _connect_result_161: int = button.button_down.connect(_on_button_down.bind(button))
	var _connect_result_162: int = button.button_up.connect(_on_button_up.bind(button))
	var _connect_result_163: int = button.resized.connect(_on_button_resized.bind(button))
	var _connect_result_164: int = button.tree_exited.connect(_on_button_tree_exited.bind(button), CONNECT_ONE_SHOT)
	return true


func _apply_button_visual_style(button: BaseButton) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_create_button_style(_button_normal_color, _button_focus_border_color, 2)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_button_style(_button_hover_color, _button_focus_border_color, 2)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_button_style(_button_pressed_color, _button_focus_border_color, 3)
	)
	button.add_theme_stylebox_override(
		"focus",
		_create_button_style(Color.TRANSPARENT, _button_focus_border_color, 3)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_create_button_style(_button_disabled_color, _button_focus_border_color.darkened(0.12), 1)
	)
	button.add_theme_color_override("font_color", _button_font_color)
	button.add_theme_color_override("font_hover_color", _button_font_color)
	button.add_theme_color_override("font_pressed_color", _button_font_color)
	button.add_theme_color_override("font_focus_color", _button_font_color)
	button.add_theme_color_override("font_disabled_color", _button_font_disabled_color)
	_apply_button_focus_ring_style(button)


func _create_button_style(
	color: Color,
	border_color: Color = Color.TRANSPARENT,
	border_width: int = 0
) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	style.set_content_margin(SIDE_LEFT, 12.0)
	style.set_content_margin(SIDE_TOP, 8.0)
	style.set_content_margin(SIDE_RIGHT, 12.0)
	style.set_content_margin(SIDE_BOTTOM, 8.0)
	return style


func _ensure_button_focus_ring(button: BaseButton) -> ColorRect:
	if not is_instance_valid(button):
		return null

	var existing_node: Node = button.get_node_or_null(_BUTTON_FOCUS_RING_NODE_NAME)
	if existing_node is ColorRect:
		var existing_ring: ColorRect = existing_node
		_apply_button_focus_ring_style(button)
		return existing_ring

	var ring: ColorRect = ColorRect.new()
	ring.name = _BUTTON_FOCUS_RING_NODE_NAME
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	ring.color = Color.WHITE
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.offset_left = -_FOCUS_RING_MARGIN
	ring.offset_top = -_FOCUS_RING_MARGIN
	ring.offset_right = _FOCUS_RING_MARGIN
	ring.offset_bottom = _FOCUS_RING_MARGIN
	ring.z_index = 16

	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = _BUTTON_FOCUS_RING_SHADER
	ring.material = shader_material
	button.add_child(ring, false, Node.INTERNAL_MODE_FRONT)
	_apply_button_focus_ring_style(button)
	return ring


func _apply_button_focus_ring_style(button: BaseButton) -> void:
	var ring: ColorRect = _get_button_focus_ring(button)
	if not is_instance_valid(ring):
		return

	if not is_instance_valid(_shader_parameters):
		_shader_parameters = _get_shader_parameter_utility()
	if not is_instance_valid(_shader_parameters):
		push_error("[GameUiMotionUtility] 缺少 GFShaderParameterUtility，无法应用按钮焦点样式。")
		return

	if _button_focus_shader_profile != null:
		var _profile_count: int = _shader_parameters.apply_profile(
			ring,
			_button_focus_shader_profile,
			_get_shader_apply_options()
		)
	var _dynamic_count: int = _shader_parameters.apply_parameters(
		ring,
		{
			&"rect_size": button.size + Vector2.ONE * _FOCUS_RING_MARGIN * 2.0,
			&"color": _button_focus_border_color,
		},
		_get_shader_apply_options()
	)


func _get_button_focus_ring(button: BaseButton) -> ColorRect:
	if not is_instance_valid(button):
		return null

	var node: Node = button.get_node_or_null(_BUTTON_FOCUS_RING_NODE_NAME)
	if node is ColorRect:
		var ring: ColorRect = node
		return ring
	return null


func _set_button_focus_ring_visible(button: BaseButton, is_visible: bool) -> void:
	var ring: ColorRect = _get_button_focus_ring(button)
	if is_instance_valid(ring):
		ring.visible = is_visible


func _update_button_focus_ring_visibility(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		_set_button_focus_ring_visible(button, false)
		return

	_set_button_focus_ring_visible(button, _is_button_active(button))


func _apply_support_control_style(control: Control) -> void:
	if GFVariantData.to_bool(_get_control_meta(control, _STATIC_STYLE_META, false)):
		return

	control.set_meta(_STATIC_STYLE_META, true)
	if control is Label:
		var label: Label = control
		_style_label(label)
	elif control is RichTextLabel:
		var rich_text_label: RichTextLabel = control
		_style_rich_text_label(rich_text_label)
	elif control is SpinBox:
		var spin_box: SpinBox = control
		_style_spin_box(spin_box)
	elif control is LineEdit:
		var line_edit: LineEdit = control
		_style_line_edit(line_edit)
	elif control is Range:
		var range_control: Range = control
		_style_range(range_control)
	elif control is PanelContainer:
		var panel_container: PanelContainer = control
		_style_panel_container(panel_container)


func _style_label(label: Label) -> void:
	label.add_theme_color_override("font_color", _text_primary_color)


func _style_rich_text_label(label: RichTextLabel) -> void:
	label.add_theme_color_override("default_color", _text_secondary_color)
	label.add_theme_color_override("font_selected_color", _text_primary_color)


func _style_line_edit(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override(
		"normal",
		_create_field_style(_field_surface_color, _field_border_color, 1)
	)
	line_edit.add_theme_stylebox_override(
		"focus",
		_create_field_style(_field_focus_surface_color, _field_focus_border_color, 2)
	)
	line_edit.add_theme_stylebox_override(
		"read_only",
		_create_field_style(_field_surface_color.darkened(0.04), _field_border_color, 1)
	)
	line_edit.add_theme_color_override("font_color", _text_primary_color)
	line_edit.add_theme_color_override("font_placeholder_color", _text_secondary_color)
	line_edit.add_theme_color_override("caret_color", _field_focus_border_color)


func _style_spin_box(spin_box: SpinBox) -> void:
	spin_box.add_theme_color_override("font_color", _text_primary_color)
	spin_box.add_theme_color_override("font_disabled_color", _text_secondary_color)
	spin_box.add_theme_color_override("font_hover_color", _text_primary_color)
	spin_box.add_theme_color_override("font_focus_color", _text_primary_color)

	var line_edit: LineEdit = spin_box.get_line_edit()
	if is_instance_valid(line_edit):
		_style_line_edit(line_edit)


func _style_range(range_control: Range) -> void:
	range_control.add_theme_stylebox_override(
		"slider",
		_create_field_style(_slider_track_color, Color.TRANSPARENT, 0)
	)
	range_control.add_theme_stylebox_override(
		"grabber_area",
		_create_field_style(_slider_grabber_color, Color.TRANSPARENT, 0)
	)
	range_control.add_theme_stylebox_override(
		"grabber_area_highlight",
		_create_field_style(_slider_grabber_highlight_color, Color.TRANSPARENT, 0)
	)


func _style_panel_container(panel_container: PanelContainer) -> void:
	panel_container.add_theme_stylebox_override(
		"panel",
		_create_field_style(_panel_surface_color, _field_border_color, 1)
	)


func _create_field_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	style.set_content_margin(SIDE_LEFT, 10.0)
	style.set_content_margin(SIDE_TOP, 7.0)
	style.set_content_margin(SIDE_RIGHT, 10.0)
	style.set_content_margin(SIDE_BOTTOM, 7.0)
	return style


func _play_control_reveal(
	control: Control,
	offset: Vector2,
	duration: float,
	delay: float,
	start_scale: float,
	animate_position: bool
) -> Tween:
	if not is_instance_valid(control):
		return null

	_store_control_base_state(control, animate_position)
	_kill_control_tween(control)

	var base_position: Vector2 = control.position
	if animate_position:
		base_position = _get_control_vector2_meta(
			control,
			_CONTROL_BASE_POSITION_META,
			control.position
		)
	var base_scale: Vector2 = _get_control_vector2_meta(
		control,
		_CONTROL_BASE_SCALE_META,
		control.scale
	)
	var base_modulate: Color = _get_control_color_meta(
		control,
		_CONTROL_BASE_MODULATE_META,
		control.modulate
	)
	var start_modulate: Color = base_modulate
	start_modulate.a = 0.0

	if animate_position:
		control.position = base_position + offset
	control.scale = base_scale * start_scale
	control.modulate = start_modulate

	if not control.is_inside_tree():
		if animate_position:
			control.position = base_position
		control.scale = base_scale
		control.modulate = base_modulate
		return null

	var tween: Tween = control.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	if animate_position:
		var position_tweener: PropertyTweener = tween.tween_property(control, "position", base_position, duration)
		var _position_delay_result: Tweener = position_tweener.set_delay(delay)
	var scale_tweener: PropertyTweener = tween.tween_property(control, "scale", base_scale, duration)
	var _scale_delay_result: Tweener = scale_tweener.set_delay(delay)
	var modulate_tweener: PropertyTweener = tween.tween_property(control, "modulate", base_modulate, duration)
	var _modulate_delay_result: Tweener = modulate_tweener.set_delay(delay)
	control.set_meta(_CONTROL_TWEEN_META, tween)
	return tween


func _animate_button(
	button: BaseButton,
	scale_multiplier: float,
	modulate: Color,
	duration: float
) -> void:
	if not is_instance_valid(button):
		return

	_kill_button_tween(button)

	var base_scale: Vector2 = _get_button_base_scale(button)
	if not button.is_inside_tree():
		button.scale = base_scale * scale_multiplier
		button.modulate = modulate
		return

	var tween: Tween = button.create_tween()
	var _parallel_result: Tween = tween.set_parallel(true)
	var _transition_result: Tween = tween.set_trans(Tween.TRANS_CUBIC)
	var _ease_result: Tween = tween.set_ease(Tween.EASE_OUT)
	var _scale_tweener: PropertyTweener = tween.tween_property(button, "scale", base_scale * scale_multiplier, duration)
	var _modulate_tweener: PropertyTweener = tween.tween_property(button, "modulate", modulate, duration)
	button.set_meta(_TWEEN_META, tween)


func _restore_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if _is_button_active(button):
		_animate_button(button, _HOVER_SCALE, _get_active_modulate(button), _HOVER_DURATION)
	else:
		_animate_button(button, 1.0, _REST_MODULATE, _HOVER_DURATION)


func _is_button_active(button: BaseButton) -> bool:
	return (
		GFVariantData.to_bool(_get_button_meta(button, _HOVERED_META, false))
		or GFVariantData.to_bool(_get_button_meta(button, _FOCUSED_META, false))
	)


func _get_active_modulate(button: BaseButton) -> Color:
	if GFVariantData.to_bool(_get_button_meta(button, _FOCUSED_META, false)):
		return _FOCUS_MODULATE
	return _HOVER_MODULATE


func _get_button_base_scale(button: BaseButton) -> Vector2:
	var value: Variant = _get_button_meta(button, _BASE_SCALE_META, Vector2.ONE)
	if value is Vector2:
		return value
	return Vector2.ONE


func _kill_button_tween(button: BaseButton) -> void:
	var tween: Tween = _get_tween_value(_get_button_meta(button, _TWEEN_META, null))
	if tween != null and tween.is_valid():
		tween.kill()
	button.set_meta(_TWEEN_META, null)


func _get_button_meta(button: BaseButton, key: StringName, default_value: Variant) -> Variant:
	if is_instance_valid(button) and button.has_meta(key):
		return button.get_meta(key)
	return default_value


func _get_tween_value(value: Variant) -> Tween:
	if value is Tween:
		var tween: Tween = value
		return tween
	return null


func _store_control_base_state(control: Control, store_position: bool) -> void:
	if store_position and not control.has_meta(_CONTROL_BASE_POSITION_META):
		control.set_meta(_CONTROL_BASE_POSITION_META, control.position)
	if not control.has_meta(_CONTROL_BASE_SCALE_META):
		control.set_meta(_CONTROL_BASE_SCALE_META, control.scale)
	if not control.has_meta(_CONTROL_BASE_MODULATE_META):
		control.set_meta(_CONTROL_BASE_MODULATE_META, control.modulate)


func _kill_control_tween(control: Control) -> void:
	var tween: Tween = _get_tween_value(_get_control_meta(control, _CONTROL_TWEEN_META, null))
	if tween != null and tween.is_valid():
		tween.kill()
	control.set_meta(_CONTROL_TWEEN_META, null)


func _get_control_meta(control: Control, key: StringName, default_value: Variant) -> Variant:
	if is_instance_valid(control) and control.has_meta(key):
		return control.get_meta(key)
	return default_value


func _get_control_vector2_meta(control: Control, key: StringName, default_value: Vector2) -> Vector2:
	var value: Variant = _get_control_meta(control, key, default_value)
	if value is Vector2:
		return value
	return default_value


func _get_control_color_meta(control: Control, key: StringName, default_value: Color) -> Color:
	var value: Variant = _get_control_meta(control, key, default_value)
	if value is Color:
		return value
	return default_value


func _reset_palette() -> void:
	_button_normal_color = _BUTTON_NORMAL_COLOR
	_button_hover_color = _BUTTON_HOVER_COLOR
	_button_pressed_color = _BUTTON_PRESSED_COLOR
	_button_focus_border_color = _BUTTON_FOCUS_BORDER_COLOR
	_button_disabled_color = _BUTTON_DISABLED_COLOR
	_button_font_color = _BUTTON_FONT_COLOR
	_button_font_disabled_color = _BUTTON_FONT_DISABLED_COLOR
	_text_primary_color = _TEXT_PRIMARY_COLOR
	_text_secondary_color = _TEXT_SECONDARY_COLOR
	_field_surface_color = _FIELD_SURFACE_COLOR
	_field_focus_surface_color = _FIELD_FOCUS_SURFACE_COLOR
	_field_border_color = _FIELD_BORDER_COLOR
	_field_focus_border_color = _FIELD_FOCUS_BORDER_COLOR
	_panel_surface_color = _PANEL_SURFACE_COLOR
	_slider_track_color = Color(0.9372549, 0.81960785, 0.3647059, 0.42)
	_slider_grabber_color = Color(0.61960787, 0.85882354, 0.8352941, 0.92)
	_slider_grabber_highlight_color = Color(0.8745098, 0.29411766, 0.6039216, 0.88)
	_button_focus_shader_profile = null


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


func _refresh_palette_tree(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	var refreshed_count: int = 0
	if root is BaseButton:
		var button: BaseButton = root
		_apply_button_visual_style(button)
		var _focus_ring: ColorRect = _ensure_button_focus_ring(button)
		refreshed_count += 1
	elif root is Control:
		var control: Control = root
		control.set_meta(_STATIC_STYLE_META, false)
		_apply_support_control_style(control)
		refreshed_count += 1

	for child: Node in root.get_children():
		refreshed_count += _refresh_palette_tree(child)
	return refreshed_count


# --- 信号处理函数 ---

func _on_button_mouse_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_HOVERED_META, true)
	_update_button_focus_ring_visibility(button)
	interactive_control_selected.emit(button)
	_animate_button(button, _HOVER_SCALE, _HOVER_MODULATE, _HOVER_DURATION)


func _on_button_mouse_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_HOVERED_META, false)
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_focus_entered(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	button.set_meta(_FOCUSED_META, true)
	_update_button_focus_ring_visibility(button)
	interactive_control_selected.emit(button)
	_animate_button(button, _HOVER_SCALE, _FOCUS_MODULATE, _HOVER_DURATION)


func _on_button_focus_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta(_FOCUSED_META, false)
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_down(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_set_button_focus_ring_visible(button, true)
	interactive_control_confirmed.emit(button)
	_animate_button(button, _PRESS_SCALE, _PRESS_MODULATE, _PRESS_DURATION)


func _on_button_up(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_update_button_focus_ring_visibility(button)
	_restore_button(button)


func _on_button_resized(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_apply_button_focus_ring_style(button)


func _on_button_tree_exited(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_tween(button)
