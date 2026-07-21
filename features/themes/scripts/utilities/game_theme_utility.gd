## GameThemeUtility: 项目级主题激活服务。
##
## 主题列表来自内容包描述符；完整资源通过 GFAssetLoadSession 加载到 staging group，
## 校验和事务激活成功后才替换当前资源组。声音银行额外使用 GF 挂载令牌管理生命周期。
class_name GameThemeUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal visual_theme_changed(theme: GameTheme)
signal sound_theme_changed(theme: GameAudioTheme)
signal initial_themes_ready(succeeded: bool)
signal visual_theme_activation_started(theme_id: StringName)
signal visual_theme_activation_finished(theme_id: StringName, succeeded: bool)
signal sound_theme_activation_started(theme_id: StringName)
signal sound_theme_activation_finished(theme_id: StringName, succeeded: bool)


# --- 常量 ---

const VISUAL_THEME_SETTING_KEY: StringName = &"appearance/theme_id"
const SOUND_THEME_SETTING_KEY: StringName = &"audio/sound_theme_id"
const DEFAULT_THEME_ID: StringName = &"halftone_atlas"
const DEFAULT_SOUND_THEME_ID: StringName = &"printworks"
const _VISUAL_ASSET_LANE_ID: StringName = &"game.theme.visual"
const _SOUND_ASSET_LANE_ID: StringName = &"game.theme.sound"
const _ASSET_LOAD_CONCURRENCY: int = 4


# --- 私有变量 ---

var _settings: GFSettingsUtility = null
var _audio: GFAudioUtility = null
var _assets: GFAssetUtility = null
var _style: GameUiStyleUtility = null
var _motion: GameUiMotionUtility = null
var _board_feedback: GameBoardFeedbackUtility = null
var _celebration_vfx: GameCelebrationVfxUtility = null
var _theme_catalog: GameThemeCatalogUtility = null
var _shader_parameters: GFShaderParameterUtility = null
var _signal_utility: GFSignalUtility = null
var _current_visual_theme: GameTheme = null
var _current_sound_theme: GameAudioTheme = null
var _active_visual_asset_group_id: StringName = &""
var _active_sound_asset_group_id: StringName = &""
var _pending_visual_asset_session: GFAssetLoadSession = null
var _pending_sound_asset_session: GFAssetLoadSession = null
var _visual_activation_serial: int = 0
var _sound_activation_serial: int = 0
var _initial_activation_started: bool = false
var _initial_activation_completed: bool = false
var _initial_activation_succeeded: bool = false
var _active_audio_bank_id: StringName = &""
var _active_audio_mount_token: int = 0
var _pending_sound_theme: GameAudioTheme = null
var _pending_audio_bank_id: StringName = &""
var _pending_audio_mount_token: int = 0
var _previous_sound_theme: GameAudioTheme = null
var _last_visual_activation_report: Dictionary = {}
var _last_sound_activation_report: Dictionary = {}


# --- GF 生命周期方法 ---

func init() -> void:
	_clear_runtime_state()


func get_required_utilities() -> Array[Script]:
	return [
		GameBoardFeedbackUtility,
		GameCelebrationVfxUtility,
		GameThemeCatalogUtility,
		GameUiStyleUtility,
		GameUiMotionUtility,
		GFAudioUtility,
		GFAssetUtility,
		GFSettingsUtility,
		GFShaderParameterUtility,
		GFSignalUtility,
	]


func ready() -> void:
	_settings = _get_settings_utility()
	_audio = _get_audio_utility()
	_assets = _get_asset_utility()
	_style = _get_style_utility()
	_motion = _get_motion_utility()
	_board_feedback = _get_board_feedback_utility()
	_celebration_vfx = _get_celebration_vfx_utility()
	_theme_catalog = _get_theme_catalog_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_signal_utility = _get_signal_utility()
	_connect_settings()
	_connect_motion_audio_feedback()


func dispose() -> void:
	_cancel_pending_asset_sessions(&"theme_utility_disposed")
	_unmount_current_audio_bank()
	_release_active_asset_groups()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_settings = null
	_audio = null
	_assets = null
	_style = null
	_motion = null
	_board_feedback = null
	_celebration_vfx = null
	_theme_catalog = null
	_shader_parameters = null
	_signal_utility = null
	_clear_runtime_state()


func release_dependencies() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_settings = null
	_audio = null
	_assets = null
	_style = null
	_motion = null
	_board_feedback = null
	_celebration_vfx = null
	_theme_catalog = null
	_shader_parameters = null
	_signal_utility = null
	super.release_dependencies()


# --- 公共方法 ---

func get_visual_theme_descriptors() -> Array[GameThemeDescriptor]:
	if not is_instance_valid(_theme_catalog):
		return []
	return _theme_catalog.get_visual_theme_descriptors()


func get_sound_theme_descriptors() -> Array[GameThemeDescriptor]:
	if not is_instance_valid(_theme_catalog):
		return []
	return _theme_catalog.get_sound_theme_descriptors()


func get_current_visual_theme() -> GameTheme:
	return _current_visual_theme


func get_current_sound_theme() -> GameAudioTheme:
	return _current_sound_theme


func get_current_visual_theme_id() -> StringName:
	if is_instance_valid(_current_visual_theme):
		return _current_visual_theme.theme_id
	return _get_default_visual_theme_id()


func get_current_sound_theme_id() -> StringName:
	if is_instance_valid(_current_sound_theme):
		return _current_sound_theme.theme_id
	return _get_default_sound_theme_id()


func is_initial_activation_completed() -> bool:
	return _initial_activation_completed


func did_initial_activation_succeed() -> bool:
	return _initial_activation_completed and _initial_activation_succeeded


## 加载并激活设置中声明的初始视觉与声音主题。
## 启动编排器必须等待该方法完成后再进入首个业务场景。
func ensure_initial_themes_ready() -> bool:
	if _initial_activation_completed:
		return _initial_activation_succeeded
	if _initial_activation_started:
		var _completion_value: Variant = await initial_themes_ready
		return _initial_activation_succeeded

	_initial_activation_started = true
	var visual_activated: bool = await _activate_visual_theme_with_assets(
		_get_setting_string_name(VISUAL_THEME_SETTING_KEY, _get_default_visual_theme_id()),
		true,
		false
	)
	if not is_lifecycle_active():
		_complete_initial_activation(false)
		return false
	var sound_activated: bool = await _activate_sound_theme_with_assets(
		_get_setting_string_name(SOUND_THEME_SETTING_KEY, _get_default_sound_theme_id()),
		true,
		false
	)
	_complete_initial_activation(visual_activated and sound_activated)
	return _initial_activation_succeeded


## @param theme_id: 待显示的视觉主题 ID。
func get_visual_theme_display_text(theme_id: StringName) -> String:
	if is_instance_valid(_theme_catalog):
		var descriptor: GameThemeDescriptor = _theme_catalog.get_visual_theme_descriptor(theme_id)
		if descriptor != null:
			return descriptor.get_display_text()
	return String(theme_id if theme_id != &"" else _get_default_visual_theme_id())


## @param theme_id: 待显示的声音主题 ID。
func get_sound_theme_display_text(theme_id: StringName) -> String:
	if is_instance_valid(_theme_catalog):
		var descriptor: GameThemeDescriptor = _theme_catalog.get_sound_theme_descriptor(theme_id)
		if descriptor != null:
			return descriptor.get_display_text()
	return String(theme_id if theme_id != &"" else _get_default_sound_theme_id())


## 切换当前视觉主题；失败时保持原主题和设置不变。
## @param theme_id: 待激活的视觉主题 ID。
func set_current_visual_theme_id(theme_id: StringName) -> bool:
	var activated: bool = await _activate_visual_theme_with_assets(theme_id, true, true)
	return activated


## 切换当前声音主题；失败时恢复原银行并保持设置不变。
## @param theme_id: 待激活的声音主题 ID。
func set_current_sound_theme_id(theme_id: StringName) -> bool:
	var activated: bool = await _activate_sound_theme_with_assets(theme_id, true, true)
	return activated


## @param fallback: 当前主题未提供棋盘主题时使用的回退资源。
func resolve_board_theme(fallback: BoardTheme) -> BoardTheme:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		return theme.get_board_theme_with_fallback(fallback)
	return fallback


## @param fallback: 当前主题未提供颜色方案时使用的回退字典。
func resolve_color_schemes(fallback: Dictionary) -> Dictionary:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		return theme.get_color_schemes_with_fallback(fallback)
	return fallback


## 返回当前主题的方块家族视觉目录。
func resolve_tile_visual_theme() -> TileVisualTheme:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		return theme.get_tile_visual_theme()
	return null


## 按稳定家族 ID 返回当前主题中的方块视觉配置。
## @param family_id: `TileDefinition` 提供的稳定视觉家族 ID。
func resolve_tile_visual_style(family_id: StringName) -> TileVisualFamilyStyle:
	var visual_theme: TileVisualTheme = resolve_tile_visual_theme()
	if is_instance_valid(visual_theme):
		return visual_theme.get_family_style(family_id)
	return null


## @param rect: 接收当前主题背景的目标 ColorRect。
## @param fallback_board_theme: 当前主题不可用时使用的棋盘主题。
func apply_background_to_color_rect(
	rect: ColorRect,
	fallback_board_theme: BoardTheme = null
) -> void:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		_apply_background_to_color_rect(rect, theme, fallback_board_theme)
		return
	if is_instance_valid(rect) and is_instance_valid(fallback_board_theme):
		rect.color = fallback_board_theme.game_background_color


## @param root: 应用当前主题的 UI 子树根节点。
func apply_current_theme_to_tree(root: Node) -> int:
	var theme: GameTheme = get_current_visual_theme()
	if not is_instance_valid(theme):
		return 0
	var applied_count: int = 0
	if is_instance_valid(_style) and is_instance_valid(theme.ui_palette):
		applied_count += _style.apply_palette_to_tree(root, theme.ui_palette)
	applied_count += _apply_backgrounds_to_tree(root, theme)
	return applied_count


## @param event_id: 当前声音主题银行中的语义事件 ID。
func play_current_sound_event(event_id: StringName) -> void:
	if event_id == &"" or not is_instance_valid(_audio):
		return
	if not is_instance_valid(_current_sound_theme) or _active_audio_mount_token <= 0:
		return
	_audio.play_sfx_event(event_id, _active_audio_bank_id)


func play_ui_select_sound() -> void:
	if is_instance_valid(_current_sound_theme):
		play_current_sound_event(_current_sound_theme.ui_select_event)


func play_ui_confirm_sound() -> void:
	if is_instance_valid(_current_sound_theme):
		play_current_sound_event(_current_sound_theme.ui_confirm_event)


func play_tile_spawn_sound() -> void:
	if is_instance_valid(_current_sound_theme):
		play_current_sound_event(_current_sound_theme.tile_spawn_event)


func play_tile_move_sound() -> void:
	if is_instance_valid(_current_sound_theme):
		play_current_sound_event(_current_sound_theme.tile_move_event)


func play_tile_merge_sound() -> void:
	if is_instance_valid(_current_sound_theme):
		play_current_sound_event(_current_sound_theme.tile_merge_event)


func play_game_over_sound() -> void:
	if is_instance_valid(_current_sound_theme):
		play_current_sound_event(_current_sound_theme.game_over_event)


func get_debug_snapshot() -> Dictionary:
	return {
		"current_visual_theme_id": get_current_visual_theme_id(),
		"current_sound_theme_id": get_current_sound_theme_id(),
		"available_visual_theme_count": get_visual_theme_descriptors().size(),
		"available_sound_theme_count": get_sound_theme_descriptors().size(),
		"initial_activation_completed": _initial_activation_completed,
		"initial_activation_succeeded": _initial_activation_succeeded,
		"active_visual_asset_group_id": _active_visual_asset_group_id,
		"active_sound_asset_group_id": _active_sound_asset_group_id,
		"pending_visual_asset_session_state": _get_session_state(
			_pending_visual_asset_session
		),
		"pending_sound_asset_session_state": _get_session_state(
			_pending_sound_asset_session
		),
		"active_audio_bank_id": _active_audio_bank_id,
		"active_audio_mount_token": _active_audio_mount_token,
		"visual_activation": _last_visual_activation_report.duplicate(true),
		"sound_activation": _last_sound_activation_report.duplicate(true),
		"catalog": (
			_theme_catalog.get_debug_snapshot()
			if is_instance_valid(_theme_catalog)
			else {}
		),
	}


# --- 私有/主题激活事务 ---

func _activate_visual_theme_with_assets(
	theme_id: StringName,
	persist_setting: bool,
	emit_change: bool
) -> bool:
	var descriptor: GameThemeDescriptor = _resolve_visual_descriptor_or_default(theme_id)
	if descriptor == null or not is_instance_valid(_assets):
		return false
	if is_instance_valid(_current_visual_theme):
		if (
			_current_visual_theme.theme_id == descriptor.theme_id
			and _active_visual_asset_group_id != &""
		):
			if persist_setting:
				_set_setting_string_name(VISUAL_THEME_SETTING_KEY, descriptor.theme_id)
			return true

	_visual_activation_serial += 1
	var request_serial: int = _visual_activation_serial
	_cancel_asset_session(_pending_visual_asset_session, &"visual_theme_superseded")
	_pending_visual_asset_session = null
	var resource_path: String = _theme_catalog.get_visual_theme_resource_path(
		descriptor.theme_id
	)
	var plan: GFAssetPreloadPlan = _build_theme_asset_plan(
		&"visual",
		descriptor.theme_id,
		resource_path,
		request_serial
	)
	visual_theme_activation_started.emit(descriptor.theme_id)
	if plan == null:
		_record_asset_activation_failure(
			true,
			"无法为视觉主题构建资源预加载计划。",
			resource_path
		)
		visual_theme_activation_finished.emit(descriptor.theme_id, false)
		return false

	var session: GFAssetLoadSession = _assets.start_preload_session(
		plan,
		{
			"auto_commit": false,
			"metadata": {
				"theme_kind": &"visual",
				"theme_id": descriptor.theme_id,
				"resource_path": resource_path,
			},
		}
	)
	_pending_visual_asset_session = session
	var preload_ready: bool = await _wait_for_asset_session_ready(session)
	if not is_lifecycle_active():
		_cancel_asset_session(session, &"theme_utility_inactive")
		return false
	if request_serial != _visual_activation_serial or session != _pending_visual_asset_session:
		_cancel_asset_session(session, &"visual_theme_superseded")
		visual_theme_activation_finished.emit(descriptor.theme_id, false)
		return false
	if not preload_ready:
		_record_asset_activation_failure(
			true,
			"视觉主题资源预加载失败。",
			resource_path,
			session
		)
		_finish_visual_asset_request(session, descriptor.theme_id, false)
		return false

	var resource: Resource = _assets.get_cached(resource_path)
	if not resource is GameTheme:
		_cancel_asset_session(session, &"invalid_visual_theme_resource")
		_record_asset_activation_failure(
			true,
			"预加载结果不是 GameTheme。",
			resource_path,
			session
		)
		_finish_visual_asset_request(session, descriptor.theme_id, false)
		return false
	var theme: GameTheme = resource
	if theme.theme_id != descriptor.theme_id:
		_cancel_asset_session(session, &"visual_theme_id_mismatch")
		_record_asset_activation_failure(
			true,
			"视觉主题资源 ID 与内容描述符不一致。",
			resource_path,
			session
		)
		_finish_visual_asset_request(session, descriptor.theme_id, false)
		return false
	if not session.commit():
		_record_asset_activation_failure(
			true,
			"视觉主题资源组提交失败。",
			resource_path,
			session
		)
		_finish_visual_asset_request(session, descriptor.theme_id, false)
		return false

	var new_group_id: StringName = session.get_group_id()
	var previous_group_id: StringName = _active_visual_asset_group_id
	if not _activate_visual_theme_resource(theme):
		_release_asset_group(new_group_id)
		_finish_visual_asset_request(session, descriptor.theme_id, false)
		return false
	_active_visual_asset_group_id = new_group_id
	_release_replaced_asset_group(previous_group_id, new_group_id)
	if persist_setting:
		_set_setting_string_name(VISUAL_THEME_SETTING_KEY, theme.theme_id)
	if emit_change:
		visual_theme_changed.emit(theme)
	_finish_visual_asset_request(session, descriptor.theme_id, true)
	return true


func _activate_sound_theme_with_assets(
	theme_id: StringName,
	persist_setting: bool,
	emit_change: bool
) -> bool:
	var descriptor: GameThemeDescriptor = _resolve_sound_descriptor_or_default(theme_id)
	if descriptor == null or not is_instance_valid(_assets):
		return false
	if is_instance_valid(_current_sound_theme):
		if (
			_current_sound_theme.theme_id == descriptor.theme_id
			and _active_audio_mount_token > 0
			and _active_sound_asset_group_id != &""
		):
			if persist_setting:
				_set_setting_string_name(SOUND_THEME_SETTING_KEY, descriptor.theme_id)
			return true

	_sound_activation_serial += 1
	var request_serial: int = _sound_activation_serial
	_cancel_asset_session(_pending_sound_asset_session, &"sound_theme_superseded")
	_pending_sound_asset_session = null
	var resource_path: String = _theme_catalog.get_sound_theme_resource_path(
		descriptor.theme_id
	)
	var plan: GFAssetPreloadPlan = _build_theme_asset_plan(
		&"sound",
		descriptor.theme_id,
		resource_path,
		request_serial
	)
	sound_theme_activation_started.emit(descriptor.theme_id)
	if plan == null:
		_record_asset_activation_failure(
			false,
			"无法为声音主题构建资源预加载计划。",
			resource_path
		)
		sound_theme_activation_finished.emit(descriptor.theme_id, false)
		return false

	var session: GFAssetLoadSession = _assets.start_preload_session(
		plan,
		{
			"auto_commit": false,
			"metadata": {
				"theme_kind": &"sound",
				"theme_id": descriptor.theme_id,
				"resource_path": resource_path,
			},
		}
	)
	_pending_sound_asset_session = session
	var preload_ready: bool = await _wait_for_asset_session_ready(session)
	if not is_lifecycle_active():
		_cancel_asset_session(session, &"theme_utility_inactive")
		return false
	if request_serial != _sound_activation_serial or session != _pending_sound_asset_session:
		_cancel_asset_session(session, &"sound_theme_superseded")
		sound_theme_activation_finished.emit(descriptor.theme_id, false)
		return false
	if not preload_ready:
		_record_asset_activation_failure(
			false,
			"声音主题资源预加载失败。",
			resource_path,
			session
		)
		_finish_sound_asset_request(session, descriptor.theme_id, false)
		return false

	var resource: Resource = _assets.get_cached(resource_path)
	if not resource is GameAudioTheme:
		_cancel_asset_session(session, &"invalid_sound_theme_resource")
		_record_asset_activation_failure(
			false,
			"预加载结果不是 GameAudioTheme。",
			resource_path,
			session
		)
		_finish_sound_asset_request(session, descriptor.theme_id, false)
		return false
	var theme: GameAudioTheme = resource
	if theme.theme_id != descriptor.theme_id:
		_cancel_asset_session(session, &"sound_theme_id_mismatch")
		_record_asset_activation_failure(
			false,
			"声音主题资源 ID 与内容描述符不一致。",
			resource_path,
			session
		)
		_finish_sound_asset_request(session, descriptor.theme_id, false)
		return false
	if not session.commit():
		_record_asset_activation_failure(
			false,
			"声音主题资源组提交失败。",
			resource_path,
			session
		)
		_finish_sound_asset_request(session, descriptor.theme_id, false)
		return false

	var new_group_id: StringName = session.get_group_id()
	var previous_group_id: StringName = _active_sound_asset_group_id
	if not _activate_sound_theme_resource(theme):
		_release_asset_group(new_group_id)
		_finish_sound_asset_request(session, descriptor.theme_id, false)
		return false
	_active_sound_asset_group_id = new_group_id
	_release_replaced_asset_group(previous_group_id, new_group_id)
	if persist_setting:
		_set_setting_string_name(SOUND_THEME_SETTING_KEY, theme.theme_id)
	if emit_change:
		sound_theme_changed.emit(theme)
	_finish_sound_asset_request(session, descriptor.theme_id, true)
	return true


func _activate_visual_theme_resource(theme: GameTheme) -> bool:
	var previous_theme: GameTheme = _current_visual_theme
	var transaction: GFActivationTransaction = GFActivationTransaction.new().configure(
		&"game.visual_theme",
		"Visual theme activation",
		{"theme_id": theme.theme_id}
	)
	var _step_added: bool = transaction.add_step(
		&"apply_visual_theme",
		Callable(self, "_transaction_apply_visual_theme").bind(theme),
		Callable(self, "_transaction_apply_visual_theme").bind(previous_theme),
		{
			"validate_callback": Callable(
				self,
				"_transaction_validate_visual_theme"
			).bind(theme),
		}
	)
	_last_visual_activation_report = transaction.commit()
	if not GFVariantData.get_option_bool(_last_visual_activation_report, "ok", false):
		_log_activation_failure("视觉主题", _last_visual_activation_report)
		return false

	_current_visual_theme = theme
	return true


func _activate_sound_theme_resource(theme: GameAudioTheme) -> bool:
	_pending_sound_theme = theme
	_pending_audio_bank_id = theme.get_resolved_bank_id()
	_pending_audio_mount_token = 0
	_previous_sound_theme = _current_sound_theme
	var transaction: GFActivationTransaction = GFActivationTransaction.new().configure(
		&"game.sound_theme",
		"Sound theme activation",
		{"theme_id": theme.theme_id, "bank_id": _pending_audio_bank_id}
	)
	var _mount_step_added: bool = transaction.add_step(
		&"mount_audio_bank",
		Callable(self, "_transaction_mount_pending_audio_bank"),
		Callable(self, "_transaction_unmount_pending_audio_bank"),
		{
			"validate_callback": Callable(
				self,
				"_transaction_validate_sound_theme"
			).bind(theme),
		}
	)
	var _unmount_step_added: bool = transaction.add_step(
		&"unmount_previous_audio_bank",
		Callable(self, "_transaction_unmount_active_audio_bank"),
		Callable(self, "_transaction_restore_previous_audio_bank")
	)
	_last_sound_activation_report = transaction.commit()
	if not GFVariantData.get_option_bool(_last_sound_activation_report, "ok", false):
		_log_activation_failure("音效主题", _last_sound_activation_report)
		_clear_pending_sound_activation()
		return false

	_current_sound_theme = theme
	_active_audio_bank_id = _pending_audio_bank_id
	_active_audio_mount_token = _pending_audio_mount_token
	_clear_pending_sound_activation()
	return true


func _transaction_validate_visual_theme(
	_context: Dictionary,
	theme: GameTheme
) -> Dictionary:
	if not is_instance_valid(theme):
		return {"ok": false, "kind": &"invalid_visual_theme"}
	return theme.get_validation_report().to_dict()


func _transaction_apply_visual_theme(_context: Dictionary, theme: GameTheme) -> bool:
	if not is_instance_valid(theme):
		return true
	if (
		not is_instance_valid(_style)
		or not is_instance_valid(_board_feedback)
		or not is_instance_valid(_celebration_vfx)
	):
		return false
	_style.apply_palette(theme.ui_palette)
	if not _board_feedback.apply_profile(theme.board_feedback_profile):
		return false
	return _celebration_vfx.apply_theme(theme.celebration_vfx_theme)


func _transaction_validate_sound_theme(
	_context: Dictionary,
	theme: GameAudioTheme
) -> Dictionary:
	if not is_instance_valid(theme):
		return {"ok": false, "kind": &"invalid_sound_theme"}
	return theme.get_validation_report().to_dict()


func _transaction_mount_pending_audio_bank(_context: Dictionary) -> bool:
	if not is_instance_valid(_audio) or not is_instance_valid(_pending_sound_theme):
		return false
	_pending_audio_mount_token = _audio.mount_audio_bank(
		_pending_audio_bank_id,
		_pending_sound_theme.audio_bank,
		true
	)
	return _pending_audio_mount_token > 0


func _transaction_unmount_pending_audio_bank(_context: Dictionary) -> bool:
	if _pending_audio_mount_token <= 0:
		return true
	var unmounted: bool = _audio.unmount_audio_bank(
		_pending_audio_bank_id,
		_pending_audio_mount_token
	)
	if unmounted:
		_pending_audio_mount_token = 0
	return unmounted


func _transaction_unmount_active_audio_bank(_context: Dictionary) -> bool:
	if _active_audio_mount_token <= 0 or _active_audio_bank_id == &"":
		return true
	return _audio.unmount_audio_bank(_active_audio_bank_id, _active_audio_mount_token)


func _transaction_restore_previous_audio_bank(_context: Dictionary) -> bool:
	if not is_instance_valid(_previous_sound_theme):
		return true
	_active_audio_bank_id = _previous_sound_theme.get_resolved_bank_id()
	_active_audio_mount_token = _audio.mount_audio_bank(
		_active_audio_bank_id,
		_previous_sound_theme.audio_bank,
		true
	)
	return _active_audio_mount_token > 0


# --- 私有/辅助方法 ---

func _resolve_visual_descriptor_or_default(theme_id: StringName) -> GameThemeDescriptor:
	if not is_instance_valid(_theme_catalog):
		return null
	var descriptor: GameThemeDescriptor = _theme_catalog.get_visual_theme_descriptor(theme_id)
	if descriptor != null:
		return descriptor
	return _theme_catalog.get_visual_theme_descriptor(_get_default_visual_theme_id())


func _resolve_sound_descriptor_or_default(theme_id: StringName) -> GameThemeDescriptor:
	if not is_instance_valid(_theme_catalog):
		return null
	var descriptor: GameThemeDescriptor = _theme_catalog.get_sound_theme_descriptor(theme_id)
	if descriptor != null:
		return descriptor
	return _theme_catalog.get_sound_theme_descriptor(_get_default_sound_theme_id())


func _build_theme_asset_plan(
	theme_kind: StringName,
	theme_id: StringName,
	resource_path: String,
	request_serial: int
) -> GFAssetPreloadPlan:
	if resource_path.is_empty() or theme_id == &"" or request_serial <= 0:
		return null
	var dependency_paths: PackedStringArray = GFResourceRegistryTools.collect_dependency_paths(
		resource_path,
		{
			"recursive": true,
			"include_root": true,
		}
	)
	if not dependency_paths.has(resource_path):
		var _root_appended: bool = dependency_paths.append(resource_path)
		dependency_paths.sort()
	if dependency_paths.is_empty():
		return null

	var entries: Array = []
	for dependency_path: String in dependency_paths:
		entries.append({
			"path": dependency_path,
			"metadata": {
				"theme_kind": theme_kind,
				"theme_id": theme_id,
				"root_resource": dependency_path == resource_path,
			},
		})
	var group_id: StringName = StringName(
		"game.theme.%s.%s.%d"
		% [String(theme_kind), String(theme_id), request_serial]
	)
	var lane_id: StringName = (
		_VISUAL_ASSET_LANE_ID if theme_kind == &"visual" else _SOUND_ASSET_LANE_ID
	)
	var plan: GFAssetPreloadPlan = GFAssetPreloadPlan.new()
	var _configured_plan: GFAssetPreloadPlan = plan.configure(
		group_id,
		entries,
		{
			"plan_id": StringName("%s.preload" % String(group_id)),
			"pin_cache": true,
			"lane_id": lane_id,
			"max_concurrent_loads": _ASSET_LOAD_CONCURRENCY,
			"metadata": {
				"theme_kind": theme_kind,
				"theme_id": theme_id,
				"resource_path": resource_path,
			},
		}
	)
	if not GFVariantData.get_option_bool(plan.validate(), "ok", false):
		return null
	return plan


func _wait_for_asset_session_ready(session: GFAssetLoadSession) -> bool:
	if not is_instance_valid(session):
		return false
	while session.get_state() in [
		GFAssetLoadSession.State.CREATED,
		GFAssetLoadSession.State.LOADING,
		GFAssetLoadSession.State.ROLLBACK_PENDING,
	]:
		var _state_change: Variant = await session.state_changed
	return session.get_state() == GFAssetLoadSession.State.READY


func _cancel_asset_session(session: GFAssetLoadSession, reason: StringName) -> void:
	if not is_instance_valid(session) or session.is_completed():
		return
	var _rollback_started: bool = session.rollback(reason)


func _finish_visual_asset_request(
	session: GFAssetLoadSession,
	theme_id: StringName,
	succeeded: bool
) -> void:
	if session == _pending_visual_asset_session:
		_pending_visual_asset_session = null
	visual_theme_activation_finished.emit(theme_id, succeeded)


func _finish_sound_asset_request(
	session: GFAssetLoadSession,
	theme_id: StringName,
	succeeded: bool
) -> void:
	if session == _pending_sound_asset_session:
		_pending_sound_asset_session = null
	sound_theme_activation_finished.emit(theme_id, succeeded)


func _record_asset_activation_failure(
	visual_theme: bool,
	message: String,
	resource_path: String,
	session: GFAssetLoadSession = null
) -> void:
	var report: Dictionary = {
		"ok": false,
		"summary": message,
		"resource_path": resource_path,
		"session_state": _get_session_state(session),
		"load_report": (
			session.get_load_report() if is_instance_valid(session) else {}
		),
	}
	if visual_theme:
		_last_visual_activation_report = report
		_log_activation_failure("视觉主题", report)
	else:
		_last_sound_activation_report = report
		_log_activation_failure("音效主题", report)


func _release_replaced_asset_group(
	previous_group_id: StringName,
	current_group_id: StringName
) -> void:
	if previous_group_id == &"" or previous_group_id == current_group_id:
		return
	_release_asset_group(previous_group_id)


func _release_asset_group(group_id: StringName) -> void:
	if group_id != &"" and is_instance_valid(_assets):
		_assets.unload_group(group_id, true)


func _release_active_asset_groups() -> void:
	_release_asset_group(_active_visual_asset_group_id)
	_release_asset_group(_active_sound_asset_group_id)
	_active_visual_asset_group_id = &""
	_active_sound_asset_group_id = &""


func _cancel_pending_asset_sessions(reason: StringName) -> void:
	_visual_activation_serial += 1
	_sound_activation_serial += 1
	_cancel_asset_session(_pending_visual_asset_session, reason)
	_cancel_asset_session(_pending_sound_asset_session, reason)
	_pending_visual_asset_session = null
	_pending_sound_asset_session = null


func _complete_initial_activation(succeeded: bool) -> void:
	if _initial_activation_completed:
		return
	_initial_activation_completed = true
	_initial_activation_succeeded = succeeded
	initial_themes_ready.emit(succeeded)


func _get_session_state(session: GFAssetLoadSession) -> int:
	return session.get_state() if is_instance_valid(session) else -1


func _get_default_visual_theme_id() -> StringName:
	if is_instance_valid(_theme_catalog):
		var theme_id: StringName = _theme_catalog.get_default_visual_theme_id()
		if theme_id != &"":
			return theme_id
	return DEFAULT_THEME_ID


func _get_default_sound_theme_id() -> StringName:
	if is_instance_valid(_theme_catalog):
		var theme_id: StringName = _theme_catalog.get_default_sound_theme_id()
		if theme_id != &"":
			return theme_id
	return DEFAULT_SOUND_THEME_ID


func _connect_settings() -> void:
	if not is_instance_valid(_settings) or not is_instance_valid(_signal_utility):
		return
	var _connection: GFSignalConnection = _signal_utility.connect_signal(
		_settings.setting_changed,
		_on_setting_changed,
		self
	)


func _connect_motion_audio_feedback() -> void:
	if not is_instance_valid(_motion) or not is_instance_valid(_signal_utility):
		return
	var _select_connection: GFSignalConnection = _signal_utility.connect_signal(
		_motion.interactive_control_selected,
		_on_interactive_control_selected,
		self
	)
	var _confirm_connection: GFSignalConnection = _signal_utility.connect_signal(
		_motion.interactive_control_confirmed,
		_on_interactive_control_confirmed,
		self
	)


func _get_setting_string_name(key: StringName, fallback: StringName) -> StringName:
	if not is_instance_valid(_settings):
		return fallback
	return GFVariantData.to_string_name(_settings.get_value(key, fallback), fallback)


func _set_setting_string_name(key: StringName, value: StringName) -> void:
	if is_instance_valid(_settings):
		_settings.set_value(key, value)


func _unmount_current_audio_bank() -> void:
	if not is_instance_valid(_audio):
		return
	if _active_audio_bank_id != &"" and _active_audio_mount_token > 0:
		var _unmounted: bool = _audio.unmount_audio_bank(
			_active_audio_bank_id,
			_active_audio_mount_token
		)
	_active_audio_bank_id = &""
	_active_audio_mount_token = 0


func _clear_pending_sound_activation() -> void:
	_pending_sound_theme = null
	_pending_audio_bank_id = &""
	_pending_audio_mount_token = 0
	_previous_sound_theme = null


func _clear_runtime_state() -> void:
	_current_visual_theme = null
	_current_sound_theme = null
	_active_visual_asset_group_id = &""
	_active_sound_asset_group_id = &""
	_pending_visual_asset_session = null
	_pending_sound_asset_session = null
	_visual_activation_serial = 0
	_sound_activation_serial = 0
	_initial_activation_started = false
	_initial_activation_completed = false
	_initial_activation_succeeded = false
	_active_audio_bank_id = &""
	_active_audio_mount_token = 0
	_clear_pending_sound_activation()
	_last_visual_activation_report.clear()
	_last_sound_activation_report.clear()


func _apply_backgrounds_to_tree(root: Node, theme: GameTheme) -> int:
	if not is_instance_valid(root) or not is_instance_valid(theme):
		return 0
	var applied_count: int = 0
	if root is ColorRect and root.name == "Background":
		var background_rect: ColorRect = root
		_apply_background_to_color_rect(background_rect, theme)
		applied_count += 1
	for child: Node in root.get_children():
		applied_count += _apply_backgrounds_to_tree(child, theme)
	return applied_count


func _apply_background_to_color_rect(
	rect: ColorRect,
	theme: GameTheme,
	fallback_board_theme: BoardTheme = null
) -> void:
	if not is_instance_valid(rect) or not is_instance_valid(theme):
		return
	var resolved_board_theme: BoardTheme = theme.get_board_theme_with_fallback(
		fallback_board_theme
	)
	rect.color = theme.get_background_base_color()
	if is_instance_valid(resolved_board_theme):
		rect.color = resolved_board_theme.game_background_color
	if theme.background_shader_profile == null or not is_instance_valid(_shader_parameters):
		return
	var _applied_count: int = _shader_parameters.apply_profile(
		rect,
		theme.background_shader_profile,
		{
			"duplicate_material": false,
			"require_declared_parameters": true,
			"warn_on_invalid_target": true,
			"warn_on_missing_parameters": true,
			"copy_values": true,
		}
	)


func _log_activation_failure(label: String, report: Dictionary) -> void:
	push_error(
		"[GameThemeUtility] %s激活失败：%s"
		% [label, GFVariantData.get_option_string(report, "summary", "unknown error")]
	)


func _get_settings_utility() -> GFSettingsUtility:
	var utility_value: Object = get_utility(GFSettingsUtility)
	if utility_value is GFSettingsUtility:
		var settings: GFSettingsUtility = utility_value
		return settings
	return null


func _get_shader_parameter_utility() -> GFShaderParameterUtility:
	var utility_value: Object = get_utility(GFShaderParameterUtility)
	if utility_value is GFShaderParameterUtility:
		var shader_utility: GFShaderParameterUtility = utility_value
		return shader_utility
	return null


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _get_audio_utility() -> GFAudioUtility:
	var utility_value: Object = get_utility(GFAudioUtility)
	if utility_value is GFAudioUtility:
		var audio: GFAudioUtility = utility_value
		return audio
	return null


func _get_asset_utility() -> GFAssetUtility:
	var utility_value: Object = get_utility(GFAssetUtility)
	if utility_value is GFAssetUtility:
		var asset_utility: GFAssetUtility = utility_value
		return asset_utility
	return null


func _get_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = get_utility(GameUiMotionUtility)
	if utility_value is GameUiMotionUtility:
		var motion: GameUiMotionUtility = utility_value
		return motion
	return null


func _get_style_utility() -> GameUiStyleUtility:
	var utility_value: Object = get_utility(GameUiStyleUtility)
	if utility_value is GameUiStyleUtility:
		var style: GameUiStyleUtility = utility_value
		return style
	return null


func _get_board_feedback_utility() -> GameBoardFeedbackUtility:
	var utility_value: Object = get_utility(GameBoardFeedbackUtility)
	if utility_value is GameBoardFeedbackUtility:
		return utility_value
	return null


func _get_celebration_vfx_utility() -> GameCelebrationVfxUtility:
	var utility_value: Object = get_utility(GameCelebrationVfxUtility)
	if utility_value is GameCelebrationVfxUtility:
		var celebration_vfx: GameCelebrationVfxUtility = utility_value
		return celebration_vfx
	return null


func _get_theme_catalog_utility() -> GameThemeCatalogUtility:
	var utility_value: Object = get_utility(GameThemeCatalogUtility)
	if utility_value is GameThemeCatalogUtility:
		var catalog: GameThemeCatalogUtility = utility_value
		return catalog
	return null


# --- 信号处理函数 ---

func _on_setting_changed(key: StringName, _old_value: Variant, new_value: Variant) -> void:
	if key == VISUAL_THEME_SETTING_KEY:
		var requested_visual_id: StringName = GFVariantData.to_string_name(
			new_value,
			_get_default_visual_theme_id()
		)
		var visual_activated: bool = await _activate_visual_theme_with_assets(
			requested_visual_id,
			false,
			true
		)
		if is_lifecycle_active() and not visual_activated:
			_set_setting_string_name(VISUAL_THEME_SETTING_KEY, get_current_visual_theme_id())
	elif key == SOUND_THEME_SETTING_KEY:
		var requested_sound_id: StringName = GFVariantData.to_string_name(
			new_value,
			_get_default_sound_theme_id()
		)
		var sound_activated: bool = await _activate_sound_theme_with_assets(
			requested_sound_id,
			false,
			true
		)
		if is_lifecycle_active() and not sound_activated:
			_set_setting_string_name(SOUND_THEME_SETTING_KEY, get_current_sound_theme_id())


func _on_interactive_control_selected(_control: Control) -> void:
	play_ui_select_sound()


func _on_interactive_control_confirmed(_control: Control) -> void:
	play_ui_confirm_sound()
