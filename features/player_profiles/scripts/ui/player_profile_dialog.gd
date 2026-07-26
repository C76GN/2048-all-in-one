## PlayerProfileDialog: 本地账号、个人统计与设备榜单的统一入口。
class_name PlayerProfileDialog
extends GameUiController


# --- 常量 ---

## 720px 竖屏不能再挤压横向标题栏；在常见紧凑平板宽度前改为纵向分区。
const _COMPACT_BREAKPOINT: float = 800.0
const _MINIMUM_TOUCH_TARGET_SIZE: float = 44.0


# --- 私有变量 ---

var _account_system: LocalAccountSystem = null
var _progress_system: ProgressStatsSystem = null
var _mode_catalog: GameModeCatalogUtility = null
var _signal_utility: GFSignalUtility = null
var _viewport_utility: GFViewportUtility = null
var _mode_names: Dictionary = {}
var _leaderboard_identities: Array[Dictionary] = []
var _layout_update_queued: bool = false


# --- @onready 变量 ---

@onready var _outer_margin: MarginContainer = %OuterMargin
@onready var _header: BoxContainer = %Header
@onready var _title_label: Label = %TitleLabel
@onready var _account_option: OptionButton = %AccountOption
@onready var _back_button: Button = %BackButton
@onready var _account_tools: BoxContainer = %AccountTools
@onready var _name_input: LineEdit = %NameInput
@onready var _create_button: Button = %CreateButton
@onready var _rename_button: Button = %RenameButton
@onready var _delete_button: Button = %DeleteButton
@onready var _status_label: Label = %StatusLabel
@onready var _profile_tab: VBoxContainer = %ProfileTab
@onready var _leaderboard_tab: VBoxContainer = %LeaderboardTab
@onready var _account_summary_label: Label = %AccountSummaryLabel
@onready var _mode_list: VBoxContainer = %ModeList
@onready var _mode_empty_label: Label = %ModeEmptyLabel
@onready var _leaderboard_group_option: OptionButton = %LeaderboardGroupOption
@onready var _leaderboard_list: VBoxContainer = %LeaderboardList
@onready var _leaderboard_empty_label: Label = %LeaderboardEmptyLabel
@onready var _delete_confirmation: ConfirmationDialog = %DeleteConfirmation


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_resolve_dependencies()
	_bind_signals()
	_configure_confirmation_touch_targets()
	_update_static_text()
	_rebuild_all()
	_queue_layout_update()
	_account_option.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_dialog()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)


# --- 私有/辅助方法 ---

func _resolve_dependencies() -> void:
	var account_value: Object = get_system(LocalAccountSystem)
	if account_value is LocalAccountSystem:
		_account_system = account_value
	var progress_value: Object = get_system(ProgressStatsSystem)
	if progress_value is ProgressStatsSystem:
		_progress_system = progress_value
	var catalog_value: Object = get_utility(GameModeCatalogUtility)
	if catalog_value is GameModeCatalogUtility:
		_mode_catalog = catalog_value
	var signal_value: Object = get_utility(GFSignalUtility)
	if signal_value is GFSignalUtility:
		_signal_utility = signal_value
	var viewport_value: Object = get_utility(GFViewportUtility)
	if viewport_value is GFViewportUtility:
		_viewport_utility = viewport_value


func _bind_signals() -> void:
	if not is_instance_valid(_signal_utility):
		push_error("[PlayerProfileDialog] 缺少 GFSignalUtility。")
		return
	var _back_connection: GFSignalConnection = _signal_utility.connect_signal(
		_back_button.pressed,
		_close_dialog,
		self
	)
	var _account_connection: GFSignalConnection = _signal_utility.connect_signal(
		_account_option.item_selected,
		_on_account_selected,
		self
	)
	var _create_connection: GFSignalConnection = _signal_utility.connect_signal(
		_create_button.pressed,
		_on_create_pressed,
		self
	)
	var _rename_connection: GFSignalConnection = _signal_utility.connect_signal(
		_rename_button.pressed,
		_on_rename_pressed,
		self
	)
	var _delete_connection: GFSignalConnection = _signal_utility.connect_signal(
		_delete_button.pressed,
		_on_delete_pressed,
		self
	)
	var _delete_confirmed_connection: GFSignalConnection = _signal_utility.connect_signal(
		_delete_confirmation.confirmed,
		_on_delete_confirmed,
		self
	)
	var _group_connection: GFSignalConnection = _signal_utility.connect_signal(
		_leaderboard_group_option.item_selected,
		_on_leaderboard_group_selected,
		self
	)
	var _resize_connection: GFSignalConnection = _signal_utility.connect_signal(
		resized,
		_queue_layout_update,
		self
	)
	if is_instance_valid(_account_system):
		var _active_connection: GFSignalConnection = _signal_utility.connect_signal(
			_account_system.active_account_changed,
			_on_account_changed,
			self
		)
		var _catalog_connection: GFSignalConnection = _signal_utility.connect_signal(
			_account_system.account_catalog_changed,
			_on_account_catalog_changed,
			self
		)


func _update_static_text() -> void:
	_title_label.text = tr("PLAYER_PROFILE_TITLE")
	_back_button.text = tr("BACK_BUTTON")
	_name_input.placeholder_text = tr("PLAYER_NAME_PLACEHOLDER")
	_create_button.text = tr("PLAYER_CREATE")
	_rename_button.text = tr("PLAYER_RENAME")
	_delete_button.text = tr("PLAYER_DELETE")
	_profile_tab.name = tr("PLAYER_PROFILE_TAB")
	_leaderboard_tab.name = tr("LOCAL_LEADERBOARD_TAB")
	_delete_confirmation.title = tr("PLAYER_DELETE_CONFIRM_TITLE")
	_delete_confirmation.ok_button_text = tr("PLAYER_DELETE")
	_delete_confirmation.cancel_button_text = tr("DELETE_CANCEL_ACTION")


func _rebuild_all() -> void:
	_rebuild_account_selector()
	_rebuild_profile()
	_rebuild_leaderboard_groups()
	_rebuild_leaderboard()


func _rebuild_account_selector() -> void:
	_account_option.clear()
	if not is_instance_valid(_account_system):
		_set_status(tr("PLAYER_PROFILE_UNAVAILABLE"), true)
		return
	var accounts: Array[LocalPlayerAccount] = _account_system.get_accounts()
	var active: LocalPlayerAccount = _account_system.get_active_account()
	var selected_index: int = 0
	for index: int in range(accounts.size()):
		var account: LocalPlayerAccount = accounts[index]
		_account_option.add_item(account.display_name)
		_account_option.set_item_metadata(index, account.account_id)
		if active != null and active.account_id == account.account_id:
			selected_index = index
	_account_option.select(selected_index)
	_account_option.disabled = accounts.size() <= 1
	_delete_button.disabled = accounts.size() <= 1
	if active != null:
		_name_input.text = active.display_name


func _rebuild_profile() -> void:
	_clear_container(_mode_list)
	var active: LocalPlayerAccount = (
		_account_system.get_active_account()
		if is_instance_valid(_account_system)
		else null
	)
	if active == null or not is_instance_valid(_progress_system):
		_account_summary_label.text = tr("PLAYER_PROFILE_UNAVAILABLE")
		_mode_empty_label.visible = true
		_mode_list.visible = false
		return

	var summaries: Array[Dictionary] = (
		_progress_system.get_profile_mode_summaries(active.account_id)
	)
	var total_plays: int = 0
	var best_score: int = 0
	for summary: Dictionary in summaries:
		total_plays += GFVariantData.get_option_int(summary, &"plays", 0)
		best_score = maxi(
			best_score,
			GFVariantData.get_option_int(summary, &"best_score", 0)
		)
		_mode_list.add_child(_make_mode_summary_row(summary))
	_account_summary_label.text = tr("PLAYER_ACCOUNT_SUMMARY") % [
		active.display_name,
		total_plays,
		best_score,
		GameClockUtility.format_datetime_value(active.last_active_at),
	]
	_mode_empty_label.visible = summaries.is_empty()
	_mode_empty_label.text = tr("PLAYER_MODE_STATS_EMPTY")
	_mode_list.visible = not summaries.is_empty()


func _make_mode_summary_row(summary: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.y = 88.0
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	var mode_id: String = GFVariantData.get_option_string(summary, &"mode_id")
	var title: Label = Label.new()
	title.text = _resolve_mode_name(mode_id)
	title.add_theme_font_size_override("font_size", 20)
	content.add_child(title)
	var metrics: Label = Label.new()
	metrics.text = tr("PLAYER_MODE_METRICS") % [
		GFVariantData.get_option_int(summary, &"plays", 0),
		GFVariantData.get_option_int(summary, &"best_score", 0),
		GFVariantData.get_option_int(summary, &"max_tile", 0),
	]
	metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(metrics)
	var timing: Label = Label.new()
	timing.text = tr("PLAYER_MODE_TIMING") % [
		_format_duration(
			GFVariantData.get_option_int(
				summary,
				&"best_duration_msec",
				0
			)
		),
		_format_duration(
			GFVariantData.get_option_int(
				summary,
				&"average_duration_msec",
				0
			)
		),
	]
	timing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(timing)
	return panel


func _rebuild_leaderboard_groups() -> void:
	var selected_key: String = ""
	if (
		not _leaderboard_identities.is_empty()
		and _leaderboard_group_option.selected >= 0
		and _leaderboard_group_option.selected < _leaderboard_identities.size()
	):
		selected_key = GameResultRecordedData.calculate_leaderboard_group_key(
			_leaderboard_identities[_leaderboard_group_option.selected]
		)
	_leaderboard_group_option.clear()
	_leaderboard_identities.clear()
	if not is_instance_valid(_progress_system):
		_set_empty_leaderboard_group_option()
		return
	_leaderboard_identities = (
		_progress_system.get_device_leaderboard_identities()
	)
	var selected_index: int = 0
	for index: int in range(_leaderboard_identities.size()):
		var identity: Dictionary = _leaderboard_identities[index]
		_leaderboard_group_option.add_item(_make_group_label(identity))
		if (
			GameResultRecordedData.calculate_leaderboard_group_key(identity)
			== selected_key
		):
			selected_index = index
	if not _leaderboard_identities.is_empty():
		_leaderboard_group_option.select(selected_index)
		_leaderboard_group_option.disabled = false
	else:
		_set_empty_leaderboard_group_option()


func _rebuild_leaderboard() -> void:
	_clear_container(_leaderboard_list)
	if (
		not is_instance_valid(_progress_system)
		or _leaderboard_identities.is_empty()
	):
		_leaderboard_empty_label.visible = true
		_leaderboard_empty_label.text = tr("LOCAL_LEADERBOARD_EMPTY")
		_leaderboard_list.visible = false
		return
	var selected_index: int = clampi(
		_leaderboard_group_option.selected,
		0,
		_leaderboard_identities.size() - 1
	)
	var rows: Array[Dictionary] = _progress_system.get_device_local_leaderboard(
		_leaderboard_identities[selected_index]
	)
	for row: Dictionary in rows:
		_leaderboard_list.add_child(_make_leaderboard_row(row))
	_leaderboard_empty_label.visible = rows.is_empty()
	_leaderboard_empty_label.text = tr("LOCAL_LEADERBOARD_EMPTY")
	_leaderboard_list.visible = not rows.is_empty()


func _set_empty_leaderboard_group_option() -> void:
	_leaderboard_group_option.add_item(tr("LOCAL_LEADERBOARD_ALL_MODES"))
	_leaderboard_group_option.select(0)
	_leaderboard_group_option.disabled = true


func _make_leaderboard_row(row: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.y = 62.0
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var content: HBoxContainer = HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var rank_label: Label = Label.new()
	rank_label.custom_minimum_size.x = 44.0
	rank_label.text = "#%d" % GFVariantData.get_option_int(row, &"rank", 0)
	rank_label.add_theme_font_size_override("font_size", 20)
	content.add_child(rank_label)
	var name_label: Label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = GFVariantData.get_option_string(row, &"display_name")
	content.add_child(name_label)
	var result_value: Variant = GFVariantData.get_option_value(row, &"result")
	var result: GameResultRecordedData = (
		result_value if result_value is GameResultRecordedData else null
	)
	var score_label: Label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.text = (
		tr("LOCAL_LEADERBOARD_SCORE") % [
			result.score,
			result.max_tile,
			result.steps,
		]
		if result != null
		else "-"
	)
	content.add_child(score_label)
	return panel


func _make_group_label(identity: Dictionary) -> String:
	return tr("LOCAL_LEADERBOARD_GROUP") % [
		_resolve_mode_name(
			GFVariantData.get_option_string(identity, &"mode_id")
		),
		_resolve_board_display_name(
			GFVariantData.get_option_string(identity, &"board_key")
		),
		GFVariantData.get_option_int(identity, &"ruleset_version", 0),
	]


func _resolve_mode_name(mode_id: String) -> String:
	if _mode_names.has(mode_id):
		return tr(GFVariantData.get_option_string(_mode_names, mode_id))
	if is_instance_valid(_mode_catalog):
		for config_path: String in _mode_catalog.get_registered_config_paths():
			if config_path.get_file().get_basename() != mode_id:
				continue
			var config: GameModeConfig = _mode_catalog.get_config(config_path)
			if config != null:
				_mode_names[mode_id] = config.mode_name
				return tr(config.mode_name)
	return tr("UNKNOWN_MODE")


## 把用于严格分组的稳定棋盘键转换为玩家可读文案，绝不把资源 ID 或指纹带到 UI。
func _resolve_board_display_name(board_key: String) -> String:
	var topology_id: String = board_key.get_slice("@", 0)
	if topology_id.begins_with("board.player."):
		return tr("BOARD_EDITOR_OPEN")
	var dimensions: String = _extract_board_dimensions(topology_id)
	if not dimensions.is_empty():
		return "%s %s" % [dimensions, tr("LOCAL_LEADERBOARD_BOARD_GENERIC")]
	return tr("LOCAL_LEADERBOARD_BOARD_GENERIC")


func _extract_board_dimensions(topology_id: String) -> String:
	var segments: PackedStringArray = topology_id.split(".")
	if segments.is_empty():
		return ""
	var candidate: String = segments[segments.size() - 1]
	var axes: PackedStringArray = candidate.split("x")
	if axes.size() != 2 or not axes[0].is_valid_int() or not axes[1].is_valid_int():
		return ""
	var width: int = axes[0].to_int()
	var height: int = axes[1].to_int()
	if width <= 0 or height <= 0:
		return ""
	return "%d×%d" % [width, height]


func _format_duration(duration_msec: int) -> String:
	if duration_msec <= 0:
		return tr("PLAYER_TIME_NONE")
	var total_seconds: int = int(duration_msec / 1000.0)
	var hours: int = int(total_seconds / 3600.0)
	var minutes: int = int((total_seconds % 3600) / 60.0)
	var seconds: int = total_seconds % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]


func _clear_container(container: Node) -> void:
	for child: Node in container.get_children():
		child.queue_free()


func _configure_confirmation_touch_targets() -> void:
	var ok_button: Button = _delete_confirmation.get_ok_button()
	var cancel_button: Button = _delete_confirmation.get_cancel_button()
	if is_instance_valid(ok_button):
		ok_button.custom_minimum_size = Vector2(
			112.0,
			_MINIMUM_TOUCH_TARGET_SIZE
		)
	if is_instance_valid(cancel_button):
		cancel_button.custom_minimum_size = Vector2(
			112.0,
			_MINIMUM_TOUCH_TARGET_SIZE
		)


func _set_status(message: String, is_error: bool = false) -> void:
	_status_label.text = message
	_status_label.visible = not message.is_empty()
	_status_label.modulate = (
		Color(1.0, 0.62, 0.55) if is_error else Color(0.7, 0.9, 0.72)
	)


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var compact: bool = size.x < _COMPACT_BREAKPOINT
	_header.vertical = compact
	_account_tools.vertical = compact
	var margins: Dictionary = (
		{"top": 8.0, "left": 8.0, "bottom": 8.0, "right": 8.0}
		if compact
		else {"top": 22.0, "left": 28.0, "bottom": 22.0, "right": 28.0}
	)
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = (
			_viewport_utility.apply_display_safe_area_margins(
				_outer_margin,
				get_viewport(),
				margins
			)
		)


func _selected_account_id() -> String:
	if _account_option.selected < 0:
		return ""
	var value: Variant = _account_option.get_item_metadata(
		_account_option.selected
	)
	return value if value is String else ""


func _close_dialog() -> void:
	var _closed: bool = _close_current_popup_route(
		GameUiRouterUtility.ROUTE_PLAYER_PROFILE
	)


# --- 信号处理函数 ---

func _on_account_selected(index: int) -> void:
	if not is_instance_valid(_account_system):
		return
	var value: Variant = _account_option.get_item_metadata(index)
	if not value is String:
		return
	var account_id: String = GFVariantData.to_text(value)
	var error: Error = _account_system.switch_account(account_id)
	if error != OK:
		_set_status(tr("PLAYER_SWITCH_FAILED") % error, true)
		_rebuild_account_selector()
	else:
		_set_status(tr("PLAYER_SWITCHED"), false)
		_rebuild_all()


func _on_create_pressed() -> void:
	if not is_instance_valid(_account_system):
		return
	var error: Error = _account_system.create_account(_name_input.text)
	if error != OK:
		_set_status(tr("PLAYER_CREATE_FAILED") % error, true)
		return
	_name_input.clear()
	_set_status(tr("PLAYER_CREATED"), false)
	_rebuild_all()


func _on_rename_pressed() -> void:
	if not is_instance_valid(_account_system):
		return
	var account_id: String = _selected_account_id()
	var error: Error = _account_system.rename_account(
		account_id,
		_name_input.text
	)
	if error != OK:
		_set_status(tr("PLAYER_RENAME_FAILED") % error, true)
		return
	_set_status(tr("PLAYER_RENAMED"), false)
	_rebuild_all()


func _on_delete_pressed() -> void:
	if _delete_button.disabled:
		return
	var active: LocalPlayerAccount = (
		_account_system.get_active_account()
		if is_instance_valid(_account_system)
		else null
	)
	if active == null:
		return
	_delete_confirmation.dialog_text = tr("PLAYER_DELETE_CONFIRM") % (
		active.display_name
	)
	_delete_confirmation.popup_centered()


func _on_delete_confirmed() -> void:
	if not is_instance_valid(_account_system):
		return
	var account_id: String = _selected_account_id()
	var error: Error = _account_system.delete_account(account_id)
	if error != OK:
		_set_status(tr("PLAYER_DELETE_FAILED") % error, true)
		return
	_set_status(tr("PLAYER_DELETED"), false)
	_rebuild_all()


func _on_leaderboard_group_selected(_index: int) -> void:
	_rebuild_leaderboard()


func _on_account_changed(_account: LocalPlayerAccount) -> void:
	_rebuild_all()


func _on_account_catalog_changed() -> void:
	_rebuild_all()
