# scripts/global/save_manager.gd

## SaveManager: 负责处理游戏数据持久化的全局单例。
##
## 该脚本管理着一个包含所有模式最高分数据的字典，并提供了
## 保存到本地文件和从本地文件加载的功能。它处理了文件不存在
## 的情况，并为游戏逻辑提供了简单的数据读写接口。
extends Node


# --- 常量 ---

## 存档文件的路径。
const SAVE_PATH: String = "user://game_save.tres"


# --- 私有变量 ---

var _save_data: GameSaveResource


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_load_game_data()
	_apply_settings()


# --- 公共方法 ---

## 根据模式ID和棋盘大小，获取最高分。
func get_high_score(mode_id: String, grid_size: int) -> int:
	var grid_size_str: String = "%dx%d" % [grid_size, grid_size]
	var scores: Dictionary = _save_data.scores

	if scores.has(mode_id) and scores[mode_id].has(grid_size_str):
		return scores[mode_id][grid_size_str]

	return 0


## 设置或更新一个模式在特定棋盘大小下的最高分。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	var current_high_score: int = get_high_score(mode_id, grid_size)

	if score > current_high_score:
		var grid_size_str: String = "%dx%d" % [grid_size, grid_size]

		if not _save_data.scores.has(mode_id):
			_save_data.scores[mode_id] = {}

		_save_data.scores[mode_id][grid_size_str] = score
		print("新纪录诞生! 模式: %s, 尺寸: %s, 分数: %d" % [mode_id, grid_size_str, score])
		_save_game_data()


## 设置并保存语言环境。
## @param locale: 语言代码 (例如 "zh", "en")。
func set_language(locale: String) -> void:
	_save_data.settings[&"locale"] = locale
	_save_game_data()
	_apply_settings()


## 获取当前保存的语言设置。
func get_language() -> String:
	return _save_data.settings.get(&"locale", "zh")


# --- 私有/辅助方法 ---

func _save_game_data() -> void:
	var error: Error = ResourceSaver.save(_save_data, SAVE_PATH)
	if error != OK:
		push_error("SaveManager: 无法保存存档文件: %d" % error)


func _load_game_data() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		_save_data = ResourceLoader.load(SAVE_PATH) as GameSaveResource

	if not is_instance_valid(_save_data):
		_save_data = GameSaveResource.new()

	_save_data.ensure_defaults()


func _apply_settings() -> void:
	var locale: String = get_language()
	TranslationServer.set_locale(locale)
	print("已应用语言设置: ", locale)
