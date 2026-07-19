## GameUiStyleUtility: 统一应用主题色板、控件 StyleBox 与焦点表现。
class_name GameUiStyleUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 枚举 ---

## 文本在主题色板中的语义角色。
enum TextRole {
	PRIMARY,
	SECONDARY,
	MUTED,
	FEEDBACK,
}

## 面板表面的语义角色。
enum SurfaceRole {
	PANEL,
	FIELD,
	SELECTED,
}

## 面板边框的语义角色。
enum BorderRole {
	DEFAULT,
	FOCUS,
	SELECTED,
}


# --- 常量 ---

const _STATIC_STYLE_META: StringName = &"_game_ui_style_applied"
const _TEXT_ROLE_META: StringName = &"_game_ui_style_text_role"
const _TEXT_FONT_SIZE_META: StringName = &"_game_ui_style_text_font_size"
const _TEXT_SHADOW_META: StringName = &"_game_ui_style_text_shadow"
const _SURFACE_ROLE_META: StringName = &"_game_ui_style_surface_role"
const _BORDER_ROLE_META: StringName = &"_game_ui_style_border_role"
const _BORDER_WIDTH_META: StringName = &"_game_ui_style_border_width"
const _BUTTON_FOCUS_RING_NODE_NAME: String = "ButtonFocusRing"
const _BUTTON_FOCUS_RING_SHADER_ASSET_KEY: StringName = &"asset.shader.ui.button_focus_dash"

const _BUTTON_NORMAL_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.96)
const _BUTTON_HOVER_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
const _BUTTON_PRESSED_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _BUTTON_FOCUS_BORDER_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _BUTTON_DISABLED_COLOR: Color = Color(0.95686275, 0.92941177, 0.8666667, 0.46)
const _BUTTON_FONT_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _BUTTON_FONT_DISABLED_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.42)
const _TEXT_PRIMARY_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _TEXT_SECONDARY_COLOR: Color = Color(0.4, 0.35686275, 0.32156864, 0.96)
const _TEXT_SHADOW_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.52)
const _FIELD_SURFACE_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.94)
const _FIELD_FOCUS_SURFACE_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.88)
const _FIELD_BORDER_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 0.72)
const _FIELD_FOCUS_BORDER_COLOR: Color = Color(0.8745098, 0.29411766, 0.6039216, 1.0)
const _PANEL_SURFACE_COLOR: Color = Color(1.0, 0.972549, 0.9098039, 0.88)
const _SELECTED_SURFACE_COLOR: Color = Color(0.8745098, 0.29411766, 0.6039216, 0.72)
const _SELECTED_BORDER_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
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
var _text_shadow_color: Color = _TEXT_SHADOW_COLOR
var _field_surface_color: Color = _FIELD_SURFACE_COLOR
var _field_focus_surface_color: Color = _FIELD_FOCUS_SURFACE_COLOR
var _field_border_color: Color = _FIELD_BORDER_COLOR
var _field_focus_border_color: Color = _FIELD_FOCUS_BORDER_COLOR
var _panel_surface_color: Color = _PANEL_SURFACE_COLOR
var _selected_surface_color: Color = _SELECTED_SURFACE_COLOR
var _selected_border_color: Color = _SELECTED_BORDER_COLOR
var _slider_track_color: Color = Color(0.9372549, 0.81960785, 0.3647059, 0.42)
var _slider_grabber_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 0.92)
var _slider_grabber_highlight_color: Color = Color(0.8745098, 0.29411766, 0.6039216, 0.88)
var _button_focus_shader_profile: GFShaderParameterProfile
var _asset_library: GameAssetLibraryUtility
var _button_focus_ring_shader: Shader
var _shader_parameters: GFShaderParameterUtility


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GameAssetLibraryUtility, GFShaderParameterUtility]


func ready() -> void:
	_asset_library = _get_asset_library_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_button_focus_ring_shader = _load_button_focus_ring_shader()
	if not is_instance_valid(_asset_library):
		push_error("[GameUiStyleUtility] 缺少 GameAssetLibraryUtility。")
	if not is_instance_valid(_shader_parameters):
		push_error("[GameUiStyleUtility] 缺少 GFShaderParameterUtility。")
	if not is_instance_valid(_button_focus_ring_shader):
		push_error(
			"[GameUiStyleUtility] 无法通过素材键加载按钮焦点 shader：%s。"
			% String(_BUTTON_FOCUS_RING_SHADER_ASSET_KEY)
		)


func dispose() -> void:
	_button_focus_shader_profile = null
	_asset_library = null
	_button_focus_ring_shader = null
	_shader_parameters = null


func release_dependencies() -> void:
	_asset_library = null
	_button_focus_ring_shader = null
	_shader_parameters = null
	super.release_dependencies()


# --- 公共方法 ---

## 应用一套 UI 色板，后续样式刷新会使用该色板。
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
	_text_shadow_color = palette.button_hover_color
	_text_shadow_color.a = 0.52
	_field_surface_color = palette.field_surface_color
	_field_focus_surface_color = palette.field_focus_surface_color
	_field_border_color = palette.field_border_color
	_field_focus_border_color = palette.field_focus_border_color
	_panel_surface_color = palette.panel_surface_color
	_selected_surface_color = palette.selected_surface_color
	_selected_border_color = palette.selected_border_color
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
	return refresh_tree(root)


## 返回数值变化反馈色；正向变化使用选中强调色，负向变化使用焦点边框色。
## @param is_increase: 是否为正向数值变化。
func get_value_change_color(is_increase: bool) -> Color:
	return _selected_border_color if is_increase else _field_focus_border_color


## 使用当前色板刷新整个 UI 子树。
## @param root: 要扫描的 UI 根节点。
## @return: 本次刷新的 Control 数量。
func refresh_tree(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	var refreshed_count: int = 0
	if root is BaseButton:
		var button: BaseButton = root
		prepare_button(button)
		refreshed_count += 1
	elif root is Control:
		var control: Control = root
		control.set_meta(_STATIC_STYLE_META, false)
		style_control(control)
		refreshed_count += 1

	for child: Node in root.get_children():
		refreshed_count += refresh_tree(child)
	return refreshed_count


## 使用当前色板为一个支持的 Control 应用静态样式。
## @param control: 要应用样式的控件。
func style_control(control: Control) -> void:
	if not is_instance_valid(control):
		return
	if control is BaseButton:
		var button: BaseButton = control
		prepare_button(button)
		return
	if GFVariantData.to_bool(_get_control_meta(control, _STATIC_STYLE_META, false)):
		return

	control.set_meta(_STATIC_STYLE_META, true)
	if control is Label:
		var label: Label = control
		_apply_label_style(label)
	elif control is RichTextLabel:
		var rich_text_label: RichTextLabel = control
		_apply_rich_text_label_style(rich_text_label)
	elif control is SpinBox:
		var spin_box: SpinBox = control
		_style_spin_box(spin_box)
	elif control is LineEdit:
		var line_edit: LineEdit = control
		style_line_edit(line_edit)
	elif control is Range:
		var range_control: Range = control
		_style_range(range_control)
	elif control is PanelContainer:
		var panel_container: PanelContainer = control
		_style_panel_container(panel_container)
	elif control is Panel and control.has_meta(_SURFACE_ROLE_META):
		var panel: Panel = control
		_apply_semantic_panel_style(panel)
	elif control is ItemList:
		var item_list: ItemList = control
		_style_item_list(item_list)
	elif control is HSeparator:
		var separator: HSeparator = control
		style_separator(separator)


## 为 Label 保存语义角色并立即应用当前主题样式。
## @param label: 目标文本控件。
## @param role: 文本语义角色。
## @param font_size: 大于 0 时覆盖字号，否则保留场景字号。
## @param use_shadow: 是否使用主题化硬边阴影。
func style_label(
	label: Label,
	role: TextRole = TextRole.PRIMARY,
	font_size: int = 0,
	use_shadow: bool = false
) -> void:
	if not is_instance_valid(label):
		return
	label.set_meta(_TEXT_ROLE_META, int(role))
	label.set_meta(_TEXT_FONT_SIZE_META, maxi(font_size, 0))
	label.set_meta(_TEXT_SHADOW_META, use_shadow)
	label.set_meta(_STATIC_STYLE_META, true)
	_apply_label_style(label)


## 为 RichTextLabel 保存语义角色并立即应用当前主题样式。
## @param label: 目标富文本控件。
## @param role: 文本语义角色。
func style_rich_text_label(
	label: RichTextLabel,
	role: TextRole = TextRole.SECONDARY
) -> void:
	if not is_instance_valid(label):
		return
	label.set_meta(_TEXT_ROLE_META, int(role))
	label.set_meta(_STATIC_STYLE_META, true)
	_apply_rich_text_label_style(label)


## 为 Panel 保存语义表面状态并立即应用当前主题样式。
## @param panel: 目标 Panel。
## @param surface_role: 面板填充语义。
## @param border_role: 面板边框语义。
## @param border_width: 边框宽度。
func style_panel(
	panel: Panel,
	surface_role: SurfaceRole = SurfaceRole.PANEL,
	border_role: BorderRole = BorderRole.DEFAULT,
	border_width: int = 1
) -> void:
	if not is_instance_valid(panel):
		return
	panel.set_meta(_SURFACE_ROLE_META, int(surface_role))
	panel.set_meta(_BORDER_ROLE_META, int(border_role))
	panel.set_meta(_BORDER_WIDTH_META, maxi(border_width, 0))
	panel.set_meta(_STATIC_STYLE_META, true)
	_apply_semantic_panel_style(panel)


## 为 LineEdit 应用当前主题字段样式。
## @param line_edit: 目标输入框。
func style_line_edit(line_edit: LineEdit) -> void:
	if not is_instance_valid(line_edit):
		return
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
	line_edit.add_theme_color_override("font_placeholder_color", _get_text_color(TextRole.MUTED))
	line_edit.add_theme_color_override("caret_color", _field_focus_border_color)


## 为分隔线应用当前主题的弱边框颜色。
## @param separator: 目标横向分隔线。
func style_separator(separator: HSeparator) -> void:
	if not is_instance_valid(separator):
		return
	var separator_color: Color = _field_border_color
	separator_color.a *= 0.78
	separator.modulate = separator_color


## 为按钮应用当前色板并确保焦点 Shader 节点存在。
## @param button: 目标按钮。
func prepare_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_apply_button_visual_style(button)
	var _focus_ring: ColorRect = _ensure_button_focus_ring(button)


## 更新按钮焦点 Shader 的尺寸和当前色板参数。
## @param button: 目标按钮。
func refresh_button_focus_ring(button: BaseButton) -> void:
	_apply_button_focus_ring_style(button)


## 切换按钮焦点 Shader 的可见状态。
## @param button: 目标按钮。
## @param is_visible: 是否显示。
func set_button_focus_visible(button: BaseButton, is_visible: bool) -> void:
	var ring: ColorRect = _get_button_focus_ring(button)
	if is_instance_valid(ring):
		ring.visible = is_visible


# --- 私有/辅助方法 ---

func _apply_label_style(label: Label) -> void:
	var role: int = GFVariantData.to_int(
		_get_control_meta(label, _TEXT_ROLE_META, TextRole.PRIMARY)
	)
	label.add_theme_color_override("font_color", _get_text_color(role))
	if role == TextRole.FEEDBACK:
		label.add_theme_color_override("font_outline_color", _text_primary_color)
		label.add_theme_constant_override("outline_size", 2)
	var font_size: int = GFVariantData.to_int(
		_get_control_meta(label, _TEXT_FONT_SIZE_META, 0)
	)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	var use_shadow: bool = GFVariantData.to_bool(
		_get_control_meta(label, _TEXT_SHADOW_META, false)
	)
	if use_shadow:
		label.add_theme_color_override("font_shadow_color", _text_shadow_color)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
	else:
		label.remove_theme_color_override("font_shadow_color")
		label.remove_theme_constant_override("shadow_offset_x")
		label.remove_theme_constant_override("shadow_offset_y")


func _get_text_color(role: int) -> Color:
	if role == TextRole.FEEDBACK:
		return Color.WHITE
	if role == TextRole.SECONDARY:
		return _text_secondary_color
	if role == TextRole.MUTED:
		var muted_color: Color = _text_secondary_color
		muted_color.a *= 0.82
		return muted_color
	return _text_primary_color


func _apply_rich_text_label_style(label: RichTextLabel) -> void:
	var role: int = GFVariantData.to_int(
		_get_control_meta(label, _TEXT_ROLE_META, TextRole.SECONDARY)
	)
	label.add_theme_color_override("default_color", _get_text_color(role))
	label.add_theme_color_override("font_selected_color", _text_primary_color)
	label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)


func _apply_semantic_panel_style(panel: Panel) -> void:
	var surface_role: int = GFVariantData.to_int(
		_get_control_meta(panel, _SURFACE_ROLE_META, SurfaceRole.PANEL)
	)
	var border_role: int = GFVariantData.to_int(
		_get_control_meta(panel, _BORDER_ROLE_META, BorderRole.DEFAULT)
	)
	var border_width: int = GFVariantData.to_int(
		_get_control_meta(panel, _BORDER_WIDTH_META, 1)
	)
	var surface_color: Color = _get_surface_color(surface_role)
	if border_role == BorderRole.FOCUS:
		surface_color = surface_color.lightened(0.035)
	panel.add_theme_stylebox_override(
		"panel",
		_create_panel_surface_style(
			surface_color,
			_get_border_color(border_role),
			border_width
		)
	)


func _style_spin_box(spin_box: SpinBox) -> void:
	spin_box.add_theme_color_override("font_color", _text_primary_color)
	spin_box.add_theme_color_override("font_disabled_color", _text_secondary_color)
	spin_box.add_theme_color_override("font_hover_color", _text_primary_color)
	spin_box.add_theme_color_override("font_focus_color", _text_primary_color)
	var line_edit: LineEdit = spin_box.get_line_edit()
	if is_instance_valid(line_edit):
		style_line_edit(line_edit)


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


func _style_item_list(item_list: ItemList) -> void:
	item_list.add_theme_stylebox_override(
		"panel",
		_create_field_style(_field_surface_color, _field_border_color, 1)
	)
	item_list.add_theme_stylebox_override(
		"focus",
		_create_field_style(Color.TRANSPARENT, _field_focus_border_color, 2)
	)
	item_list.add_theme_stylebox_override(
		"selected",
		_create_field_style(_selected_surface_color, _selected_border_color, 1)
	)
	item_list.add_theme_stylebox_override(
		"selected_focus",
		_create_field_style(_selected_surface_color, _field_focus_border_color, 2)
	)
	item_list.add_theme_color_override("font_color", _text_primary_color)
	item_list.add_theme_color_override("font_selected_color", _text_primary_color)


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


func _create_field_style(
	bg_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
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


func _create_panel_surface_style(
	bg_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.shadow_color = Color.TRANSPARENT
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style


func _get_surface_color(role: int) -> Color:
	if role == SurfaceRole.FIELD:
		return _field_surface_color
	if role == SurfaceRole.SELECTED:
		return _selected_surface_color
	return _panel_surface_color


func _get_border_color(role: int) -> Color:
	if role == BorderRole.FOCUS:
		return _field_focus_border_color
	if role == BorderRole.SELECTED:
		return _selected_border_color
	return _field_border_color


func _ensure_button_focus_ring(button: BaseButton) -> ColorRect:
	if not is_instance_valid(button):
		return null
	var focus_ring_shader: Shader = _get_button_focus_ring_shader()
	if not is_instance_valid(focus_ring_shader):
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
	shader_material.shader = focus_ring_shader
	ring.material = shader_material
	button.add_child(ring, false, Node.INTERNAL_MODE_FRONT)
	_apply_button_focus_ring_style(button)
	return ring


func _apply_button_focus_ring_style(button: BaseButton) -> void:
	var ring: ColorRect = _get_button_focus_ring(button)
	if not is_instance_valid(ring) or not is_instance_valid(_shader_parameters):
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
	_text_shadow_color = _TEXT_SHADOW_COLOR
	_field_surface_color = _FIELD_SURFACE_COLOR
	_field_focus_surface_color = _FIELD_FOCUS_SURFACE_COLOR
	_field_border_color = _FIELD_BORDER_COLOR
	_field_focus_border_color = _FIELD_FOCUS_BORDER_COLOR
	_panel_surface_color = _PANEL_SURFACE_COLOR
	_selected_surface_color = _SELECTED_SURFACE_COLOR
	_selected_border_color = _SELECTED_BORDER_COLOR
	_slider_track_color = Color(0.9372549, 0.81960785, 0.3647059, 0.42)
	_slider_grabber_color = Color(0.61960787, 0.85882354, 0.8352941, 0.92)
	_slider_grabber_highlight_color = Color(0.8745098, 0.29411766, 0.6039216, 0.88)
	_button_focus_shader_profile = null


func _get_control_meta(control: Control, key: StringName, default_value: Variant) -> Variant:
	if is_instance_valid(control) and control.has_meta(key):
		return control.get_meta(key)
	return default_value


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		var shader_utility: GFShaderParameterUtility = utility_value
		return shader_utility
	return null


func _get_asset_library_utility() -> GameAssetLibraryUtility:
	var utility_value: Object = get_utility(GameAssetLibraryUtility)
	if utility_value is GameAssetLibraryUtility:
		var asset_library: GameAssetLibraryUtility = utility_value
		return asset_library
	return null


func _get_button_focus_ring_shader() -> Shader:
	if is_instance_valid(_button_focus_ring_shader):
		return _button_focus_ring_shader
	if not is_instance_valid(_asset_library):
		_asset_library = _get_asset_library_utility()
	_button_focus_ring_shader = _load_button_focus_ring_shader()
	return _button_focus_ring_shader


func _load_button_focus_ring_shader() -> Shader:
	if not is_instance_valid(_asset_library):
		return null
	var resource: Resource = _asset_library.load_asset(
		_BUTTON_FOCUS_RING_SHADER_ASSET_KEY,
		"Shader"
	)
	if resource is Shader:
		var shader: Shader = resource
		return shader
	return null


func _get_shader_apply_options() -> Dictionary:
	return {
		"duplicate_material": false,
		"require_declared_parameters": true,
		"warn_on_invalid_target": true,
		"warn_on_missing_parameters": true,
		"copy_values": true,
	}
