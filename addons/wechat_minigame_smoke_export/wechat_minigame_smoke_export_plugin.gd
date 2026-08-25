@tool
extends EditorExportPlugin

## 微信小游戏 profile 专用字体导出定制器。
## 历史目录名保留为项目配置兼容路径；实现同时服务 smoke 与 release profile。


# --- 常量 ---

const _SMOKE_FEATURE: String = "wechat_minigame_smoke"
const _RELEASE_FEATURE: String = "wechat_minigame_release"
const _CUSTOMIZATION_VERSION: int = 3
const _PROFILE_FONT_PATHS: Dictionary = {
	_SMOKE_FEATURE: "res://shared/assets/fonts/wechat_smoke_sans_subset.ttf",
	_RELEASE_FEATURE: "res://shared/assets/fonts/wechat_release_sans_subset.ttf",
}
const _FONT_VARIATION_PATHS: PackedStringArray = [
	"res://shared/assets/fonts/ui_sans_regular.tres",
	"res://shared/assets/fonts/ui_sans_display.tres",
]


# --- 私有变量 ---

var _active_font_path: String = ""


# --- Godot 生命周期方法 ---

func _get_name() -> String:
	return "WeChatMiniGameProfileFontExportPlugin"


func _begin_customize_resources(
	_platform: EditorExportPlatform,
	features: PackedStringArray
) -> bool:
	_active_font_path = ""
	for feature_value: Variant in _PROFILE_FONT_PATHS.keys():
		var feature: String = str(feature_value)
		if not features.has(feature):
			continue
		if not _active_font_path.is_empty():
			push_error(
				"[WeChatMiniGameProfileFontExportPlugin] 微信导出字体 feature 冲突。"
			)
			_active_font_path = ""
			return false
		_active_font_path = str(_PROFILE_FONT_PATHS[feature])
	return not _active_font_path.is_empty()


func _customize_resource(resource: Resource, path: String) -> Resource:
	if not _FONT_VARIATION_PATHS.has(path):
		return null
	var profile_font: Resource = load(_active_font_path)
	if not profile_font is FontFile:
		push_error(
			"[WeChatMiniGameProfileFontExportPlugin] 导出字体无法加载：%s。" % _active_font_path
		)
		return resource
	var customized_resource: Resource = resource.duplicate(true)
	if customized_resource is FontVariation:
		var customized_font: FontVariation = customized_resource
		customized_font.base_font = profile_font
		return customized_font
	push_error(
		"[WeChatMiniGameProfileFontExportPlugin] 目标不是 FontVariation：%s。" % path
	)
	return resource


func _get_customization_configuration_hash() -> int:
	var identity: PackedStringArray = PackedStringArray([
		str(_CUSTOMIZATION_VERSION),
		_active_font_path,
	])
	var features: Array = _PROFILE_FONT_PATHS.keys()
	features.sort()
	for feature_value: Variant in features:
		var feature: String = str(feature_value)
		var font_path: String = str(_PROFILE_FONT_PATHS[feature])
		var _identity_added: bool = identity.append(
			"%s:%s" % [feature, FileAccess.get_sha256(font_path)]
		)
	return ":".join(identity).hash()
