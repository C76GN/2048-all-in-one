## GameThemeRegistry: 维护项目可用的视觉主题和音效主题列表。
class_name GameThemeRegistry
extends Resource


# --- 导出变量 ---

@export var default_theme_id: StringName = &"halftone_atlas"
@export var default_sound_theme_id: StringName = &"printworks"
@export var themes: Array[GameTheme] = []
@export var sound_themes: Array[GameAudioTheme] = []


# --- 公共方法 ---

## 根据稳定 ID 查找视觉主题。
## @param theme_id: 视觉主题稳定 ID。
func get_theme(theme_id: StringName) -> GameTheme:
	for theme: GameTheme in themes:
		if is_instance_valid(theme) and theme.theme_id == theme_id:
			return theme
	return null


func get_default_theme() -> GameTheme:
	var default_theme: GameTheme = get_theme(default_theme_id)
	if is_instance_valid(default_theme):
		return default_theme
	for theme: GameTheme in themes:
		if is_instance_valid(theme):
			return theme
	return null


## 根据稳定 ID 查找音效主题。
## @param theme_id: 音效主题稳定 ID。
func get_sound_theme(theme_id: StringName) -> GameAudioTheme:
	for theme: GameAudioTheme in sound_themes:
		if is_instance_valid(theme) and theme.theme_id == theme_id:
			return theme
	return null


func get_default_sound_theme() -> GameAudioTheme:
	var default_theme: GameAudioTheme = get_sound_theme(default_sound_theme_id)
	if is_instance_valid(default_theme):
		return default_theme
	for theme: GameAudioTheme in sound_themes:
		if is_instance_valid(theme):
			return theme
	return null


func get_theme_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for theme: GameTheme in themes:
		if is_instance_valid(theme) and theme.theme_id != &"":
			ids.append(theme.theme_id)
	return ids


func get_sound_theme_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for theme: GameAudioTheme in sound_themes:
		if is_instance_valid(theme) and theme.theme_id != &"":
			ids.append(theme.theme_id)
	return ids
