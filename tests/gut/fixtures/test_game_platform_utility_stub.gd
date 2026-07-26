## TestGamePlatformUtilityStub: 为跨 Feature 测试提供无场景树副作用的平台生命周期边界。
class_name TestGamePlatformUtilityStub
extends GamePlatformUtility


func get_required_utilities() -> Array[Script]:
	return []


func init() -> void:
	ignore_pause = true
	ignore_time_scale = true


func ready() -> void:
	pass


func dispose() -> void:
	pass


## 发布一个已经规范化的平台生命周期事件。
## @param event_type: GFPlatformLifecycleEvent 的稳定事件类型。
## @param sequence: 单调事件序号。
func publish_lifecycle_event(
	event_type: StringName,
	sequence: int = 0
) -> void:
	lifecycle_event_received.emit(GFPlatformLifecycleEvent.new().configure(
		event_type,
		&"test_platform",
		{},
		sequence
	))
