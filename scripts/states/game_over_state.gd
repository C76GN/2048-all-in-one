## GameOverState: 游戏结束状态。
##
## 停止输入，触发结算逻辑。纯代码实现。
class_name GameOverState
extends GFState


# --- 重写方法 ---

## 进入游戏结束状态。
## @param _msg: 状态切换传入的上下文字典。
func enter(_msg: Dictionary = {}) -> void:
	# 清理所有规则，防止在 GameOver 状态下继续触发规则
	var rule_manager: RuleSystem = get_system(RuleSystem) as RuleSystem
	if rule_manager:
		rule_manager.clear_rules()

	send_simple_event(EventNames.GAME_STATE_CHANGED, EventNames.STATE_GAME_OVER)


func exit() -> void:
	pass
