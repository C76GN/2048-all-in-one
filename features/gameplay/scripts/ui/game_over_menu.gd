## GameOverMenu: 游戏结束菜单的UI控制器。
##
## 在游戏失败后显示，提供重来或返回主菜单的选项。
## 通过 GF 事件系统通知系统层执行操作。
class_name GameOverMenu
extends GameUiController


# --- 常量 ---

const _ROUTE_SETTINGS_MENU: StringName = &"settings_menu"
const _ROUTE_GAME_OVER_MENU: StringName = &"game_over_menu"
const _SUMMARY_FORMAT_FALLBACK: String = "%s · %dx%d\n本局：%d 分 · %d 步 · 最大方块 %d\n历史：最高分 %d · 最佳步数 %s · 最大方块 %s\n平均：%s 分 · %s 步\n完整对局：%d"
const _SUMMARY_FORMAT_WITH_TARGET_FALLBACK: String = "%s · %dx%d\n本局：%d 分 · %d 步 · 最大方块 %d\n历史：最高分 %d · 最佳步数 %s · 最大方块 %s\n平均：%s 分 · %s 步\n目标 %d：本局%s · 累计 %d 次 · %d%%\n完整对局：%d"


# --- 私有变量 ---

var _has_played_new_record_celebration: bool = false


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
	var style_utility: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style_utility):
		push_error("[GameOverMenu] 缺少 GameUiStyleUtility，无法应用结算语义样式。")
		return
	style_utility.style_label(_title_label, GameUiStyleUtility.TextRole.PRIMARY, 34, true)
	style_utility.style_label(_summary_label, GameUiStyleUtility.TextRole.SECONDARY, 16)


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
	var topology: BoardTopology = _get_current_topology(current_game_model)
	var board_size: Vector2i = topology.get_bounds_size() if topology != null else Vector2i(4, 4)
	var mode_config: GameModeConfig = _get_current_mode_config(current_game_model)
	var mode_name: String = _get_mode_name(mode_config)
	var stats: Dictionary = _get_current_stats(mode_config, topology)
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
		_play_new_record_celebration_once()
	if target_value > 0:
		_summary_label.text = prefix + GameTextFormatUtility.format_template(
			tr("GAME_OVER_SUMMARY_FORMAT_WITH_TARGET"),
			_SUMMARY_FORMAT_WITH_TARGET_FALLBACK,
			[
				mode_name,
				board_size.x,
				board_size.y,
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
			board_size.x,
			board_size.y,
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


func _get_progress_stats_system() -> ProgressStatsSystem:
	var system_value: Object = get_system(ProgressStatsSystem)
	if system_value is ProgressStatsSystem:
		var progress_stats_system: ProgressStatsSystem = system_value
		return progress_stats_system
	return null


func _get_celebration_vfx_utility() -> GameCelebrationVfxUtility:
	var utility_value: Object = get_utility(GameCelebrationVfxUtility)
	if utility_value is GameCelebrationVfxUtility:
		var celebration_vfx: GameCelebrationVfxUtility = utility_value
		return celebration_vfx
	return null


func _play_new_record_celebration_once() -> void:
	if _has_played_new_record_celebration:
		return
	_has_played_new_record_celebration = true
	var celebration_vfx: GameCelebrationVfxUtility = _get_celebration_vfx_utility()
	if is_instance_valid(celebration_vfx):
		var _played: bool = celebration_vfx.play_new_record_celebration()


func _drain_celebration() -> void:
	var celebration_vfx: GameCelebrationVfxUtility = _get_celebration_vfx_utility()
	if is_instance_valid(celebration_vfx):
		celebration_vfx.drain_active_celebrations()


func _get_current_topology(current_game_model: CurrentGameModel) -> BoardTopology:
	if not is_instance_valid(current_game_model):
		return null
	var topology_value: Variant = current_game_model.current_board_topology.get_value()
	if topology_value is BoardTopology:
		var topology: BoardTopology = topology_value
		return topology
	return null


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


func _get_current_stats(mode_config: GameModeConfig, topology: BoardTopology) -> Dictionary:
	if not is_instance_valid(mode_config):
		return {}
	if not is_instance_valid(topology):
		return {}
	var progress_stats_system: ProgressStatsSystem = _get_progress_stats_system()
	if not is_instance_valid(progress_stats_system):
		return {}
	var mode_id: String = mode_config.resource_path.get_file().get_basename()
	return progress_stats_system.get_game_stats(mode_id, topology.get_stable_key())


func _format_optional_stat(value: int) -> String:
	if value <= 0:
		return tr("UI_NONE")
	return str(value)


func _format_target_reached(value: bool) -> String:
	return tr("UI_TARGET_REACHED") if value else tr("UI_TARGET_NOT_REACHED")


# --- 信号处理函数 ---

## 响应"重来"按钮的点击事件。
func _on_restart_button_pressed() -> void:
	_drain_celebration()
	var _sent: bool = _close_current_popup_route_and_send_event(
		_ROUTE_GAME_OVER_MENU,
		EventNames.RESTART_GAME_REQUESTED
	)


## 响应"返回主界面"按钮的点击事件。
func _on_main_menu_button_pressed() -> void:
	_drain_celebration()
	var _sent: bool = _close_current_popup_route_and_send_event(
		_ROUTE_GAME_OVER_MENU,
		EventNames.RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED
	)


func _on_settings_button_pressed() -> void:
	_drain_celebration()
	var ui_router: GFUIRouterUtility = _get_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[GameOverMenu] 缺少 GFUIRouterUtility，无法打开设置菜单。")
		return
	var settings_panel: Node = ui_router.push_route(_ROUTE_SETTINGS_MENU, {}, {}, _configure_settings_panel)
	if not is_instance_valid(settings_panel):
		push_error("[GameOverMenu] GF UI 路由未能打开设置菜单。")
