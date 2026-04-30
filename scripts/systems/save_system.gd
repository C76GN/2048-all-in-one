## SaveSystem: 负责处理游戏最高分数据持久化的系统。
##
## 最高分使用 GFStorageUtility 的字典存储管线，设置交给 GFSettingsUtility 管理。
class_name SaveSystem
extends GFSystem


# --- 常量 ---

const _LOG_TAG: String = "SaveSystem"
const SAVE_FILE_NAME: String = "game_save.sav"
const _KEY_SCORES: String = "scores"


# --- 私有变量 ---

var _storage: GFStorageUtility
var _save_data: Dictionary = {}
var _is_game_data_loaded: bool = false
var _log: GFLogUtility


# --- Godot 生命周期方法 ---

func ready() -> void:
	_storage = get_utility(GFStorageUtility) as GFStorageUtility
	_log = get_utility(GFLogUtility) as GFLogUtility
	_load_game_data()


func dispose() -> void:
	_storage = null
	_save_data.clear()
	_is_game_data_loaded = false
	_log = null


# --- 公共方法 ---

## 根据模式ID和棋盘大小，获取最高分。
func get_high_score(mode_id: String, grid_size: int) -> int:
	_ensure_game_data_loaded()
	
	var grid_size_str: String = "%dx%d" % [grid_size, grid_size]
	var scores := _get_scores()

	var mode_scores_value: Variant = scores.get(mode_id, {})
	if mode_scores_value is Dictionary:
		var mode_scores: Dictionary = mode_scores_value
		if mode_scores.has(grid_size_str):
			return int(mode_scores[grid_size_str])

	return 0


## 设置或更新一个模式在特定棋盘大小下的最高分。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	_ensure_game_data_loaded()
	
	var current_high_score: int = get_high_score(mode_id, grid_size)
	if score <= current_high_score:
		return

	var grid_size_str: String = "%dx%d" % [grid_size, grid_size]
	var scores := _get_scores()
	var mode_scores := _get_mode_scores(scores, mode_id)

	mode_scores[grid_size_str] = score
	scores[mode_id] = mode_scores
	if _log:
		_log.info(_LOG_TAG, "新纪录: mode=%s, grid=%s, score=%d" % [mode_id, grid_size_str, score])
	_save_game_data()


## 设置并保存语言环境。
func set_language(locale: String) -> void:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		display_settings.set_locale(locale)
	else:
		TranslationServer.set_locale(locale)

	if _log:
		_log.info(_LOG_TAG, "已应用语言设置: %s" % locale)


## 获取当前保存的语言设置。
func get_language() -> String:
	var display_settings := get_utility(GFDisplaySettingsUtility) as GFDisplaySettingsUtility
	if is_instance_valid(display_settings):
		return display_settings.get_locale()

	var settings := get_utility(GFSettingsUtility) as GFSettingsUtility
	if is_instance_valid(settings):
		return String(settings.get_value(GFDisplaySettingsUtility.LOCALE_KEY, "zh"))

	return "zh"


# --- 私有方法 ---

func _save_game_data() -> void:
	if not is_instance_valid(_storage):
		return

	var error := _storage.save_data(SAVE_FILE_NAME, _save_data)
	if error != OK and is_instance_valid(_log):
		_log.error(_LOG_TAG, "保存最高分失败，错误码: %d" % error)


func _load_game_data() -> void:
	_save_data = {}
	if is_instance_valid(_storage):
		_save_data = _storage.load_data(SAVE_FILE_NAME)

	_save_data.erase(GFStorageCodec.META_KEY)
	_ensure_game_data_defaults()
	_is_game_data_loaded = true


func _ensure_game_data_loaded() -> void:
	if _is_game_data_loaded:
		return

	_load_game_data()


func _ensure_game_data_defaults() -> void:
	if not _save_data.has(_KEY_SCORES) or not (_save_data[_KEY_SCORES] is Dictionary):
		_save_data[_KEY_SCORES] = {}


func _get_scores() -> Dictionary:
	_ensure_game_data_defaults()
	return _save_data[_KEY_SCORES]


func _get_mode_scores(scores: Dictionary, mode_id: String) -> Dictionary:
	var mode_scores_value: Variant = scores.get(mode_id, {})
	if mode_scores_value is Dictionary:
		return mode_scores_value

	return {}
