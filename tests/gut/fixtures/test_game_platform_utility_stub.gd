## TestGamePlatformUtilityStub: 为跨 Feature 测试提供无场景树副作用的平台生命周期边界。
class_name TestGamePlatformUtilityStub
extends GamePlatformUtility


# --- 公共变量 ---

var clipboard_text: String = ""
var clipboard_write_succeeds: bool = true


# --- 私有变量 ---

var _test_clipboard_request_serial: int = 0
var _clock: GFManualClock = GFManualClock.new()


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return []


func init() -> void:
	ignore_pause = true
	ignore_time_scale = true


func ready() -> void:
	pass


func dispose() -> void:
	clipboard_text = ""
	_test_clipboard_request_serial = 0


# --- 公共方法 ---

## 记录测试中的平台剪贴板写入。
## @param text: 要写入的纯文本。
## @return: 由 clipboard_write_succeeds 控制的确定性 GF 平台终态句柄。
func copy_text_to_clipboard(text: String) -> GFPlatformRequestHandle:
	_test_clipboard_request_serial += 1
	var request: GFPlatformBridgeRequest = GFPlatformBridgeRequest.new().configure(
		StringName("test_clipboard_%d" % _test_clipboard_request_serial),
		CONTRACT_CLIPBOARD,
		METHOD_CLIPBOARD_WRITE,
		{&"text": text}
	)
	var handle: GFPlatformRequestHandle = GFPlatformRequestHandle.new()
	var _configured: bool = handle.configure_from_platform_layer(
		request,
		_clock
	)
	if text.is_empty() or not clipboard_write_succeeds:
		var _failed: bool = handle.fail_from_platform_layer(
			&"clipboard_write_failed",
			"Test clipboard write failed."
		)
		return handle
	clipboard_text = text
	var _succeeded: bool = handle.succeed_from_platform_layer(
		{&"written": true},
		&"written"
	)
	return handle


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
