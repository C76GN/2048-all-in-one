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


## 生成主题注册表及全部主题资源的聚合校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameThemeRegistry",
		{
			"resource_path": resource_path,
			"visual_theme_count": themes.size(),
			"sound_theme_count": sound_themes.size(),
		}
	)
	_validate_visual_themes(report)
	_validate_sound_themes(report)
	if default_theme_id == &"" or not is_instance_valid(get_theme(default_theme_id)):
		_add_error(
			report,
			&"missing_default_visual_theme",
			"default_theme_id 未指向有效视觉主题：%s。" % String(default_theme_id),
			&"default_theme_id"
		)
	if default_sound_theme_id == &"" or not is_instance_valid(get_sound_theme(default_sound_theme_id)):
		_add_error(
			report,
			&"missing_default_sound_theme",
			"default_sound_theme_id 未指向有效音效主题：%s。" % String(default_sound_theme_id),
			&"default_sound_theme_id"
		)
	return report


# --- 私有/辅助方法 ---

func _validate_visual_themes(report: GFValidationReport) -> void:
	if themes.is_empty():
		_add_error(report, &"empty_visual_themes", "themes 为空。", &"themes")
		return
	var seen_ids: Dictionary = {}
	for index: int in range(themes.size()):
		var theme: GameTheme = themes[index]
		if not is_instance_valid(theme):
			_add_error(report, &"invalid_visual_theme", "themes[%d] 无效。" % index, "themes/%d" % index)
			continue
		if theme.theme_id != &"" and seen_ids.has(theme.theme_id):
			_add_error(
				report,
				&"duplicate_visual_theme_id",
				"视觉主题 ID 重复：%s。" % String(theme.theme_id),
				theme.theme_id
			)
		else:
			seen_ids[theme.theme_id] = index
		var _theme_report: RefCounted = report.merge(theme.get_validation_report(), false)


func _validate_sound_themes(report: GFValidationReport) -> void:
	if sound_themes.is_empty():
		_add_error(report, &"empty_sound_themes", "sound_themes 为空。", &"sound_themes")
		return
	var seen_ids: Dictionary = {}
	for index: int in range(sound_themes.size()):
		var theme: GameAudioTheme = sound_themes[index]
		if not is_instance_valid(theme):
			_add_error(report, &"invalid_sound_theme", "sound_themes[%d] 无效。" % index, "sound_themes/%d" % index)
			continue
		if theme.theme_id != &"" and seen_ids.has(theme.theme_id):
			_add_error(
				report,
				&"duplicate_sound_theme_id",
				"音效主题 ID 重复：%s。" % String(theme.theme_id),
				theme.theme_id
			)
		else:
			seen_ids[theme.theme_id] = index
		var _theme_report: RefCounted = report.merge(theme.get_validation_report(), false)


func _add_error(report: GFValidationReport, kind: StringName, message: String, key: Variant) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
