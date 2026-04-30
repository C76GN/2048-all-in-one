## SettingsMenu: 游戏设置界面的 UI 控制器。
##
## 负责处理语言、显示与音频等通用设置选项。
class_name SettingsMenu
extends "res://scripts/ui/base/game_ui_controller.gd"


# --- 常量 ---

const _FIELD_LANGUAGE_INDEX: StringName = &"language_index"
const _FIELD_WINDOW_MODE_INDEX: StringName = &"window_mode_index"
const _FIELD_VSYNC_INDEX: StringName = &"vsync_index"
const _FIELD_MASTER_VOLUME: StringName = &"master_volume"
const _LOCALE_EN: String = "en"
const _LOCALE_ZH: String = "zh"
const _AUDIO_BUS_MASTER: String = "Master"


# --- 公共变量 ---

## 返回按钮是否切回主菜单；作为弹层打开时应设为 false。
var return_to_main_menu_on_back: bool = true


# --- 私有变量 ---

var _form_binder: GFFormBinder


# --- @onready 变量 (节点引用) ---

@onready var _page_title: Label = %PageTitle
@onready var _language_option: OptionButton = %LanguageOptionButton
@onready var _window_mode_option: OptionButton = %WindowModeOptionButton
@onready var _vsync_option: OptionButton = %VSyncOptionButton
@onready var _master_volume_slider: HSlider = %MasterVolumeSlider
@onready var _volume_value_label: Label = %VolumeValueLabel
@onready var _back_button: Button = %BackButton

## 语言选项标签。
@onready var _language_label: Label = _language_option.get_parent().get_node("Label")

## 窗口模式标签。
@onready var _window_mode_label: Label = _window_mode_option.get_parent().get_node("Label")

## 垂直同步标签。
@onready var _vsync_label: Label = _vsync_option.get_parent().get_node("Label")

## 主音量标签。
@onready var _master_volume_label: Label = _master_volume_slider.get_parent().get_node("Label")

## 操作面板标题标签。
@onready var _controls_header_label: Label = _back_button.get_parent().get_node("Label")


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_setup_setting_options()
	_sync_controls_from_settings()
	_setup_form_binder()
	_back_button.pressed.connect(_on_back_button_pressed)

	_update_ui_text()
	_language_option.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()


# --- 私有/辅助方法 ---

func _setup_setting_options() -> void:
	_setup_language_options()
	_setup_window_mode_options()
	_setup_vsync_options()


func _setup_language_options() -> void:
	_language_option.clear()
	_language_option.add_item(tr("LANG_ZH"), 0)
	_language_option.set_item_metadata(0, _LOCALE_ZH)
	_language_option.add_item(tr("LANG_EN"), 1)
	_language_option.set_item_metadata(1, _LOCALE_EN)


func _setup_window_mode_options() -> void:
	_window_mode_option.clear()
	_window_mode_option.add_item(tr("WINDOW_MODE_WINDOWED"), 0)
	_window_mode_option.set_item_metadata(0, int(DisplayServer.WINDOW_MODE_WINDOWED))
	_window_mode_option.add_item(tr("WINDOW_MODE_FULLSCREEN"), 1)
	_window_mode_option.set_item_metadata(1, int(DisplayServer.WINDOW_MODE_FULLSCREEN))
	_window_mode_option.add_item(tr("WINDOW_MODE_EXCLUSIVE_FULLSCREEN"), 2)
	_window_mode_option.set_item_metadata(2, int(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN))


func _setup_vsync_options() -> void:
	_vsync_option.clear()
	_vsync_option.add_item(tr("VSYNC_DISABLED"), 0)
	_vsync_option.set_item_metadata(0, int(DisplayServer.VSYNC_DISABLED))
	_vsync_option.add_item(tr("VSYNC_ENABLED"), 1)
	_vsync_option.set_item_metadata(1, int(DisplayServer.VSYNC_ENABLED))
	_vsync_option.add_item(tr("VSYNC_ADAPTIVE"), 2)
	_vsync_option.set_item_metadata(2, int(DisplayServer.VSYNC_ADAPTIVE))


func _setup_form_binder() -> void:
	_form_binder = GFFormBinder.new()
	_form_binder.bind_field(_FIELD_LANGUAGE_INDEX, _language_option, 0)
	_form_binder.bind_field(_FIELD_WINDOW_MODE_INDEX, _window_mode_option, 0)
	_form_binder.bind_field(_FIELD_VSYNC_INDEX, _vsync_option, 1)
	_form_binder.bind_field(_FIELD_MASTER_VOLUME, _master_volume_slider, 1.0)
	_form_binder.field_changed.connect(_on_form_field_changed)


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


func _get_current_locale() -> String:
	var save_system := get_system(SaveSystem) as SaveSystem
	if is_instance_valid(save_system):
		return save_system.get_language()

	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		return display_settings.get_locale()

	return _LOCALE_ZH


func _get_current_window_mode() -> DisplayServer.WindowMode:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		return display_settings.get_window_mode()

	return DisplayServer.window_get_mode()


func _get_current_vsync_mode() -> DisplayServer.VSyncMode:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		return display_settings.get_vsync_mode()

	return DisplayServer.window_get_vsync_mode()


func _get_current_master_volume() -> float:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		return display_settings.get_audio_bus_volume(_AUDIO_BUS_MASTER, 1.0)

	return 1.0


func _get_locale_index(locale: String) -> int:
	return 1 if locale.begins_with(_LOCALE_EN) else 0


func _get_locale_for_index(index: int) -> String:
	if index < 0 or index >= _language_option.item_count:
		return _LOCALE_ZH

	return String(_language_option.get_item_metadata(index))


func _get_window_mode_for_index(index: int) -> DisplayServer.WindowMode:
	return int(_get_option_metadata(_window_mode_option, index, DisplayServer.WINDOW_MODE_WINDOWED)) as DisplayServer.WindowMode


func _get_vsync_mode_for_index(index: int) -> DisplayServer.VSyncMode:
	return int(_get_option_metadata(_vsync_option, index, DisplayServer.VSYNC_ENABLED)) as DisplayServer.VSyncMode


func _get_option_metadata(option: OptionButton, index: int, fallback: Variant) -> Variant:
	if not is_instance_valid(option) or index < 0 or index >= option.item_count:
		return fallback

	return option.get_item_metadata(index)


func _get_option_index_for_metadata(option: OptionButton, metadata: int) -> int:
	if not is_instance_valid(option):
		return 0

	for index in range(option.item_count):
		if int(option.get_item_metadata(index)) == metadata:
			return index
	return 0


func _update_volume_value_label(value: float) -> void:
	if is_instance_valid(_volume_value_label):
		_volume_value_label.text = str(roundi(clampf(value, 0.0, 1.0) * 100.0)) + "%"


func _update_ui_text() -> void:
	if is_instance_valid(_page_title):
		_page_title.text = tr("SETTINGS_TITLE")
	if is_instance_valid(_back_button):
		_back_button.text = tr("BACK_BUTTON")
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


# --- 信号处理函数 ---

func _on_form_field_changed(key: StringName, value: Variant) -> void:
	match key:
		_FIELD_LANGUAGE_INDEX:
			_apply_locale(int(value))
		_FIELD_WINDOW_MODE_INDEX:
			_apply_window_mode(int(value))
		_FIELD_VSYNC_INDEX:
			_apply_vsync_mode(int(value))
		_FIELD_MASTER_VOLUME:
			_apply_master_volume(float(value))


func _apply_locale(index: int) -> void:
	var locale := _get_locale_for_index(index)
	var save_system := get_system(SaveSystem) as SaveSystem
	if is_instance_valid(save_system):
		save_system.set_language(locale)

	_sync_controls_from_settings()
	_update_ui_text()


func _apply_window_mode(index: int) -> void:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		display_settings.set_window_mode(_get_window_mode_for_index(index))


func _apply_vsync_mode(index: int) -> void:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		display_settings.set_vsync_mode(_get_vsync_mode_for_index(index))


func _apply_master_volume(value: float) -> void:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		display_settings.set_audio_bus_volume(_AUDIO_BUS_MASTER, value)
	_update_volume_value_label(value)


func _on_back_button_pressed() -> void:
	if not return_to_main_menu_on_back:
		var ui_util := get_utility(GFUIUtility) as GFUIUtility
		if ui_util:
			ui_util.pop_panel()
		return

	var router := get_system(SceneRouterSystem) as SceneRouterSystem
	if router:
		router.return_to_main_menu()
