## GameOverState: 游戏结束状态。
##
## 停止输入，触发结算逻辑。纯代码实现。
class_name GameOverState
extends "res://addons/gf/standard/state_machine/pure/gf_state.gd"


# --- 重写方法 ---

## 进入游戏结束状态。
## @param _msg: 状态切换传入的上下文字典。
func enter(_msg: Dictionary = {}) -> void:
	# 清理所有规则，防止在 GameOver 状态下继续触发规则
	var rule_manager: RuleSystem = _get_rule_system()
	if is_instance_valid(rule_manager):
		rule_manager.clear_rules()

	send_simple_event(EventNames.GAME_STATE_CHANGED, EventNames.STATE_GAME_OVER)


func exit() -> void:
	pass


# --- 私有/辅助方法 ---

func _get_rule_system() -> RuleSystem:
	var system_value: Object = get_system(RuleSystem)
	if system_value is RuleSystem:
		var rule_system: RuleSystem = system_value
		return rule_system
	return null
