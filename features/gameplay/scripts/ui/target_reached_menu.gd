## TargetReachedMenu: 首次达成当前模式目标后的非强制提示面板。
##
## 该面板不结束对局，只给玩家继续挑战、重开或返回主界面的清晰选择。
class_name TargetReachedMenu
extends "res://shared/scripts/ui/base/game_ui_controller.gd"


# --- 常量 ---

const _SUMMARY_FORMAT_FALLBACK: String = "目标 %d 已完成\n当前：%d 分 · %d 步 · 最大方块 %d"


# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _message_label: Label = $CenterContainer/VBoxContainer/MessageLabel
@onready var _summary_label: Label = $CenterContainer/VBoxContainer/SummaryLabel
@onready var _continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	var _continue_connect: int = _continue_button.pressed.connect(_on_continue_button_pressed)
	var _restart_connect: int = _restart_button.pressed.connect(_on_restart_button_pressed)
	var _main_menu_connect: int = _main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	_update_ui_text()
	call_deferred(&"_refresh_summary")
	_continue_button.grab_focus()


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_TARGET_REACHED")
	if is_instance_valid(_message_label):
		_message_label.text = tr("TARGET_REACHED_PANEL_MESSAGE")
	if is_instance_valid(_summary_label) and _summary_label.text.is_empty():
		_summary_label.text = tr("TARGET_REACHED_SUMMARY_LOADING")
	if is_instance_valid(_continue_button):
		_continue_button.text = tr("BTN_CONTINUE_CHALLENGE")
	if is_instance_valid(_restart_button):
		_restart_button.text = tr("BTN_RESTART")
	if is_instance_valid(_main_menu_button):
		_main_menu_button.text = tr("BTN_MAIN_MENU")


func _refresh_summary() -> void:
	if not is_instance_valid(_summary_label):
		return

	var status_model: GameStatusModel = _get_game_status_model()
	if not is_instance_valid(status_model):
		_summary_label.text = tr("TARGET_REACHED_SUMMARY_UNAVAILABLE")
		return

	var target_value: int = GFVariantData.to_int(status_model.target_tile_value.get_value(), 0)
	var score: int = GFVariantData.to_int(status_model.score.get_value(), 0)
	var move_count: int = GFVariantData.to_int(status_model.move_count.get_value(), 0)
	var highest_tile: int = GFVariantData.to_int(status_model.highest_tile.get_value(), 0)
	_summary_label.text = _format_summary(target_value, score, move_count, highest_tile)


func _format_summary(target_value: int, score: int, move_count: int, highest_tile: int) -> String:
	return GameTextFormatUtility.format_template(
		tr("TARGET_REACHED_SUMMARY_FORMAT"),
		_SUMMARY_FORMAT_FALLBACK,
		[target_value, score, move_count, highest_tile]
	)


func _get_game_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


# --- 信号处理函数 ---

func _on_continue_button_pressed() -> void:
	send_simple_event(EventNames.RESUME_GAME_REQUESTED)


func _on_restart_button_pressed() -> void:
	send_simple_event(EventNames.RESTART_GAME_REQUESTED)


func _on_main_menu_button_pressed() -> void:
	send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)
