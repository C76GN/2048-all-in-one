# scripts/models/app_config_model.gd

## AppConfigModel: 负责保存整个应用程序的全局配置状态。
##
## 负责管理应用级别的全局配置与游戏启动状态，
## 用于跨场景传递数据（如选定的游戏模式、棋盘大小、待加载的书签或回放数据）。
class_name AppConfigModel
extends GFModel


# --- 公共变量 (使用 BindableProperty 包装) ---

## 存储当前已选择的游戏模式配置文件的资源路径。
var selected_mode_config_path: BindableProperty = BindableProperty.new("")

## 存储当前已选择的游戏棋盘尺寸。
var selected_grid_size: BindableProperty = BindableProperty.new(4)

## 存储当前正在播放或准备播放的回放数据资源。
var current_replay_data: BindableProperty = BindableProperty.new(null)

## 存储从书签列表选择的、即将用于加载游戏的书签数据。
var selected_bookmark_data: BindableProperty = BindableProperty.new(null)

## 存储开局时产生的或者用户输入的固定种子，用于重玩同一局。
var selected_seed: BindableProperty = BindableProperty.new(0)


# --- Godot 生命周期方法 ---

func init() -> void:
	pass
