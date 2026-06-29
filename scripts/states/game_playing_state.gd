## GamePlayingState: 游戏进行中状态。
##
## 激活输入源，允许玩家操作。纯代码实现。
class_name GamePlayingState
extends "res://addons/gf/standard/state_machine/pure/gf_state.gd"


# --- 重写方法 ---

## 进入游戏进行状态。
## @param _msg: 状态切换传入的上下文字典。
func enter(_msg: Dictionary = {}) -> void:
	send_simple_event(EventNames.GAME_STATE_CHANGED, EventNames.STATE_PLAYING)


func exit() -> void:
	pass
