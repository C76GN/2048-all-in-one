## TileVisualFamilyStyle: 单个方块视觉家族在某套主题中的稳定表现配置。
##
## 数值色阶仍由 TileColorScheme 管理；这里仅声明不随数值变化的身份特征，
## 包括轮廓、稀疏符号、比例、轻微错版和家族描边。
class_name TileVisualFamilyStyle
extends Resource


# --- 导出变量 ---

@export var family_id: StringName = &""
@export var silhouette_id: StringName = &""
@export var motif_id: StringName = &""
@export var shape_scale: Vector2 = Vector2(0.94, 0.94)
@export_range(-4.0, 4.0, 0.1) var shape_rotation_degrees: float = 0.0
@export_range(1.0, 10.0, 0.5) var border_width: float = 4.0
@export var border_color: Color = Color(0.18431373, 0.1882353, 0.21568628, 1.0)
@export var accent_color: Color = Color(0.61960787, 0.85882354, 0.8352941, 1.0)
@export_range(0.0, 0.5, 0.01) var motif_opacity: float = 0.14
@export var registration_offset: Vector2 = Vector2(2.0, 2.0)


# --- 公共方法 ---

func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"TileVisualFamilyStyle:%s" % String(family_id),
		{
			"family_id": family_id,
			"resource_path": resource_path,
		}
	)
	if family_id == &"":
		_add_error(report, &"missing_family_id", "family_id 不能为空。", &"family_id")
	if silhouette_id == &"":
		_add_error(report, &"missing_silhouette_id", "silhouette_id 不能为空。", &"silhouette_id")
	if motif_id == &"":
		_add_error(report, &"missing_motif_id", "motif_id 不能为空。", &"motif_id")
	if shape_scale.x <= 0.0 or shape_scale.y <= 0.0 or shape_scale.x > 1.0 or shape_scale.y > 1.0:
		_add_error(
			report,
			&"invalid_shape_scale",
			"shape_scale 必须位于 (0, 1]，避免方块越出稳定单元格。",
			&"shape_scale"
		)
	if border_width <= 0.0:
		_add_error(report, &"invalid_border_width", "border_width 必须大于 0。", &"border_width")
	return report


# --- 私有/辅助方法 ---

func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: StringName
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
