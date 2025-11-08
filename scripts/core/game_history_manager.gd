# scripts/core/game_history_manager.gd

## GameHistoryManager: 负责管理游戏状态历史记录的专用节点。
##
## 该类封装了所有与状态快照、历史追溯（撤回/Undo）和加载/保存历史
## 相关的功能。它将这部分复杂的逻辑从 GamePlay 中分离出来，使其职责更纯粹。
class_name GameHistoryManager
extends Node

# --- 私有变量 ---

## 存储完整游戏状态快照的数组。数组中的每个元素都是一个字典。
var _history: Array[Dictionary] = []


# --- 公共方法 ---

## 清空所有历史记录，用于开始新游戏。
func clear() -> void:
	_history.clear()


## 将一个新的游戏状态快照保存到历史记录中。
## @param state: 一个包含当前游戏完整状态的字典。
func save_state(state: Dictionary) -> void:
	_history.push_back(state)


## 执行一次“撤回”操作。
##
## 它会移除历史记录中的最后一个状态，并返回前一个状态。
## @remark 调用此函数前，应先使用 can_undo() 检查操作是否有效。
## @return: 返回恢复后应应用的游戏状态字典。
func undo() -> Dictionary:
	# 假定调用者已经通过 can_undo() 确认了操作的有效性。
	# 移除当前状态。
	_history.pop_back()
	# 返回撤回后的新当前状态（即之前的状态）。
	return _history.back()


## 检查当前是否可以执行撤回操作。
## @return: 如果历史记录中有多于一个状态，则返回 true。
func can_undo() -> bool:
	return _history.size() > 1


## 加载一个完整的历史记录数组。
## 这在从书签（存档）恢复游戏时使用。
## @param history_array: 从 BookmarkData 加载的历史记录。
func load_history(history_array: Array[Dictionary]) -> void:
	_history = history_array


## 获取当前完整的历史记录数组。
## 这在创建书签（存档）时使用。
## @return: 包含所有历史状态的数组。
func get_history() -> Array[Dictionary]:
	return _history


## 获取当前历史记录的长度。
func get_history_size() -> int:
	return _history.size()


## 提取并返回用于保存回放的玩家动作序列。
## @return: 一个包含所有玩家输入动作 (Vector2i) 的数组。
func get_action_sequence() -> Array[Vector2i]:
	var actions: Array[Vector2i] = []
	# 从索引1开始，因为索引0是初始状态，没有关联的动作。
	for i in range(1, _history.size()):
		actions.append(_history[i]["action"])
	return actions
