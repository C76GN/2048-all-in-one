## GameThemeCatalogUtility: 项目主题内容目录。
##
## 从 ProjectContentCatalogUtility 的 manifest metadata 构建轻量主题描述符，并在主题
## 真正激活时才通过稳定资源键加载完整资源。
class_name GameThemeCatalogUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 常量 ---

const RESOURCE_TYPE_HINT: String = "Resource"
const VISUAL_THEME_CATALOG_ROLE: String = "visual_theme"
const SOUND_THEME_CATALOG_ROLE: String = "sound_theme"
const _VISUAL_THEME_KEY_PREFIX: String = "game.theme."
const _SOUND_THEME_KEY_PREFIX: String = "game.audio_theme."


# --- 私有变量 ---

var _project_content_catalog: ProjectContentCatalogUtility = null
var _visual_descriptors: Dictionary = {}
var _sound_descriptors: Dictionary = {}
var _visual_theme_order: PackedStringArray = PackedStringArray()
var _sound_theme_order: PackedStringArray = PackedStringArray()
var _default_visual_theme_id: StringName = &""
var _default_sound_theme_id: StringName = &""
var _catalog_validation_report: GFValidationReport = null


# --- GF 生命周期方法 ---

func init() -> void:
	_clear_index()


func get_required_utilities() -> Array[Script]:
	return [ProjectContentCatalogUtility]


func ready() -> void:
	_project_content_catalog = _get_project_content_catalog_utility()
	_rebuild_index()
	_log_validation_issues(_catalog_validation_report)


func dispose() -> void:
	_project_content_catalog = null
	_clear_index()


func release_dependencies() -> void:
	_project_content_catalog = null
	super.release_dependencies()


# --- 公共方法 ---

func get_visual_theme_descriptors() -> Array[GameThemeDescriptor]:
	return _copy_descriptors(_visual_theme_order, _visual_descriptors)


func get_sound_theme_descriptors() -> Array[GameThemeDescriptor]:
	return _copy_descriptors(_sound_theme_order, _sound_descriptors)


func get_default_visual_theme_id() -> StringName:
	return _default_visual_theme_id


func get_default_sound_theme_id() -> StringName:
	return _default_sound_theme_id


## @param theme_id: 待查询的视觉主题 ID。
func has_visual_theme(theme_id: StringName) -> bool:
	return theme_id != &"" and _visual_descriptors.has(theme_id)


## @param theme_id: 待查询的声音主题 ID。
func has_sound_theme(theme_id: StringName) -> bool:
	return theme_id != &"" and _sound_descriptors.has(theme_id)


## @param theme_id: 待复制的视觉主题描述符 ID。
func get_visual_theme_descriptor(theme_id: StringName) -> GameThemeDescriptor:
	return _copy_descriptor(_visual_descriptors.get(theme_id))


## @param theme_id: 待复制的声音主题描述符 ID。
func get_sound_theme_descriptor(theme_id: StringName) -> GameThemeDescriptor:
	return _copy_descriptor(_sound_descriptors.get(theme_id))


## @param theme_id: 待按需加载的视觉主题 ID。
func load_visual_theme(theme_id: StringName) -> GameTheme:
	var descriptor: GameThemeDescriptor = _get_descriptor(_visual_descriptors, theme_id)
	if descriptor == null:
		return null
	var resource: Resource = _load_descriptor_resource(descriptor)
	if resource is GameTheme:
		var theme: GameTheme = resource
		if theme.theme_id == descriptor.theme_id:
			return theme
		push_error(
			"[GameThemeCatalogUtility] 视觉主题资源 ID 与 manifest 不一致：%s。"
			% String(descriptor.resource_key)
		)
	return null


## @param theme_id: 待按需加载的声音主题 ID。
func load_sound_theme(theme_id: StringName) -> GameAudioTheme:
	var descriptor: GameThemeDescriptor = _get_descriptor(_sound_descriptors, theme_id)
	if descriptor == null:
		return null
	var resource: Resource = _load_descriptor_resource(descriptor)
	if resource is GameAudioTheme:
		var theme: GameAudioTheme = resource
		if theme.theme_id == descriptor.theme_id:
			return theme
		push_error(
			"[GameThemeCatalogUtility] 音效主题资源 ID 与 manifest 不一致：%s。"
			% String(descriptor.resource_key)
		)
	return null


## 获取仅校验 manifest 描述符的报告副本，不加载全部主题资源。
func get_catalog_validation_report() -> GFValidationReport:
	if not is_instance_valid(_catalog_validation_report):
		return GFValidationReport.new("GameThemeCatalog")
	var duplicate_value: RefCounted = _catalog_validation_report.duplicate_report()
	if duplicate_value is GFValidationReport:
		var duplicate_report: GFValidationReport = duplicate_value
		return duplicate_report
	return GFValidationReport.new("GameThemeCatalog")


## 显式加载并校验全部主题资源，供审计与测试使用。
func validate_all_theme_resources() -> GFValidationReport:
	var report: GFValidationReport = get_catalog_validation_report()
	for descriptor: GameThemeDescriptor in get_visual_theme_descriptors():
		var visual_theme: GameTheme = load_visual_theme(descriptor.theme_id)
		if not is_instance_valid(visual_theme):
			_add_error(
				report,
				&"visual_theme_load_failed",
				"视觉主题资源加载失败。",
				descriptor.resource_key
			)
			continue
		var _visual_report: RefCounted = report.merge(
			visual_theme.get_validation_report(),
			false
		)
	for descriptor: GameThemeDescriptor in get_sound_theme_descriptors():
		var sound_theme: GameAudioTheme = load_sound_theme(descriptor.theme_id)
		if not is_instance_valid(sound_theme):
			_add_error(
				report,
				&"sound_theme_load_failed",
				"音效主题资源加载失败。",
				descriptor.resource_key
			)
			continue
		var _sound_report: RefCounted = report.merge(
			sound_theme.get_validation_report(),
			false
		)
	return report


func get_debug_snapshot() -> Dictionary:
	var visual_descriptors: Array[Dictionary] = []
	for descriptor: GameThemeDescriptor in get_visual_theme_descriptors():
		visual_descriptors.append(descriptor.to_debug_dictionary())
	var sound_descriptors: Array[Dictionary] = []
	for descriptor: GameThemeDescriptor in get_sound_theme_descriptors():
		sound_descriptors.append(descriptor.to_debug_dictionary())

	return {
		"default_visual_theme_id": _default_visual_theme_id,
		"default_sound_theme_id": _default_sound_theme_id,
		"visual_themes": visual_descriptors,
		"sound_themes": sound_descriptors,
		"catalog_validation": (
			_catalog_validation_report.to_dict()
			if is_instance_valid(_catalog_validation_report)
			else {}
		),
		"project_content_catalog": (
			_project_content_catalog.get_debug_snapshot()
			if is_instance_valid(_project_content_catalog)
			else {}
		),
	}


# --- 私有/辅助方法 ---

func _rebuild_index() -> void:
	_clear_index()
	_catalog_validation_report = GFValidationReport.new("GameThemeCatalog")
	if not is_instance_valid(_project_content_catalog):
		_add_error(
			_catalog_validation_report,
			&"missing_project_content_catalog",
			"缺少 ProjectContentCatalogUtility。",
			&"project_content_catalog"
		)
		return

	_index_entries(
		_project_content_catalog.query_resources({
			"type_hint": RESOURCE_TYPE_HINT,
			"key_prefix": _VISUAL_THEME_KEY_PREFIX,
			"metadata": {"catalog_role": VISUAL_THEME_CATALOG_ROLE},
		}),
		GameThemeDescriptor.KIND_VISUAL,
		_visual_descriptors,
		_visual_theme_order
	)
	_index_entries(
		_project_content_catalog.query_resources({
			"type_hint": RESOURCE_TYPE_HINT,
			"key_prefix": _SOUND_THEME_KEY_PREFIX,
			"metadata": {"catalog_role": SOUND_THEME_CATALOG_ROLE},
		}),
		GameThemeDescriptor.KIND_SOUND,
		_sound_descriptors,
		_sound_theme_order
	)
	_validate_defaults()


func _index_entries(
	entries: Array[Dictionary],
	theme_kind: StringName,
	target: Dictionary,
	order: PackedStringArray
) -> void:
	for entry: Dictionary in entries:
		var metadata: Dictionary = GFVariantData.get_option_dictionary(entry, "metadata")
		var theme_id: StringName = GFVariantData.get_option_string_name(metadata, "theme_id")
		var resource_key: StringName = GFVariantData.get_option_string_name(entry, "key")
		if theme_id == &"":
			_add_error(
				_catalog_validation_report,
				&"missing_theme_id",
				"主题内容包条目缺少 metadata.theme_id。",
				resource_key
			)
			continue
		if target.has(theme_id):
			_add_error(
				_catalog_validation_report,
				&"duplicate_theme_id",
				"主题 ID 重复：%s。" % String(theme_id),
				theme_id
			)
			continue

		var descriptor: GameThemeDescriptor = GameThemeDescriptor.new().configure(
			theme_id,
			theme_kind,
			resource_key,
			GFVariantData.get_option_string_name(entry, "package_id"),
			GFVariantData.get_option_string(metadata, "display_name_key"),
			GFVariantData.get_option_string(metadata, "description_key"),
			GFVariantData.get_option_bool(metadata, "is_default", false),
			GFVariantData.get_option_int(entry, "priority")
		)
		target[theme_id] = descriptor
		var _ordered: bool = order.append(String(theme_id))
		if not descriptor.is_default:
			continue
		if theme_kind == GameThemeDescriptor.KIND_VISUAL:
			if _default_visual_theme_id != &"":
				_add_error(
					_catalog_validation_report,
					&"multiple_default_visual_themes",
					"只能声明一个默认视觉主题。",
					theme_id
				)
			else:
				_default_visual_theme_id = theme_id
		elif theme_kind == GameThemeDescriptor.KIND_SOUND:
			if _default_sound_theme_id != &"":
				_add_error(
					_catalog_validation_report,
					&"multiple_default_sound_themes",
					"只能声明一个默认音效主题。",
					theme_id
				)
			else:
				_default_sound_theme_id = theme_id


func _validate_defaults() -> void:
	if _visual_descriptors.is_empty():
		_add_error(
			_catalog_validation_report,
			&"empty_visual_theme_catalog",
			"内容包目录未声明视觉主题。",
			&"visual_themes"
		)
	elif _default_visual_theme_id == &"":
		_add_error(
			_catalog_validation_report,
			&"missing_default_visual_theme",
			"内容包目录未声明默认视觉主题。",
			&"visual_themes"
		)
	if _sound_descriptors.is_empty():
		_add_error(
			_catalog_validation_report,
			&"empty_sound_theme_catalog",
			"内容包目录未声明音效主题。",
			&"sound_themes"
		)
	elif _default_sound_theme_id == &"":
		_add_error(
			_catalog_validation_report,
			&"missing_default_sound_theme",
			"内容包目录未声明默认音效主题。",
			&"sound_themes"
		)


func _load_descriptor_resource(descriptor: GameThemeDescriptor) -> Resource:
	if descriptor == null or not is_instance_valid(_project_content_catalog):
		return null
	return _project_content_catalog.load_resource(descriptor.resource_key, RESOURCE_TYPE_HINT)


func _copy_descriptors(
	order: PackedStringArray,
	descriptors: Dictionary
) -> Array[GameThemeDescriptor]:
	var result: Array[GameThemeDescriptor] = []
	for theme_id_text: String in order:
		var descriptor: GameThemeDescriptor = _get_descriptor(
			descriptors,
			StringName(theme_id_text)
		)
		if descriptor != null:
			result.append(descriptor.duplicate_descriptor())
	return result


func _get_descriptor(descriptors: Dictionary, theme_id: StringName) -> GameThemeDescriptor:
	var value: Variant = descriptors.get(theme_id)
	if value is GameThemeDescriptor:
		var descriptor: GameThemeDescriptor = value
		return descriptor
	return null


func _copy_descriptor(value: Variant) -> GameThemeDescriptor:
	if value is GameThemeDescriptor:
		var descriptor: GameThemeDescriptor = value
		return descriptor.duplicate_descriptor()
	return null


func _clear_index() -> void:
	_visual_descriptors.clear()
	_sound_descriptors.clear()
	_visual_theme_order.clear()
	_sound_theme_order.clear()
	_default_visual_theme_id = &""
	_default_sound_theme_id = &""
	_catalog_validation_report = null


func _add_error(
	report: GFValidationReport,
	kind: StringName,
	message: String,
	key: Variant
) -> void:
	var _issue: RefCounted = report.add_error(kind, message, key)


func _log_validation_issues(report: GFValidationReport) -> void:
	if not is_instance_valid(report):
		return
	for issue: GFValidationIssue in report.issues:
		if issue == null:
			continue
		if issue.is_error():
			push_error("[GameThemeCatalogUtility] %s" % issue.message)
		elif issue.is_warning():
			push_warning("[GameThemeCatalogUtility] %s" % issue.message)


func _get_project_content_catalog_utility() -> ProjectContentCatalogUtility:
	var utility_value: Object = get_utility(ProjectContentCatalogUtility)
	if utility_value is ProjectContentCatalogUtility:
		var catalog: ProjectContentCatalogUtility = utility_value
		return catalog
	return null
