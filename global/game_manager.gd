# global/game_manager.gd

## GlobalGameManager: 负责处理全局游戏状态与核心流程控制的单例脚本。
##
## 作为一个自动加载的全局节点 (Singleton)，它在整个游戏生命周期中持续存在，
## 主要用于提供场景切换、安全退出游戏以及跨场景传递数据（如所选的游戏模式配置）等核心服务。
extends Node

# 主菜单是应用的固定入口，将其路径作为常量是合理的。
const MAIN_MENU_SCENE_PATH = "res://scenes/main_menu.tscn"

# --- 核心游戏状态 ---
var _selected_mode_config_path: String
var _selected_grid_size: int = 4

# --- 随机性管理 ---
# 全局唯一的随机数生成器实例
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# 当前游戏正在使用的种子
var _current_seed: int = 0


# --- 公共接口 ---

## 初始化或重置随机数生成器。
## @param p_seed: 用于初始化RNG的种子。如果为0，则使用随机种子。
func initialize_rng(p_seed: int = 0) -> void:
	if p_seed == 0:
		_rng.randomize()
		_current_seed = _rng.seed
	else:
		_current_seed = p_seed
		_rng.seed = _current_seed
	print("RNG 已使用种子初始化: ", _current_seed)


## 选择一个游戏模式并切换到游戏场景，传递棋盘大小和种子。
func select_mode_and_start(config_path: String, game_scene: PackedScene, grid_size: int, p_seed: int):
	if not config_path.begins_with("res://") or not config_path.ends_with(".tres"):
		push_error("错误: 模式配置文件路径必须是有效的资源路径: " + config_path)
		return
	
	if game_scene == null:
		push_error("错误: 游戏场景 (game_scene) 未提供。")
		return

	_selected_mode_config_path = config_path
	_selected_grid_size = grid_size
	
	# 在开始新游戏前，使用指定的种子初始化RNG
	initialize_rng(p_seed)
	
	goto_scene_packed(game_scene)

## 获取当前选择的模式配置路径。
func get_selected_mode_config_path() -> String:
	return _selected_mode_config_path

## 获取当前选择的棋盘大小。
func get_selected_grid_size() -> int:
	return _selected_grid_size
	
## 获取当前游戏的种子。
func get_current_seed() -> int:
	return _current_seed

## 获取全局唯一的随机数生成器实例。
func get_rng() -> RandomNumberGenerator:
	return _rng

## 统一的返回主菜单功能，打破场景间的循环依赖。
func return_to_main_menu():
	goto_scene(MAIN_MENU_SCENE_PATH)

## 使用 PackedScene 资源进行场景切换，更安全。
func goto_scene_packed(scene: PackedScene):
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null

	var new_scene_instance = scene.instantiate()
	get_tree().root.add_child(new_scene_instance)
	get_tree().current_scene = new_scene_instance
	print("已切换到场景: ", scene.resource_path)

## 切换到指定的场景路径。
func goto_scene(path: String) -> void:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		push_error("错误: 场景路径必须是绝对的场景资源路径，例如 'res://scenes/my_scene.tscn'")
		return
	
	var next_scene_packed = load(path)
	if next_scene_packed == null:
		push_error("错误: 无法加载场景资源: " + path)
		return
		
	goto_scene_packed(next_scene_packed)

## 安全地退出整个游戏应用。
func quit_game() -> void:
	print("正在退出游戏...")
	get_tree().quit()
