# scripts/core/replay_input_source.gd

## ReplayInputSource: 实现了从回放数据生成动作的策略。
##
## 该节点在初始化时接收一个 ReplayData 资源，并提供一个接口
## 来播放指定索引的动作。它本身是无状态的。
class_name ReplayInputSource
extends BaseInputSource

# --- 私有变量 ---
var _replay_data: ReplayData


# --- 公共方法 ---

## 使用一个 ReplayData 资源来初始化此输入源。
func initialize(p_replay_data: ReplayData) -> void:
	_replay_data = p_replay_data


## 播放指定索引的动作。
func play_step(step_index: int) -> void:
	if not is_instance_valid(_replay_data):
		push_error("ReplayInputSource: ReplayData 无效。")
		return

	if step_index >= 0 and step_index < _replay_data.actions.size():
		var action = _replay_data.actions[step_index]
		action_triggered.emit(action)
	else:
		push_warning("ReplayInputSource: 尝试播放一个越界的步骤索引: %d" % step_index)


## 获取总步数。
func get_total_steps() -> int:
	if not is_instance_valid(_replay_data):
		return 0
	return _replay_data.actions.size()
