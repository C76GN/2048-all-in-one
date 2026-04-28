# scripts/states/gf_state_playing.gd

## GFStatePlaying: 游戏进行中状态。
##
## 激活输入源，允许玩家操作。纯代码实现。
class_name GFStatePlaying
extends GFState


# --- 重写方法 ---

func enter(_msg: Dictionary = {}) -> void:
	send_simple_event(EventNames.GAME_STATE_CHANGED, EventNames.STATE_PLAYING)


func exit() -> void:
	pass
