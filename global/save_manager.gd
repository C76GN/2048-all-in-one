# global/save_manager.gd

## SaveManager: 负责处理游戏数据持久化的全局单例。
##
## 该脚本管理着一个包含所有模式最高分数据的字典，并提供了
## 保存到本地文件和从本地文件加载的功能。它处理了文件不存在
## 的情况，并为游戏逻辑提供了简单的数据读写接口。
extends Node

# 存档文件的路径，保存在用户数据目录中
const SAVE_FILE_PATH = "user://scores.dat"

# 内部存储所有分数数据的字典。
# 结构: { "mode_id": { "grid_size_str": score } }
# 例如: { "classic": { "4x4": 15200, "5x5": 32000 } }
var _scores_data: Dictionary = {}

## Godot生命周期函数：当单例节点进入场景树时调用。
func _ready() -> void:
	# 游戏启动时，自动加载已有的分数记录。
	load_scores()

# --- 公共数据接口 ---

## 根据模式ID和棋盘大小，获取最高分。
## @param mode_id: 模式的唯一标识符（例如 "classic", "fibonacci"）。
## @param grid_size: 棋盘的尺寸 (例如 4, 5, 6)。
## @return: 返回对应的最高分，如果没有记录则返回 0。
func get_high_score(mode_id: String, grid_size: int) -> int:
	var grid_size_str = "%dx%d" % [grid_size, grid_size]
	
	if _scores_data.has(mode_id) and _scores_data[mode_id].has(grid_size_str):
		return _scores_data[mode_id][grid_size_str]
	
	return 0

## 设置或更新一个模式在特定棋盘大小下的最高分。
## 只有当新分数高于旧分数时才会更新。
## @param mode_id: 模式的唯一标识符。
## @param grid_size: 棋盘的尺寸。
## @param score: 本次游戏获得的分数。
func set_high_score(mode_id: String, grid_size: int, score: int) -> void:
	var current_high_score = get_high_score(mode_id, grid_size)
	
	if score > current_high_score:
		var grid_size_str = "%dx%d" % [grid_size, grid_size]
		
		# 如果该模式还没有任何记录，先创建一个空字典。
		if not _scores_data.has(mode_id):
			_scores_data[mode_id] = {}
			
		_scores_data[mode_id][grid_size_str] = score
		print("新纪录诞生! 模式: %s, 尺寸: %s, 分数: %d" % [mode_id, grid_size_str, score])
		
		# 更新分数后，立即保存到文件。
		save_scores()

# --- 文件读写逻辑 ---

## 将当前的分数数据保存到本地文件。
func save_scores() -> void:
	# 使用 FileAccess.open 来安全地打开文件进行写入。
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("保存分数失败！无法打开文件: %s" % SAVE_FILE_PATH)
		return

	# 将字典转换为JSON字符串。
	var json_string = JSON.stringify(_scores_data, "\t") # 使用 "\t" 进行格式化，方便调试查看
	
	# 将字符串写入文件并关闭。
	file.store_string(json_string)
	file.close()
	print("分数已成功保存到: %s" % SAVE_FILE_PATH)

## 从本地文件加载分数数据。
func load_scores() -> void:
	# 首先检查文件是否存在。
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("存档文件不存在，将使用空的计分板。")
		return

	# 打开文件进行读取。
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("加载分数失败！无法打开文件: %s" % SAVE_FILE_PATH)
		return

	# 读取整个文件的内容。
	var content = file.get_as_text()
	file.close()
	
	# 解析JSON字符串。
	var parse_result = JSON.parse_string(content)
	if parse_result == null:
		push_error("加载分数失败！JSON格式错误。")
		_scores_data = {} # 解析失败时重置数据，防止崩溃
		return
		
	_scores_data = parse_result
	print("分数已从 %s 成功加载。" % SAVE_FILE_PATH)
