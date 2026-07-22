## SettingsMenu: 游戏设置界面的 UI 控制器。
##
## 负责处理语言、显示与音频等通用设置选项。
class_name SettingsMenu
extends GameUiController


# --- 枚举 ---

enum SettingsSection {
	GENERAL,
	AUDIO,
	CONTROLS,
}


# --- 常量 ---

const _FIELD_LANGUAGE_INDEX: StringName = &"language_index"
const _FIELD_WINDOW_MODE_INDEX: StringName = &"window_mode_index"
const _FIELD_VSYNC_INDEX: StringName = &"vsync_index"
const _FIELD_MASTER_VOLUME: StringName = &"master_volume"
const _FIELD_INPUT_TIMING_INDEX: StringName = &"input_timing_index"
const _LOCALE_EN: String = "en"
const _LOCALE_ZH: String = "zh"
const _AUDIO_BUS_MASTER: String = "Master"
const _ROUTE_SETTINGS_MENU: StringName = &"settings_menu"
const _COMPACT_LAYOUT_MAX_WIDTH: float = 760.0
const _DESKTOP_MARGIN_HORIZONTAL: int = 48
const _DESKTOP_MARGIN_VERTICAL: int = 34
const _COMPACT_MARGIN_HORIZONTAL: int = 12
const _COMPACT_MARGIN_VERTICAL: int = 14
const _COMPACT_FIELD_LABEL_WIDTH: float = 112.0
const _DESKTOP_FIELD_LABEL_WIDTH: float = 150.0
const _COMPACT_BINDING_LABEL_WIDTH: float = 124.0
const _DESKTOP_BINDING_LABEL_WIDTH: float = 185.0
const _DESKTOP_BINDING_BUTTON_WIDTH: float = 250.0
const _COMPACT_CONTROL_HEIGHT: float = 44.0
const _DESKTOP_CONTROL_HEIGHT: float = 38.0
const _COMPACT_BINDING_ROW_HEIGHT: float = 44.0
const _DESKTOP_BINDING_ROW_HEIGHT: float = 34.0


# --- 公共变量 ---

## 返回按钮是否切回主菜单；作为弹层打开时应设为 false。
var return_to_main_menu_on_back: bool = true


# --- 私有变量 ---

var _form_binder: GFFormBinder
var _input_profile: GameInputProfileUtility
var _input_detector: GFInputDetector
var _pending_binding: Dictionary = {}
var _is_compact_layout: bool = false
var _responsive_layout_update_queued: bool = false
var _active_section: SettingsSection = SettingsSection.GENERAL


# --- @onready 变量 (节点引用) ---

@onready var _page_title: Label = %PageTitle
@onready var _margin_container: MarginContainer = %SafeMargin
@onready var _body: BoxContainer = %Body
@onready var _category_rail: BoxContainer = %CategoryRail
@onready var _content_panel: MarginContainer = %ContentPanel
@onready var _general_tab_button: Button = %GeneralTabButton
@onready var _audio_tab_button: Button = %AudioTabButton
@onready var _controls_tab_button: Button = %ControlsTabButton
@onready var _general_section: VBoxContainer = %GeneralSection
@onready var _audio_section: VBoxContainer = %AudioSection
@onready var _controls_section: VBoxContainer = %ControlsSection
@onready var _general_section_title: Label = %GeneralSectionTitle
@onready var _audio_section_title: Label = %AudioSectionTitle
@onready var _controls_section_title: Label = %ControlsSectionTitle
@onready var _auto_save_label: Label = %AutoSaveLabel
@onready var _language_option: OptionButton = %LanguageOptionButton
@onready var _window_mode_option: OptionButton = %WindowModeOptionButton
@onready var _vsync_option: OptionButton = %VSyncOptionButton
@onready var _master_volume_slider: HSlider = %MasterVolumeSlider
@onready var _volume_value_label: Label = %VolumeValueLabel
@onready var _back_button: Button = %BackButton
@onready var _input_timing_option: OptionButton = %InputTimingOptionButton
@onready var _input_bindings_header: Label = %InputBindingsHeader
@onready var _input_bindings_container: VBoxContainer = %InputBindingsContainer
@onready var _reset_bindings_button: Button = %ResetBindingsButton
@onready var _input_binding_status_label: Label = %InputBindingStatusLabel

## 语言选项标签。
@onready var _language_label: Label = _get_sibling_label(_language_option)

## 窗口模式标签。
@onready var _window_mode_label: Label = _get_sibling_label(_window_mode_option)

## 垂直同步标签。
@onready var _vsync_label: Label = _get_sibling_label(_vsync_option)

## 主音量标签。
@onready var _master_volume_label: Label = _get_sibling_label(_master_volume_slider)

## 操作页标题标签。
@onready var _controls_header_label: Label = %ControlsSectionTitle


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_input_profile = _get_input_profile_utility()
	_setup_input_detector()
	_setup_setting_options()
	_sync_controls_from_settings()
	_setup_form_binder()
	var _connect_result_62: int = _back_button.pressed.connect(_on_back_button_pressed)
	var _general_tab_connection: int = _general_tab_button.pressed.connect(
		_set_active_section.bind(SettingsSection.GENERAL)
	)
	var _audio_tab_connection: int = _audio_tab_button.pressed.connect(
		_set_active_section.bind(SettingsSection.AUDIO)
	)
	var _controls_tab_connection: int = _controls_tab_button.pressed.connect(
		_set_active_section.bind(SettingsSection.CONTROLS)
	)
	var _reset_connect_result: int = _reset_bindings_button.pressed.connect(
		_on_reset_bindings_pressed
	)
	if is_instance_valid(_input_profile):
		var _bindings_changed_connection: int = _input_profile.bindings_changed.connect(
			_rebuild_input_binding_rows
		)

	_apply_semantic_styles()
	_set_active_section(SettingsSection.GENERAL)
	_apply_responsive_layout()
	_update_ui_text()
	_rebuild_input_binding_rows()
	_language_option.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_queue_responsive_layout_update()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_input_detector) and _input_detector.is_detecting():
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 公共方法 ---

## 返回设置页是否应采用移动端单列布局。
## @param viewport_size: 当前逻辑视口尺寸。
## @return 宽度低于移动端断点时返回 true。
static func is_compact_layout(viewport_size: Vector2) -> bool:
	return viewport_size.x > 0.0 and viewport_size.x < _COMPACT_LAYOUT_MAX_WIDTH


# --- 私有/辅助方法 ---

func _queue_responsive_layout_update() -> void:
	if _responsive_layout_update_queued:
		return
	_responsive_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_responsive_layout_update_queued = false
	if not is_inside_tree():
		return
	_is_compact_layout = is_compact_layout(size)
	_body.vertical = _is_compact_layout
	_category_rail.vertical = not _is_compact_layout
	_category_rail.custom_minimum_size.x = 0.0 if _is_compact_layout else 210.0
	_content_panel.custom_minimum_size.x = 0.0 if _is_compact_layout else 620.0
	_body.add_theme_constant_override("separation", 12 if _is_compact_layout else 20)
	_category_rail.add_theme_constant_override("separation", 6 if _is_compact_layout else 8)
	_margin_container.add_theme_constant_override(
		"margin_left",
		_COMPACT_MARGIN_HORIZONTAL if _is_compact_layout else _DESKTOP_MARGIN_HORIZONTAL
	)
	_margin_container.add_theme_constant_override(
		"margin_right",
		_COMPACT_MARGIN_HORIZONTAL if _is_compact_layout else _DESKTOP_MARGIN_HORIZONTAL
	)
	_margin_container.add_theme_constant_override(
		"margin_top",
		_COMPACT_MARGIN_VERTICAL if _is_compact_layout else _DESKTOP_MARGIN_VERTICAL
	)
	_margin_container.add_theme_constant_override(
		"margin_bottom",
		_COMPACT_MARGIN_VERTICAL if _is_compact_layout else _DESKTOP_MARGIN_VERTICAL
	)
	_page_title.add_theme_font_size_override("font_size", 30 if _is_compact_layout else 38)
	_auto_save_label.visible = not _is_compact_layout
	for tab_button: Button in [
		_general_tab_button,
		_audio_tab_button,
		_controls_tab_button,
	]:
		tab_button.custom_minimum_size = Vector2(
			0.0 if _is_compact_layout else 210.0,
			44.0 if _is_compact_layout else 50.0
		)
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_field_widths()
	_rebuild_input_binding_rows()


func _apply_field_widths() -> void:
	var labels: Array[Label] = [
		_language_label,
		_window_mode_label,
		_vsync_label,
		_master_volume_label,
		_get_sibling_label(_input_timing_option),
	]
	for label: Label in labels:
		if is_instance_valid(label):
			label.custom_minimum_size.x = (
				_COMPACT_FIELD_LABEL_WIDTH
				if _is_compact_layout
				else _DESKTOP_FIELD_LABEL_WIDTH
			)
	var option_controls: Array[Control] = [
		_language_option,
		_window_mode_option,
		_vsync_option,
		_input_timing_option,
	]
	for option_control: Control in option_controls:
		option_control.custom_minimum_size.x = 0.0 if _is_compact_layout else 200.0
		option_control.custom_minimum_size.y = (
			_COMPACT_CONTROL_HEIGHT if _is_compact_layout else _DESKTOP_CONTROL_HEIGHT
		)
	_master_volume_slider.custom_minimum_size.x = 0.0 if _is_compact_layout else 200.0
	_master_volume_slider.custom_minimum_size.y = (
		_COMPACT_CONTROL_HEIGHT if _is_compact_layout else _DESKTOP_CONTROL_HEIGHT
	)
	_volume_value_label.custom_minimum_size.x = 54.0 if _is_compact_layout else 64.0
	_reset_bindings_button.custom_minimum_size.y = (
		_COMPACT_CONTROL_HEIGHT if _is_compact_layout else 36.0
	)


func _set_active_section(section: SettingsSection) -> void:
	_active_section = section
	_general_section.visible = section == SettingsSection.GENERAL
	_audio_section.visible = section == SettingsSection.AUDIO
	_controls_section.visible = section == SettingsSection.CONTROLS
	_general_tab_button.set_pressed_no_signal(section == SettingsSection.GENERAL)
	_audio_tab_button.set_pressed_no_signal(section == SettingsSection.AUDIO)
	_controls_tab_button.set_pressed_no_signal(section == SettingsSection.CONTROLS)
	match section:
		SettingsSection.AUDIO:
			_master_volume_slider.grab_focus()
		SettingsSection.CONTROLS:
			_input_timing_option.grab_focus()
		_:
			_language_option.grab_focus()


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_label(_page_title, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_general_section_title, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_audio_section_title, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_controls_section_title, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_auto_save_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_input_bindings_header, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_volume_value_label, GameUiStyleUtility.TextRole.NUMERIC)
	style.style_button(_back_button, GameUiStyleUtility.ButtonRole.ICON)
	style.style_button(_general_tab_button, GameUiStyleUtility.ButtonRole.QUIET)
	style.style_button(_audio_tab_button, GameUiStyleUtility.ButtonRole.QUIET)
	style.style_button(_controls_tab_button, GameUiStyleUtility.ButtonRole.QUIET)
	style.style_button(_reset_bindings_button, GameUiStyleUtility.ButtonRole.SECONDARY)

func _setup_setting_options() -> void:
	_setup_language_options()
	_setup_window_mode_options()
	_setup_vsync_options()
	_setup_input_timing_options()


func _setup_input_timing_options() -> void:
	_write_option_items(_input_timing_option, [
		_make_option_item(
			tr("INPUT_TIMING_BUFFERED"),
			GameInputProfileUtility.InputTimingMode.BUFFERED,
			0
		),
		_make_option_item(
			tr("INPUT_TIMING_BLOCK"),
			GameInputProfileUtility.InputTimingMode.BLOCK_WHILE_ANIMATING,
			1
		),
		_make_option_item(
			tr("INPUT_TIMING_REALTIME"),
			GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET,
			2
		),
	])


func _get_sibling_label(control: Control) -> Label:
	if not is_instance_valid(control):
		return null

	var parent: Node = control.get_parent()
	if not is_instance_valid(parent):
		return null

	var label_node: Node = parent.get_node_or_null("Label")
	if label_node is Label:
		var label: Label = label_node
		return label
	return null


func _setup_language_options() -> void:
	_write_option_items(_language_option, [
		_make_option_item(tr("LANG_ZH"), _LOCALE_ZH, 0),
		_make_option_item(tr("LANG_EN"), _LOCALE_EN, 1),
	])


func _setup_window_mode_options() -> void:
	_write_option_items(_window_mode_option, [
		_make_option_item(tr("WINDOW_MODE_WINDOWED"), int(DisplayServer.WINDOW_MODE_WINDOWED), 0),
		_make_option_item(tr("WINDOW_MODE_FULLSCREEN"), int(DisplayServer.WINDOW_MODE_FULLSCREEN), 1),
		_make_option_item(tr("WINDOW_MODE_EXCLUSIVE_FULLSCREEN"), int(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN), 2),
	])


func _setup_vsync_options() -> void:
	_write_option_items(_vsync_option, [
		_make_option_item(tr("VSYNC_DISABLED"), int(DisplayServer.VSYNC_DISABLED), 0),
		_make_option_item(tr("VSYNC_ENABLED"), int(DisplayServer.VSYNC_ENABLED), 1),
		_make_option_item(tr("VSYNC_ADAPTIVE"), int(DisplayServer.VSYNC_ADAPTIVE), 2),
	])


func _write_option_items(option: OptionButton, items: Array[Dictionary]) -> void:
	var _written_count: int = GFItemListBinder.write_items(option, items, {
		"text_key": &"text",
		"id_key": &"id",
		"metadata_key": &"metadata",
	})


static func _make_option_item(text: String, metadata: Variant, id: int) -> Dictionary:
	return {
		"text": text,
		"metadata": metadata,
		"id": id,
	}


func _setup_form_binder() -> void:
	_form_binder = GFFormBinder.new()
	_form_binder.bind_field(_FIELD_LANGUAGE_INDEX, _language_option, 0)
	_form_binder.bind_field(_FIELD_WINDOW_MODE_INDEX, _window_mode_option, 0)
	_form_binder.bind_field(_FIELD_VSYNC_INDEX, _vsync_option, 1)
	_form_binder.bind_field(_FIELD_MASTER_VOLUME, _master_volume_slider, 1.0)
	_form_binder.bind_field(_FIELD_INPUT_TIMING_INDEX, _input_timing_option, 2)
	var _connect_result_121: int = _form_binder.field_changed.connect(_on_form_field_changed)


func _sync_controls_from_settings() -> void:
	if is_instance_valid(_language_option):
		_language_option.select(_get_locale_index(_get_current_locale()))
	if is_instance_valid(_window_mode_option):
		_window_mode_option.select(_get_option_index_for_metadata(
			_window_mode_option,
			int(_get_current_window_mode())
		))
	if is_instance_valid(_vsync_option):
		_vsync_option.select(_get_option_index_for_metadata(_vsync_option, int(_get_current_vsync_mode())))
	if is_instance_valid(_master_volume_slider):
		_master_volume_slider.value = _get_current_master_volume()
		_update_volume_value_label(_master_volume_slider.value)
	if is_instance_valid(_input_timing_option):
		_input_timing_option.select(_get_option_index_for_metadata(
			_input_timing_option,
			int(_get_current_input_timing_mode())
		))


func _get_current_locale() -> String:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法读取语言设置。")
		return _LOCALE_ZH
	return display_settings.get_locale()


func _get_current_window_mode() -> DisplayServer.WindowMode:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法读取窗口模式。")
		return DisplayServer.WINDOW_MODE_WINDOWED
	return display_settings.get_window_mode()


func _get_current_vsync_mode() -> DisplayServer.VSyncMode:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法读取垂直同步设置。")
		return DisplayServer.VSYNC_ENABLED
	return display_settings.get_vsync_mode()


func _get_current_master_volume() -> float:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法读取主音量。")
		return 1.0
	return display_settings.get_audio_bus_volume(_AUDIO_BUS_MASTER, 1.0)


func _get_current_input_timing_mode() -> GameInputProfileUtility.InputTimingMode:
	if not is_instance_valid(_input_profile):
		return GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET
	return _input_profile.get_input_timing_mode()


func _get_locale_index(locale: String) -> int:
	return 1 if locale.begins_with(_LOCALE_EN) else 0


func _get_locale_for_index(index: int) -> String:
	if index < 0 or index >= _language_option.item_count:
		return _LOCALE_ZH

	return GFVariantData.to_text(_language_option.get_item_metadata(index), _LOCALE_ZH)


func _get_window_mode_for_index(index: int) -> DisplayServer.WindowMode:
	return _to_window_mode(GFVariantData.to_int(_get_option_metadata(_window_mode_option, index, DisplayServer.WINDOW_MODE_WINDOWED), int(DisplayServer.WINDOW_MODE_WINDOWED)))


func _get_vsync_mode_for_index(index: int) -> DisplayServer.VSyncMode:
	return _to_vsync_mode(GFVariantData.to_int(_get_option_metadata(_vsync_option, index, DisplayServer.VSYNC_ENABLED), int(DisplayServer.VSYNC_ENABLED)))


func _get_option_metadata(option: OptionButton, index: int, fallback: Variant) -> Variant:
	if not is_instance_valid(option) or index < 0 or index >= option.item_count:
		return fallback

	return option.get_item_metadata(index)


func _get_option_index_for_metadata(option: OptionButton, metadata: int) -> int:
	if not is_instance_valid(option):
		return 0

	for index: int in range(option.item_count):
		if GFVariantData.to_int(option.get_item_metadata(index), 0) == metadata:
			return index
	return 0


func _get_option_index_for_string_name(option: OptionButton, metadata: StringName) -> int:
	if not is_instance_valid(option):
		return 0

	for index: int in range(option.item_count):
		if GFVariantData.to_string_name(option.get_item_metadata(index), &"") == metadata:
			return index
	return 0


func _get_string_name_for_index(option: OptionButton, index: int, fallback: StringName) -> StringName:
	return GFVariantData.to_string_name(_get_option_metadata(option, index, fallback), fallback)


func _update_volume_value_label(value: float) -> void:
	if is_instance_valid(_volume_value_label):
		_volume_value_label.text = str(roundi(clampf(value, 0.0, 1.0) * 100.0)) + "%"


func _update_ui_text() -> void:
	if not is_node_ready():
		return
	if is_instance_valid(_page_title):
		_page_title.text = tr("SETTINGS_TITLE")
	if is_instance_valid(_back_button):
		_back_button.text = tr("BACK_BUTTON")
	_general_tab_button.text = tr("SETTINGS_TAB_GENERAL")
	_audio_tab_button.text = tr("SETTINGS_TAB_AUDIO")
	_controls_tab_button.text = tr("SETTINGS_TAB_CONTROLS")
	_general_section_title.text = tr("SETTINGS_SECTION_GENERAL")
	_audio_section_title.text = tr("SETTINGS_SECTION_AUDIO")
	_controls_section_title.text = tr("SETTINGS_SECTION_CONTROLS")
	_auto_save_label.text = tr("SETTINGS_AUTO_SAVE_HINT")
	if is_instance_valid(_language_option) and _language_option.item_count >= 2:
		_language_option.set_item_text(0, tr("LANG_ZH"))
		_language_option.set_item_text(1, tr("LANG_EN"))
	if is_instance_valid(_window_mode_option) and _window_mode_option.item_count >= 3:
		_window_mode_option.set_item_text(0, tr("WINDOW_MODE_WINDOWED"))
		_window_mode_option.set_item_text(1, tr("WINDOW_MODE_FULLSCREEN"))
		_window_mode_option.set_item_text(2, tr("WINDOW_MODE_EXCLUSIVE_FULLSCREEN"))
	if is_instance_valid(_vsync_option) and _vsync_option.item_count >= 3:
		_vsync_option.set_item_text(0, tr("VSYNC_DISABLED"))
		_vsync_option.set_item_text(1, tr("VSYNC_ENABLED"))
		_vsync_option.set_item_text(2, tr("VSYNC_ADAPTIVE"))
	if is_instance_valid(_language_label):
		_language_label.text = tr("LANGUAGE_LABEL")
	if is_instance_valid(_window_mode_label):
		_window_mode_label.text = tr("WINDOW_MODE_LABEL")
	if is_instance_valid(_vsync_label):
		_vsync_label.text = tr("VSYNC_LABEL")
	if is_instance_valid(_master_volume_label):
		_master_volume_label.text = tr("MASTER_VOLUME_LABEL")
	if is_instance_valid(_controls_header_label):
		_controls_header_label.text = tr("CONTROLS_TITLE")
	if is_instance_valid(_master_volume_slider):
		_update_volume_value_label(_master_volume_slider.value)
	if is_instance_valid(_input_timing_option) and _input_timing_option.item_count >= 3:
		_input_timing_option.set_item_text(0, tr("INPUT_TIMING_BUFFERED"))
		_input_timing_option.set_item_text(1, tr("INPUT_TIMING_BLOCK"))
		_input_timing_option.set_item_text(2, tr("INPUT_TIMING_REALTIME"))
	var input_timing_label: Label = _get_sibling_label(_input_timing_option)
	if is_instance_valid(input_timing_label):
		input_timing_label.text = tr("INPUT_TIMING_MODE_LABEL")
	if is_instance_valid(_input_bindings_header):
		_input_bindings_header.text = tr("INPUT_BINDINGS_TITLE")
	if is_instance_valid(_reset_bindings_button):
		_reset_bindings_button.text = tr("INPUT_BINDINGS_RESET_ALL")
	_rebuild_input_binding_rows()


func _apply_locale(index: int) -> void:
	var locale: String = _get_locale_for_index(index)
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法写入语言设置。")
		return
	display_settings.set_locale(locale)

	_sync_controls_from_settings()
	_update_ui_text()


func _apply_window_mode(index: int) -> void:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法写入窗口模式。")
		return
	display_settings.set_window_mode(_get_window_mode_for_index(index))


func _apply_vsync_mode(index: int) -> void:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法写入垂直同步设置。")
		return
	display_settings.set_vsync_mode(_get_vsync_mode_for_index(index))


func _apply_master_volume(value: float) -> void:
	var display_settings: GFDisplaySettingsUtility = _get_display_settings_utility()
	if not is_instance_valid(display_settings):
		push_error("[SettingsMenu] 缺少 GFDisplaySettingsUtility，无法写入主音量。")
		return
	display_settings.set_audio_bus_volume(_AUDIO_BUS_MASTER, value)
	_update_volume_value_label(value)


func _apply_input_timing_mode(index: int) -> void:
	if not is_instance_valid(_input_profile):
		return
	var mode_value: int = GFVariantData.to_int(
		_get_option_metadata(
			_input_timing_option,
			index,
			GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET
		),
		GameInputProfileUtility.InputTimingMode.REALTIME_RETARGET
	)
	_input_profile.set_input_timing_mode(mode_value)


func _setup_input_detector() -> void:
	_input_detector = GFInputDetector.new()
	_input_detector.name = "InputDetector"
	_input_detector.countdown_seconds = 0.18
	_input_detector.timeout_seconds = 10.0
	var escape_event: InputEventKey = InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	_input_detector.abort_events = [escape_event]
	add_child(_input_detector)
	var _detected_connection: int = _input_detector.input_detected.connect(
		_on_binding_input_detected
	)


func _rebuild_input_binding_rows() -> void:
	if not is_instance_valid(_input_bindings_container):
		return
	for child: Node in _input_bindings_container.get_children():
		_input_bindings_container.remove_child(child)
		child.queue_free()
	if not is_instance_valid(_input_profile):
		_set_input_binding_status(tr("INPUT_BINDINGS_UNAVAILABLE"))
		return

	var ui_style: GameUiStyleUtility = _get_ui_style_utility()
	var items: Array[Dictionary] = _input_profile.get_gameplay_binding_items()
	for item: Dictionary in items:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var action_id: StringName = GFVariantData.get_option_string_name(item, "action_id")
		var binding_index: int = GFVariantData.get_option_int(item, "binding_index")
		var action_label: Label = Label.new()
		action_label.custom_minimum_size.x = (
			_COMPACT_BINDING_LABEL_WIDTH
			if _is_compact_layout
			else _DESKTOP_BINDING_LABEL_WIDTH
		)
		action_label.text = "%s %d" % [_get_input_action_text(action_id, item), binding_index + 1]
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		action_label.tooltip_text = action_label.text
		if is_instance_valid(ui_style):
			ui_style.style_label(action_label, GameUiStyleUtility.TextRole.PRIMARY)
		row.add_child(action_label)

		var binding_button: Button = Button.new()
		binding_button.custom_minimum_size = Vector2(
			0.0 if _is_compact_layout else _DESKTOP_BINDING_BUTTON_WIDTH,
			_COMPACT_BINDING_ROW_HEIGHT
			if _is_compact_layout
			else _DESKTOP_BINDING_ROW_HEIGHT
		)
		binding_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_button.text = GFVariantData.get_option_string(item, "event_text", tr("INPUT_BINDING_UNBOUND"))
		binding_button.tooltip_text = tr("INPUT_BINDING_CHANGE_HINT")
		if is_instance_valid(ui_style):
			ui_style.style_button(binding_button, GameUiStyleUtility.ButtonRole.SECONDARY)
		var _binding_connection: int = binding_button.pressed.connect(
			_on_binding_button_pressed.bind(item)
		)
		row.add_child(binding_button)

		var reset_button: Button = Button.new()
		reset_button.custom_minimum_size = Vector2(
			44.0 if _is_compact_layout else 36.0,
			_COMPACT_BINDING_ROW_HEIGHT
			if _is_compact_layout
			else _DESKTOP_BINDING_ROW_HEIGHT
		)
		reset_button.text = ""
		reset_button.tooltip_text = tr("INPUT_BINDING_RESET_ONE")
		if is_instance_valid(ui_style):
			ui_style.style_button(reset_button, GameUiStyleUtility.ButtonRole.ICON)
			var _icon_applied: bool = ui_style.set_button_icon_from_asset(
				reset_button,
				&"asset.texture.icon.undo_2",
				18
			)
		var _reset_connection: int = reset_button.pressed.connect(
			_on_reset_binding_pressed.bind(action_id, binding_index)
		)
		row.add_child(reset_button)
		_input_bindings_container.add_child(row)
	var ui_motion: GameUiMotionUtility = _get_ui_motion_utility()
	if is_instance_valid(ui_motion):
		var _bound_count: int = ui_motion.bind_interactive_controls(_input_bindings_container)


func _get_input_action_text(action_id: StringName, item: Dictionary) -> String:
	var translation_key: String = "INPUT_ACTION_%s" % String(action_id).to_upper()
	var translated: String = tr(translation_key)
	if translated != translation_key:
		return translated
	return GFVariantData.get_option_string(item, "action_name", String(action_id))


func _on_binding_button_pressed(item: Dictionary) -> void:
	if not is_instance_valid(_input_detector) or _input_detector.is_detecting():
		return
	_pending_binding = item.duplicate(true)
	_set_input_binding_status(tr("INPUT_BINDING_LISTENING"))
	var device_types: Array[int] = [
		GFInputDetector.DeviceType.KEYBOARD,
		GFInputDetector.DeviceType.MOUSE,
		GFInputDetector.DeviceType.JOYPAD,
	]
	_input_detector.begin_detection(device_types)


func _on_binding_input_detected(input_event: InputEvent) -> void:
	if _pending_binding.is_empty():
		return
	if input_event == null:
		_set_input_binding_status(tr("INPUT_BINDING_CANCELLED"))
		_pending_binding.clear()
		return
	var report: Dictionary = _input_profile.try_set_binding(
		GFVariantData.get_option_string_name(_pending_binding, "context_id"),
		GFVariantData.get_option_string_name(_pending_binding, "action_id"),
		GFVariantData.get_option_int(_pending_binding, "binding_index"),
		input_event
	)
	_pending_binding.clear()
	if not GFVariantData.get_option_bool(report, "ok"):
		_set_input_binding_status(tr("INPUT_BINDING_CONFLICT"))
		return
	_set_input_binding_status(tr("INPUT_BINDING_SAVED"))
	_rebuild_input_binding_rows()


func _on_reset_binding_pressed(action_id: StringName, binding_index: int) -> void:
	if not is_instance_valid(_input_profile):
		return
	_input_profile.reset_binding(GameInputProfileUtility.GAMEPLAY_INPUT_CONTEXT.context_id, action_id, binding_index)
	_set_input_binding_status(tr("INPUT_BINDING_RESET_DONE"))
	_rebuild_input_binding_rows()


func _on_reset_bindings_pressed() -> void:
	if not is_instance_valid(_input_profile):
		return
	_input_profile.reset_all_bindings()
	_set_input_binding_status(tr("INPUT_BINDING_RESET_DONE"))
	_rebuild_input_binding_rows()


func _set_input_binding_status(message: String) -> void:
	if is_instance_valid(_input_binding_status_label):
		_input_binding_status_label.text = message


func _get_display_settings_utility() -> GFDisplaySettingsUtility:
	var utility_value: Object = get_utility(GFDisplaySettingsUtility)
	if utility_value is GFDisplaySettingsUtility:
		var display_settings: GFDisplaySettingsUtility = utility_value
		return display_settings
	return null


func _get_input_profile_utility() -> GameInputProfileUtility:
	var utility_value: Object = get_utility(GameInputProfileUtility)
	if utility_value is GameInputProfileUtility:
		var input_profile: GameInputProfileUtility = utility_value
		return input_profile
	return null


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


static func _to_window_mode(value: int) -> DisplayServer.WindowMode:
	match value:
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return DisplayServer.WINDOW_MODE_MAXIMIZED
		DisplayServer.WINDOW_MODE_MINIMIZED:
			return DisplayServer.WINDOW_MODE_MINIMIZED
		_:
			return DisplayServer.WINDOW_MODE_WINDOWED


static func _to_vsync_mode(value: int) -> DisplayServer.VSyncMode:
	match value:
		DisplayServer.VSYNC_DISABLED:
			return DisplayServer.VSYNC_DISABLED
		DisplayServer.VSYNC_ADAPTIVE:
			return DisplayServer.VSYNC_ADAPTIVE
		DisplayServer.VSYNC_MAILBOX:
			return DisplayServer.VSYNC_MAILBOX
		_:
			return DisplayServer.VSYNC_ENABLED


# --- 信号处理函数 ---

func _on_form_field_changed(key: StringName, value: Variant) -> void:
	match key:
		_FIELD_LANGUAGE_INDEX:
			_apply_locale(GFVariantData.to_int(value, 0))
		_FIELD_WINDOW_MODE_INDEX:
			_apply_window_mode(GFVariantData.to_int(value, int(DisplayServer.WINDOW_MODE_WINDOWED)))
		_FIELD_VSYNC_INDEX:
			_apply_vsync_mode(GFVariantData.to_int(value, int(DisplayServer.VSYNC_ENABLED)))
		_FIELD_MASTER_VOLUME:
			_apply_master_volume(GFVariantData.to_float(value, 1.0))
		_FIELD_INPUT_TIMING_INDEX:
			_apply_input_timing_mode(GFVariantData.to_int(value, 2))


func _on_back_button_pressed() -> void:
	if not return_to_main_menu_on_back:
		var _closed: bool = _close_current_popup_route(_ROUTE_SETTINGS_MENU)
		return

	var router: SceneRouterSystem = _get_scene_router_system()
	if not is_instance_valid(router):
		push_error("[SettingsMenu] 缺少 SceneRouterSystem，无法返回主菜单。")
		return
	router.return_to_main_menu()
