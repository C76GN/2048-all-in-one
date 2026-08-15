## MainMenu: 主菜单界面的 UI 控制器。
##
## 负责处理主菜单中的所有用户交互，
## 并通过 SceneRouterSystem 执行场景切换或退出游戏。
class_name MainMenu
extends GameUiController


# --- 常量 ---

const _DESKTOP_SAFE_AREA_MARGINS: Dictionary = {
	"top": 44.0,
	"left": 56.0,
	"bottom": 42.0,
	"right": 56.0,
}
const _INTRO_BRAND_STAGGER: float = 0.045
const _RETURN_BRAND_STAGGER: float = 0.022
const _INTRO_MENU_STAGGER: float = 0.032
const _RETURN_MENU_STAGGER: float = 0.018
const _INTRO_MENU_DELAY: float = 0.24
const _FULL_INTRO_WINDOW: float = 0.92
const _POPUP_INTENT_PRELOAD_GROUP_ID: StringName = &"main_menu_popup_intent"
const _POPUP_INTENT_PRELOAD_PLAN_ID: StringName = &"main_menu_popup_intent.preload"
const _POPUP_INTENT_PRELOAD_ROUTE_IDS: Array[String] = [
	"tile_catalog",
	"tile_lab",
	"player_profile",
	"achievements",
]


# --- 导出变量 ---

## 模式选择场景路径。
@export_file("*.tscn") var mode_selection_scene_path: String = ""

## 回放列表场景路径。
@export_file("*.tscn") var replay_list_scene_path: String = ""

## 书签列表场景路径。
@export_file("*.tscn") var bookmark_list_scene_path: String = ""

## 设置场景路径。
@export_file("*.tscn") var settings_scene_path: String = ""

## 游戏主场景路径。
@export_file("*.tscn") var game_scene_path: String = ""


# --- 私有变量 ---

static var _has_played_full_intro: bool = false

var _layout_update_queued: bool = false
var _viewport_utility: GFViewportUtility = null
var _content_scroll: ScrollContainer = null
var _latest_valid_bookmark: BookmarkData = null
var _initial_scroll_restored: bool = false
var _intro_in_progress: bool = false
var _intro_completion_tween: Tween = null
var _popup_route_open_pending: bool = false
var _popup_route_button_disabled_states: Dictionary = {}
var _popup_intent_preload_session: GFAssetLoadSession = null
var _popup_intent_asset_utility: GFAssetUtility = null


# --- @onready 变量 (节点引用) ---

@onready var _start_game_button: Button = %StartGameButton
@onready var _continue_game_button: Button = %ContinueGameButton
@onready var _continue_hint_label: Label = %ContinueHintLabel
@onready var _load_bookmark_button: Button = %LoadBookmarkButton
@onready var _replays_button: Button = %ReplaysButton
@onready var _tile_catalog_button: Button = %TileCatalogButton
@onready var _tile_lab_button: Button = %TileLabButton
@onready var _player_profile_button: Button = %PlayerProfileButton
@onready var _achievements_button: Button = %AchievementsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _safe_margin: MarginContainer = %SafeMargin
@onready var _content: BoxContainer = %Content
@onready var _showcase: VBoxContainer = %Showcase
@onready var _board_preview_frame: Panel = %BoardPreviewFrame
@onready var _board_motif: MainMenuBoardMotif = (
	$SafeMargin/Content/Showcase/BoardPreviewFrame/BoardMotif
)
@onready var _menu_column: VBoxContainer = %MenuColumn
@onready var _title_label: Label = %TitleLabel
@onready var _edition_label: Label = %EditionLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _kicker_label: Label = %KickerLabel
@onready var _menu_kicker_label: Label = %MenuKickerLabel
@onready var _collection_label: Label = %CollectionLabel
@onready var _system_label: Label = %SystemLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_viewport_utility = _get_viewport_utility()
	_content_scroll = GameTaskPageLayoutUtility.ensure_vertical_scroll_parent(
		_content,
		&"MainMenuScroll"
	)
	var _connect_result_36: int = _start_game_button.pressed.connect(_on_start_game_button_pressed)
	var _continue_connection: int = _continue_game_button.pressed.connect(
		_on_continue_game_button_pressed
	)
	var _connect_result_37: int = _load_bookmark_button.pressed.connect(_on_load_bookmark_button_pressed)
	var _connect_result_38: int = _replays_button.pressed.connect(_on_replays_button_pressed)
	var _catalog_connection: int = _tile_catalog_button.pressed.connect(_on_tile_catalog_button_pressed)
	var _tile_lab_connection: int = _tile_lab_button.pressed.connect(
		_on_tile_lab_button_pressed
	)
	var _profile_connection: int = _player_profile_button.pressed.connect(
		_on_player_profile_button_pressed
	)
	var _achievements_connection: int = _achievements_button.pressed.connect(_on_achievements_button_pressed)
	var _connect_result_39: int = _settings_button.pressed.connect(_on_settings_button_pressed)
	var _connect_result_40: int = _quit_button.pressed.connect(_on_quit_button_pressed)
	var _resize_connection: int = resized.connect(_queue_layout_update)
	_bind_full_scene_preload_hints()
	_bind_board_motif_interactions()

	_apply_semantic_styles()
	_queue_layout_update()
	_start_game_button.grab_focus()
	_update_ui_text()
	_refresh_continue_game_state()
	call_deferred(&"_play_content_reveal")
	call_deferred(&"_start_popup_intent_preload_after_first_draw")


func _exit_tree() -> void:
	_release_popup_intent_preload()


func _unhandled_input(event: InputEvent) -> void:
	if _intro_in_progress and _is_intro_skip_event(event):
		_finish_intro_now()


# --- 私有/辅助方法 ---

func _goto_scene(scene_path: String, property_name: String) -> void:
	if scene_path.is_empty():
		push_error("[MainMenu] 场景路径 %s 未设置。" % property_name)
		return

	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		router.goto_scene(scene_path)


func _start_popup_intent_preload_after_first_draw() -> void:
	if not is_inside_tree() or is_instance_valid(_popup_intent_preload_session):
		return
	var platform_utility: GamePlatformUtility = _get_platform_utility()
	if not is_instance_valid(platform_utility) or platform_utility.is_headless_runtime():
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	if not is_inside_tree() or is_instance_valid(_popup_intent_preload_session):
		return

	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	var asset_value: Object = _find_optional_utility(GFAssetUtility)
	if not is_instance_valid(ui_router) or not asset_value is GFAssetUtility:
		return
	var asset_utility: GFAssetUtility = asset_value
	var preload_result: Dictionary = ui_router.build_preload_plan(
		GameUiRouterUtility.ROUTE_TILE_CATALOG,
		{
			"max_depth": 0,
			"max_routes": _POPUP_INTENT_PRELOAD_ROUTE_IDS.size(),
			"include_source": true,
			"fixed_route_ids": _POPUP_INTENT_PRELOAD_ROUTE_IDS,
			"group_id": _POPUP_INTENT_PRELOAD_GROUP_ID,
			"plan_id": _POPUP_INTENT_PRELOAD_PLAN_ID,
			"pin_cache": true,
			"lane_id": &"ui.main_menu_popup_intent",
			"max_concurrent_loads": 2,
			"check_exists": true,
			"metadata": {
				"owner": &"main_menu",
				"purpose": &"popup_first_open_latency",
			},
		}
	)
	if (
		not GFVariantData.get_option_bool(preload_result, "ok")
		or not GFVariantData.get_option_bool(preload_result, "healthy")
	):
		return
	var plan_value: Variant = preload_result.get("asset_plan")
	if not plan_value is GFAssetPreloadPlan:
		return
	var plan: GFAssetPreloadPlan = plan_value
	var session: GFAssetLoadSession = asset_utility.start_preload_session(
		plan,
		{
			"auto_commit": true,
			"metadata": {
				"owner": &"main_menu",
				"purpose": &"popup_first_open_latency",
			},
		}
	)
	if session == null:
		return
	_popup_intent_asset_utility = asset_utility
	_popup_intent_preload_session = session
	if not is_inside_tree():
		_release_popup_intent_preload()


func _release_popup_intent_preload() -> void:
	var session: GFAssetLoadSession = _popup_intent_preload_session
	var asset_utility: GFAssetUtility = _popup_intent_asset_utility
	_popup_intent_preload_session = null
	_popup_intent_asset_utility = null
	if session != null and not session.is_completed():
		var _rolled_back: bool = session.rollback(&"main_menu_exit")
	if is_instance_valid(asset_utility):
		# GF #108 修复前禁止 eager removal；这里只释放分组 pin，缓存交给有界 LRU。
		asset_utility.unload_group(_POPUP_INTENT_PRELOAD_GROUP_ID, false)


func _bind_full_scene_preload_hints() -> void:
	_bind_scene_preload_hint(_start_game_button, mode_selection_scene_path)
	_bind_scene_preload_hint(_continue_game_button, game_scene_path)
	_bind_scene_preload_hint(_load_bookmark_button, bookmark_list_scene_path)
	_bind_scene_preload_hint(_replays_button, replay_list_scene_path)
	_bind_scene_preload_hint(_settings_button, settings_scene_path)


func _bind_scene_preload_hint(button: Button, scene_path: String) -> void:
	if not is_instance_valid(button) or scene_path.is_empty():
		return
	var focus_callback: Callable = _prime_scene_for_button.bind(button, scene_path)
	var hover_callback: Callable = _prime_scene_for_button.bind(button, scene_path)
	if not button.focus_entered.is_connected(focus_callback):
		var _focus_connection: int = button.focus_entered.connect(focus_callback)
	if not button.mouse_entered.is_connected(hover_callback):
		var _hover_connection: int = button.mouse_entered.connect(hover_callback)


func _bind_board_motif_interactions() -> void:
	if not is_instance_valid(_board_motif):
		return
	var buttons: Array[BaseButton] = _get_menu_button_sequence()
	var interaction_kinds: Array[MainMenuBoardMotif.InteractionKind] = [
		MainMenuBoardMotif.InteractionKind.START_EXPERIMENT,
		MainMenuBoardMotif.InteractionKind.CONTINUE_EXPERIMENT,
		MainMenuBoardMotif.InteractionKind.FROZEN_PROOF,
		MainMenuBoardMotif.InteractionKind.PROCESS_TAPE,
		MainMenuBoardMotif.InteractionKind.SAMPLE_ATLAS,
		MainMenuBoardMotif.InteractionKind.RULE_WORKBENCH,
		MainMenuBoardMotif.InteractionKind.OPERATOR_PROFILE,
		MainMenuBoardMotif.InteractionKind.ACHIEVEMENT_STAMPS,
		MainMenuBoardMotif.InteractionKind.CALIBRATION,
		MainMenuBoardMotif.InteractionKind.LEAVE_LAB,
	]
	for index: int in range(buttons.size()):
		var button: BaseButton = buttons[index]
		if not is_instance_valid(button):
			continue
		var callback: Callable = _play_board_motif_interaction.bind(
			interaction_kinds[index]
		)
		if not button.focus_entered.is_connected(callback):
			var _focus_connection: int = button.focus_entered.connect(callback)
		if not button.mouse_entered.is_connected(callback):
			var _hover_connection: int = button.mouse_entered.connect(callback)


func _play_board_motif_interaction(
	interaction_kind: MainMenuBoardMotif.InteractionKind
) -> void:
	if is_instance_valid(_board_motif):
		_board_motif.play_semantic_response(interaction_kind)


func _prime_scene_for_button(button: Button, scene_path: String) -> void:
	if (
		not is_instance_valid(button)
		or button.disabled
		or scene_path.is_empty()
	):
		return
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		var _preload_error: Error = router.prime_scene(scene_path)


func _update_ui_text() -> void:
	if is_instance_valid(_kicker_label):
		_kicker_label.text = tr("MAIN_MENU_KICKER")
	if is_instance_valid(_subtitle_label):
		_subtitle_label.text = tr("MAIN_MENU_SUBTITLE")
	if is_instance_valid(_menu_kicker_label):
		_menu_kicker_label.text = tr("MAIN_MENU_PLAY")
	if is_instance_valid(_collection_label):
		_collection_label.text = tr("MAIN_MENU_COLLECTION")
	if is_instance_valid(_system_label):
		_system_label.text = tr("MAIN_MENU_SYSTEM")
	if is_instance_valid(_start_game_button):
		_start_game_button.text = tr("BTN_START_GAME")
	if is_instance_valid(_continue_game_button):
		_continue_game_button.text = tr("BTN_CONTINUE_GAME")
		_continue_game_button.tooltip_text = (
			tr("CONTINUE_GAME_HINT")
			if not _continue_game_button.disabled
			else tr("CONTINUE_GAME_UNAVAILABLE_HINT")
		)
	if is_instance_valid(_continue_hint_label):
		_continue_hint_label.text = tr("CONTINUE_GAME_UNAVAILABLE_HINT")
	if is_instance_valid(_load_bookmark_button):
		_load_bookmark_button.text = tr("BTN_LOAD_SAVE")
	if is_instance_valid(_replays_button):
		_replays_button.text = tr("BTN_REPLAY_LIST")
	if is_instance_valid(_tile_catalog_button):
		_tile_catalog_button.text = tr("BTN_TILE_CATALOG")
	if is_instance_valid(_tile_lab_button):
		_tile_lab_button.text = tr("BTN_TILE_LAB")
	if is_instance_valid(_player_profile_button):
		_player_profile_button.text = tr("BTN_PLAYER_PROFILE")
	if is_instance_valid(_achievements_button):
		_achievements_button.text = tr("BTN_ACHIEVEMENTS")
	if is_instance_valid(_settings_button):
		_settings_button.text = tr("SETTINGS_TITLE")
	if is_instance_valid(_quit_button):
		_quit_button.text = tr("BTN_QUIT")


func _apply_semantic_styles() -> void:
	var style: GameUiStyleUtility = _get_ui_style_utility()
	if not is_instance_valid(style):
		return
	style.style_label(_title_label, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_edition_label, GameUiStyleUtility.TextRole.DISPLAY)
	style.style_label(_subtitle_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_kicker_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_menu_kicker_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_collection_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_system_label, GameUiStyleUtility.TextRole.SECONDARY)
	style.style_label(_continue_hint_label, GameUiStyleUtility.TextRole.MUTED)
	style.style_button(_start_game_button, GameUiStyleUtility.ButtonRole.PRIMARY)
	style.style_button(_continue_game_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_load_bookmark_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_replays_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_tile_catalog_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_tile_lab_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_player_profile_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_achievements_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_settings_button, GameUiStyleUtility.ButtonRole.SECONDARY)
	style.style_button(_quit_button, GameUiStyleUtility.ButtonRole.SECONDARY)


func _play_content_reveal() -> void:
	var shortened: bool = _has_played_full_intro
	_has_played_full_intro = true
	var reduced_motion: bool = _is_reduced_motion_enabled()
	_intro_in_progress = not shortened and not reduced_motion
	if is_instance_valid(_board_motif):
		_board_motif.play_intro(reduced_motion, shortened)

	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion):
		return

	var brand_pieces: Array[Control] = [
		_kicker_label,
		_title_label,
		_edition_label,
		_subtitle_label,
	]
	var _brand_reveal_count: int = motion.play_piece_assembly(
		brand_pieces,
		_RETURN_BRAND_STAGGER if shortened else _INTRO_BRAND_STAGGER
	)
	var _menu_reveal_count: int = motion.play_button_deal_sequence(
		_get_menu_button_sequence(),
		Vector2(34.0, 0.0),
		_RETURN_MENU_STAGGER if shortened else _INTRO_MENU_STAGGER,
		0.0 if shortened else _INTRO_MENU_DELAY
	)
	if _intro_in_progress:
		_intro_completion_tween = create_tween()
		var _pause_mode_result: Tween = _intro_completion_tween.set_pause_mode(
			Tween.TWEEN_PAUSE_PROCESS
		)
		var _intro_wait: IntervalTweener = _intro_completion_tween.tween_interval(
			_FULL_INTRO_WINDOW
		)
		var _intro_finished: CallbackTweener = _intro_completion_tween.tween_callback(
			_mark_intro_complete
		)


func _finish_intro_now() -> void:
	if not _intro_in_progress:
		return
	_intro_in_progress = false
	if _intro_completion_tween != null and _intro_completion_tween.is_valid():
		_intro_completion_tween.kill()
	_intro_completion_tween = null
	if is_instance_valid(_board_motif):
		_board_motif.finish_intro()
	var motion: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion):
		return
	for brand_piece: Control in [
		_kicker_label,
		_title_label,
		_edition_label,
		_subtitle_label,
	]:
		motion.complete_control_motion(brand_piece)
	for menu_button: BaseButton in _get_menu_button_sequence():
		motion.complete_button_motion(menu_button)


func _get_menu_button_sequence() -> Array[BaseButton]:
	var buttons: Array[BaseButton] = [
		_start_game_button,
		_continue_game_button,
		_load_bookmark_button,
		_replays_button,
		_tile_catalog_button,
		_tile_lab_button,
		_player_profile_button,
		_achievements_button,
		_settings_button,
		_quit_button,
	]
	return buttons


func _mark_intro_complete() -> void:
	_intro_in_progress = false
	_intro_completion_tween = null


func _is_intro_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		return key_event.pressed and not key_event.echo
	if event is InputEventJoypadButton:
		var joypad_event: InputEventJoypadButton = event
		return joypad_event.pressed
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return mouse_event.pressed
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event
		return touch_event.pressed
	return false


func _queue_layout_update() -> void:
	if _layout_update_queued:
		return
	_layout_update_queued = true
	call_deferred(&"_apply_responsive_layout")


func _apply_responsive_layout() -> void:
	_layout_update_queued = false
	if not is_inside_tree():
		return
	var task_layout_mode: int = GameTaskPageLayoutUtility.classify_layout(size)
	var compact: bool = task_layout_mode != GameTaskPageLayoutUtility.LayoutMode.DESKTOP
	var compact_landscape: bool = (
		task_layout_mode == GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE
	)
	_content.vertical = compact
	_board_preview_frame.visible = true
	_board_preview_frame.custom_minimum_size = _get_board_preview_minimum_size(
		task_layout_mode
	)
	_board_preview_frame.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_EXPAND_FILL
	)
	_showcase.size_flags_vertical = (
		Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL
	)
	_menu_column.size_flags_vertical = (
		Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_SHRINK_CENTER
	)
	_showcase.custom_minimum_size.x = 0.0 if compact else 520.0
	_menu_column.custom_minimum_size.x = 0.0 if compact else 360.0
	_content.add_theme_constant_override(
		"separation",
		12 if compact_landscape else (18 if compact else 56)
	)
	_menu_column.add_theme_constant_override(
		"separation",
		6 if compact_landscape else (8 if compact else 10)
	)
	_apply_safe_area_margins(
		GameTaskPageLayoutUtility.get_safe_area_extra_margins(
			task_layout_mode,
			_DESKTOP_SAFE_AREA_MARGINS
		)
	)
	_title_label.add_theme_font_size_override(
		"font_size",
		44 if compact_landscape else (56 if compact else 104)
	)
	_edition_label.add_theme_font_size_override(
		"font_size",
		16 if compact_landscape else (18 if compact else 24)
	)
	_subtitle_label.add_theme_font_size_override(
		"font_size",
		12 if compact_landscape else (13 if compact else 16)
	)
	_subtitle_label.custom_minimum_size.x = 180.0 if compact else 220.0
	_start_game_button.custom_minimum_size.y = (
		52.0 if compact_landscape else (58.0 if compact else 68.0)
	)
	_continue_game_button.custom_minimum_size.y = (
		44.0 if compact_landscape else (48.0 if compact else 54.0)
	)
	_load_bookmark_button.custom_minimum_size.y = (
		44.0 if compact_landscape else (48.0 if compact else 54.0)
	)
	if is_instance_valid(_content_scroll) and not _initial_scroll_restored:
		_initial_scroll_restored = true
		call_deferred(&"_restore_initial_scroll_position")


static func _get_board_preview_minimum_size(
	page_layout_mode: GameTaskPageLayoutUtility.LayoutMode
) -> Vector2:
	match page_layout_mode:
		GameTaskPageLayoutUtility.LayoutMode.COMPACT_LANDSCAPE:
			return Vector2(224.0, 128.0)
		GameTaskPageLayoutUtility.LayoutMode.PORTRAIT:
			return Vector2(240.0, 164.0)
		_:
			return Vector2(440.0, 378.0)


func _restore_initial_scroll_position() -> void:
	if not is_instance_valid(_content_scroll):
		return
	_content_scroll.scroll_vertical = 0


func _apply_safe_area_margins(extra_margins: Dictionary) -> void:
	if is_instance_valid(_viewport_utility):
		var _safe_area_report: Dictionary = _viewport_utility.apply_display_safe_area_margins(
			_safe_margin,
			get_viewport(),
			extra_margins
		)
		return
	GameTaskPageLayoutUtility.apply_margin_fallback(_safe_margin, extra_margins)


func _get_scene_router_system() -> SceneRouterSystem:
	var system_value: Object = get_system(SceneRouterSystem)
	if system_value is SceneRouterSystem:
		var scene_router: SceneRouterSystem = system_value
		return scene_router
	return null


func _get_viewport_utility() -> GFViewportUtility:
	var utility_value: Object = get_utility(GFViewportUtility)
	if utility_value is GFViewportUtility:
		var viewport_utility: GFViewportUtility = utility_value
		return viewport_utility
	return null


func _get_platform_utility() -> GamePlatformUtility:
	var utility_value: Object = get_utility(GamePlatformUtility)
	if utility_value is GamePlatformUtility:
		var platform_utility: GamePlatformUtility = utility_value
		return platform_utility
	return null


func _is_reduced_motion_enabled() -> bool:
	var utility_value: Object = get_utility(GameAccessibilityUtility)
	if utility_value is GameAccessibilityUtility:
		var accessibility: GameAccessibilityUtility = utility_value
		return accessibility.get_state().reduced_motion
	return false


func _get_bookmark_system() -> BookmarkSystem:
	var system_value: Object = get_system(BookmarkSystem)
	if system_value is BookmarkSystem:
		var bookmark_system: BookmarkSystem = system_value
		return bookmark_system
	return null


func _get_app_config_model() -> AppConfigModel:
	var model_value: Object = get_model(AppConfigModel)
	if model_value is AppConfigModel:
		var app_config: AppConfigModel = model_value
		return app_config
	return null


func _get_mode_catalog_utility() -> GameModeCatalogUtility:
	var utility_value: Object = get_utility(GameModeCatalogUtility)
	if utility_value is GameModeCatalogUtility:
		var mode_catalog: GameModeCatalogUtility = utility_value
		return mode_catalog
	return null


func _get_determinism_utility() -> GameDeterminismUtility:
	var utility_value: Object = get_utility(GameDeterminismUtility)
	if utility_value is GameDeterminismUtility:
		var determinism: GameDeterminismUtility = utility_value
		return determinism
	return null


func _refresh_continue_game_state() -> void:
	_latest_valid_bookmark = _find_latest_valid_bookmark()
	if not is_instance_valid(_continue_game_button):
		return
	_continue_game_button.disabled = not is_instance_valid(_latest_valid_bookmark)
	if is_instance_valid(_continue_hint_label):
		_continue_hint_label.visible = _continue_game_button.disabled
	_continue_game_button.tooltip_text = (
		tr("CONTINUE_GAME_HINT")
		if not _continue_game_button.disabled
		else tr("CONTINUE_GAME_UNAVAILABLE_HINT")
	)
	if not _continue_game_button.disabled:
		_prime_scene_for_button(_continue_game_button, game_scene_path)


func _find_latest_valid_bookmark() -> BookmarkData:
	var bookmark_system: BookmarkSystem = _get_bookmark_system()
	var mode_catalog: GameModeCatalogUtility = _get_mode_catalog_utility()
	var determinism: GameDeterminismUtility = _get_determinism_utility()
	if (
		not is_instance_valid(bookmark_system)
		or not is_instance_valid(mode_catalog)
		or not is_instance_valid(determinism)
	):
		return null

	var registered_paths: PackedStringArray = mode_catalog.get_registered_config_paths()
	for bookmark: BookmarkData in bookmark_system.load_bookmarks():
		if not registered_paths.has(bookmark.mode_config_path):
			continue
		var mode_config: GameModeConfig = mode_catalog.get_config(bookmark.mode_config_path)
		if not _is_bookmark_valid_for_resume(bookmark, mode_config, determinism):
			continue
		return bookmark
	return null


static func _is_bookmark_valid_for_resume(
	bookmark: BookmarkData,
	mode_config: GameModeConfig,
	determinism: GameDeterminismUtility
) -> bool:
	return (
		is_instance_valid(bookmark)
		and is_instance_valid(mode_config)
		and is_instance_valid(determinism)
		and mode_config.validate()
		and bookmark.target_tile_value == maxi(mode_config.target_tile_value, 0)
		and bookmark.matches_ruleset(mode_config, determinism)
	)


func _resume_bookmark(bookmark: BookmarkData) -> void:
	if not is_instance_valid(bookmark):
		return
	var app_config: AppConfigModel = _get_app_config_model()
	if not is_instance_valid(app_config):
		push_error("[MainMenu] 缺少 AppConfigModel，无法继续存档。")
		return
	app_config.current_replay_data.set_value(null)
	app_config.selected_bookmark_data.set_value(bookmark)
	app_config.selected_mode_config_path.set_value("")
	app_config.selected_board_topology.set_value(null)
	_goto_scene(game_scene_path, "game_scene_path")


func _report_route_open_failure(result: GFUIRouteResult, route_id: StringName) -> void:
	if result == null or result.is_successful():
		return
	push_error("[MainMenu] GF UI 路由打开失败：route=%s, status=%s, reason=%s。" % [
		route_id,
		result.get_status(),
		result.get_reason(),
	])


func _open_popup_route(
	route_id: StringName,
	origin_button: BaseButton,
	panel_name: String
) -> void:
	if _popup_route_open_pending:
		return
	var ui_router: GameUiRouterUtility = _get_game_ui_router_utility()
	if not is_instance_valid(ui_router):
		push_error("[MainMenu] 缺少 GFUIRouterUtility，无法打开%s。" % panel_name)
		return
	if not _begin_popup_route_open():
		return

	var result: GFUIRouteResult = await ui_router.push_owned_route_async(self, route_id)
	if not is_inside_tree():
		_finish_popup_route_open(origin_button, false)
		return
	var opened: bool = result != null and result.is_successful()
	_finish_popup_route_open(origin_button, opened)
	_report_route_open_failure(result, route_id)


func _begin_popup_route_open() -> bool:
	if _popup_route_open_pending:
		return false
	_popup_route_open_pending = true
	_popup_route_button_disabled_states.clear()
	for button: BaseButton in _get_menu_button_sequence():
		if not is_instance_valid(button):
			continue
		_popup_route_button_disabled_states[button] = button.disabled
		button.disabled = true
	return true


func _finish_popup_route_open(origin_button: BaseButton, opened: bool) -> void:
	if not _popup_route_open_pending:
		return
	_popup_route_open_pending = false
	for button: BaseButton in _get_menu_button_sequence():
		if not is_instance_valid(button):
			continue
		button.disabled = GFVariantData.to_bool(
			_popup_route_button_disabled_states.get(button, false)
		)
	_popup_route_button_disabled_states.clear()
	if (
		not opened
		and is_instance_valid(origin_button)
		and origin_button.is_inside_tree()
		and not origin_button.disabled
	):
		origin_button.grab_focus()


# --- 信号处理函数 ---

func _on_start_game_button_pressed() -> void:
	_goto_scene(mode_selection_scene_path, "mode_selection_scene_path")


func _on_continue_game_button_pressed() -> void:
	_refresh_continue_game_state()
	if is_instance_valid(_latest_valid_bookmark):
		_resume_bookmark(_latest_valid_bookmark)


func _on_load_bookmark_button_pressed() -> void:
	_goto_scene(bookmark_list_scene_path, "bookmark_list_scene_path")


func _on_replays_button_pressed() -> void:
	_goto_scene(replay_list_scene_path, "replay_list_scene_path")


func _on_tile_catalog_button_pressed() -> void:
	await _open_popup_route(
		GameUiRouterUtility.ROUTE_TILE_CATALOG,
		_tile_catalog_button,
		"方块图鉴"
	)


func _on_tile_lab_button_pressed() -> void:
	await _open_popup_route(
		GameUiRouterUtility.ROUTE_TILE_LAB,
		_tile_lab_button,
		"方块试验台"
	)


func _on_player_profile_button_pressed() -> void:
	await _open_popup_route(
		GameUiRouterUtility.ROUTE_PLAYER_PROFILE,
		_player_profile_button,
		"玩家档案"
	)


func _on_achievements_button_pressed() -> void:
	await _open_popup_route(
		GameUiRouterUtility.ROUTE_ACHIEVEMENTS,
		_achievements_button,
		"成就列表"
	)


func _on_settings_button_pressed() -> void:
	_goto_scene(settings_scene_path, "settings_scene_path")


func _on_quit_button_pressed() -> void:
	var router: SceneRouterSystem = _get_scene_router_system()
	if is_instance_valid(router):
		var _quit_completion: GFAsyncCompletion = router.quit_game()
