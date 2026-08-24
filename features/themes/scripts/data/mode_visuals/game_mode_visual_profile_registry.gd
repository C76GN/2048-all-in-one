## GameModeVisualProfileRegistry: 模式默认视觉配置的唯一包内注册表。
class_name GameModeVisualProfileRegistry
extends Resource


@export var default_profile_id: StringName = &"classic"
@export var profiles: Array[GameModeVisualProfile] = []


## 空 ID 显式解析为注册表默认项；未知非空 ID 失败关闭。
## @param profile_id: 待解析的模式视觉 profile ID；空值使用默认 ID。
func get_profile(profile_id: StringName) -> GameModeVisualProfile:
	var resolved_id: StringName = (
		profile_id
		if profile_id != &""
		else default_profile_id
	)
	for profile: GameModeVisualProfile in profiles:
		if is_instance_valid(profile) and profile.profile_id == resolved_id:
			return profile
	return null


func get_validation_report() -> GFValidationReport:
	var report: GFValidationReport = GFValidationReport.new(
		"GameModeVisualProfileRegistry",
		{
			"default_profile_id": default_profile_id,
			"resource_path": resource_path,
		}
	)
	if default_profile_id == &"":
		_add_error(
			report,
			&"missing_default_profile_id",
			"default_profile_id 不能为空。",
			&"default_profile_id"
		)
	if profiles.is_empty():
		_add_error(report, &"empty_profiles", "profiles 不能为空。", &"profiles")

	var seen_profile_ids: Dictionary = {}
	for profile_index: int in range(profiles.size()):
		var profile: GameModeVisualProfile = profiles[profile_index]
		if not is_instance_valid(profile):
			_add_error(
				report,
				&"missing_profile",
				"profiles[%d] 未配置。" % profile_index,
				"profiles/%d" % profile_index
			)
			continue
		var _merged_report: RefCounted = report.merge(
			profile.get_validation_report(),
			false
		)
		if profile.profile_id == &"":
			continue
		if seen_profile_ids.has(profile.profile_id):
			_add_error(
				report,
				&"duplicate_profile_id",
				"模式视觉 profile id 重复：%s。" % String(profile.profile_id),
				profile.profile_id
			)
		else:
			seen_profile_ids[profile.profile_id] = true

	if default_profile_id != &"" and not seen_profile_ids.has(default_profile_id):
		_add_error(
			report,
			&"unknown_default_profile_id",
			"default_profile_id 未指向已声明 profile。",
			default_profile_id
		)
	return report


# --- 私有/辅助方法 ---

func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key, resource_path)
