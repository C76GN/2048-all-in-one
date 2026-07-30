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
const _RESULT_IDENTITY_FORMAT_FALLBACK: String = "种子 %d · 状态校验 %s"
const _COMPETITION_ELIGIBLE_FALLBACK: String = "本地比赛榜：合格"
const _COMPETITION_RANK_FORMAT_FALLBACK: String = "本地比赛榜：合格 · 第 %d 名"
const _COMPETITION_INELIGIBLE_FORMAT_FALLBACK: String = "本地比赛榜：不计入 · %s"
const _MAX_SURFACE_WIDTH: float = 620.0
const _MIN_SURFACE_WIDTH: float = 280.0
const _SURFACE_HORIZONTAL_GUTTER: float = 72.0
const _STACK_ACTIONS_MAX_WIDTH: float = 600.0


# --- 私有变量 ---

var _has_played_new_record_celebration: bool = false
var _has_revealed_result: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _summary_surface: SurfaceVboxContainer = $CenterContainer/VBoxContainer
@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _new_record_label: Label = $CenterContainer/VBoxContainer/NewRecordLabel
@onready var _context_label: Label = $CenterContainer/VBoxContainer/ContextLabel
@onready var _run_summary_label: Label = $CenterContainer/VBoxContainer/RunSummaryLabel
@onready var _summary_separator: HSeparator = $CenterContainer/VBoxContainer/SummarySeparator
@onready var _summary_label: Label = $CenterContainer/VBoxContainer/SummaryLabel
@onready var _identity_label: Label = $CenterContainer/VBoxContainer/IdentityLabel
@onready var _actions: GridContainer = $CenterContainer/VBoxContainer/Actions
@onready var _restart_button: Button = %RestartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	var _connect_result_24: int = _restart_button.pressed.connect(_on_restart_button_pressed)
	var _connect_result_25: int = _settings_button.pressed.connect(_on_settings_button_pressed)
	var _connect_result_26: int = _main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	var _resized_connect: int = resized.connect(_apply_responsive_layout)

	_update_ui_text()
	_apply_visual_style()
	_apply_responsive_layout()
	call_deferred(&"_refresh_summary")
	_restart_button.grab_focus()


# --- 私有/辅助方法 ---

func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_GAME_OVER")
	if is_instance_valid(_new_record_label):
		_new_record_label.text = tr("GAME_OVER_NEW_RECORD_PREFIX")
		_new_record_label.visible = false
	if is_instance_valid(_context_label):
		_context_label.visible = false
	if is_instance_valid(_run_summary_label):
		_run_summary_label.visible = false
	if is_instance_valid(_identity_label):
		_identity_label.visible = false
	if is_instance_valid(_summary_label):
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
	style_utility.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY, 32, true)
	style_utility.style_label(
		_new_record_label,
		GameUiStyleUtility.TextRole.PRIMARY,
		20,
		true
	)
	style_utility.style_label(
		_context_label,
		GameUiStyleUtility.TextRole.PRIMARY,
		16
	)
	style_utility.style_label(
		_run_summary_label,
		GameUiStyleUtility.TextRole.NUMERIC,
		20
	)
	style_utility.style_separator(_summary_separator)
	style_utility.style_label(
		_summary_label,
		GameUiStyleUtility.TextRole.SECONDARY,
		15
	)
	style_utility.style_label(
		_identity_label,
		GameUiStyleUtility.TextRole.MUTED,
		13
	)
	style_utility.style_button(
		_restart_button,
		GameUiStyleUtility.ButtonRole.PRIMARY
	)
	style_utility.style_button(
		_settings_button,
		GameUiStyleUtility.ButtonRole.SECONDARY
	)
	style_utility.style_button(
		_main_menu_button,
		GameUiStyleUtility.ButtonRole.QUIET
	)


func _apply_responsive_layout() -> void:
	if (
		not is_instance_valid(_summary_surface)
		or not is_instance_valid(_actions)
	):
		return
	var available_width: float = size.x
	if available_width <= 0.0:
		available_width = get_viewport_rect().size.x
	var surface_width: float = clampf(
		available_width - _SURFACE_HORIZONTAL_GUTTER,
		_MIN_SURFACE_WIDTH,
		_MAX_SURFACE_WIDTH
	)
	_summary_surface.custom_minimum_size.x = surface_width
	_actions.columns = 1 if available_width < _STACK_ACTIONS_MAX_WIDTH else 3


func _refresh_summary() -> void:
	if not is_instance_valid(_summary_label):
		return

	var status_model: GameStatusModel = _get_game_status_model()
	if not is_instance_valid(status_model):
		_new_record_label.visible = false
		_context_label.visible = false
		_run_summary_label.visible = false
		_identity_label.visible = false
		_summary_label.text = tr("GAME_OVER_SUMMARY_UNAVAILABLE")
		_play_result_reveal_once()
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

	var is_new_record: bool = score > initial_high_score
	if is_new_record:
		_play_new_record_celebration_once()
	var summary_text: String = ""
	if target_value > 0:
		summary_text = GameTextFormatUtility.format_template(
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
	else:
		summary_text = GameTextFormatUtility.format_template(
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
	var result_explanation: String = _format_result_explanation(
		_get_last_game_result(current_game_model)
	)
	var end_reason_explanation: String = _get_end_reason_explanation()
	_apply_summary_sections(
		summary_text,
		is_new_record,
		end_reason_explanation,
		result_explanation
	)
	_play_result_reveal_once()


func _apply_summary_sections(
	summary_text: String,
	is_new_record: bool,
	end_reason_explanation: String,
	result_explanation: String
) -> void:
	var lines: PackedStringArray = summary_text.split("\n", false)
	_new_record_label.visible = is_new_record
	_context_label.text = lines[0].strip_edges() if lines.size() > 0 else ""
	_context_label.visible = not _context_label.text.is_empty()
	_run_summary_label.text = lines[1].strip_edges() if lines.size() > 1 else ""
	_run_summary_label.visible = not _run_summary_label.text.is_empty()

	var detail_lines: PackedStringArray = PackedStringArray()
	for index: int in range(2, lines.size()):
		var detail_line: String = lines[index].strip_edges()
		if not detail_line.is_empty():
			var _detail_appended: bool = detail_lines.append(detail_line)
	if not end_reason_explanation.is_empty():
		var _reason_appended: bool = detail_lines.append(end_reason_explanation)
	_summary_label.text = (
		"\n".join(detail_lines)
		if not detail_lines.is_empty()
		else tr("GAME_OVER_SUMMARY_UNAVAILABLE")
	)

	_identity_label.text = result_explanation
	_identity_label.visible = not result_explanation.is_empty()


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


## 读取流程系统发布的权威结束上下文；状态模型不持有结束原因。
func _get_game_flow_system() -> GameFlowSystem:
	var system_value: Object = get_system(GameFlowSystem)
	if system_value is GameFlowSystem:
		var game_flow_system: GameFlowSystem = system_value
		return game_flow_system
	return null


func _get_end_reason_explanation() -> String:
	var game_flow_system: GameFlowSystem = _get_game_flow_system()
	if not is_instance_valid(game_flow_system):
		return ""
	var session_context: Dictionary = game_flow_system.get_accessibility_context()
	var end_reason: StringName = GFVariantData.get_option_string_name(
		session_context,
		&"end_reason"
	)
	if end_reason == &"no_moves":
		return tr("GAME_OVER_END_REASON_NO_MOVES")
	return ""


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


func _play_result_reveal_once() -> void:
	if _has_revealed_result:
		return
	_has_revealed_result = true
	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion):
		return
	var result_controls: Array[Control] = [
		_title_label,
		_new_record_label,
		_context_label,
		_run_summary_label,
		_summary_separator,
		_summary_label,
		_identity_label,
	]
	var _revealed_count: int = motion.play_reward_result_controls(
		result_controls
	)


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


func _get_last_game_result(
	current_game_model: CurrentGameModel
) -> GameResultRecordedData:
	if not is_instance_valid(current_game_model):
		return null
	var result_value: Variant = current_game_model.last_game_result.get_value()
	return result_value if result_value is GameResultRecordedData else null


func _format_result_explanation(result: GameResultRecordedData) -> String:
	if result == null or not result.is_valid():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	var _ignored_identity_appended: bool = lines.append(GameTextFormatUtility.format_template(
		tr("GAME_OVER_RESULT_IDENTITY_FORMAT"),
		_RESULT_IDENTITY_FORMAT_FALLBACK,
		[
			result.initial_seed,
			result.final_state_hash.substr(0, 12),
		]
	))
	if result.is_competition_eligible():
		var progress_stats: ProgressStatsSystem = _get_progress_stats_system()
		var rank: int = (
			progress_stats.get_local_rank(result)
			if is_instance_valid(progress_stats)
			else 0
		)
		var _ignored_rank_appended: bool = lines.append(
			GameTextFormatUtility.format_template(
				tr("GAME_OVER_COMPETITION_RANK_FORMAT"),
				_COMPETITION_RANK_FORMAT_FALLBACK,
				[rank]
			)
			if rank > 0
			else GameTextFormatUtility.format_template(
				tr("GAME_OVER_COMPETITION_ELIGIBLE"),
				_COMPETITION_ELIGIBLE_FALLBACK,
				[]
			)
		)
	else:
		var reason_labels: PackedStringArray = PackedStringArray()
		for reason_code: StringName in (
			result.competition_eligibility.get_disqualifying_reason_codes()
		):
			var _ignored_reason_appended: bool = reason_labels.append(
				_get_eligibility_reason_label(reason_code)
			)
		var reason_separator: String = tr("ELIGIBILITY_REASON_SEPARATOR")
		if reason_separator == "ELIGIBILITY_REASON_SEPARATOR":
			reason_separator = "、"
		var _ignored_ineligible_appended: bool = lines.append(GameTextFormatUtility.format_template(
			tr("GAME_OVER_COMPETITION_INELIGIBLE_FORMAT"),
			_COMPETITION_INELIGIBLE_FORMAT_FALLBACK,
			[reason_separator.join(reason_labels)]
		))
	return "\n".join(lines)


func _get_eligibility_reason_label(reason_code: StringName) -> String:
	match reason_code:
		GameCompetitionEligibility.REASON_DEBUG:
			return tr("ELIGIBILITY_REASON_DEBUG")
		GameCompetitionEligibility.REASON_REPLAY_CONTINUATION:
			return tr("ELIGIBILITY_REASON_REPLAY_CONTINUATION")
		GameCompetitionEligibility.REASON_BOOKMARK:
			return tr("ELIGIBILITY_REASON_BOOKMARK")
		GameCompetitionEligibility.REASON_UNDO_REDO:
			return tr("ELIGIBILITY_REASON_UNDO_REDO")
		GameCompetitionEligibility.REASON_CUSTOM_BOARD:
			return tr("ELIGIBILITY_REASON_CUSTOM_BOARD")
		GameCompetitionEligibility.REASON_MANUAL_SEED:
			return tr("ELIGIBILITY_REASON_MANUAL_SEED")
	return String(reason_code)


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
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[GameOverMenu] 缺少 GFUIRouterUtility，无法打开设置菜单。")
		return
	var result: GFUIRouteResult = await ui_router.push_owned_route_async(
		self,
		_ROUTE_SETTINGS_MENU,
		{},
		{},
		_configure_settings_panel,
		GFUIRouterUtility.PRELOAD_NONE
	)
	if result != null and not result.is_successful():
		push_error("[GameOverMenu] GF UI 路由未能打开设置菜单：status=%s, reason=%s。" % [
			result.get_status(),
			result.get_reason(),
		])
