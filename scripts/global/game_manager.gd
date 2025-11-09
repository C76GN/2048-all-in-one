# global/game_manager.gd

## GlobalGameManager: 负责处理全局游戏状态与核心流程控制的单例脚本。
##
## 作为一个自动加载的全局节点 (Singleton)，它在整个游戏生命周期中持续存在，
## 主要用于提供场景切换、安全退出游戏以及跨场景传递数据（如所选的游戏模式配置）等核心服务。
extends Node

# --- 导出变量 ---

## 在编辑器中设置主菜单场景资源。
@export var main_menu_scene: PackedScene


# --- 公共变量 ---

## 存储当前正在播放或准备播放的回放数据资源。
var current_replay_data: ReplayData

## 存储从书签列表选择的、即将用于加载游戏的书签数据。
var selected_bookmark_data: BookmarkData = null


# --- 私有变量 ---

## 存储当前已选择的游戏模式配置文件的资源路径。
var _selected_mode_config_path: String

## 存储当前已选择的游戏棋盘尺寸。
var _selected_grid_size: int = 4


# --- 公共方法 ---

## 选择一个游戏模式并切换到游戏场景，传递棋盘大小和种子。
## @param config_path: 模式配置文件的资源路径。
## @param game_scene: 游戏场景的资源。
## @param grid_size: 棋盘的尺寸。
## @param p_seed: 随机数种子。
func select_mode_and_start(config_path: String, game_scene: PackedScene, grid_size: int, p_seed: int) -> void:
	if not config_path.begins_with("res://") or not config_path.ends_with(".tres"):
		push_error("错误: 模式配置文件路径必须是有效的资源路径: " + config_path)
		return

	if game_scene == null:
		push_error("错误: 游戏场景 (game_scene) 未提供。")
		return

	_selected_mode_config_path = config_path
	_selected_grid_size = grid_size
	RNGManager.initialize_rng(p_seed)
	goto_scene_packed(game_scene)


## 获取当前选择的模式配置路径。
## @return 选中的模式配置资源路径。
func get_selected_mode_config_path() -> String:
	return _selected_mode_config_path


## 获取当前选择的棋盘大小。
## @return 选中的棋盘尺寸。
func get_selected_grid_size() -> int:
	return _selected_grid_size


## 返回到主菜单。
func return_to_main_menu() -> void:
	if not is_instance_valid(main_menu_scene):
		push_error("GlobalGameManager: 主菜单场景未配置！")
		return

	goto_scene_packed(main_menu_scene)


## 切换到指定的场景资源。
## @param scene: 待切换的场景资源。
func goto_scene_packed(scene: PackedScene) -> void:
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
		get_tree().current_scene = null

	var new_scene_instance = scene.instantiate()
	get_tree().root.add_child(new_scene_instance)
	get_tree().current_scene = new_scene_instance
	print("已切换到场景: ", scene.resource_path)


## 切换到指定的场景路径。
## @param path: 待切换的场景路径。
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


## 选择一个书签并切换到游戏场景。
## @param p_bookmark_data: 书签数据。
## @param game_scene: 游戏场景的资源。
func load_game_from_bookmark(p_bookmark_data: BookmarkData, game_scene: PackedScene) -> void:
	if not is_instance_valid(p_bookmark_data):
		push_error("错误: 提供的书签数据无效。")
		return

	if game_scene == null:
		push_error("错误: 游戏场景 (game_scene) 未提供。")
		return

	selected_bookmark_data = p_bookmark_data
	_selected_mode_config_path = ""
	_selected_grid_size = 0

	goto_scene_packed(game_scene)
