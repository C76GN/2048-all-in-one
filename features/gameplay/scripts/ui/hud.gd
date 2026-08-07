## Hud: 游戏界面的状态显示器。
##
## 该脚本负责接收来自游戏控制器的数据，并将其格式化后显示在对应的UI标签上。
## 它会根据传入数据的键动态创建或复用标签，实现对不同游戏模式的自适应。
class_name Hud
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 常量 ---

## 动态流程标签列表场景。
const FLOW_LABEL_LIST_SCENE: PackedScene = preload("res://shared/scenes/ui/flow_label_list.tscn")
const GameHintResultType = preload(
	"res://features/gameplay/scripts/data/game_hint_result.gd"
)
const DeterministicHintQueryType = preload(
	"res://features/gameplay/scripts/queries/deterministic_hint_query.gd"
)
const _SCORE_DELTA_LABEL_SCENE: PackedScene = preload(
	"res://features/gameplay/scenes/ui/score_delta_label.tscn"
)
const _FEEDBACK_SCALE: float = 1.035
const _FEEDBACK_DURATION: float = 0.22
const _FEEDBACK_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _SCORE_FORMAT_FALLBACK: String = "分数: %d"
const _MOVE_COUNT_FORMAT_FALLBACK: String = "移动次数: %d"
const _HIGH_SCORE_FORMAT_FALLBACK: String = "最高分: %d"
const _HIGHEST_TILE_FORMAT_FALLBACK: String = "最大方块: %d"
const _HUD_INPUT_SOURCE_ID: StringName = &"gameplay.hud_controls"
const _HUD_ACTION_HOLD_SECONDS: float = 0.08
const _SCORE_FEEDBACK_DELAY_SECONDS: float = 0.055
const _HINT_MAX_STEPS: int = 12000
const _HINT_MAX_ELAPSED_MSEC: int = 12
const _HINT_UNAVAILABLE_FALLBACK: String = "当前棋盘无法生成提示。"
const _ACCESSIBILITY_SUBTITLE_DURATION_SECONDS: float = 3.6
const _NOTIFICATION_TEXT_COLOR: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
const _NOTIFICATION_INFO_COLOR: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
const _NOTIFICATION_SUCCESS_COLOR: Color = Color(0.49411765, 0.79607844, 0.827451, 1.0)
const _NOTIFICATION_WARNING_COLOR: Color = Color(0.9372549, 0.81960785, 0.3647059, 1.0)
const _NOTIFICATION_ERROR_COLOR: Color = Color(0.827451, 0.38431373, 0.29411766, 1.0)
const _NOTIFICATION_OFFSET_SCALE_LOW: float = 0.75
const _NOTIFICATION_OFFSET_SCALE_NORMAL: float = 1.0
const _NOTIFICATION_OFFSET_SCALE_HIGH: float = 1.25
const _NOTIFICATION_OFFSET_SCALE_CRITICAL: float = 1.5
const _NOTIFICATION_SURFACE_HEIGHT: float = 68.0
const _WIDE_SIDE_CARD_MINIMUM_WIDTH: float = 1440.0
const _ACTION_ICON_ASSET_KEYS: Dictionary = {
	"%PauseButton": &"asset.texture.icon.pause",
	"%UndoButton": &"asset.texture.icon.undo_2",
	"%RedoButton": &"asset.texture.icon.redo_2",
	"%BookmarkButton": &"asset.texture.icon.bookmark_plus",
}


# --- 私有变量 ---

## 一个字典，用于缓存已创建的UI节点，以避免每帧重复创建。
## 结构: { "data_key": ControlNode }
var _stat_labels: Dictionary = {}

var _is_dirty: bool = false
var _game_status_model: GameStatusModel
var _grid_model: GridModel
var _determinism_utility: GameDeterminismUtility
var _notification_utility: GFNotificationUtility
var _signal_utility: GFSignalUtility
var _ui_style_utility: GameUiStyleUtility
var _ui_motion_utility: GameUiMotionUtility
var _accessibility_utility: GameAccessibilityUtility
var _accessibility_summary_utility: GameAccessibilitySummaryUtility
var _score_value_label: Label
var _score_gain_label: Label
var _move_count_value_label: Label
var _highest_tile_value_label: Label
var _score_caption_label: Label
var _moves_caption_label: Label
var _highest_tile_caption_label: Label
var _notification_label: RichTextLabel
var _notification_panel: PanelContainer
var _notification_slot: Control
var _feedback_rail: VBoxContainer
var _details_panel: Control
var _details_toggle_button: Button
var _active_notification_id: int = 0
var _last_display_values: Dictionary = {}
var _is_compact_mode: bool = false
var _is_portrait_mode: bool = false
var _details_expanded: bool = true
var _input_mapping: GFInputMappingUtility
var _realtime_timer: GameRealtimeTimerUtility
var _hud_input_source: GFVirtualInputSource
var _hud_action_pulse: GameVirtualActionPulseUtility
var _safe_area: Control
var _move_hint_label: Label
var _action_hint_label: Label
var _top_score_panel: PanelContainer
var _control_hint_panel: PanelContainer
var _hints: VBoxContainer
var _d_pad: GridContainer
var _action_panel: PanelContainer
var _hint_button: Button
var _hint_result_panel: PanelContainer
var _hint_result_label: RichTextLabel
var _hint_snapshot_id: String = ""
var _hint_cancel_source: GFCancellationSource
var _accessibility_subtitle_panel: PanelContainer
var _accessibility_subtitle_label: Label
var _board_summary_label: RichTextLabel
var _copy_board_summary_button: Button
var _board_info_panel: PanelContainer
var _board_info_label: Label
var _accessibility_subtitle_serial: int = 0
var _score_feedback_delay_active: bool = false
var _score_feedback_pending: bool = false
var _pending_score_feedback_old: int = 0
var _pending_score_feedback_new: int = 0
var _notification_motion_tween: Tween
var _notification_rest_position: Vector2 = Vector2.ZERO
var _notification_rest_position_valid: bool = false


# --- @onready 变量 (节点引用) ---

@onready var _stats_container: VBoxContainer = %StatsContainer
@onready var _title_label: Label = %TitleLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_game_status_model = _get_game_status_model()
	_grid_model = _get_grid_model()
	_determinism_utility = _get_determinism_utility()
	_notification_utility = _get_notification_utility()
	_signal_utility = _get_signal_utility()
	_ui_style_utility = _get_ui_style_utility()
	_ui_motion_utility = _get_ui_motion_utility()
	_accessibility_utility = _get_accessibility_utility()
	_accessibility_summary_utility = _get_accessibility_summary_utility()
	_input_mapping = _get_input_mapping_utility()
	_realtime_timer = _get_realtime_timer_utility()
	if is_instance_valid(_input_mapping) and is_instance_valid(_realtime_timer):
		_hud_input_source = _input_mapping.create_virtual_source(
			_HUD_INPUT_SOURCE_ID,
			-1,
			_realtime_timer
		)
		_hud_action_pulse = GameVirtualActionPulseUtility.new().configure(_hud_input_source)
	elif not is_instance_valid(_realtime_timer):
		push_error("[Hud] 缺少 GameRealtimeTimerUtility，无法创建有界 HUD 输入脉冲。")
	if not is_instance_valid(_ui_style_utility):
		push_error("[Hud] 缺少 GameUiStyleUtility，无法应用 HUD 语义样式。")
	if not is_instance_valid(_ui_motion_utility):
		push_error("[Hud] 缺少 GameUiMotionUtility，无法播放状态反馈动效。")
	
	_score_value_label = _get_label_node("%ScoreValueLabel")
	_move_count_value_label = _get_label_node("%MoveCountValueLabel")
	_highest_tile_value_label = _get_label_node("%HighestTileValueLabel")
	_score_caption_label = _get_label_node("%ScoreCaptionLabel")
	_moves_caption_label = _get_label_node("%MovesCaptionLabel")
	_highest_tile_caption_label = _get_label_node("%HighestTileCaptionLabel")
	_notification_label = _get_rich_text_label_node("%NotificationLabel")
	_notification_panel = _get_panel_container_node("%NotificationPanel")
	_notification_slot = _get_control_node("%NotificationSlot")
	_feedback_rail = _get_vbox_container_node("%FeedbackRail")
	_details_panel = _get_control_node("%DetailsPanel")
	_details_toggle_button = _get_button_node("%DetailsToggleButton")
	_safe_area = _get_control_node("%SafeArea")
	_move_hint_label = _get_label_node("%MoveHintLabel")
	_action_hint_label = _get_label_node("%ActionHintLabel")
	_top_score_panel = _get_panel_container_node("%TopScorePanel")
	_control_hint_panel = _get_panel_container_node("%ControlHintPanel")
	_hints = _get_vbox_container_node("%Hints")
	_d_pad = _get_grid_container_node("%DPad")
	_action_panel = _get_panel_container_node("%ActionPanel")
	_hint_button = _get_button_node("%HintButton")
	_hint_result_panel = _get_panel_container_node("%HintResultPanel")
	_hint_result_label = _get_rich_text_label_node("%HintResultLabel")
	_accessibility_subtitle_panel = _get_panel_container_node(
		"%AccessibilitySubtitlePanel"
	)
	_accessibility_subtitle_label = _get_label_node(
		"%AccessibilitySubtitleLabel"
	)
	_board_summary_label = _get_rich_text_label_node("%BoardSummaryLabel")
	_copy_board_summary_button = _get_button_node("%CopyBoardSummaryButton")
	_board_info_panel = _get_panel_container_node("%BoardInfoPanel")
	_board_info_label = _get_label_node("%BoardInfoLabel")
	if not is_instance_valid(_notification_label):
		push_error("[Hud] 缺少 NotificationLabel，无法呈现 GF 通知。")
	if not is_instance_valid(_grid_model) or not is_instance_valid(_determinism_utility):
		push_error("[Hud] 缺少棋盘或确定性工具，提示功能不可用。")
	
	if is_instance_valid(_game_status_model):
		_game_status_model.score.bind_to(self, _on_score_changed)
		_game_status_model.move_count.bind_to(self, _on_move_count_changed)
		_game_status_model.high_score.bind_to(self, _on_high_score_changed)
		_game_status_model.highest_tile.bind_to(self, _on_highest_tile_changed)
		_game_status_model.ratio_resolutions.bind_to(self, _on_ratio_resolutions_changed)
		_game_status_model.extra_stats.bind_to(self, _on_extra_stats_changed)
		
		_refresh_all()

	_connect_notification_signals()
	_connect_compact_hud_signals()
	_connect_hud_action_signals()
	_connect_accessibility_summary_signals()
	_sync_active_notification()
	register_simple_event(EventNames.HUD_UPDATE_REQUESTED, GFEventListener.from_method(self, &"_on_hud_update_requested", 1))
	register_simple_event(EventNames.HINT_REQUESTED, GFEventListener.from_method(self, &"_on_hint_requested", 1))
	register_simple_event(EventNames.BOARD_REFRESH_REQUESTED, GFEventListener.from_method(self, &"_on_hint_invalidated", 1))
	register_simple_event(EventNames.BOARD_RESIZED, GFEventListener.from_method(self, &"_on_hint_invalidated", 1))
	register_simple_event(EventNames.GAME_STATE_CHANGED, GFEventListener.from_method(self, &"_on_hint_invalidated", 1))
	_update_ui_text()
	_apply_semantic_styles()
	_apply_hud_layout()
	_apply_details_visibility()
	_refresh_board_info()


func _exit_tree() -> void:
	_score_feedback_delay_active = false
	_score_feedback_pending = false
	_accessibility_subtitle_serial += 1
	_kill_notification_motion(true)
	_hide_accessibility_subtitle()
	_cancel_hint_query(&"hud_exited")
	_hide_hint_result()
	if is_instance_valid(_hud_action_pulse):
		_hud_action_pulse.dispose()
	_hud_action_pulse = null
	_hud_input_source = null
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	super._exit_tree()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 公共方法 ---

## 切换移动端紧凑状态；紧凑状态默认折叠低频详情。
## @param enabled: 是否启用紧凑状态。
func set_compact_mode(enabled: bool) -> void:
	if enabled and not _is_compact_mode:
		_details_expanded = false
	elif not enabled and _is_compact_mode and not _is_portrait_mode:
		_details_expanded = _safe_area.size.x >= _WIDE_SIDE_CARD_MINIMUM_WIDTH
	_is_compact_mode = enabled
	_apply_hud_layout()
	_apply_details_visibility()


## 切换竖屏触控布局；方向区只在该布局常驻。
## @param enabled: 是否为竖屏玩法布局。
func set_portrait_mode(enabled: bool) -> void:
	_is_portrait_mode = enabled
	_apply_hud_layout()


## 应用屏幕安全区；HUD 保持一个父节点，只调整可用屏幕边界。
## @param insets: 包含 top、left、bottom、right 的屏幕内缩字典。
func apply_screen_insets(insets: Dictionary) -> void:
	if not is_instance_valid(_safe_area):
		return
	_safe_area.offset_left = GFVariantData.get_option_float(insets, "left")
	_safe_area.offset_top = GFVariantData.get_option_float(insets, "top")
	_safe_area.offset_right = -GFVariantData.get_option_float(insets, "right")
	_safe_area.offset_bottom = -GFVariantData.get_option_float(insets, "bottom")


# --- 私有/辅助方法 ---

## 全局刷新 UI 显示。
func _refresh_all() -> void:
	if not is_instance_valid(_game_status_model):
		return

	# 1. 更新显式标签
	var score_value: int = GFVariantData.to_int(_game_status_model.score.get_value(), 0)
	var move_count_value: int = GFVariantData.to_int(_game_status_model.move_count.get_value(), 0)
	var high_score_value: int = GFVariantData.to_int(_game_status_model.high_score.get_value(), 0)
	var highest_tile_value: int = GFVariantData.to_int(_game_status_model.highest_tile.get_value(), 0)

	if is_instance_valid(_score_value_label):
		_score_value_label.text = str(score_value)
	
	if is_instance_valid(_move_count_value_label):
		_move_count_value_label.text = str(move_count_value)

	if is_instance_valid(_highest_tile_value_label):
		_highest_tile_value_label.text = str(highest_tile_value)
	
	var local_dict: Dictionary = {}
	
	if not is_instance_valid(_score_value_label):
		var score_text: String = tr("LABEL_SCORE")
		if score_text == "LABEL_SCORE" or not ":" in score_text:
			score_text = tr("SCORE_LABEL")
		local_dict[&"score"] = _format_stat_text(
			score_text,
			_SCORE_FORMAT_FALLBACK,
			score_value
		)
	
	if not is_instance_valid(_move_count_value_label):
		var move_text: String = tr("LABEL_MOVES")
		if move_text == "LABEL_MOVES" or not ":" in move_text:
			move_text = tr("MOVE_COUNT_LABEL")
		local_dict[&"move_count"] = _format_stat_text(
			move_text,
			_MOVE_COUNT_FORMAT_FALLBACK,
			move_count_value
		)

	local_dict[&"high_score"] = GameTextFormatUtility.format_template(
		tr("HIGH_SCORE_LABEL"),
		_HIGH_SCORE_FORMAT_FALLBACK,
		[high_score_value]
	)
	if not is_instance_valid(_highest_tile_value_label):
		local_dict[&"highest_tile"] = GameTextFormatUtility.format_template(
			tr("HIGHEST_TILE_LABEL"),
			_HIGHEST_TILE_FORMAT_FALLBACK,
			[highest_tile_value]
		)
	
	var query_result: Variant = send_query(GetHudStatsQuery.new())
	if query_result is Dictionary:
		var query_dict: Dictionary = GFVariantData.to_dictionary(query_result)
		local_dict.merge(query_dict)

	_update_dynamic_list(local_dict)
	_refresh_board_info()


func _refresh_board_info() -> void:
	if not is_instance_valid(_board_info_label) or not is_instance_valid(_grid_model):
		return
	var topology: BoardTopology = _grid_model.topology
	if not is_instance_valid(topology):
		_board_info_label.text = "棋盘信息\n等待棋盘数据..."
		return
	var bounds: Vector2i = topology.get_bounds_size()
	var cell_count: int = topology.get_cell_count()
	var occupied_count: int = _grid_model.get_occupied_cells().size()
	var max_value: int = _grid_model.get_max_tile_value()
	_board_info_label.text = "棋盘信息\n棋盘 %dx%d · %d 个有效格\n%d 个方块 · 最大方块 %d" % [
		bounds.x,
		bounds.y,
		cell_count,
		occupied_count,
		max_value,
	]


func _update_dynamic_list(dict: Dictionary) -> void:
	# 1. 隐藏不再存在的 key
	for key: Variant in _stat_labels:
		if not dict.has(key):
			var stale_node: Control = _get_stat_label_node(key)
			if is_instance_valid(stale_node):
				stale_node.visible = false

	var keys_in_order: Array = dict.keys()

	# 2. 动态创建或更新 UI 节点
	for key: Variant in keys_in_order:
		var data_to_display: Variant = dict[key]

		if _is_display_value_empty(data_to_display):
			if _stat_labels.has(key):
				var hidden_node: Control = _get_stat_label_node(key)
				if is_instance_valid(hidden_node):
					hidden_node.visible = false
			continue

		var ui_node: Control
		var needs_recreation: bool = false
		
		if _stat_labels.has(key):
			var existing_node: Control = _get_stat_label_node(key)
			if not is_instance_valid(existing_node):
				needs_recreation = true
			elif (
				(data_to_display is Array and not existing_node is FlowLabelList)
				or (not data_to_display is Array and existing_node is FlowLabelList)
			):
				existing_node.queue_free()
				needs_recreation = true
		else:
			needs_recreation = true

		if needs_recreation:
			if data_to_display is Array:
				var flow_label_node: Node = FLOW_LABEL_LIST_SCENE.instantiate()
				if not flow_label_node is Control:
					continue
				var flow_control: Control = flow_label_node
				ui_node = flow_control
			else:
				var new_label: RichTextLabel = RichTextLabel.new()
				new_label.bbcode_enabled = true
				new_label.fit_content = true
				new_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_style_dynamic_rich_label(new_label)
				ui_node = new_label

			_stats_container.add_child(ui_node)
			_stat_labels[key] = ui_node
		else:
			ui_node = _get_stat_label_node(key)
			if not is_instance_valid(ui_node):
				continue

		if ui_node is FlowLabelList:
			var data_array: Array = GFVariantData.to_array(data_to_display)
			var flow_label_list: FlowLabelList = ui_node
			flow_label_list.update_data(data_array)
		elif ui_node is RichTextLabel:
			var rich_label: RichTextLabel = ui_node
			_style_dynamic_rich_label(rich_label)
			rich_label.text = str(data_to_display)

		ui_node.visible = true
		var display_signature: String = _make_display_signature(data_to_display)
		if not _last_display_values.has(key) or _last_display_values[key] != display_signature:
			_pulse_control(ui_node)
		_last_display_values[key] = display_signature


func _update_ui_text() -> void:
	if is_instance_valid(_title_label):
		_title_label.text = tr("TITLE_GAME_STATUS")
	if is_instance_valid(_score_caption_label):
		_score_caption_label.text = _extract_caption(tr("LABEL_SCORE"), "分数", "LABEL_SCORE")
	if is_instance_valid(_moves_caption_label):
		_moves_caption_label.text = _extract_caption(tr("LABEL_MOVES"), "步数", "LABEL_MOVES")
	if is_instance_valid(_highest_tile_caption_label):
		_highest_tile_caption_label.text = _extract_caption(
			tr("HIGHEST_TILE_LABEL"),
			"最大方块",
			"HIGHEST_TILE_LABEL"
		)
	if is_instance_valid(_move_hint_label):
		_move_hint_label.text = tr("CONTROLS_MOVE_HINT")
	if is_instance_valid(_action_hint_label):
		_action_hint_label.text = tr("CONTROLS_ACTION_HINT")
	if is_instance_valid(_hint_button):
		_hint_button.tooltip_text = _translate_with_fallback(
			"HINT_BUTTON_TOOLTIP",
			"分析当前棋盘"
		)
	if is_instance_valid(_copy_board_summary_button):
		_copy_board_summary_button.text = _translate_with_fallback(
			"ACCESSIBILITY_COPY_BOARD_SUMMARY",
			"复制棋盘摘要"
		)
	if (
		is_instance_valid(_board_summary_label)
		and _board_summary_label.text.is_empty()
	):
		_board_summary_label.text = _translate_with_fallback(
			"ACCESSIBILITY_BOARD_SUMMARY_LOADING",
			"展开后显示当前棋盘摘要。"
		)
	_update_details_toggle_button()


func _apply_semantic_styles() -> void:
	if not is_instance_valid(_ui_style_utility):
		return
	_ui_style_utility.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY)
	for caption: Label in [
		_score_caption_label,
		_moves_caption_label,
		_highest_tile_caption_label,
	]:
		_ui_style_utility.style_label(caption, GameUiStyleUtility.TextRole.SECONDARY)
	for value_label: Label in [
		_score_value_label,
		_move_count_value_label,
		_highest_tile_value_label,
	]:
		_ui_style_utility.style_label(value_label, GameUiStyleUtility.TextRole.NUMERIC)
	_ui_style_utility.style_label(
		_accessibility_subtitle_label,
		GameUiStyleUtility.TextRole.SECONDARY
	)
	_ui_style_utility.style_rich_text_label(
		_board_summary_label,
		GameUiStyleUtility.TextRole.SECONDARY
	)
	_ui_style_utility.style_button(
		_copy_board_summary_button,
		GameUiStyleUtility.ButtonRole.SECONDARY
	)
	for action_name: String in [
		"%DetailsToggleButton",
		"%MoveUpButton",
		"%MoveDownButton",
		"%MoveLeftButton",
		"%MoveRightButton",
		"%PauseButton",
		"%UndoButton",
		"%RedoButton",
		"%BookmarkButton",
		"%HintButton",
	]:
		var button: Button = _get_button_node(NodePath(action_name))
		if is_instance_valid(button):
			_ui_style_utility.style_button(button, GameUiStyleUtility.ButtonRole.ICON)
			if _ACTION_ICON_ASSET_KEYS.has(action_name):
				var icon_key: StringName = GFVariantData.to_string_name(
					_ACTION_ICON_ASSET_KEYS[action_name]
				)
				var _icon_applied: bool = _ui_style_utility.set_button_icon_from_asset(
					button,
					icon_key,
					19
				)
	if is_instance_valid(_board_info_label):
		_ui_style_utility.style_label(
			_board_info_label,
			GameUiStyleUtility.TextRole.PRIMARY,
			15,
			false
		)


func _apply_hud_layout() -> void:
	if not is_node_ready():
		return
	var safe_width: float = (
		_safe_area.size.x
		if is_instance_valid(_safe_area) and _safe_area.size.x > 0.0
		else 1280.0
	)
	var use_narrow_landscape_actions: bool = (
		not _is_portrait_mode
		and (_is_compact_mode or safe_width < 1100.0)
	)
	var show_wide_side_cards: bool = (
		not _is_compact_mode
		and not _is_portrait_mode
		and safe_width >= _WIDE_SIDE_CARD_MINIMUM_WIDTH
	)
	if not show_wide_side_cards:
		# 1280 宽度仍是主流窗口尺寸；详细卡片与棋盘共存会挤压棋盘，
		# 让主棋盘优先保持完整，宽屏再恢复编辑部式双侧卡片。
		_details_expanded = false
	if is_instance_valid(_control_hint_panel):
		_control_hint_panel.visible = _is_portrait_mode
	if is_instance_valid(_board_info_panel):
		_board_info_panel.visible = show_wide_side_cards
	if is_instance_valid(_hints):
		_hints.visible = false
	if is_instance_valid(_d_pad):
		_d_pad.visible = _is_portrait_mode

	if is_instance_valid(_top_score_panel):
		var score_half_width: float = (
			174.0
			if _is_portrait_mode
			else (190.0 if safe_width < 1100.0 else 230.0)
		)
		_top_score_panel.offset_left = -score_half_width
		_top_score_panel.offset_top = 8.0 if _is_portrait_mode else 12.0
		_top_score_panel.offset_right = score_half_width
		_top_score_panel.offset_bottom = 68.0 if _is_portrait_mode else 78.0

	if is_instance_valid(_details_toggle_button):
		_details_toggle_button.offset_left = 0.0 if _is_portrait_mode else 18.0
		_details_toggle_button.offset_top = 76.0 if _is_portrait_mode else 18.0
		_details_toggle_button.offset_right = 44.0 if _is_portrait_mode else 62.0
		_details_toggle_button.offset_bottom = 120.0 if _is_portrait_mode else 62.0
	if is_instance_valid(_details_panel):
		_details_panel.offset_left = 0.0 if _is_portrait_mode else 18.0
		_details_panel.offset_top = 124.0 if _is_portrait_mode else 66.0
		_details_panel.offset_right = 300.0 if _is_portrait_mode else 358.0
		_details_panel.offset_bottom = 532.0 if _is_portrait_mode else 520.0
	_apply_feedback_rail_layout()

	if is_instance_valid(_control_hint_panel) and _is_portrait_mode:
		_control_hint_panel.offset_left = 0.0
		_control_hint_panel.offset_top = -108.0
		_control_hint_panel.offset_right = 152.0
		_control_hint_panel.offset_bottom = 0.0
	if is_instance_valid(_action_panel):
		_action_panel.offset_left = (
			-264.0
			if _is_portrait_mode
			else (-282.0 if use_narrow_landscape_actions else -342.0)
		)
		_action_panel.offset_top = -60.0 if _is_portrait_mode else -78.0
		_action_panel.offset_right = 0.0 if _is_portrait_mode else -18.0
		_action_panel.offset_bottom = 0.0 if _is_portrait_mode else -18.0
	if is_instance_valid(_hint_result_panel):
		_hint_result_panel.offset_left = (
			-320.0
			if _is_portrait_mode
			else (-282.0 if use_narrow_landscape_actions else -378.0)
		)
		_hint_result_panel.offset_top = -174.0 if _is_portrait_mode else -190.0
		_hint_result_panel.offset_right = 0.0 if _is_portrait_mode else -18.0
		_hint_result_panel.offset_bottom = -68.0 if _is_portrait_mode else -86.0
	if is_instance_valid(_hint_result_label):
		_hint_result_label.custom_minimum_size.x = (
			296.0
			if _is_portrait_mode
			else (240.0 if use_narrow_landscape_actions else 336.0)
		)
	for action_name: String in [
		"%PauseButton",
		"%UndoButton",
		"%RedoButton",
		"%BookmarkButton",
		"%HintButton",
	]:
		var action_button: Button = _get_button_node(NodePath(action_name))
		if is_instance_valid(action_button):
			action_button.custom_minimum_size.x = (
				44.0
				if _is_portrait_mode or use_narrow_landscape_actions
				else 54.0
			)


func _apply_feedback_rail_layout() -> void:
	if not is_instance_valid(_feedback_rail):
		return
	if _is_portrait_mode:
		var safe_width: float = (
			_safe_area.size.x
			if is_instance_valid(_safe_area) and _safe_area.size.x > 0.0
			else 390.0
		)
		var rail_width: float = clampf(safe_width - 24.0, 280.0, 500.0)
		_feedback_rail.anchor_left = 0.5
		_feedback_rail.anchor_top = 1.0
		_feedback_rail.anchor_right = 0.5
		_feedback_rail.anchor_bottom = 1.0
		_feedback_rail.offset_left = -rail_width * 0.5
		_feedback_rail.offset_top = -268.0
		_feedback_rail.offset_right = rail_width * 0.5
		_feedback_rail.offset_bottom = -116.0
		if is_instance_valid(_notification_slot) and _notification_slot.visible:
			_reset_notification_surface_layout()
		return

	var landscape_rail_width: float = 300.0 if _is_compact_mode else 340.0
	var rail_top: float = 106.0
	_feedback_rail.anchor_left = 1.0
	_feedback_rail.anchor_top = 0.0
	_feedback_rail.anchor_right = 1.0
	_feedback_rail.anchor_bottom = 0.0
	_feedback_rail.offset_left = -landscape_rail_width - 18.0
	_feedback_rail.offset_top = rail_top
	_feedback_rail.offset_right = -18.0
	_feedback_rail.offset_bottom = rail_top + 286.0
	if is_instance_valid(_notification_slot) and _notification_slot.visible:
		_reset_notification_surface_layout()


func _apply_notification_level(
	level: int,
	priority: int = GFNotificationUtility.Priority.NORMAL
) -> void:
	if not is_instance_valid(_notification_panel):
		return
	var border_color: Color = _NOTIFICATION_INFO_COLOR
	match level:
		GFNotificationUtility.Level.SUCCESS:
			border_color = _NOTIFICATION_SUCCESS_COLOR
		GFNotificationUtility.Level.WARNING:
			border_color = _NOTIFICATION_WARNING_COLOR
		GFNotificationUtility.Level.ERROR:
			border_color = _NOTIFICATION_ERROR_COLOR
	var stylebox: StyleBox = _notification_panel.get_theme_stylebox("panel")
	if not stylebox is StyleBoxFlat:
		return
	var duplicated_stylebox: Resource = stylebox.duplicate()
	if not duplicated_stylebox is StyleBoxFlat:
		return
	var level_style: StyleBoxFlat = duplicated_stylebox
	level_style.border_color = border_color
	var border_width: int = 2
	if priority >= GFNotificationUtility.Priority.CRITICAL:
		border_width = 4
	elif priority >= GFNotificationUtility.Priority.HIGH:
		border_width = 3
	level_style.border_width_left = border_width
	level_style.border_width_top = border_width
	level_style.border_width_right = border_width
	level_style.border_width_bottom = border_width
	_notification_panel.add_theme_stylebox_override("panel", level_style)


func _extract_caption(template: String, fallback: String, missing_key: String) -> String:
	if template.is_empty() or template == missing_key:
		return fallback
	var result: String = template
	var placeholder_index: int = result.find("%")
	if placeholder_index >= 0:
		result = result.left(placeholder_index)
	result = result.strip_edges().trim_suffix(":").trim_suffix("：").strip_edges()
	return result if not result.is_empty() else fallback


func _format_stat_text(template: String, fallback: String, value: int) -> String:
	if template.contains("%"):
		return GameTextFormatUtility.format_template(template, fallback, [value])
	return template + " [b]" + str(value) + "[/b]"


func _style_dynamic_rich_label(label: RichTextLabel) -> void:
	if not is_instance_valid(label) or not is_instance_valid(_ui_style_utility):
		return
	_ui_style_utility.style_rich_text_label(label, GameUiStyleUtility.TextRole.PRIMARY)
	label.modulate = Color.WHITE


func _mark_dirty() -> void:
	if not _is_dirty:
		_is_dirty = true
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	if _is_dirty:
		_is_dirty = false
		_refresh_all()


func _pulse_control(control: Control) -> void:
	if not is_instance_valid(control) or not is_instance_valid(_ui_motion_utility):
		return
	var _feedback_tween: Tween = _ui_motion_utility.play_control_pulse(
		control,
		_FEEDBACK_SCALE,
		_FEEDBACK_COLOR,
		_FEEDBACK_DURATION
	)


func _play_notification_entry(priority: int) -> void:
	var target: Control = _get_notification_motion_target()
	if not is_instance_valid(target):
		return
	_kill_notification_motion(true)
	_reset_notification_surface_layout()
	_notification_rest_position = target.position
	_notification_rest_position_valid = true
	target.visible = true
	if not is_instance_valid(_ui_motion_utility):
		target.position = _notification_rest_position
		target.modulate = Color.WHITE
		return

	var enter_offset: Vector2 = _get_notification_enter_offset(priority)
	var tween: Tween = _ui_motion_utility.play_toast_entry(
		target,
		_notification_rest_position,
		enter_offset
	)
	if tween == null:
		return
	var _finished_connection: int = tween.finished.connect(
		_on_notification_entry_finished.bind(tween),
		CONNECT_ONE_SHOT
	)
	_notification_motion_tween = tween


func _play_notification_exit(notification_id: int) -> void:
	var target: Control = _get_notification_motion_target()
	if not is_instance_valid(target):
		_hide_notification_immediately()
		return
	_kill_notification_motion(true)
	if not is_instance_valid(_ui_motion_utility):
		_finish_notification_exit(notification_id)
		return

	_notification_rest_position = target.position
	_notification_rest_position_valid = true
	var tween: Tween = _ui_motion_utility.play_toast_exit(
		target,
		_notification_rest_position
	)
	if tween == null:
		_finish_notification_exit(notification_id)
		return
	var _finished_connection: int = tween.finished.connect(
		_finish_notification_exit.bind(notification_id),
		CONNECT_ONE_SHOT
	)
	_notification_motion_tween = tween


func _on_notification_entry_finished(completed_tween: Tween) -> void:
	if _notification_motion_tween == completed_tween:
		_notification_motion_tween = null


func _finish_notification_exit(notification_id: int) -> void:
	if notification_id != _active_notification_id:
		return
	_hide_notification_immediately()


func _hide_notification_immediately() -> void:
	_kill_notification_motion(true)
	_active_notification_id = 0
	if is_instance_valid(_notification_label):
		_notification_label.text = ""
		_notification_label.visible = false
	_set_notification_surface_visible(false)
	var target: Control = _get_notification_motion_target()
	if is_instance_valid(target):
		target.modulate = Color.WHITE
	_notification_rest_position_valid = false


func _kill_notification_motion(restore_target: bool) -> void:
	var target: Control = _get_notification_motion_target()
	if is_instance_valid(target) and is_instance_valid(_ui_motion_utility):
		_ui_motion_utility.complete_control_motion(target)
	elif (
		is_instance_valid(target)
		and restore_target
		and _notification_rest_position_valid
	):
		target.position = _notification_rest_position
		target.modulate = Color.WHITE
	_notification_motion_tween = null
	if (
		not restore_target
		or not _notification_rest_position_valid
		or not is_instance_valid(target)
	):
		return
	target.position = _notification_rest_position
	target.modulate = Color.WHITE


func _get_notification_motion_target() -> Control:
	if is_instance_valid(_notification_panel):
		return _notification_panel
	return _notification_label


func _set_notification_surface_visible(visible: bool) -> void:
	if is_instance_valid(_notification_slot):
		_notification_slot.visible = visible
	if is_instance_valid(_notification_panel):
		_notification_panel.visible = visible
		if visible:
			_reset_notification_surface_layout()
	elif is_instance_valid(_notification_label):
		_notification_label.visible = visible


func _reset_notification_surface_layout() -> void:
	if (
		not is_instance_valid(_notification_panel)
		or _notification_panel.get_parent() != _notification_slot
	):
		return
	# 隐藏的 Container 子项不会参与排序，首次显示时可能仍保留编辑器旧尺寸。
	# 改为显式 top-left 视觉根；后续 position Tween 不再与 anchors/Container 排序竞争。
	var surface_width: float = maxf(
		_notification_slot.size.x,
		_feedback_rail.size.x if is_instance_valid(_feedback_rail) else 0.0
	)
	_notification_panel.anchor_left = 0.0
	_notification_panel.anchor_top = 0.0
	_notification_panel.anchor_right = 0.0
	_notification_panel.anchor_bottom = 0.0
	_notification_panel.position = Vector2.ZERO
	_notification_panel.size = Vector2(
		maxf(surface_width, _notification_panel.get_combined_minimum_size().x),
		_NOTIFICATION_SURFACE_HEIGHT
	)


func _uses_reduced_motion() -> bool:
	return (
		is_instance_valid(_accessibility_utility)
		and _accessibility_utility.get_state().reduced_motion
	)


func _get_notification_motion_profile() -> GameUiMotionProfile:
	if is_instance_valid(_ui_motion_utility):
		return _ui_motion_utility.get_profile()
	return GameUiMotionProfile.new()


func _get_notification_enter_offset(priority: int) -> Vector2:
	var scale_factor: float = _NOTIFICATION_OFFSET_SCALE_NORMAL
	if priority >= GFNotificationUtility.Priority.CRITICAL:
		scale_factor = _NOTIFICATION_OFFSET_SCALE_CRITICAL
	elif priority >= GFNotificationUtility.Priority.HIGH:
		scale_factor = _NOTIFICATION_OFFSET_SCALE_HIGH
	elif priority <= GFNotificationUtility.Priority.LOW:
		scale_factor = _NOTIFICATION_OFFSET_SCALE_LOW
	return _get_notification_motion_profile().toast_enter_offset * scale_factor


func _get_stat_label_node(key: Variant) -> Control:
	var node_value: Variant = _stat_labels[key] if _stat_labels.has(key) else null
	if node_value is Control:
		var control: Control = node_value
		return control
	return null


func _get_game_status_model() -> GameStatusModel:
	var model_value: Object = get_model(GameStatusModel)
	if model_value is GameStatusModel:
		var status_model: GameStatusModel = model_value
		return status_model
	return null


func _get_grid_model() -> GridModel:
	var model_value: Object = get_model(GridModel)
	if model_value is GridModel:
		var grid_model: GridModel = model_value
		return grid_model
	return null


func _get_determinism_utility() -> GameDeterminismUtility:
	var utility_value: Object = get_utility(GameDeterminismUtility)
	if utility_value is GameDeterminismUtility:
		var determinism_utility: GameDeterminismUtility = utility_value
		return determinism_utility
	return null


func _get_notification_utility() -> GFNotificationUtility:
	var utility_value: Object = get_utility(GFNotificationUtility)
	if utility_value is GFNotificationUtility:
		var notification_utility: GFNotificationUtility = utility_value
		return notification_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = get_utility(GameUiMotionUtility)
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_ui_style_utility() -> GameUiStyleUtility:
	var utility_value: Object = get_utility(GameUiStyleUtility)
	if utility_value is GameUiStyleUtility:
		var style_utility: GameUiStyleUtility = utility_value
		return style_utility
	return null


func _get_accessibility_utility() -> GameAccessibilityUtility:
	var utility_value: Object = get_utility(GameAccessibilityUtility)
	if utility_value is GameAccessibilityUtility:
		return utility_value
	return null


func _get_accessibility_summary_utility() -> GameAccessibilitySummaryUtility:
	var utility_value: Object = get_utility(GameAccessibilitySummaryUtility)
	if utility_value is GameAccessibilitySummaryUtility:
		return utility_value
	return null


func _get_label_node(path: NodePath) -> Label:
	var node_value: Node = get_node_or_null(path)
	if node_value is Label:
		var label: Label = node_value
		return label
	return null


func _get_rich_text_label_node(path: NodePath) -> RichTextLabel:
	var node_value: Node = get_node_or_null(path)
	if node_value is RichTextLabel:
		var label: RichTextLabel = node_value
		return label
	return null


func _get_vbox_container_node(path: NodePath) -> VBoxContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is VBoxContainer:
		var container: VBoxContainer = node_value
		return container
	return null


func _get_grid_container_node(path: NodePath) -> GridContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is GridContainer:
		var container: GridContainer = node_value
		return container
	return null


func _get_panel_container_node(path: NodePath) -> PanelContainer:
	var node_value: Node = get_node_or_null(path)
	if node_value is PanelContainer:
		var panel: PanelContainer = node_value
		return panel
	return null


func _get_control_node(path: NodePath) -> Control:
	var node_value: Node = get_node_or_null(path)
	if node_value is Control:
		var control: Control = node_value
		return control
	return null


func _get_button_node(path: NodePath) -> Button:
	var node_value: Node = get_node_or_null(path)
	if node_value is Button:
		var button: Button = node_value
		return button
	return null


func _get_input_mapping_utility() -> GFInputMappingUtility:
	var utility_value: Object = get_utility(GFInputMappingUtility)
	if utility_value is GFInputMappingUtility:
		var input_mapping: GFInputMappingUtility = utility_value
		return input_mapping
	return null


func _get_realtime_timer_utility() -> GameRealtimeTimerUtility:
	var utility_value: Object = get_utility(GameRealtimeTimerUtility)
	if utility_value is GameRealtimeTimerUtility:
		var timer_utility: GameRealtimeTimerUtility = utility_value
		return timer_utility
	return null


func _connect_notification_signals() -> void:
	if not is_instance_valid(_notification_utility):
		push_error("[Hud] 缺少 GFNotificationUtility，无法读取通知队列。")
		return
	if not is_instance_valid(_signal_utility):
		push_error("[Hud] 缺少 GFSignalUtility，无法管理通知信号生命周期。")
		return

	var _started_connection: GFSignalConnection = _signal_utility.connect_signal(
		_notification_utility.notification_started,
		_on_notification_started,
		self
	)
	var _finished_connection: GFSignalConnection = _signal_utility.connect_signal(
		_notification_utility.notification_finished,
		_on_notification_finished,
		self
	)


func _connect_compact_hud_signals() -> void:
	if not is_instance_valid(_signal_utility) or not is_instance_valid(_details_toggle_button):
		return
	var _toggle_connection: GFSignalConnection = _signal_utility.connect_signal(
		_details_toggle_button.pressed,
		_on_details_toggle_pressed,
		self
	)


func _connect_accessibility_summary_signals() -> void:
	if not is_instance_valid(_signal_utility):
		return
	if is_instance_valid(_accessibility_summary_utility):
		var _summary_connection: GFSignalConnection = _signal_utility.connect_signal(
			_accessibility_summary_utility.summary_published,
			_on_accessibility_summary_published,
			self
		)
	if is_instance_valid(_accessibility_utility):
		var _state_connection: GFSignalConnection = _signal_utility.connect_signal(
			_accessibility_utility.state_changed,
			_on_accessibility_state_changed,
			self
		)
	if is_instance_valid(_copy_board_summary_button):
		var _copy_connection: GFSignalConnection = _signal_utility.connect_signal(
			_copy_board_summary_button.pressed,
			_on_copy_board_summary_pressed,
			self
		)


func _connect_hud_action_signals() -> void:
	if not is_instance_valid(_signal_utility):
		return
	var button_actions: Dictionary = {
		_get_button_node("%MoveUpButton"): GameplayInputActions.MOVE_UP,
		_get_button_node("%MoveDownButton"): GameplayInputActions.MOVE_DOWN,
		_get_button_node("%MoveLeftButton"): GameplayInputActions.MOVE_LEFT,
		_get_button_node("%MoveRightButton"): GameplayInputActions.MOVE_RIGHT,
		_get_button_node("%PauseButton"): GameplayInputActions.PAUSE,
		_get_button_node("%UndoButton"): GameplayInputActions.UNDO,
		_get_button_node("%RedoButton"): GameplayInputActions.REDO,
		_get_button_node("%BookmarkButton"): GameplayInputActions.SAVE_BOOKMARK,
		_get_button_node("%HintButton"): GameplayInputActions.REQUEST_HINT,
	}
	for button_value: Variant in button_actions.keys():
		if not button_value is Button:
			continue
		var button: Button = button_value
		var action_id: StringName = GFVariantData.to_string_name(button_actions[button])
		var _pressed_connection: GFSignalConnection = _signal_utility.connect_signal(
			button.pressed,
			_inject_hud_action.bind(action_id),
			self
		)


func _inject_hud_action(action_id: StringName) -> void:
	if action_id == &"" or not is_instance_valid(_hud_action_pulse):
		return
	var _injected: bool = _hud_action_pulse.pulse(
		action_id,
		self,
		_HUD_ACTION_HOLD_SECONDS
	)


func _apply_details_visibility() -> void:
	if is_instance_valid(_details_panel):
		_details_panel.visible = _details_expanded and not _is_compact_mode and not _is_portrait_mode
	if is_instance_valid(_details_toggle_button):
		_details_toggle_button.visible = true
	_update_details_toggle_button()


func _update_details_toggle_button() -> void:
	if not is_instance_valid(_details_toggle_button):
		return
	_details_toggle_button.text = "-" if _details_expanded else "+"
	var tooltip_key: String = "HUD_DETAILS_COLLAPSE" if _details_expanded else "HUD_DETAILS_EXPAND"
	var fallback: String = "收起详细状态" if _details_expanded else "展开详细状态"
	var translated_tooltip: String = tr(tooltip_key)
	_details_toggle_button.tooltip_text = (
		fallback if translated_tooltip == tooltip_key else translated_tooltip
	)


func _run_hint_query() -> void:
	_hide_hint_result()
	_cancel_hint_query(&"superseded")
	if not is_instance_valid(_grid_model) or not is_instance_valid(_determinism_utility):
		_show_hint_unavailable()
		return

	var board_snapshot: Dictionary = _grid_model.get_snapshot()
	var snapshot_id: String = _determinism_utility.calculate_board_checksum(board_snapshot)
	if snapshot_id.is_empty():
		_show_hint_unavailable()
		return

	_hint_cancel_source = GFCancellationSource.new()
	var _lifetime_bound: bool = _hint_cancel_source.cancel_when_node_exits(
		self,
		&"hud_exited",
		{&"operation": &"deterministic_game_hint"}
	)
	var budget: GFExecutionBudget = GFExecutionBudget.new({
		&"max_steps": _HINT_MAX_STEPS,
		&"max_elapsed_msec": _HINT_MAX_ELAPSED_MSEC,
		&"cancel_token": _hint_cancel_source.get_token(),
		&"metadata": {
			&"operation": &"deterministic_game_hint",
			&"snapshot_id": snapshot_id,
		},
	})
	var result: GameHintResultType = DeterministicHintQueryType.new().evaluate(
		board_snapshot,
		snapshot_id,
		budget
	)
	_hint_cancel_source.dispose()
	_hint_cancel_source = null

	var current_snapshot_id: String = _calculate_current_snapshot_id()
	if not result.can_display_for(current_snapshot_id):
		if result.termination_reason == GameHintResultType.TERMINATION_INVALID_SNAPSHOT:
			_show_hint_unavailable()
		return
	_show_hint_result(result)


func _show_hint_result(result: GameHintResultType) -> void:
	if (
		result == null
		or not is_instance_valid(_hint_result_panel)
		or not is_instance_valid(_hint_result_label)
	):
		return
	var current_snapshot_id: String = _calculate_current_snapshot_id()
	if not result.can_display_for(current_snapshot_id):
		_hide_hint_result()
		return
	_hint_snapshot_id = result.snapshot_id
	_hint_result_label.text = _format_hint_result(result)
	_hint_result_panel.visible = true
	_pulse_control(_hint_result_panel)


func _hide_hint_result() -> void:
	_hint_snapshot_id = ""
	if is_instance_valid(_hint_result_label):
		_hint_result_label.text = ""
	if is_instance_valid(_hint_result_panel):
		_hint_result_panel.visible = false


func _cancel_hint_query(reason: StringName) -> void:
	if _hint_cancel_source == null:
		return
	var _cancelled: bool = _hint_cancel_source.cancel(
		reason,
		{&"operation": &"deterministic_game_hint"}
	)
	_hint_cancel_source.dispose()
	_hint_cancel_source = null


func _calculate_current_snapshot_id() -> String:
	if not is_instance_valid(_grid_model) or not is_instance_valid(_determinism_utility):
		return ""
	return _determinism_utility.calculate_board_checksum(_grid_model.get_snapshot())


func _format_hint_result(result: GameHintResultType) -> String:
	var direction_label: String = _hint_direction_label(result.suggested_direction)
	var heading: String = GameTextFormatUtility.format_template(
		tr("HINT_RESULT_HEADING"),
		"提示：%s %s",
		[_hint_direction_arrow(result.suggested_direction), direction_label]
	)
	var metrics: String = GameTextFormatUtility.format_template(
		tr("HINT_RESULT_METRICS"),
		"%d 节点 · %d ms · %s",
		[
			result.nodes_evaluated,
			result.elapsed_msec,
			_hint_termination_label(result.termination_reason),
		]
	)
	return "[b]%s[/b]\n%s\n[color=#695752]%s[/color]" % [
		heading,
		result.explanation,
		metrics,
	]


func _hint_direction_arrow(direction: Vector2i) -> String:
	match direction:
		Vector2i.UP:
			return "↑"
		Vector2i.DOWN:
			return "↓"
		Vector2i.LEFT:
			return "←"
		Vector2i.RIGHT:
			return "→"
		_:
			return "?"


func _hint_direction_label(direction: Vector2i) -> String:
	match direction:
		Vector2i.UP:
			return _translate_with_fallback("HINT_DIRECTION_UP", "向上")
		Vector2i.DOWN:
			return _translate_with_fallback("HINT_DIRECTION_DOWN", "向下")
		Vector2i.LEFT:
			return _translate_with_fallback("HINT_DIRECTION_LEFT", "向左")
		Vector2i.RIGHT:
			return _translate_with_fallback("HINT_DIRECTION_RIGHT", "向右")
		_:
			return _translate_with_fallback("HINT_DIRECTION_UNKNOWN", "未知方向")


func _hint_termination_label(reason: StringName) -> String:
	match reason:
		GameHintResultType.TERMINATION_COMPLETED:
			return _translate_with_fallback("HINT_REASON_COMPLETED", "分析完成")
		GameHintResultType.TERMINATION_TIME_LIMIT:
			return _translate_with_fallback("HINT_REASON_TIME_LIMIT", "达到时间上限")
		GameHintResultType.TERMINATION_STEP_LIMIT:
			return _translate_with_fallback("HINT_REASON_STEP_LIMIT", "达到步数上限")
		_:
			return String(reason)


func _show_hint_unavailable() -> void:
	if not is_instance_valid(_notification_utility):
		return
	var _notification_id: int = _notification_utility.push_notification(
		_translate_with_fallback("HINT_UNAVAILABLE_MSG", _HINT_UNAVAILABLE_FALLBACK),
		"",
		GFNotificationUtility.Level.WARNING,
		{
			"duration_seconds": 1.8,
			"key": "gameplay.hint_unavailable",
			"priority": GFNotificationUtility.Priority.LOW,
			"metadata": {"surface": "gameplay_hud"},
		}
	)


func _translate_with_fallback(key: String, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == key or translated.is_empty() else translated


func _refresh_accessibility_board_summary() -> GameAccessibilitySummary:
	if (
		not is_instance_valid(_accessibility_summary_utility)
		or not is_instance_valid(_grid_model)
	):
		return null
	var session_context: Dictionary = {}
	var game_flow_value: Object = get_system(GameFlowSystem)
	if game_flow_value is GameFlowSystem:
		var game_flow: GameFlowSystem = game_flow_value
		session_context = game_flow.get_accessibility_context()
	return _accessibility_summary_utility.publish_board_summary(
		_grid_model.get_snapshot(),
		session_context
	)


func _are_turn_subtitles_enabled() -> bool:
	if not is_instance_valid(_accessibility_utility):
		return true
	var state: GameAccessibilityState = _accessibility_utility.get_state()
	return state.turn_subtitles_enabled


func _show_accessibility_summary(summary: GameAccessibilitySummary) -> void:
	if not is_instance_valid(summary) or not summary.is_valid_summary():
		return
	if is_instance_valid(_board_summary_label):
		_board_summary_label.text = summary.board_text
	if (
		not _are_turn_subtitles_enabled()
		or not is_instance_valid(_accessibility_subtitle_panel)
		or not is_instance_valid(_accessibility_subtitle_label)
	):
		_hide_accessibility_subtitle()
		return

	_accessibility_subtitle_serial += 1
	var current_serial: int = _accessibility_subtitle_serial
	_accessibility_subtitle_label.text = summary.subtitle_text
	_accessibility_subtitle_panel.visible = true
	var _deferred_hide: Variant = call_deferred(
		&"_hide_accessibility_subtitle_after_delay",
		current_serial
	)


func _hide_accessibility_subtitle_after_delay(serial: int) -> void:
	var wait_result: Dictionary = await GFAsyncWaitUtility.delay_seconds(
		_ACCESSIBILITY_SUBTITLE_DURATION_SECONDS,
		{
			&"guard_node": self,
			&"respect_time_scale": false,
		}
	)
	if (
		not GFVariantData.get_option_bool(wait_result, &"completed")
		or serial != _accessibility_subtitle_serial
	):
		return
	_hide_accessibility_subtitle()


func _hide_accessibility_subtitle() -> void:
	if is_instance_valid(_accessibility_subtitle_label):
		_accessibility_subtitle_label.text = ""
	if is_instance_valid(_accessibility_subtitle_panel):
		_accessibility_subtitle_panel.visible = false


func _notify_board_summary_copy_result(copied: bool) -> void:
	if not is_instance_valid(_notification_utility):
		return
	var message: String = _translate_with_fallback(
		(
			"ACCESSIBILITY_BOARD_SUMMARY_COPIED"
			if copied
			else "ACCESSIBILITY_BOARD_SUMMARY_COPY_FAILED"
		),
		"棋盘摘要已复制。" if copied else "无法复制棋盘摘要。"
	)
	var _notification_id: int = _notification_utility.push_notification(
		message,
		"",
		(
			GFNotificationUtility.Level.SUCCESS
			if copied
			else GFNotificationUtility.Level.WARNING
		),
		{
			&"duration_seconds": 1.8,
			&"key": "accessibility.board_summary_copy",
			&"priority": (
				GFNotificationUtility.Priority.LOW
				if copied
				else GFNotificationUtility.Priority.HIGH
			),
			&"metadata": {&"surface": &"gameplay_hud"},
		}
	)


func _sync_active_notification() -> void:
	if not is_instance_valid(_notification_utility):
		_set_notification_message(0, "")
		return
	var notification_record: Dictionary = _notification_utility.get_active_notification()
	if notification_record.is_empty():
		_set_notification_message(0, "")
		return
	_on_notification_started(notification_record)


func _set_notification_message(
	notification_id: int,
	message: String,
	level: int = GFNotificationUtility.Level.INFO,
	priority: int = GFNotificationUtility.Priority.NORMAL,
	_metadata: Dictionary = {}
) -> void:
	if message.is_empty():
		_hide_notification_immediately()
		return
	if not is_instance_valid(_notification_label):
		return
	_active_notification_id = notification_id
	_notification_label.text = message
	_notification_label.visible = true
	_notification_label.add_theme_color_override(
		"default_color",
		_NOTIFICATION_TEXT_COLOR
	)
	if is_instance_valid(_notification_panel):
		_set_notification_surface_visible(true)
		_apply_notification_level(level, priority)
	else:
		_notification_label.visible = true
	_play_notification_entry(priority)


static func _is_display_value_empty(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		var text_value: String = value
		return text_value.is_empty()
	if value is Array:
		var array_value: Array = value
		return array_value.is_empty()
	return false


func _make_display_signature(value: Variant) -> String:
	return var_to_str(value)


func _ensure_score_gain_label() -> Label:
	if is_instance_valid(_score_gain_label):
		return _score_gain_label
	if not is_instance_valid(_score_value_label):
		return null

	var node: Node = _SCORE_DELTA_LABEL_SCENE.instantiate()
	if not node is Label:
		node.free()
		return null
	_score_gain_label = node
	_score_value_label.add_child(_score_gain_label)
	if is_instance_valid(_ui_style_utility):
		_ui_style_utility.style_label(
			_score_gain_label,
			GameUiStyleUtility.TextRole.FEEDBACK,
			16
		)
	return _score_gain_label


func _play_score_change_feedback(old_value: int, new_value: int) -> void:
	if not is_instance_valid(_score_value_label) or not is_instance_valid(_ui_motion_utility):
		return
	var score_gain_label: Label = _ensure_score_gain_label()
	var _score_tween: Tween = _ui_motion_utility.play_numeric_change(
		_score_value_label,
		old_value,
		new_value,
		score_gain_label
	)


func _queue_score_change_feedback(old_value: int, new_value: int) -> bool:
	if not _score_feedback_pending:
		_pending_score_feedback_old = old_value
	_score_feedback_pending = true
	_pending_score_feedback_new = new_value
	if _score_feedback_delay_active:
		return false
	_score_feedback_delay_active = true
	return true


func _take_pending_score_change_feedback() -> PackedInt32Array:
	_score_feedback_delay_active = false
	if not _score_feedback_pending:
		return PackedInt32Array()
	var values: PackedInt32Array = PackedInt32Array([
		_pending_score_feedback_old,
		_pending_score_feedback_new,
	])
	_score_feedback_pending = false
	return values


func _play_delayed_score_change_feedback() -> void:
	var wait_result: Dictionary = await GFAsyncWaitUtility.delay_seconds(
		_SCORE_FEEDBACK_DELAY_SECONDS,
		{
			&"guard_node": self,
			&"respect_time_scale": false,
		}
	)
	if not GFVariantData.get_option_bool(wait_result, "completed"):
		_score_feedback_delay_active = false
		return
	var score_values: PackedInt32Array = _take_pending_score_change_feedback()
	if score_values.size() != 2:
		return
	_play_score_change_feedback(score_values[0], score_values[1])


# --- 信号处理函数 ---

func _on_hud_update_requested(_p: Variant = null) -> void:
	_hide_hint_result()
	_mark_dirty()


func _on_hint_requested(_payload: Variant = null) -> void:
	_run_hint_query()


func _on_hint_invalidated(_payload: Variant = null) -> void:
	_cancel_hint_query(&"snapshot_changed")
	_hide_hint_result()
	_refresh_board_info()


func _on_score_changed(old_value: int, new_value: int) -> void:
	_mark_dirty()
	if not _queue_score_change_feedback(old_value, new_value):
		return
	var _deferred_call: Variant = call_deferred(
		&"_play_delayed_score_change_feedback"
	)

func _on_move_count_changed(_old_value: int, _new_value: int) -> void:
	_hide_hint_result()
	_pulse_control(_move_count_value_label)
	_mark_dirty()


func _on_high_score_changed(_old: int, _new_value: int) -> void:
	_mark_dirty()


func _on_highest_tile_changed(_old: int, _new_value: int) -> void:
	_pulse_control(_highest_tile_value_label)
	_mark_dirty()


func _on_details_toggle_pressed() -> void:
	_details_expanded = not _details_expanded
	if _details_expanded:
		var _summary: GameAccessibilitySummary = (
			_refresh_accessibility_board_summary()
		)
	_apply_details_visibility()


func _on_accessibility_summary_published(
	summary: GameAccessibilitySummary
) -> void:
	_show_accessibility_summary(summary)


func _on_accessibility_state_changed(state: GameAccessibilityState) -> void:
	if not is_instance_valid(state) or not state.turn_subtitles_enabled:
		_accessibility_subtitle_serial += 1
		_hide_accessibility_subtitle()


func _on_copy_board_summary_pressed() -> void:
	var _summary: GameAccessibilitySummary = (
		_refresh_accessibility_board_summary()
	)
	if not is_instance_valid(_accessibility_summary_utility):
		_notify_board_summary_copy_result(false)
		return
	var handle: GFPlatformRequestHandle = (
		_accessibility_summary_utility.copy_latest_board_text()
	)
	if handle == null:
		_notify_board_summary_copy_result(false)
	elif handle.is_completed():
		_notify_board_summary_copy_result(handle.is_successful())
	elif not is_instance_valid(_signal_utility):
		_notify_board_summary_copy_result(false)
	else:
		var copy_result_connection: GFSignalConnection = _signal_utility.connect_signal(
			handle.completed,
			_on_board_summary_copy_completed,
			self
		)
		if copy_result_connection != null:
			var _first_connection: GFSignalConnection = (
				copy_result_connection.first()
			)
		else:
			_notify_board_summary_copy_result(false)


func _on_board_summary_copy_completed(result: GFPlatformBridgeResult) -> void:
	_notify_board_summary_copy_result(result != null and result.ok)


func _on_notification_started(notification_record: Dictionary) -> void:
	_set_notification_message(
		GFVariantData.get_option_int(notification_record, "id"),
		GFVariantData.get_option_string(notification_record, "message"),
		GFVariantData.get_option_int(
			notification_record,
			"level",
			GFNotificationUtility.Level.INFO
		),
		GFVariantData.get_option_int(
			notification_record,
			"priority",
			GFNotificationUtility.Priority.NORMAL
		),
		GFVariantData.get_option_dictionary(notification_record, "metadata")
	)


func _on_notification_finished(notification_record: Dictionary, _reason: String) -> void:
	var notification_id: int = GFVariantData.get_option_int(notification_record, "id")
	if notification_id == _active_notification_id:
		_play_notification_exit(notification_id)


func _on_ratio_resolutions_changed(_old: int, _new: int) -> void:
	_mark_dirty()


## 响应式更新动态统计数据。
## @param _old: 旧数据字典。
## @param _dict: 新数据字典。结构：{ "key": "显示文本" 或 Array[Dictionary] }
func _on_extra_stats_changed(_old: Dictionary, _dict: Dictionary) -> void:
	_mark_dirty()
