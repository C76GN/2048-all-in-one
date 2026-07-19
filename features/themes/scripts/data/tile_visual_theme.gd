## TileVisualTheme: 一套完整主题中的方块家族视觉目录。
class_name TileVisualTheme
extends Resource


# --- 导出变量 ---

@export var theme_id: StringName = &""
@export var family_styles: Array[TileVisualFamilyStyle] = []


# --- 公共方法 ---

## 按稳定家族 ID 解析视觉配置。
## @param family_id: `TileDefinition` 提供的稳定视觉家族 ID。
func get_family_style(family_id: StringName) -> TileVisualFamilyStyle:
	for style: TileVisualFamilyStyle in family_styles:
		if style != null and style.family_id == family_id:
			return style
	return null


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"TileVisualTheme:%s" % String(theme_id),
		{
			"theme_id": theme_id,
			"resource_path": resource_path,
		}
	)
	if theme_id == &"":
		_add_error(report, &"missing_theme_id", "theme_id 不能为空。", &"theme_id")
	if family_styles.is_empty():
		_add_error(report, &"empty_family_styles", "family_styles 不能为空。", &"family_styles")
		return report

	var seen_family_ids: Dictionary = {}
	for style: TileVisualFamilyStyle in family_styles:
		if style == null:
			_add_error(report, &"null_family_style", "family_styles 包含空资源。", &"family_styles")
			continue
		var _style_report: RefCounted = report.merge(style.get_validation_report(), false)
		if seen_family_ids.has(style.family_id):
			_add_error(
				report,
				&"duplicate_family_id",
				"方块视觉家族重复：%s。" % style.family_id,
				style.family_id
			)
		seen_family_ids[style.family_id] = true
	return report


# --- 私有/辅助方法 ---

func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: StringName
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
