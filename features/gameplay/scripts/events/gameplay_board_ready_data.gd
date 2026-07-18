## GameplayBoardReadyData: 玩法棋盘视图完成初始化后的事件载体。
##
## 该事件只暴露可供外部工具观察的棋盘表现宿主。诊断功能可据此建立开发上下文，
## 玩法功能无需反向依赖任何诊断 UI 或 Utility。
class_name GameplayBoardReadyData
extends "res://addons/gf/kernel/base/gf_payload.gd"


# --- 公共变量 ---

## 当前对局的棋盘表现控制器。
var board: GameBoardController


# --- Godot 生命周期方法 ---

## 创建棋盘就绪事件。
## @param p_board: 当前对局的棋盘表现控制器。
func _init(p_board: GameBoardController = null) -> void:
	board = p_board
