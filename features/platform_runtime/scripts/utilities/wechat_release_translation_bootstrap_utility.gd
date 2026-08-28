## WechatReleaseTranslationBootstrapUtility：微信正式包的翻译资源注册边界。
##
## Godot 4.7 会在导出配置直接声明中文 Translation 时自动注入 ICU 支持数据。
## 微信正式包改为显式携带 Translation 资源，并在 GF 架构启动前一次性注册，
## 以保留中英文界面，同时避免把约 4.8 MiB 的 ICU 数据装入受限代码包。
class_name WechatReleaseTranslationBootstrapUtility
extends RefCounted


# --- 常量 ---

const TRANSLATION_PATHS: PackedStringArray = [
	"res://shared/assets/translations.en.translation",
	"res://shared/assets/translations.zh.translation",
]


# --- 静态变量 ---

static var _installed: bool = false
static var _owned_translations: Array[Translation] = []


# --- 公共方法 ---

## 在 Composition Root 已确认微信正式构建时注册翻译；其他平台继续由 ProjectSettings 自动加载。
## 所有资源先验证成功再提交到 TranslationServer，避免半注册状态。
## @param required: 是否处于需要手动注册翻译的微信正式构建。
static func install_if_required(required: bool) -> Error:
	if not required or _installed:
		return OK
	var staged: Array[Translation] = []
	for path: String in TRANSLATION_PATHS:
		var resource: Resource = ResourceLoader.load(path, "Translation")
		if not resource is Translation:
			return ERR_FILE_CORRUPT if ResourceLoader.exists(path) else ERR_FILE_NOT_FOUND
		var translation: Translation = resource
		staged.append(translation)
	for translation: Translation in staged:
		TranslationServer.add_translation(translation)
	_owned_translations = staged
	_installed = true
	return OK


## 返回复制隔离的必需资源路径，供发布契约与诊断读取。
static func get_required_translation_paths() -> PackedStringArray:
	return TRANSLATION_PATHS.duplicate()
