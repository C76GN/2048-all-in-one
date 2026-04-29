## EventNames: 集中管理所有 GF 简单事件的名称常量。
##
## 使用方式：EventNames.SCENE_WILL_CHANGE
## 取代硬编码字符串，避免拼写错误并提升可维护性。
class_name EventNames
extends RefCounted


# --- 场景 / 生命周期 ---

## 场景即将切换，在卸载旧场景前发出。
const SCENE_WILL_CHANGE: StringName = &"scene_will_change"

## 请求切换到指定场景。
const SCENE_CHANGE_REQUESTED: StringName = &"scene_change_requested"

## 请求返回主菜单。
const RETURN_TO_MAIN_MENU_REQUESTED: StringName = &"return_to_main_menu_requested"


# --- 游戏初始化 ---

## 请求启动游戏初始化流程。
const REQUEST_GAME_INITIALIZATION: StringName = &"request_game_initialization"

## 请求棋盘层面的初始化规则。
const REQUEST_BOARD_INITIALIZATION: StringName = &"request_board_initialization"


# --- 游戏状态 ---

## 游戏状态发生变化，payload 为状态名。
const GAME_STATE_CHANGED: StringName = &"game_state_changed"

## 游戏状态：就绪。
const STATE_READY: StringName = &"Ready"

## 游戏状态：正在进行。
const STATE_PLAYING: StringName = &"Playing"

## 游戏状态：游戏结束。
const STATE_GAME_OVER: StringName = &"GameOver"

## 游戏判负事件。
const GAME_LOST: StringName = &"game_lost"

## 游戏状态已被测试工具或调试入口修改。
const GAME_STATE_TAINTED: StringName = &"game_state_tainted"


# --- 玩家操作 ---

## 请求撤销上一步玩家操作。
const UNDO_REQUESTED: StringName = &"undo_requested"

## 请求保存当前游戏书签。
const SAVE_BOOKMARK_REQUESTED: StringName = &"save_bookmark_requested"

## 请求打开暂停 UI。
const UI_PAUSE_REQUESTED: StringName = &"ui_pause_requested"

## 请求切换暂停 UI 显示状态。
const TOGGLE_PAUSE_UI: StringName = &"toggle_pause_ui"


# --- 回合 / 得分 ---

## 当前回合结束。
const TURN_FINISHED: StringName = &"turn_finished"

## 得分变化事件，payload 为分数增量。
const SCORE_UPDATED: StringName = &"score_updated"

## 怪物被击杀。
const MONSTER_KILLED: StringName = &"monster_killed"

## 请求生成方块，payload 为 SpawnData。
const SPAWN_TILE_REQUESTED: StringName = &"spawn_tile_requested"


# --- 棋盘 ---

## 请求棋盘播放动画序列，payload 为动画指令数组。
const BOARD_ANIMATION_REQUESTED: StringName = &"board_animation_requested"

## 请求棋盘播放撤销逆向动画，payload 为快照与反向目标映射。
const BOARD_UNDO_ANIMATION_REQUESTED: StringName = &"board_undo_animation_requested"

## 请求棋盘全量刷新，payload 为棋盘快照。
const BOARD_REFRESH_REQUESTED: StringName = &"board_refresh_requested"

## 棋盘尺寸发生变化，payload 为新尺寸。
const BOARD_RESIZED: StringName = &"board_resized"

## 请求棋盘在游戏中动态扩建，payload 为新尺寸。
const BOARD_LIVE_EXPAND_REQUESTED: StringName = &"board_live_expand_requested"


# --- 回放 ---

## 请求回放前进一步。
const REPLAY_NEXT_STEP: StringName = &"replay_next_step"

## 请求回放后退一步。
const REPLAY_PREV_STEP: StringName = &"replay_prev_step"


# --- HUD ---

## 请求刷新 HUD 显示。
const HUD_UPDATE_REQUESTED: StringName = &"hud_update_requested"


# --- 菜单 UI 事件 (PauseMenu / GameOverMenu -> GameFlowSystem) ---

## 请求从暂停状态恢复游戏。
const RESUME_GAME_REQUESTED: StringName = &"resume_game_requested"

## 请求重新开始当前游戏。
const RESTART_GAME_REQUESTED: StringName = &"restart_game_requested"

## 请求从游戏内返回主菜单。
const RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED: StringName = &"return_to_main_menu_from_game_requested"


# --- 测试工具 (TestPanel) ---

## 测试面板请求指定类型的可生成数值列表，payload 为类型 ID。
const TEST_VALUES_REQUESTED: StringName = &"test_values_requested"

## 测试面板请求重置棋盘并调整大小，payload 为新尺寸。
const TEST_RESET_RESIZE_REQUESTED: StringName = &"test_reset_resize_requested"

## 测试面板请求动态扩建棋盘，payload 为新尺寸。
const TEST_LIVE_EXPAND_REQUESTED: StringName = &"test_live_expand_requested"
