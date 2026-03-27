# scripts/global/event_names.gd

## EventNames: 集中管理所有 GF 简单事件的名称常量。
##
## 使用方式: EventNames.SCENE_WILL_CHANGE （取代硬编码字符串 &"scene_will_change"）
## 这样做的好处：
## - 防止拼写错误导致的静默 bug
## - IDE 可以跳转到定义、自动补全
## - 重命名事件时只需修改一处
class_name EventNames
extends RefCounted


# --- 场景 / 生命周期 ---

## 场景即将切换（在卸载旧场景前发出）。
const SCENE_WILL_CHANGE: StringName = &"scene_will_change"

## 请求切换场景。
const SCENE_CHANGE_REQUESTED: StringName = &"scene_change_requested"

## 请求返回主菜单（SceneRouterSystem 监听）。
const RETURN_TO_MAIN_MENU_REQUESTED: StringName = &"return_to_main_menu_requested"


# --- 游戏初始化 ---

## 请求启动游戏初始化流程（GameInitSystem 监听）。
const REQUEST_GAME_INITIALIZATION: StringName = &"request_game_initialization"

## 请求棋盘层面的初始化（RuleSystem 监听）。
const REQUEST_BOARD_INITIALIZATION: StringName = &"request_board_initialization"


# --- 游戏状态 ---

## 游戏状态发生变化（Playing / GameOver）。payload: StringName
const GAME_STATE_CHANGED: StringName = &"game_state_changed"

## 游戏状态：就绪（初始状态）。
const STATE_READY: StringName = &"Ready"

## 游戏状态：正在进行。
const STATE_PLAYING: StringName = &"Playing"

## 游戏状态：游戏结束。
const STATE_GAME_OVER: StringName = &"GameOver"

## 游戏判负（game_over_rule 触发）。
const GAME_LOST: StringName = &"game_lost"

## 游戏状态被测试工具污染。
const GAME_STATE_TAINTED: StringName = &"game_state_tainted"


# --- 玩家操作 ---

## 请求撤销上一步。
const UNDO_REQUESTED: StringName = &"undo_requested"

## 请求保存书签。
const SAVE_BOOKMARK_REQUESTED: StringName = &"save_bookmark_requested"

## 请求暂停 UI。
const UI_PAUSE_REQUESTED: StringName = &"ui_pause_requested"

## 切换暂停菜单显示状态。
const TOGGLE_PAUSE_UI: StringName = &"toggle_pause_ui"


# --- 回合 / 得分 ---

## 当前回合结束。
const TURN_FINISHED: StringName = &"turn_finished"

## 得分更新。payload: int (增量)
const SCORE_UPDATED: StringName = &"score_updated"

## 怪物被击杀。
const MONSTER_KILLED: StringName = &"monster_killed"

## 请求生成方块（SpawnRule 发出）。payload: Dictionary (tile_data)
const SPAWN_TILE_REQUESTED: StringName = &"spawn_tile_requested"


# --- 棋盘 ---

## 棋盘请求播放一段动画序列。payload: instructions: Array[Dictionary]
const BOARD_ANIMATION_REQUESTED: StringName = &"board_animation_requested"

## 棋盘请求播放撤回的逆向平滑动画。payload: [snapshot: Dictionary, reverse_target_map: Dictionary]
const BOARD_UNDO_ANIMATION_REQUESTED: StringName = &"board_undo_animation_requested"

## 请求全量刷新棋盘（如撤回操作）。payload: Dictionary (grid_snapshot)
const BOARD_REFRESH_REQUESTED: StringName = &"board_refresh_requested"

## 棋盘大小发生变化。payload: int (新大小)
const BOARD_RESIZED: StringName = &"board_resized"


# --- 回放 ---

## 回放下一步。
const REPLAY_NEXT_STEP: StringName = &"replay_next_step"

## 回放上一步。
const REPLAY_PREV_STEP: StringName = &"replay_prev_step"


# --- HUD ---

## 请求更新 HUD 显示。
const HUD_UPDATE_REQUESTED: StringName = &"hud_update_requested"

## 在 HUD 上显示一条临时消息。payload: [message: String, duration: float]
const SHOW_HUD_MESSAGE: StringName = &"show_hud_message"


# --- 菜单 UI 事件 (PauseMenu / GameOverMenu → GameFlowSystem) ---

## 请求恢复游戏。
const RESUME_GAME_REQUESTED: StringName = &"resume_game_requested"

## 请求重新开始游戏。
const RESTART_GAME_REQUESTED: StringName = &"restart_game_requested"

## 请求从游戏中返回主菜单。
const RETURN_TO_MAIN_MENU_FROM_GAME_REQUESTED: StringName = &"return_to_main_menu_from_game_requested"


# --- 测试工具 ---

## 请求重置并调整棋盘大小。payload: [new_size: int]
const RESET_AND_RESIZE_WITH_PARAMS: StringName = &"reset_and_resize_with_params"


# --- 测试工具 (TestPanel) ---

## 测试面板请求强制生成。payload: [pos: Vector2i, value: int, type_id: int]
const TEST_SPAWN_REQUESTED: StringName = &"test_spawn_requested"

## 测试面板请求指定类型的数值列表。payload: type_id: int
const TEST_VALUES_REQUESTED: StringName = &"test_values_requested"

## 测试面板请求重置并调整大小。payload: new_size: int
const TEST_RESET_RESIZE_REQUESTED: StringName = &"test_reset_resize_requested"

## 测试面板请求动态扩建。payload: new_size: int
const TEST_LIVE_EXPAND_REQUESTED: StringName = &"test_live_expand_requested"
