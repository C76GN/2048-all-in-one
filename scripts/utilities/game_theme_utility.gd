## GameThemeUtility: 项目级主题服务，解析当前视觉主题与音效主题。
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
const THEME_REGISTRY_RESOURCE_KEY: StringName = &"game.theme_registry"
const CONTENT_PACKAGE_SOURCE_ROOT: String = "res://resources"
const DEFAULT_THEME_REGISTRY_PATH: String = "res://resources/registries/game_theme_registry.tres"


# --- 私有变量 ---

var _registry: GameThemeRegistry
var _settings: GFSettingsUtility
var _audio: GFAudioUtility
var _motion: GameUiMotionUtility
var _theme_catalog: GameThemeCatalogUtility
var _shader_parameters: GFShaderParameterUtility


# --- GF 生命周期方法 ---

func init() -> void:
	_registry = null


func ready() -> void:
	_settings = _get_settings_utility()
	_audio = _get_audio_utility()
	_motion = _get_motion_utility()
	_theme_catalog = _get_theme_catalog_utility()
	_shader_parameters = _get_shader_parameter_utility()
	_registry = _load_registry()
	_connect_settings()
	_apply_visual_theme_to_utilities(get_current_visual_theme())
	_apply_sound_theme_to_utilities(get_current_sound_theme())
	_connect_motion_audio_feedback()


func dispose() -> void:
	_disconnect_motion_audio_feedback()
	if is_instance_valid(_settings):
		var callback: Callable = _on_setting_changed
		if _settings.setting_changed.is_connected(callback):
			_settings.setting_changed.disconnect(callback)
	_settings = null
	_audio = null
	_motion = null
	_theme_catalog = null
	_shader_parameters = null
	_registry = null


func release_dependencies() -> void:
	_disconnect_motion_audio_feedback()
	_settings = null
	_audio = null
	_motion = null
	_theme_catalog = null
	_shader_parameters = null
	super.release_dependencies()


# --- 公共方法 ---

func get_registry() -> GameThemeRegistry:
	_ensure_registry_loaded()
	return _registry


func get_available_visual_themes() -> Array[GameTheme]:
	var registry: GameThemeRegistry = get_registry()
	if not is_instance_valid(registry):
		return []
	return registry.themes.duplicate()


func get_available_sound_themes() -> Array[GameAudioTheme]:
	var registry: GameThemeRegistry = get_registry()
	if not is_instance_valid(registry):
		return []
	return registry.sound_themes.duplicate()


func get_current_visual_theme() -> GameTheme:
	var theme_id: StringName = _get_setting_string_name(VISUAL_THEME_SETTING_KEY, DEFAULT_THEME_ID)
	var theme: GameTheme = _get_theme_or_default(theme_id)
	return theme


func get_current_sound_theme() -> GameAudioTheme:
	var theme_id: StringName = _get_setting_string_name(SOUND_THEME_SETTING_KEY, DEFAULT_SOUND_THEME_ID)
	var theme: GameAudioTheme = _get_sound_theme_or_default(theme_id)
	return theme


func get_current_visual_theme_id() -> StringName:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		return theme.theme_id
	return DEFAULT_THEME_ID


func get_current_sound_theme_id() -> StringName:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		return theme.theme_id
	return DEFAULT_SOUND_THEME_ID


## 获取视觉主题显示文本。
## @param theme_id: 视觉主题稳定 ID。
func get_visual_theme_display_text(theme_id: StringName) -> String:
	var theme: GameTheme = _get_theme_or_default(theme_id)
	if is_instance_valid(theme):
		return theme.get_display_text()
	if theme_id != &"":
		return String(theme_id)
	return String(DEFAULT_THEME_ID)


## 获取音效主题显示文本。
## @param theme_id: 音效主题稳定 ID。
func get_sound_theme_display_text(theme_id: StringName) -> String:
	var theme: GameAudioTheme = _get_sound_theme_or_default(theme_id)
	if is_instance_valid(theme):
		return theme.get_display_text()
	if theme_id != &"":
		return String(theme_id)
	return String(DEFAULT_SOUND_THEME_ID)


## 切换当前视觉主题。
## @param theme_id: 视觉主题稳定 ID；无效时回退到默认视觉主题。
func set_current_visual_theme_id(theme_id: StringName) -> void:
	var resolved_theme: GameTheme = _get_theme_or_default(theme_id)
	if not is_instance_valid(resolved_theme):
		return
	_set_setting_string_name(VISUAL_THEME_SETTING_KEY, resolved_theme.theme_id)


## 切换当前音效主题。
## @param theme_id: 音效主题稳定 ID；无效时回退到默认音效主题。
func set_current_sound_theme_id(theme_id: StringName) -> void:
	var resolved_theme: GameAudioTheme = _get_sound_theme_or_default(theme_id)
	if not is_instance_valid(resolved_theme):
		return
	_set_setting_string_name(SOUND_THEME_SETTING_KEY, resolved_theme.theme_id)


## 解析当前视觉主题下的棋盘主题。
## @param fallback: 模式配置提供的默认棋盘主题。
func resolve_board_theme(fallback: BoardTheme) -> BoardTheme:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		return theme.get_board_theme_with_fallback(fallback)
	return fallback


## 解析当前视觉主题下的方块色阶。
## @param fallback: 模式配置提供的默认方块色阶字典。
func resolve_color_schemes(fallback: Dictionary) -> Dictionary:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		return theme.get_color_schemes_with_fallback(fallback)
	return fallback


## 将当前视觉主题背景应用到 ColorRect。
## @param rect: 要应用背景的 ColorRect。
## @param fallback_board_theme: 主题未配置棋盘资源时使用的默认棋盘主题。
func apply_background_to_color_rect(rect: ColorRect, fallback_board_theme: BoardTheme = null) -> void:
	var theme: GameTheme = get_current_visual_theme()
	if is_instance_valid(theme):
		_apply_background_to_color_rect(rect, theme, fallback_board_theme)
		return

	if is_instance_valid(rect) and is_instance_valid(fallback_board_theme):
		rect.color = fallback_board_theme.game_background_color


## 将当前主题应用到一个场景树分支。
## @param root: 要刷新的节点根。
func apply_current_theme_to_tree(root: Node) -> int:
	var theme: GameTheme = get_current_visual_theme()
	if not is_instance_valid(theme):
		return 0

	var applied_count: int = 0
	if not is_instance_valid(_motion):
		_motion = _get_motion_utility()
	if is_instance_valid(_motion) and is_instance_valid(theme.ui_palette):
		applied_count += _motion.apply_palette_to_tree(root, theme.ui_palette)

	applied_count += _apply_backgrounds_to_tree(root, theme)
	return applied_count


## 按当前音效主题播放一个稳定事件 ID。
## @param event_id: GameAudioTheme 中声明、并由当前 GFAudioBank 提供的事件 ID。
func play_current_sound_event(event_id: StringName) -> void:
	if event_id == &"":
		return

	var theme: GameAudioTheme = get_current_sound_theme()
	if not is_instance_valid(theme):
		return

	_apply_sound_theme_to_utilities(theme)
	if not is_instance_valid(_audio):
		return

	_audio.play_sfx_event(event_id, theme.get_resolved_bank_id())


func play_ui_select_sound() -> void:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		play_current_sound_event(theme.ui_select_event)


func play_ui_confirm_sound() -> void:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		play_current_sound_event(theme.ui_confirm_event)


func play_tile_spawn_sound() -> void:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		play_current_sound_event(theme.tile_spawn_event)


func play_tile_move_sound() -> void:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		play_current_sound_event(theme.tile_move_event)


func play_tile_merge_sound() -> void:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		play_current_sound_event(theme.tile_merge_event)


func play_game_over_sound() -> void:
	var theme: GameAudioTheme = get_current_sound_theme()
	if is_instance_valid(theme):
		play_current_sound_event(theme.game_over_event)


func get_debug_snapshot() -> Dictionary:
	var catalog_snapshot: Dictionary = {}
	if is_instance_valid(_theme_catalog):
		catalog_snapshot = _theme_catalog.get_debug_snapshot()

	return {
		"content_package_source_root": CONTENT_PACKAGE_SOURCE_ROOT,
		"theme_registry_key": THEME_REGISTRY_RESOURCE_KEY,
		"current_visual_theme_id": get_current_visual_theme_id(),
		"current_sound_theme_id": get_current_sound_theme_id(),
		"available_visual_theme_count": get_available_visual_themes().size(),
		"available_sound_theme_count": get_available_sound_themes().size(),
		"catalog": catalog_snapshot,
	}


# --- 私有/辅助方法 ---

func _load_registry() -> GameThemeRegistry:
	if not is_instance_valid(_theme_catalog):
		_theme_catalog = _get_theme_catalog_utility()
	if is_instance_valid(_theme_catalog):
		var registry: GameThemeRegistry = _theme_catalog.get_registry()
		if is_instance_valid(registry):
			return registry

	var resource: Resource = load(DEFAULT_THEME_REGISTRY_PATH)
	if resource is GameThemeRegistry:
		var registry: GameThemeRegistry = resource
		return registry
	push_error("[GameThemeUtility] 默认主题注册表加载失败：%s。" % DEFAULT_THEME_REGISTRY_PATH)
	return GameThemeRegistry.new()


func _ensure_registry_loaded() -> void:
	if not is_instance_valid(_registry):
		_registry = _load_registry()


func _connect_settings() -> void:
	if not is_instance_valid(_settings):
		return

	var callback: Callable = _on_setting_changed
	if not _settings.setting_changed.is_connected(callback):
		var _connect_result: int = _settings.setting_changed.connect(callback)


func _get_setting_string_name(key: StringName, fallback: StringName) -> StringName:
	if not is_instance_valid(_settings):
		return fallback
	return GFVariantData.to_string_name(_settings.get_value(key, fallback), fallback)


func _set_setting_string_name(key: StringName, value: StringName) -> void:
	if is_instance_valid(_settings):
		_settings.set_value(key, value)
		return

	if key == VISUAL_THEME_SETTING_KEY:
		var visual_theme: GameTheme = _get_theme_or_default(value)
		_apply_visual_theme_to_utilities(visual_theme)
		visual_theme_changed.emit(visual_theme)
	elif key == SOUND_THEME_SETTING_KEY:
		var sound_theme: GameAudioTheme = _get_sound_theme_or_default(value)
		_apply_sound_theme_to_utilities(sound_theme)
		sound_theme_changed.emit(sound_theme)


func _get_theme_or_default(theme_id: StringName) -> GameTheme:
	_ensure_registry_loaded()
	if not is_instance_valid(_registry):
		return null
	if theme_id != &"":
		var theme: GameTheme = _registry.get_theme(theme_id)
		if is_instance_valid(theme):
			return theme
	return _registry.get_default_theme()


func _get_sound_theme_or_default(theme_id: StringName) -> GameAudioTheme:
	_ensure_registry_loaded()
	if not is_instance_valid(_registry):
		return null
	if theme_id != &"":
		var theme: GameAudioTheme = _registry.get_sound_theme(theme_id)
		if is_instance_valid(theme):
			return theme
	return _registry.get_default_sound_theme()


func _apply_visual_theme_to_utilities(theme: GameTheme) -> void:
	if not is_instance_valid(theme):
		return
	if not is_instance_valid(_motion):
		_motion = _get_motion_utility()
	if is_instance_valid(_motion) and is_instance_valid(theme.ui_palette):
		_motion.apply_palette(theme.ui_palette)
	_connect_motion_audio_feedback()


func _apply_sound_theme_to_utilities(theme: GameAudioTheme) -> void:
	if not is_instance_valid(theme):
		return
	if not is_instance_valid(_audio):
		_audio = _get_audio_utility()
	if not is_instance_valid(_audio):
		return
	if is_instance_valid(theme.audio_bank):
		_audio.register_audio_bank(theme.get_resolved_bank_id(), theme.audio_bank)


func _connect_motion_audio_feedback() -> void:
	if not is_instance_valid(_motion):
		_motion = _get_motion_utility()
	if not is_instance_valid(_motion):
		return

	var select_callback: Callable = _on_interactive_control_selected
	if not _motion.interactive_control_selected.is_connected(select_callback):
		var _select_connect_result: int = _motion.interactive_control_selected.connect(select_callback)

	var confirm_callback: Callable = _on_interactive_control_confirmed
	if not _motion.interactive_control_confirmed.is_connected(confirm_callback):
		var _confirm_connect_result: int = _motion.interactive_control_confirmed.connect(confirm_callback)


func _disconnect_motion_audio_feedback() -> void:
	if not is_instance_valid(_motion):
		return

	var select_callback: Callable = _on_interactive_control_selected
	if _motion.interactive_control_selected.is_connected(select_callback):
		_motion.interactive_control_selected.disconnect(select_callback)

	var confirm_callback: Callable = _on_interactive_control_confirmed
	if _motion.interactive_control_confirmed.is_connected(confirm_callback):
		_motion.interactive_control_confirmed.disconnect(confirm_callback)


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

	var resolved_board_theme: BoardTheme = theme.get_board_theme_with_fallback(fallback_board_theme)
	rect.color = theme.get_background_base_color()
	if is_instance_valid(resolved_board_theme):
		rect.color = resolved_board_theme.game_background_color

	if theme.background_shader_profile == null:
		push_error("[GameThemeUtility] 主题缺少背景 GFShaderParameterProfile：%s。" % String(theme.theme_id))
		return
	if not is_instance_valid(_shader_parameters):
		_shader_parameters = _get_shader_parameter_utility()
	if not is_instance_valid(_shader_parameters):
		push_error("[GameThemeUtility] 缺少 GFShaderParameterUtility，无法应用背景主题。")
		return

	var _applied_count: int = _shader_parameters.apply_profile(rect, theme.background_shader_profile, {
		"duplicate_material": false,
		"require_declared_parameters": true,
		"warn_on_invalid_target": true,
		"warn_on_missing_parameters": true,
		"copy_values": true,
	})


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


func _get_theme_catalog_utility() -> GameThemeCatalogUtility:
	var utility_value: Object = get_utility(GameThemeCatalogUtility)
	if utility_value is GameThemeCatalogUtility:
		var catalog: GameThemeCatalogUtility = utility_value
		return catalog
	return null


# --- 信号处理函数 ---

func _on_setting_changed(key: StringName, _old_value: Variant, _new_value: Variant) -> void:
	if key == VISUAL_THEME_SETTING_KEY:
		var visual_theme: GameTheme = get_current_visual_theme()
		_apply_visual_theme_to_utilities(visual_theme)
		visual_theme_changed.emit(visual_theme)
	elif key == SOUND_THEME_SETTING_KEY:
		var sound_theme: GameAudioTheme = get_current_sound_theme()
		_apply_sound_theme_to_utilities(sound_theme)
		sound_theme_changed.emit(sound_theme)


func _on_interactive_control_selected(_control: Control) -> void:
	play_ui_select_sound()


func _on_interactive_control_confirmed(_control: Control) -> void:
	play_ui_confirm_sound()
