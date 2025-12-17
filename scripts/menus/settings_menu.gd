# scripts/menus/settings_menu.gd

## SettingsMenu: 游戏设置界面的UI控制器。
##
## 负责处理语言切换等设置选项。
class_name SettingsMenu
extends Control


# --- @onready 变量 (节点引用) ---

@onready var _page_title: Label = %PageTitle
@onready var _language_option: OptionButton = %LanguageOptionButton
@onready var _back_button: Button = %BackButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_setup_language_options()
	_back_button.pressed.connect(_on_back_button_pressed)
	_language_option.item_selected.connect(_on_language_selected)

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

func _setup_language_options() -> void:
	_language_option.clear()
	_language_option.add_item(tr("LANG_ZH"), 0)
	_language_option.set_item_metadata(0, "zh")
	_language_option.add_item(tr("LANG_EN"), 1)
	_language_option.set_item_metadata(1, "en")

	var current_locale: String = SaveManager.get_language()
	# 简单匹配前两个字符 (例如 zh_CN -> zh)
	if current_locale.begins_with("en"):
		_language_option.select(1)
	else:
		_language_option.select(0)


# --- 信号处理函数 ---

func _on_language_selected(index: int) -> void:
	var locale: String = _language_option.get_item_metadata(index)
	SaveManager.set_language(locale)
	var current_idx = _language_option.selected
	_setup_language_options()
	_language_option.select(current_idx)
	_update_ui_text()


func _on_back_button_pressed() -> void:
	GlobalGameManager.return_to_main_menu()


func _update_ui_text() -> void:
	if is_instance_valid(_page_title):
		_page_title.text = tr("SETTINGS_TITLE")
	if is_instance_valid(_back_button):
		_back_button.text = tr("BACK_BUTTON")
