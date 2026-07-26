## 验证项目平台边界基于 GF 平台契约工作。
extends GutTest


# --- 测试用例 ---

func test_runtime_context_is_defensive_copy_with_capabilities() -> void:
	var adapter: FakePlatformAdapter = FakePlatformAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	assert_true(GFVariantData.get_option_bool(setup, "configured"), "init 前应允许注入平台适配器。")

	var first: GFPlatformRuntimeContext = utility.get_runtime_context()
	assert_not_null(first)
	assert_true(first.platform_id == &"test_platform", "应返回测试平台上下文。")
	assert_true(utility.has_capability(GamePlatformUtility.CAPABILITY_STORAGE_LOCAL))
	first.platform_id = &"mutated"
	assert_true(
		utility.get_runtime_context().platform_id == &"test_platform",
		"外部修改不得污染内部上下文。"
	)

	await _dispose_platform_architecture(setup)


func test_lifecycle_events_receive_monotonic_sequence() -> void:
	var adapter: FakePlatformAdapter = FakePlatformAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var sink: EventSink = EventSink.new()
	var _connected: int = utility.lifecycle_event_received.connect(sink.capture)

	adapter.publish(GFPlatformLifecycleEvent.TYPE_BACKGROUND)
	adapter.publish(GFPlatformLifecycleEvent.TYPE_FOREGROUND)

	assert_true(sink.events.size() == 2, "应收到两个生命周期事件。")
	assert_true(sink.events[0].sequence == 1, "第一个事件序号应为 1。")
	assert_true(sink.events[1].sequence == 2, "第二个事件序号应为 2。")
	assert_true(
		sink.events[0].event_type == GFPlatformLifecycleEvent.TYPE_BACKGROUND,
		"第一个事件应进入后台。"
	)
	assert_true(
		sink.events[1].event_type == GFPlatformLifecycleEvent.TYPE_FOREGROUND,
		"第二个事件应回到前台。"
	)

	await _dispose_platform_architecture(setup)


func test_bridge_contract_is_covered_and_unknown_sdk_call_fails_explicitly() -> void:
	var adapter: FakePlatformAdapter = FakePlatformAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)

	var report: Dictionary = utility.get_bridge_contract_report()
	assert_true(GFVariantData.get_option_bool(report, "ok"), str(report))

	var request: GFPlatformBridgeRequest = GFPlatformBridgeRequest.new().configure(
		&"request.test",
		GamePlatformUtility.CONTRACT_SDK_BRIDGE,
		&"login"
	)
	var handle: GFPlatformRequestHandle = utility.invoke_bridge(request)
	assert_not_null(handle, "平台请求必须返回 GF 终态句柄。")
	var result: GFPlatformBridgeResult = handle.get_result()
	assert_not_null(result, "同步拒绝请求应立即生成终态结果。")
	assert_false(result.ok)
	assert_true(result.status == &"unsupported", "未知 bridge 操作应明确返回 unsupported。")
	assert_true(result.request_id == &"request.test", "bridge 结果应保留请求 ID。")

	await _dispose_platform_architecture(setup)


func test_clipboard_write_uses_declared_platform_capability() -> void:
	var adapter: FakePlatformAdapter = FakePlatformAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)

	assert_true(
		utility.has_capability(GamePlatformUtility.CAPABILITY_CLIPBOARD_WRITE),
		"平台必须先声明剪贴板写入能力。"
	)
	assert_true(
		utility.copy_text_to_clipboard("棋盘摘要"),
		"用户主动复制应由项目平台边界转交 adapter。"
	)
	assert_true(adapter.clipboard_text == "棋盘摘要")
	assert_false(
		utility.copy_text_to_clipboard(""),
		"空文本不得进入平台剪贴板。"
	)

	await _dispose_platform_architecture(setup)


func test_local_clipboard_write_accepts_request_without_immediate_readback() -> void:
	var adapter: DelayedClipboardLocalAdapter = DelayedClipboardLocalAdapter.new()

	assert_true(
		adapter.create_runtime_context().has_capability(
			GamePlatformAdapter.CAPABILITY_CLIPBOARD_WRITE
		),
		"运行时明确支持写入时，本地 adapter 必须如实声明能力。"
	)
	assert_true(
		adapter.copy_text_to_clipboard("延迟可见文本"),
		"写入请求已被平台接受时，不得再要求同步读回相同文本。"
	)
	assert_true(adapter.clipboard_text == "延迟可见文本")
	assert_true(adapter.write_count == 1, "每次复制请求只应提交一次平台写入。")


func test_local_clipboard_capability_is_absent_when_runtime_does_not_support_it() -> void:
	var adapter: UnsupportedClipboardLocalAdapter = (
		UnsupportedClipboardLocalAdapter.new()
	)

	assert_false(
		adapter.create_runtime_context().has_capability(
			GamePlatformAdapter.CAPABILITY_CLIPBOARD_WRITE
		),
		"Web/移动运行时未声明 feature 时不得乐观暴露剪贴板能力。"
	)
	assert_false(adapter.copy_text_to_clipboard("不可写文本"))
	assert_true(adapter.write_count == 0, "无能力时不得向 DisplayServer 提交写入。")


# --- 私有/辅助方法 ---

func _create_platform_architecture(adapter: GamePlatformAdapter) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var runtime: GFPlatformRuntime = GFPlatformRuntime.new()
	var utility: GamePlatformUtility = GamePlatformUtility.new()
	var configured: bool = utility.configure_adapter(adapter)
	await architecture.register_utility(GFPlatformRuntime, runtime)
	await architecture.register_utility(GamePlatformUtility, utility)
	await architecture.init()
	return {
		"architecture": architecture,
		"configured": configured,
		"utility": utility,
	}


func _get_platform_utility(setup: Dictionary) -> GamePlatformUtility:
	var value: Variant = GFVariantData.get_option_value(setup, "utility")
	if value is GamePlatformUtility:
		var utility: GamePlatformUtility = value
		return utility
	return null


func _get_architecture(setup: Dictionary) -> GFArchitecture:
	var value: Variant = GFVariantData.get_option_value(setup, "architecture")
	if value is GFArchitecture:
		var architecture: GFArchitecture = value
		return architecture
	return null


func _dispose_platform_architecture(setup: Dictionary) -> void:
	var architecture: GFArchitecture = _get_architecture(setup)
	if architecture != null:
		architecture.dispose()
	await get_tree().process_frame


# --- 内部类 ---

class FakePlatformAdapter extends GamePlatformAdapter:
	var clipboard_text: String = ""


	func _init() -> void:
		adapter_id = &"platform.adapter.test"


	func is_available() -> bool:
		return true


	func create_runtime_context() -> GFPlatformRuntimeContext:
		return GFPlatformRuntimeContext.new().configure(&"test_platform", {
			"adapter_id": adapter_id,
			"display_name": "Test Platform",
			"capability_ids": PackedStringArray([
				String(CAPABILITY_LIFECYCLE),
				String(CAPABILITY_STORAGE_LOCAL),
				String(CAPABILITY_CLIPBOARD_WRITE),
			]),
			"window_size": Vector2i(800, 600),
		})


	## 记录测试剪贴板请求。
	## @param text: 要写入的纯文本。
	## @return: 非空文本返回 true。
	func copy_text_to_clipboard(text: String) -> bool:
		if text.is_empty():
			return false
		clipboard_text = text
		return true


	## 发布测试生命周期事件。
	## @param event_type: 生命周期事件类型。
	func publish(event_type: StringName) -> void:
		var _published: bool = emit_lifecycle_event(GFPlatformLifecycleEvent.new().configure(
			event_type,
			&"test_platform"
		))


class EventSink extends RefCounted:
	var events: Array[GFPlatformLifecycleEvent] = []


	## 收集平台生命周期事件。
	## @param event: 待收集的平台生命周期事件。
	func capture(event: GFPlatformLifecycleEvent) -> void:
		events.append(event)


class DelayedClipboardLocalAdapter extends LocalPlatformAdapter:
	var clipboard_text: String = ""
	var write_count: int = 0


	func _has_clipboard_write_support() -> bool:
		return true


	func _set_clipboard_text(text: String) -> void:
		clipboard_text = text
		write_count += 1


class UnsupportedClipboardLocalAdapter extends DelayedClipboardLocalAdapter:
	func _has_clipboard_write_support() -> bool:
		return false
