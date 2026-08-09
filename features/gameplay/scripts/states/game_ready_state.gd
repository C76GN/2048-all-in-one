## GameReadyState: 游戏准备状态。
##
## 此时游戏数据已加载，等待开始信号或动画完成。纯代码实现。
class_name GameReadyState
extends GFState


# --- 重写方法 ---

## 进入准备状态。
## @param _msg: 状态切换传入的上下文字典。
func enter(_msg: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass
