# scripts/systems/save_system.gd

## SaveSystem: 负责处理游戏数据持久化的系统。
##
## 负责管理游戏存档状态，通过 GFStorageUtility 实现对 GameSaveResource 的存取。
class_name SaveSystem
extends GFSystem

const SAVE_FILE_NAME: String = "game_save.tres"

var _storage: GFStorageUtility
var _save_data: GameSaveResource
var _log: GFLogUtility


func init() -> void:
	_storage = get_utility(GFStorageUtility) as GFStorageUtility
	_log = get_utility(GFLogUtility) as GFLogUtility
	_load_game_data()


# --- 公共方法 ---

## 根据模式ID和棋盘大小，获取最高分。
func get_high_score(mode_id: String, grid_size: int) -> int:
	if not _save_data:
		_load_game_data()
	
	var grid_size_str: String = "%dx%d" % [grid_size, grid_size]
	var scores: Dictionary = _save_data.scores

	if scores.has(mode_id) and scores[mode_id].has(grid_size_str):
		return scores[mode_id][grid_size_str]

	return 0


## 设置或更新一个模式在特定棋盘大小下的最高分。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	if not _save_data:
		_load_game_data()
	
	var current_high_score: int = get_high_score(mode_id, grid_size)

	if score > current_high_score:
		var grid_size_str: String = "%dx%d" % [grid_size, grid_size]

		if not _save_data.scores.has(mode_id):
			_save_data.scores[mode_id] = {}

		_save_data.scores[mode_id][grid_size_str] = score
		if _log: _log.info("SaveSystem", "新纪录诞生! 模式: %s, 尺寸: %s, 分数: %d" % [mode_id, grid_size_str, score])
		_save_game_data()


## 设置并保存语言环境。
func set_language(locale: String) -> void:
	if not _save_data:
		_load_game_data()
	
	_save_data.settings[&"locale"] = locale
	_save_game_data()
	
	TranslationServer.set_locale(locale)
	if _log: _log.info("SaveSystem", "已应用语言设置: %s" % locale)


## 获取当前保存的语言设置。
func get_language() -> String:
	if not _save_data:
		_load_game_data()
	
	return _save_data.settings.get(&"locale", "zh")


# --- 私有方法 ---

func _save_game_data() -> void:
	if _storage and is_instance_valid(_save_data):
		_storage.save_resource(SAVE_FILE_NAME, _save_data)


func _load_game_data() -> void:
	if _storage:
		_save_data = _storage.load_resource(SAVE_FILE_NAME, "GameSaveResource") as GameSaveResource

	if not is_instance_valid(_save_data):
		_save_data = GameSaveResource.new()

	if _save_data:
		_save_data.ensure_defaults()
		TranslationServer.set_locale(get_language())
