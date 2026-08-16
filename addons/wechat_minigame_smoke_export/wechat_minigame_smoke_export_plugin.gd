@tool
extends EditorExportPlugin


# --- 常量 ---

const _SMOKE_FEATURE: String = "wechat_minigame_smoke"
const _CUSTOMIZATION_VERSION: int = 2
const _SMOKE_FONT_PATH: String = "res://shared/assets/fonts/wechat_smoke_sans_subset.ttf"
const _FONT_VARIATION_PATHS: PackedStringArray = [
	"res://shared/assets/fonts/ui_sans_regular.tres",
	"res://shared/assets/fonts/ui_sans_display.tres",
]


# --- Godot 生命周期方法 ---

func _get_name() -> String:
	return "WeChatMiniGameSmokeExportPlugin"


func _begin_customize_resources(
	_platform: EditorExportPlatform,
	features: PackedStringArray
) -> bool:
	return features.has(_SMOKE_FEATURE)


func _customize_resource(resource: Resource, path: String) -> Resource:
	if not _FONT_VARIATION_PATHS.has(path):
		return null
	var smoke_font: Resource = load(_SMOKE_FONT_PATH)
	if not smoke_font is FontFile:
		push_error(
			"[WeChatMiniGameSmokeExportPlugin] 冒烟字体无法加载：%s。" % _SMOKE_FONT_PATH
		)
		return resource
	var customized_resource: Resource = resource.duplicate(true)
	if customized_resource is FontVariation:
		var customized_font: FontVariation = customized_resource
		customized_font.base_font = smoke_font
		return customized_font
	push_error("[WeChatMiniGameSmokeExportPlugin] 目标不是 FontVariation：%s。" % path)
	return resource


func _get_customization_configuration_hash() -> int:
	return ("%d:%s" % [
		_CUSTOMIZATION_VERSION,
		FileAccess.get_sha256(_SMOKE_FONT_PATH),
	]).hash()
