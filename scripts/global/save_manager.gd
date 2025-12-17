# scripts/global/save_manager.gd

## SaveManager: 负责处理游戏数据持久化的全局单例。
##
## 该脚本管理着一个包含所有模式最高分数据的字典，并提供了
## 保存到本地文件和从本地文件加载的功能。它处理了文件不存在
## 的情况，并为游戏逻辑提供了简单的数据读写接口。
extends Node


# --- 常量 ---

## 分数存档文件的路径。
const SAVE_FILE_PATH: String = "user://scores.dat"
## 设置存档文件的路径。
const SETTINGS_FILE_PATH: String = "user://settings.dat"


# --- 私有变量 ---

## 内部存储所有分数数据的字典。
var _scores_data: Dictionary = {}

## 内部存储设置数据的字典。
var _settings_data: Dictionary = {
"locale": "zh" # 默认语言
}


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_load_scores()
	_load_settings()
	_apply_settings()


# --- 公共方法 ---

## 根据模式ID和棋盘大小，获取最高分。
func get_high_score(mode_id: String, grid_size: int) -> int:
	var grid_size_str: String = "%dx%d" % [grid_size, grid_size]

	if _scores_data.has(mode_id) and _scores_data[mode_id].has(grid_size_str):
		return _scores_data[mode_id][grid_size_str]

	return 0


## 设置或更新一个模式在特定棋盘大小下的最高分。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	var current_high_score: int = get_high_score(mode_id, grid_size)

	if score > current_high_score:
		var grid_size_str: String = "%dx%d" % [grid_size, grid_size]

		if not _scores_data.has(mode_id):
			_scores_data[mode_id] = {}

		_scores_data[mode_id][grid_size_str] = score
		print("新纪录诞生! 模式: %s, 尺寸: %s, 分数: %d" % [mode_id, grid_size_str, score])
		_save_scores()


## 设置并保存语言环境。
## @param locale: 语言代码 (例如 "zh", "en")。
func set_language(locale: String) -> void:
	_settings_data["locale"] = locale
	_save_settings()
	_apply_settings()


## 获取当前保存的语言设置。
func get_language() -> String:
	return _settings_data.get("locale", "zh")


# --- 私有/辅助方法 ---

func _save_scores() -> void:
	_save_data(SAVE_FILE_PATH, _scores_data)


func _save_settings() -> void:
	_save_data(SETTINGS_FILE_PATH, _settings_data)


func _load_scores() -> void:
	var data = _load_data(SAVE_FILE_PATH)
	if data != null:
		_scores_data = data


func _load_settings() -> void:
	var data = _load_data(SETTINGS_FILE_PATH)
	if data != null:
		# 合并加载的数据，确保新添加的设置项有默认值
		_settings_data.merge(data, true)


func _apply_settings() -> void:
	var locale: String = _settings_data.get("locale", "zh")
	TranslationServer.set_locale(locale)
	print("已应用语言设置: ", locale)


## 通用的保存数据辅助函数。
func _save_data(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法保存文件: %s" % path)
		return
	var json_string: String = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()


## 通用的加载数据辅助函数。
func _load_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法加载文件: %s" % path)
		return null

	var content: String = file.get_as_text()
	file.close()
	var parse_result: Variant = JSON.parse_string(content)

	if parse_result == null:
		push_error("JSON解析失败: %s" % path)
		return null

	return parse_result
