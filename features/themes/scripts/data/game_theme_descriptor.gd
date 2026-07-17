## GameThemeDescriptor: 内容包主题条目的轻量只读描述。
##
## 设置菜单和图鉴可以枚举描述符而不加载完整主题资源；只有激活主题时才通过资源键解析。
class_name GameThemeDescriptor
extends RefCounted


# --- 常量 ---

const KIND_VISUAL: StringName = &"visual"
const KIND_SOUND: StringName = &"sound"


# --- 公共变量 ---

var theme_id: StringName = &""
var theme_kind: StringName = &""
var resource_key: StringName = &""
var package_id: StringName = &""
var display_name_key: String = ""
var description_key: String = ""
var is_default: bool = false
var priority: int = 0


# --- 公共方法 ---

## 配置内容包主题描述符。
## @param p_theme_id: 主题稳定 ID。
## @param p_theme_kind: 视觉或声音主题类别。
## @param p_resource_key: 完整主题资源的稳定资源键。
## @param p_package_id: 声明该主题的内容包 ID。
## @param p_display_name_key: 本地化显示名称键。
## @param p_description_key: 本地化描述键。
## @param p_is_default: 是否为该类别默认主题。
## @param p_priority: 主题枚举顺序优先级。
func configure(
	p_theme_id: StringName,
	p_theme_kind: StringName,
	p_resource_key: StringName,
	p_package_id: StringName,
	p_display_name_key: String,
	p_description_key: String,
	p_is_default: bool,
	p_priority: int
) -> GameThemeDescriptor:
	theme_id = p_theme_id
	theme_kind = p_theme_kind
	resource_key = p_resource_key
	package_id = p_package_id
	display_name_key = p_display_name_key
	description_key = p_description_key
	is_default = p_is_default
	priority = p_priority
	return self


func duplicate_descriptor() -> GameThemeDescriptor:
	return GameThemeDescriptor.new().configure(
		theme_id,
		theme_kind,
		resource_key,
		package_id,
		display_name_key,
		description_key,
		is_default,
		priority
	)


func get_display_text() -> String:
	if not display_name_key.is_empty():
		return tr(display_name_key)
	if theme_id != &"":
		return String(theme_id)
	return tr("UI_UNKNOWN")


func to_debug_dictionary() -> Dictionary:
	return {
		"theme_id": theme_id,
		"theme_kind": theme_kind,
		"resource_key": resource_key,
		"package_id": package_id,
		"display_name_key": display_name_key,
		"description_key": description_key,
		"is_default": is_default,
		"priority": priority,
	}
