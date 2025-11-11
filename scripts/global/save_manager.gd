# scripts/global/save_manager.gd

## SaveManager: 负责处理游戏数据持久化的全局单例。
##
## 该脚本管理着一个包含所有模式最高分数据的字典，并提供了
## 保存到本地文件和从本地文件加载的功能。它处理了文件不存在
## 的情况，并为游戏逻辑提供了简单的数据读写接口。
extends Node


# --- 常量 ---

## 存档文件的路径，保存在用户数据目录中。
const SAVE_FILE_PATH: String = "user://scores.dat"


# --- 私有变量 ---

## 内部存储所有分数数据的字典。
## 结构: { "mode_id": { "grid_size_str": score } }
## 例如: { "classic": { "4x4": 15200, "5x5": 32000 } }
var _scores_data: Dictionary = {}


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_load_scores()


# --- 公共方法 ---

## 根据模式ID和棋盘大小，获取最高分。
## @param mode_id: 模式的唯一标识符（例如 "classic", "fibonacci"）。
## @param grid_size: 棋盘的尺寸 (例如 4, 5, 6)。
## @return: 返回对应的最高分，如果没有记录则返回 0。
func get_high_score(mode_id: String, grid_size: int) -> int:
	var grid_size_str: String = "%dx%d" % [grid_size, grid_size]

	if _scores_data.has(mode_id) and _scores_data[mode_id].has(grid_size_str):
		return _scores_data[mode_id][grid_size_str]

	return 0


## 设置或更新一个模式在特定棋盘大小下的最高分。
## 只有当新分数高于旧分数时才会更新。
## @param mode_id: 模式的唯一标识符。
## @param grid_size: 棋盘的尺寸。
## @param score: 本次游戏获得的分数。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	var current_high_score: int = get_high_score(mode_id, grid_size)

	if score > current_high_score:
		var grid_size_str: String = "%dx%d" % [grid_size, grid_size]

		if not _scores_data.has(mode_id):
			_scores_data[mode_id] = {}

		_scores_data[mode_id][grid_size_str] = score
		print("新纪录诞生! 模式: %s, 尺寸: %s, 分数: %d" % [mode_id, grid_size_str, score])
		_save_scores()


# --- 私有/辅助方法 ---

## 将当前的分数数据保存到本地文件。
func _save_scores() -> void:
	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)

	if file == null:
		push_error("保存分数失败！无法打开文件: %s" % SAVE_FILE_PATH)
		return

	var json_string: String = JSON.stringify(_scores_data, "\t")
	file.store_string(json_string)
	file.close()
	print("分数已成功保存到: %s" % SAVE_FILE_PATH)


## 从本地文件加载分数数据。
func _load_scores() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("存档文件不存在，将使用空的计分板。")
		return

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)

	if file == null:
		push_error("加载分数失败！无法打开文件: %s" % SAVE_FILE_PATH)
		return

	var content: String = file.get_as_text()
	file.close()
	var parse_result: Variant = JSON.parse_string(content)

	if parse_result == null:
		push_error("加载分数失败！JSON格式错误。")
		_scores_data = {}
		return

	_scores_data = parse_result
	print("分数已从 %s 成功加载。" % SAVE_FILE_PATH)
