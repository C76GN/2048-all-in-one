# scripts/core/input_source.gd

## BaseInputSource: 所有输入源策略的基类蓝图。
##
## 该类定义了一个标准接口，用于将不同来源的输入（如玩家键盘、回放数据、AI决策）
## 统一为标准的“动作(action)”信号。GamePlay 将依赖此接口，从而与具体的输入方式解耦。
class_name BaseInputSource
extends Node


# --- 信号 ---

## 当一个动作被触发时发出。
## @param action: 代表具体动作的数据，通常是一个 Vector2i (用于移动)。
@warning_ignore("unused_signal")
signal action_triggered(action: Variant)


# --- 公共方法 ---

## 启动输入源，使其开始监听或处理输入。
func start() -> void:
	pass


## 停止输入源。
func stop() -> void:
	pass
