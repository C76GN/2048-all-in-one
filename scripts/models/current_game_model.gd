# scripts/models/current_game_model.gd

## CurrentGameModel: 存储当前游戏会话的状态数据。
##
## 用于解耦 GamePlay.gd 中持有的业务无关变量。
class_name CurrentGameModel
extends GFModel


# --- 公共变量 (使用 BindableProperty 包装) ---

## 当前加载的游戏模式配置。
var mode_config: BindableProperty = BindableProperty.new(null)

## 当前棋盘的尺寸。
var current_grid_size: BindableProperty = BindableProperty.new(4)

## 本次游戏会话的初始种子。
var initial_seed: BindableProperty = BindableProperty.new(0)

## 进入游戏时的最高分记录。
var initial_high_score: BindableProperty = BindableProperty.new(0)

## 标记当前是否为回放模式。
var is_replay_mode: BindableProperty = BindableProperty.new(false)


# --- Godot 生命周期方法 ---

func init() -> void:
	pass
