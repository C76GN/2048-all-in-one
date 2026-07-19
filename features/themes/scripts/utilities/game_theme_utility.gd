## GameThemeUtility: 项目级主题激活服务。
##
## 主题列表来自内容包描述符；完整资源仅在激活时加载。视觉与声音切换通过
## GFActivationTransaction 校验和回滚，声音银行使用 GF 挂载令牌管理生命周期。
class_name GameThemeUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal visual_theme_changed(theme: GameTheme)
signal sound_theme_changed(theme: GameAudioTheme)


# --- 常量 ---

const VISUAL_THEME_SETTING_KEY: StringName = &"appearance/theme_id"
const SOUND_THEME_SETTING_KEY: StringName = &"audio/sound_theme_id"
const DEFAULT_THEME_ID: StringName = &"halftone_atlas"
const DEFAULT_SOUND_THEME_ID: StringName = &"printworks"


# --- 私有变量 ---

var _settings: GFSettingsUtility = null
var _audio: GFAudioUtility = null
var _style: GameUiStyleUtility = null
var _motion: GameUiMotionUtility = null
var _celebration_vfx: GameCelebrationVfxUtility = null
var _theme_catalog: GameThemeCatalogUtility = null
var _shader_parameters: GFShaderParameterUtility = null
var _signal_utility: GFSignalUtility = null
var _current_visual_theme: GameTheme = null
var _current_sound_theme: GameAudioTheme = null
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
		GameCelebrationVfxUtility,
		GameThemeCatalogUtility,
		GameUiStyleUtility,
		GameUiMotionUtility,
		GFAudioUtility,
		GFSettingsUtility,
		GFShaderParameterUtility,
		GFSignalUtility,
	]


func ready() -> void:
	_settings = _get_settings_utility()
	_audio = _get_audio_utility()
	_style = _get_style_utility()
	_motion = _get_motion_utility()
	_celebration_vfx = _get_celebration_vfx_utility()
	_theme_catalog = _get_theme_catalog_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_signal_utility = _get_signal_utility()
	_connect_settings()
	_connect_motion_audio_feedback()
	var _visual_activated: bool = _activate_visual_theme(
		_get_setting_string_name(VISUAL_THEME_SETTING_KEY, _get_default_visual_theme_id()),
		false,
		false
	)
	var _sound_activated: bool = _activate_sound_theme(
		_get_setting_string_name(SOUND_THEME_SETTING_KEY, _get_default_sound_theme_id()),
		false,
		false
	)


func dispose() -> void:
	_unmount_current_audio_bank()
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_settings = null
	_audio = null
	_style = null
	_motion = null
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
	_style = null
	_motion = null
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
	return _activate_visual_theme(theme_id, true, true)


## 切换当前声音主题；失败时恢复原银行并保持设置不变。
## @param theme_id: 待激活的声音主题 ID。
func set_current_sound_theme_id(theme_id: StringName) -> bool:
	return _activate_sound_theme(theme_id, true, true)


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

func _activate_visual_theme(
	theme_id: StringName,
	persist_setting: bool,
	emit_change: bool
) -> bool:
	var theme: GameTheme = _resolve_visual_theme_or_default(theme_id)
	if not is_instance_valid(theme):
		return false
	if is_instance_valid(_current_visual_theme):
		if _current_visual_theme.theme_id == theme.theme_id:
			if persist_setting:
				_set_setting_string_name(VISUAL_THEME_SETTING_KEY, theme.theme_id)
			return true

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
	if persist_setting:
		_set_setting_string_name(VISUAL_THEME_SETTING_KEY, theme.theme_id)
	if emit_change:
		visual_theme_changed.emit(theme)
	return true


func _activate_sound_theme(
	theme_id: StringName,
	persist_setting: bool,
	emit_change: bool
) -> bool:
	var theme: GameAudioTheme = _resolve_sound_theme_or_default(theme_id)
	if not is_instance_valid(theme):
		return false
	if is_instance_valid(_current_sound_theme):
		if _current_sound_theme.theme_id == theme.theme_id and _active_audio_mount_token > 0:
			if persist_setting:
				_set_setting_string_name(SOUND_THEME_SETTING_KEY, theme.theme_id)
			return true

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
	if persist_setting:
		_set_setting_string_name(SOUND_THEME_SETTING_KEY, theme.theme_id)
	if emit_change:
		sound_theme_changed.emit(theme)
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
	if not is_instance_valid(_style) or not is_instance_valid(_celebration_vfx):
		return false
	_style.apply_palette(theme.ui_palette)
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

func _resolve_visual_theme_or_default(theme_id: StringName) -> GameTheme:
	if not is_instance_valid(_theme_catalog):
		return null
	var theme: GameTheme = _theme_catalog.load_visual_theme(theme_id)
	if is_instance_valid(theme):
		return theme
	return _theme_catalog.load_visual_theme(_get_default_visual_theme_id())


func _resolve_sound_theme_or_default(theme_id: StringName) -> GameAudioTheme:
	if not is_instance_valid(_theme_catalog):
		return null
	var theme: GameAudioTheme = _theme_catalog.load_sound_theme(theme_id)
	if is_instance_valid(theme):
		return theme
	return _theme_catalog.load_sound_theme(_get_default_sound_theme_id())


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
		if not _activate_visual_theme(requested_visual_id, false, true):
			_set_setting_string_name(VISUAL_THEME_SETTING_KEY, get_current_visual_theme_id())
	elif key == SOUND_THEME_SETTING_KEY:
		var requested_sound_id: StringName = GFVariantData.to_string_name(
			new_value,
			_get_default_sound_theme_id()
		)
		if not _activate_sound_theme(requested_sound_id, false, true):
			_set_setting_string_name(SOUND_THEME_SETTING_KEY, get_current_sound_theme_id())


func _on_interactive_control_selected(_control: Control) -> void:
	play_ui_select_sound()


func _on_interactive_control_confirmed(_control: Control) -> void:
	play_ui_confirm_sound()
