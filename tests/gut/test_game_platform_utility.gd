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
			]),
			"window_size": Vector2i(800, 600),
		})


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
