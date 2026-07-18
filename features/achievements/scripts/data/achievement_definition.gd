## AchievementDefinition: 数据驱动的成就定义。
##
## 定义只描述稳定身份、展示信息和一个单调高水位指标。运行时进度由
## AchievementSystem 投影到 GFQuestUtility，不在资源中保存玩家状态。
class_name AchievementDefinition
extends Resource


# --- 常量 ---

const _FINGERPRINT_LENGTH: int = 24


# --- 导出变量 ---

## 项目内稳定且唯一的成就 ID。
@export var achievement_id: StringName = &""

## 本地化标题键。
@export var title_key: StringName = &""

## 本地化说明键。
@export var description_key: StringName = &""

## UI 分组标识。
@export var category_id: StringName = &"general"

## 由 AchievementSystem 计算的单调高水位指标 ID。
@export var metric_id: StringName = &""

## 完成成就所需的指标值。
@export_range(1, 2147483647, 1) var target_value: int = 1

## 目录内稳定排序值。
@export var sort_order: int = 0

## 未完成前是否隐藏标题和说明。
@export var hidden_until_unlocked: bool = false

## 奖励或图标素材槽位；为空时由当前主题使用默认呈现。
@export var icon_asset_slot: StringName = &""

## 平台 ID 到外部成就 ID 的映射，例如 `steam -> ACH_FIRST_GAME`。
@export var platform_ids: Dictionary = {}


# --- 公共方法 ---

## 返回定义校验报告。
func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"AchievementDefinition",
		{"achievement_id": String(achievement_id)}
	)
	if achievement_id == &"":
		var _id_issue: RefCounted = report.add_error(
			&"missing_achievement_id",
			"achievement_id 不能为空。"
		)
	if title_key == &"" or description_key == &"":
		var _text_issue: RefCounted = report.add_error(
			&"missing_localization_key",
			"成就标题和说明本地化键不能为空。",
			achievement_id
		)
	if category_id == &"" or metric_id == &"" or target_value <= 0:
		var _criteria_issue: RefCounted = report.add_error(
			&"invalid_achievement_criteria",
			"成就分类、指标和目标值必须有效。",
			achievement_id
		)
	for platform_value: Variant in platform_ids.keys():
		var platform_id: String = GFVariantData.to_text(platform_value).strip_edges()
		var external_id: String = GFVariantData.to_text(platform_ids[platform_value]).strip_edges()
		if platform_id.is_empty() or external_id.is_empty():
			var _platform_issue: RefCounted = report.add_error(
				&"invalid_platform_achievement_id",
				"平台成就映射不得包含空键或空值。",
				achievement_id
			)
	return report


## 返回只受达成条件影响的稳定指纹。
func get_criteria_fingerprint() -> String:
	if achievement_id == &"" or metric_id == &"" or target_value <= 0:
		return ""
	var identity: String = "%s\n%s\n%d" % [
		String(achievement_id),
		String(metric_id),
		target_value,
	]
	return identity.sha256_text().substr(0, _FINGERPRINT_LENGTH)


## 返回 UI 与平台同步可消费的只读描述。
func to_descriptor() -> Dictionary:
	return {
		&"achievement_id": achievement_id,
		&"title_key": title_key,
		&"description_key": description_key,
		&"category_id": category_id,
		&"metric_id": metric_id,
		&"target_value": target_value,
		&"sort_order": sort_order,
		&"hidden_until_unlocked": hidden_until_unlocked,
		&"icon_asset_slot": icon_asset_slot,
		&"platform_ids": platform_ids.duplicate(true),
		&"criteria_fingerprint": get_criteria_fingerprint(),
		&"definition": self,
	}


## 获取指定平台的成就标识；未配置时返回空标识。
## @param platform_id: 平台 Adapter 使用的稳定平台标识。
func get_platform_achievement_id(platform_id: StringName) -> StringName:
	return GFVariantData.get_option_string_name(platform_ids, String(platform_id))
