## GameOverMenu: 游戏结束菜单的UI控制器。
##
## 在游戏失败后显示，提供重来或返回主菜单的选项。
## 通过 GF 事件系统通知系统层执行操作。
class_name GameOverMenu
extends "res://scripts/ui/base/game_ui_controller.gd"


# --- 常量 ---

const _ROUTE_SETTINGS_MENU: StringName = &"settings_menu"
const _TEXT_PRIMARY_COLOR: Color = Color(0.96, 0.92, 0.84, 1.0)
const _TEXT_SECONDARY_COLOR: Color = Color(0.78, 0.82, 0.78, 0.94)
const _TEXT_SHADOW_COLOR: Color = Color(0.025, 0.035, 0.060, 0.26)
const _SUMMARY_FORMAT_FALLBACK: String = "%s · %dx%d\n本局：%d 分 · %d 步 · 最大方块 %d\n历史：最高分 %d · 最佳步数 %s · 最大方块 %s\n平均：%s 分 · %s 步\n完整对局：%d"
const _SUMMARY_FORMAT_WITH_TARGET_FALLBACK: String = "%s · %dx%d\n本局：%d 分 · %d 步 · 最大方块 %d\n历史：最高分 %d · 最佳步数 %s · 最大方块 %s\n平均：%s 分 · %s 步\n目标 %d：本局%s · 累计 %d 次 · %d%%\n完整对局：%d"


# --- @onready 变量 (节点引用) ---

@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _summary_label: Label = $CenterContainer/VBoxContainer/SummaryLabel
@onready var _restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var _settings_button: Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var _main_menu_button: Button = $CenterContainer/VBoxContainer/MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _connect_result_24: int = _restart_button.pressed.connect(_on_restart_button_pressed)
	var _connect_result_25: int = _settings_button.pressed.connect(_on_settings_button_pressed)
	var _connect_result_26: int = _main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	_update_ui_text()
	_apply_visual_style()
	call_deferred(&"_refresh_summary")
	_restart_button.grab_focus()


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_GAME_OVER")
	if is_instance_valid(_summary_label) and _summary_label.text.is_empty():
		_summary_label.text = tr("GAME_OVER_SUMMARY_LOADING")
	if is_instance_valid(_restart_button):
		_restart_button.text = tr("BTN_REPLAY_AGAIN")
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("BTN_SETTINGS")
	if is_instance_valid(_main_menu_button):
		_main_menu_button.text = tr("BTN_MAIN_MENU")


func _apply_visual_style() -> void:
	_style_label(_title_label, _TEXT_PRIMARY_COLOR, 34, true)
	_style_label(_summary_label, _TEXT_SECONDARY_COLOR, 16, false)


func _style_label(label: Label, color: Color, font_size: int, use_shadow: bool) -> void:
	if not is_instance_valid(label):
		return

	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if use_shadow:
		label.add_theme_color_override("font_shadow_color", _TEXT_SHADOW_COLOR)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 1)


func _refresh_summary() -> void:
	if not is_instance_valid(_summary_label):
		return

	var status_model: GameStatusModel = _get_game_status_model()
	if not is_instance_valid(status_model):
		_summary_label.text = tr("GAME_OVER_SUMMARY_UNAVAILABLE")
		return

	var current_game_model: CurrentGameModel = _get_current_game_model()
	var score: int = GFVariantData.to_int(status_model.score.get_value(), 0)
	var move_count: int = GFVariantData.to_int(status_model.move_count.get_value(), 0)
	var highest_tile: int = GFVariantData.to_int(status_model.highest_tile.get_value(), 0)
	var high_score: int = GFVariantData.to_int(status_model.high_score.get_value(), score)
	var initial_high_score: int = _get_initial_high_score(current_game_model)
	var grid_size: int = _get_current_grid_size(current_game_model)
	var mode_config: GameModeConfig = _get_current_mode_config(current_game_model)
	var mode_name: String = _get_mode_name(mode_config)
	var stats: Dictionary = _get_current_stats(mode_config, grid_size)
	var plays: int = GFVariantData.to_int(stats.get("plays", 0), 0)
	var best_steps: int = GFVariantData.to_int(stats.get("best_steps", 0), 0)
	var average_score: int = GFVariantData.to_int(stats.get("average_score", 0), 0)
	var average_steps: int = GFVariantData.to_int(stats.get("average_steps", 0), 0)
	var target_value: int = GFVariantData.to_int(stats.get("target_value", 0), 0)
	var target_reached_count: int = GFVariantData.to_int(stats.get("target_reached_count", 0), 0)
	var target_reached_rate: int = GFVariantData.to_int(stats.get("target_reached_rate", 0), 0)
	var last_target_reached: bool = GFVariantData.to_bool(stats.get("last_target_reached", false), false)
	var history_max_tile: int = max(GFVariantData.to_int(stats.get("max_tile", 0), 0), highest_tile)

	var prefix: String = ""
	if score > initial_high_score:
		prefix = tr("GAME_OVER_NEW_RECORD_PREFIX") + "\n"
	if target_value > 0:
		_summary_label.text = prefix + GameTextFormatUtility.format_template(
			tr("GAME_OVER_SUMMARY_FORMAT_WITH_TARGET"),
			_SUMMARY_FORMAT_WITH_TARGET_FALLBACK,
			[
				mode_name,
				grid_size,
				grid_size,
				score,
				move_count,
				highest_tile,
				high_score,
				_format_optional_stat(best_steps),
				_format_optional_stat(history_max_tile),
				_format_optional_stat(average_score),
				_format_optional_stat(average_steps),
				target_value,
				_format_target_reached(last_target_reached),
				target_reached_count,
				target_reached_rate,
				plays,
			]
		)
		return
	_summary_label.text = prefix + GameTextFormatUtility.format_template(
		tr("GAME_OVER_SUMMARY_FORMAT"),
		_SUMMARY_FORMAT_FALLBACK,
		[
			mode_name,
			grid_size,
			grid_size,
			score,
			move_count,
			highest_tile,
			high_score,
			_format_optional_stat(best_steps),
			_format_optional_stat(history_max_tile),
			_format_optional_stat(average_score),
			_format_optional_stat(average_steps),
			plays,
		]
	)


func _configure_settings_panel(panel: Node) -> void:
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	if panel is SettingsMenu:
		var settings_menu: SettingsMenu = panel
		settings_menu.return_to_main_menu_on_back = false


func _get_game_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_current_game_model() -> CurrentGameModel:
	var model_value: Object = get_model(CurrentGameModel)
	if model_value is CurrentGameModel:
		var current_model: CurrentGameModel = model_value
		return current_model
	return null


func _get_save_system() -> SaveSystem:
	var system_value: Object = get_system(SaveSystem)
	if system_value is SaveSystem:
		var save_system: SaveSystem = system_value
		return save_system
	return null


func _get_ui_router_utility() -> GFUIRouterUtility:
	var utility_value: Object = get_utility(GFUIRouterUtility)
	if utility_value is GFUIRouterUtility:
		var ui_router: GFUIRouterUtility = utility_value
		return ui_router
	return null


func _get_current_grid_size(current_game_model: CurrentGameModel) -> int:
	if not is_instance_valid(current_game_model):
		return 4
	return GFVariantData.to_int(current_game_model.current_grid_size.get_value(), 4)


func _get_initial_high_score(current_game_model: CurrentGameModel) -> int:
	if not is_instance_valid(current_game_model):
		return 0
	return GFVariantData.to_int(current_game_model.initial_high_score.get_value(), 0)


func _get_current_mode_config(current_game_model: CurrentGameModel) -> GameModeConfig:
	if not is_instance_valid(current_game_model):
		return null

	var mode_config_value: Variant = current_game_model.mode_config.get_value()
	if mode_config_value is GameModeConfig:
		var mode_config: GameModeConfig = mode_config_value
		return mode_config
	return null


func _get_mode_name(mode_config: GameModeConfig) -> String:
	if not is_instance_valid(mode_config):
		return tr("UI_UNKNOWN")
	return tr(mode_config.mode_name)


func _get_current_stats(mode_config: GameModeConfig, grid_size: int) -> Dictionary:
	if not is_instance_valid(mode_config):
		return {}
	var save_system: SaveSystem = _get_save_system()
	if not is_instance_valid(save_system):
		return {}
	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	return save_system.get_game_stats(mode_id, grid_size)


func _format_optional_stat(value: int) -> String:
	if value <= 0:
		return tr("UI_NONE")
	return str(value)


func _format_target_reached(value: bool) -> String:
	return tr("UI_TARGET_REACHED") if value else tr("UI_TARGET_NOT_REACHED")


# --- 信号处理函数 ---

## 响应"重来"按钮的点击事件。
func _on_restart_button_pressed() -> void:
	send_simple_event(EventNames.RESTART_GAME_REQUESTED)


## 响应"返回主界面"按钮的点击事件。
func _on_main_menu_button_pressed() -> void:
	send_simple_event(EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED)


func _on_settings_button_pressed() -> void:
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if is_instance_valid(ui_router):
		var _settings_panel: Node = ui_router.push_route(_ROUTE_SETTINGS_MENU, {}, {}, _configure_settings_panel)
	else:
		push_warning("[GameOverMenu] GFUIRouterUtility 未注册，无法打开设置菜单。")
