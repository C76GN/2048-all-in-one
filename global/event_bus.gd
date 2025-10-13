# global/event_bus.gd

## EventBus: 一个全局事件总线单例。
##
## 用于解耦游戏中的各个系统。系统可以向总线发射信号，
## 而其他系统可以监听这些信号，从而实现通信，而无需直接引用彼此。
extends Node

## 在分数更新时发出。
## @param amount: 新增的分数。
@warning_ignore("unused_signal")
signal score_updated(amount: int)

## 在一次有效的移动（至少有一个方块移动或合并）完成后发出。
## @param move_data: 一个包含移动方向和受影响行/列信息的字典。
@warning_ignore("unused_signal")
signal move_made(move_data: Dictionary)

## 当有怪物在交互中被消灭时发出。
@warning_ignore("unused_signal")
signal monster_killed

## 当游戏根据规则判定为失败时发出。
@warning_ignore("unused_signal")
signal game_lost

## 当需要更新HUD显示时发出。
## @param display_data: 一个包含所有要在HUD上显示的信息的字典。
@warning_ignore("unused_signal")
signal hud_update_requested(display_data: Dictionary)

## 当棋盘尺寸发生改变时发出（重置或扩建后）。
## @param new_grid_size: 棋盘的新尺寸。
@warning_ignore("unused_signal")
signal board_resized(new_grid_size: int)
