## CurrentGameModel: 存储当前游戏会话的状态数据。
##
## 用于解耦 GamePlayController 中持有的业务无关变量。
class_name CurrentGameModel
extends "res://addons/gf/kernel/base/gf_model.gd"


# --- 公共变量 (使用 GFBindableProperty 包装) ---

## 当前加载的游戏模式配置。
var mode_config: GFBindableProperty = GFBindableProperty.new(null)

## 当前棋盘的空间拓扑。
var current_board_topology: GFBindableProperty = GFBindableProperty.new(null)

## 本次游戏会话的初始种子。
var initial_seed: GFBindableProperty = GFBindableProperty.new(0)

## 进入游戏时的最高分记录。
var initial_high_score: GFBindableProperty = GFBindableProperty.new(0)

## 标记当前是否为回放模式。
var is_replay_mode: GFBindableProperty = GFBindableProperty.new(false)


# --- Godot 生命周期方法 ---

func init() -> void:
	pass
