# global/replay_data.gd

## ReplayData: 定义了单个游戏回放所需全部信息的自定义资源。
##
## 该资源封装了复现一局游戏所需的一切：初始状态（种子、模式、尺寸）、
## 玩家的完整操作序列，以及用于导航的快照标记。
class_name ReplayData
extends Resource

## 回放保存时的Unix时间戳，可用作唯一标识符。
@export var timestamp: int = 0
## 该局游戏使用的模式配置资源路径。
@export var mode_config_path: String = ""
## 游戏开始时的初始RNG种子。
@export var initial_seed: int = 0
## 棋盘尺寸。
@export var grid_size: int = 4
## 最终得分。
@export var final_score: int = 0
## 玩家的每一步有效操作。存储为Vector2i以代表方向。
@export var actions: Array[Vector2i] = []
## 快照数组。存储的是 `actions` 数组的索引，标记了玩家在哪一步创建了快照。
@export var snapshot_indices: Array[int] = []

var file_path: String = ""
