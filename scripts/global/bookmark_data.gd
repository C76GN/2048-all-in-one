# global/bookmark_data.gd

## BookmarkData: 定义了单个游戏书签所需全部信息的自定义资源。
##
## 该资源封装了恢复一局游戏到特定时间点所需的一切：模式、RNG状态、
## 棋盘布局、分数等。它是一个完整的游戏状态快照。
class_name BookmarkData
extends Resource

# --- 导出变量 ---

## 书签保存时的Unix时间戳，可用作唯一标识符。
@export var timestamp: int = 0

## 该局游戏使用的模式配置资源路径。
@export var mode_config_path: String = ""

## 游戏状态的游戏种子。
@export var initial_seed: int = 0

## 书签保存时的分数。
@export var score: int = 0

## 书签保存时的移动次数。
@export var move_count: int = 0

## 书签保存时消灭的怪物数。
@export var monsters_killed: int = 0

## RNG生成器的内部状态，用于精确恢复。
@export var rng_state: int = 0

## 完整的棋盘状态快照。
@export var board_snapshot: Dictionary = {}

## 保存完整的撤回历史记录。
@export var game_state_history: Array[Dictionary] = []


# --- 公共变量 ---

## 此书签资源在文件系统中的完整路径。
## @remark 主要由 BookmarkManager 在加载和删除时内部使用。
var file_path: String = ""
