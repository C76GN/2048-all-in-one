## 验证项目平台边界基于 GF 平台契约工作。
extends GutTest


# --- 测试用例 ---

func test_project_adapter_satisfies_gf_descriptor_conformance() -> void:
	var adapter: FakePlatformAdapter = FakePlatformAdapter.new()
	assert_true(adapter.prepare(), "测试 Adapter 应冻结 GF 平台身份和契约描述符。")
	var required_methods: Dictionary = {
		String(GamePlatformAdapter.CONTRACT_RUNTIME_CONTEXT): PackedStringArray([
			String(GamePlatformAdapter.METHOD_RUNTIME_CONTEXT_QUERY),
		]),
		String(GamePlatformAdapter.CONTRACT_CLIPBOARD): PackedStringArray([
			String(GamePlatformAdapter.METHOD_CLIPBOARD_WRITE),
		]),
	}
	var contract_versions: Dictionary = {
		String(GamePlatformAdapter.CONTRACT_RUNTIME_CONTEXT): "1.0.0",
		String(GamePlatformAdapter.CONTRACT_CLIPBOARD): "1.0.0",
	}
	var options: Dictionary = {
		"required_contract_ids": PackedStringArray(required_methods.keys()),
		"required_contract_versions": contract_versions,
		"required_capability_ids": PackedStringArray([
			String(GamePlatformAdapter.CAPABILITY_LIFECYCLE),
			String(GamePlatformAdapter.CAPABILITY_STORAGE_LOCAL),
		]),
		"required_methods": required_methods,
		"require_descriptors": true,
	}

	var report: GFValidationReport = GFPlatformAdapterConformance.validate(
		adapter,
		options
	)
	assert_true(report.is_ok(), str(report.to_dict()))
	var inspection: Dictionary = GFPlatformAdapterConformance.inspect(
		adapter,
		options
	)
	assert_true(
		GFVariantData.get_option_bool(inspection, "ok"),
		"GF 平台一致性附录应保持通过：%s" % str(inspection)
	)
	assert_true(
		GFVariantData.get_option_bool(
			GFVariantData.get_option_dictionary(inspection, "bridge_coverage"),
			"ok"
		),
		"项目 Adapter 必须覆盖声明的全部平台 bridge contract。"
	)
	var initialization: GFAsyncCompletion = adapter.initialize()
	assert_true(initialization.is_successful(), "测试 Adapter 应同步进入 READY。")
	var query: GFPlatformBridgeRequest = GFPlatformBridgeRequest.new().configure(
		&"request.runtime_context",
		GamePlatformAdapter.CONTRACT_RUNTIME_CONTEXT,
		GamePlatformAdapter.METHOD_RUNTIME_CONTEXT_QUERY
	)
	var query_handle: GFPlatformRequestHandle = adapter.invoke(query)
	var query_result: GFPlatformBridgeResult = query_handle.get_result()
	assert_not_null(query_result, "已声明的 runtime context query 必须产生终态。")
	if query_result != null:
		assert_true(query_result.ok, "已声明的 runtime context query 必须可实际路由。")
		var context_data: Dictionary = GFVariantData.to_dictionary(
			query_result.value
		)
		assert_true(
			GFVariantData.get_option_string_name(
				context_data,
				"platform_id"
			) == &"test_platform",
			"runtime context query 必须返回当前平台身份。"
		)
	adapter.shutdown()


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


func test_architecture_activation_waits_for_delayed_platform_initialization() -> void:
	var adapter: DelayedInitializationPlatformAdapter = (
		DelayedInitializationPlatformAdapter.new()
	)
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)

	assert_true(adapter.initialize_started, "平台 adapter 应在 activation 阶段开始初始化。")
	assert_true(adapter.is_ready(), "GFArchitecture.init 返回前 adapter 必须形成 READY 终态。")
	assert_true(
		GFVariantData.get_option_bool(
			utility.get_debug_snapshot(),
			"accepting_runtime_work"
		),
		"平台 activation 成功后才可开放运行期请求。"
	)
	assert_not_null(utility.get_runtime_context(), "activation 成功应发布平台上下文。")

	await _dispose_platform_architecture(setup)


func test_headless_fact_is_published_by_local_platform_adapter() -> void:
	var adapter: HeadlessLocalPlatformAdapter = HeadlessLocalPlatformAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var context: GFPlatformRuntimeContext = utility.get_runtime_context()

	assert_not_null(context)
	if context != null:
		assert_true(
			GFVariantData.get_option_bool(context.metadata, "headless"),
			"DisplayServer headless 事实应只由平台 Adapter 发布。"
		)
		assert_true(
			GFVariantData.get_option_string(
				context.metadata,
				"display_server_name"
			) == "headless"
		)
	assert_true(
		utility.is_headless_runtime(),
		"其他 Feature 应通过 GFPlatformRuntimeContext 消费 headless 事实。"
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


func test_quiesce_disconnects_owned_signals_and_rejects_new_requests() -> void:
	var adapter: FakePlatformAdapter = FakePlatformAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var sink: EventSink = EventSink.new()
	var _connected: int = utility.lifecycle_event_received.connect(sink.capture)

	var completion: GFAsyncCompletion = utility.begin_quiesce(GFAsyncScope.new())
	assert_true(completion.is_successful(), "平台 quiesce 应形成明确成功终态。")
	adapter.publish(GFPlatformLifecycleEvent.TYPE_BACKGROUND)
	assert_true(sink.events.is_empty(), "quiesce 后 runtime Signal 不得回调平台 owner。")
	assert_null(
		utility.copy_text_to_clipboard("quiesced"),
		"quiesce 后不得再接纳新的平台请求。"
	)

	await _dispose_platform_architecture(setup)


func test_quiesce_settles_pending_activation_before_signal_teardown() -> void:
	var adapter: PendingInitializationPlatformAdapter = (
		PendingInitializationPlatformAdapter.new()
	)
	var setup: Dictionary = _create_pending_platform_utility_setup(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var activation: GFAsyncCompletion = utility.begin_activation(GFAsyncScope.new())
	var initialization_value: Variant = utility.get("_adapter_initialization")
	var initialization: GFAsyncCompletion = null
	if initialization_value is GFAsyncCompletion:
		initialization = initialization_value

	assert_true(activation.is_pending(), "受控 Adapter 应让平台 activation 保持 pending。")
	assert_not_null(initialization)
	var quiesce: GFAsyncCompletion = utility.begin_quiesce(GFAsyncScope.new())

	assert_true(quiesce.is_successful(), "平台 quiesce 应同步形成成功终态。")
	assert_true(activation.is_cancelled(), "quiesce 必须终结外层架构 activation。")
	if initialization != null:
		assert_true(initialization.is_cancelled(), "quiesce 必须同时取消底层 Adapter 初始化。")
	var signal_value: Variant = setup.get("signal_utility")
	if signal_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = signal_value
		assert_true(signal_utility.get_connection_count() == 0, "终态收敛后才可断开 owner 信号。")

	_dispose_pending_platform_utility_setup(setup)


func test_dispose_settles_pending_activation_before_signal_teardown() -> void:
	var adapter: PendingInitializationPlatformAdapter = (
		PendingInitializationPlatformAdapter.new()
	)
	var setup: Dictionary = _create_pending_platform_utility_setup(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var activation: GFAsyncCompletion = utility.begin_activation(GFAsyncScope.new())
	var initialization_value: Variant = utility.get("_adapter_initialization")
	var initialization: GFAsyncCompletion = null
	if initialization_value is GFAsyncCompletion:
		initialization = initialization_value

	assert_true(activation.is_pending(), "受控 Adapter 应让平台 activation 保持 pending。")
	utility.dispose()

	assert_true(activation.is_cancelled(), "dispose 必须终结外层架构 activation。")
	if initialization != null:
		assert_true(initialization.is_cancelled(), "dispose 必须同时取消底层 Adapter 初始化。")
	var signal_value: Variant = setup.get("signal_utility")
	if signal_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = signal_value
		assert_true(signal_utility.get_connection_count() == 0, "dispose 不得遗留 owner 信号。")

	_dispose_pending_platform_utility_setup(setup, false)


func test_local_notifications_map_and_deduplicate_focus_lifecycle_pairs() -> void:
	var adapter: DelayedClipboardLocalAdapter = DelayedClipboardLocalAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var sink: EventSink = EventSink.new()
	var _connected: int = utility.lifecycle_event_received.connect(sink.capture)
	watch_signals(utility)

	utility.forward_platform_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	utility.forward_platform_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	utility.forward_platform_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	utility.forward_platform_notification(Node.NOTIFICATION_APPLICATION_RESUMED)

	assert_true(
		sink.events.size() == 2,
		"同一后台/前台转换的 focus 与 pause/resume 通知必须去重。"
	)
	if sink.events.size() == 2:
		assert_true(
			sink.events[0].event_type == GFPlatformLifecycleEvent.TYPE_BACKGROUND
		)
		assert_true(
			sink.events[1].event_type == GFPlatformLifecycleEvent.TYPE_FOREGROUND
		)
		assert_true(sink.events[0].sequence == 1)
		assert_true(sink.events[1].sequence == 2)
	assert_signal_emit_count(
		utility,
		"context_changed",
		1,
		"真正从后台恢复时必须刷新一次上下文，成对 foreground 通知不得重复刷新。"
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
	assert_true(
		result.status == &"unsupported_contract",
		"未声明的 SDK bridge 应在进入项目 dispatch 前明确拒绝。"
	)
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
	var handle: GFPlatformRequestHandle = utility.copy_text_to_clipboard(
		"棋盘摘要"
	)
	assert_not_null(handle, "用户主动复制必须返回 GF 平台请求句柄。")
	var result: GFPlatformBridgeResult = handle.get_result()
	assert_not_null(result, "同步平台写入也必须生成唯一终态结果。")
	if result != null:
		assert_true(result.ok, "声明能力的平台应确认剪贴板写入成功。")
		assert_true(result.status == &"written")
		assert_true(
			GFVariantData.get_option_bool(
				GFVariantData.to_dictionary(result.value),
				&"written"
			)
		)
	assert_true(adapter.clipboard_text == "棋盘摘要")
	var empty_handle: GFPlatformRequestHandle = utility.copy_text_to_clipboard("")
	assert_not_null(empty_handle)
	var empty_result: GFPlatformBridgeResult = empty_handle.get_result()
	assert_not_null(empty_result, "空文本也必须以 typed failure 结束。")
	if empty_result != null:
		assert_false(empty_result.ok)
		assert_true(empty_result.status == &"invalid_clipboard_text")
		assert_true(
			empty_result.request_id != result.request_id,
			"每次剪贴板请求必须拥有唯一 request_id。"
		)

	await _dispose_platform_architecture(setup)


func test_pending_clipboard_result_does_not_call_torn_down_owner() -> void:
	var adapter: PendingClipboardPlatformAdapter = (
		PendingClipboardPlatformAdapter.new()
	)
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	var handle: GFPlatformRequestHandle = utility.copy_text_to_clipboard(
		"异步写入"
	)
	assert_not_null(handle)
	assert_true(handle.is_pending(), "异步 adapter 接受请求后应保留 pending 句柄。")

	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var callback_owner: Node = Node.new()
	var sink: ResultSink = ResultSink.new()
	var connection: GFSignalConnection = signal_utility.connect_signal(
		handle.completed,
		sink.capture,
		callback_owner
	)
	if connection != null:
		var _first_connection: GFSignalConnection = connection.first()
	assert_true(connection != null and connection.is_active())

	signal_utility.disconnect_owner(callback_owner)
	assert_false(connection.is_active(), "HUD owner 退出时必须断开迟到平台回调。")
	callback_owner.free()
	assert_true(adapter.complete_clipboard_write())
	assert_true(handle.is_successful(), "owner 退出不应阻止平台句柄形成终态。")
	assert_true(
		sink.results.is_empty(),
		"owner teardown 后的异步完成不得回调已退出 HUD。"
	)

	signal_utility.dispose()
	await _dispose_platform_architecture(setup)


func test_local_clipboard_write_accepts_request_without_immediate_readback() -> void:
	var adapter: DelayedClipboardLocalAdapter = DelayedClipboardLocalAdapter.new()
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)

	assert_true(utility.has_capability(GamePlatformAdapter.CAPABILITY_CLIPBOARD_WRITE))
	var handle: GFPlatformRequestHandle = utility.copy_text_to_clipboard(
		"延迟可见文本"
	)
	assert_not_null(handle)
	var result: GFPlatformBridgeResult = handle.get_result()
	assert_not_null(result)
	if result != null:
		assert_true(
			result.ok,
			"写入请求已被平台接受时，不得再要求同步读回相同文本。"
		)
	assert_true(adapter.clipboard_text == "延迟可见文本")
	assert_true(adapter.write_count == 1, "每次复制请求只应提交一次平台写入。")

	await _dispose_platform_architecture(setup)


func test_local_clipboard_capability_is_absent_when_runtime_does_not_support_it() -> void:
	var adapter: UnsupportedClipboardLocalAdapter = (
		UnsupportedClipboardLocalAdapter.new()
	)
	var setup: Dictionary = await _create_platform_architecture(adapter)
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	assert_false(
		utility.has_capability(
			GamePlatformAdapter.CAPABILITY_CLIPBOARD_WRITE
		),
		"Web/移动运行时未声明 feature 时不得乐观暴露剪贴板能力。"
	)
	var handle: GFPlatformRequestHandle = utility.copy_text_to_clipboard(
		"不可写文本"
	)
	assert_not_null(handle)
	var result: GFPlatformBridgeResult = handle.get_result()
	assert_not_null(result, "缺少能力也必须由 GF 请求句柄给出唯一失败终态。")
	if result != null:
		assert_false(result.ok)
		assert_true(result.status == &"invalid_contract_request")
	assert_true(adapter.write_count == 0, "无能力时不得向 DisplayServer 提交写入。")

	await _dispose_platform_architecture(setup)


# --- 私有/辅助方法 ---

func _create_platform_architecture(adapter: GamePlatformAdapter) -> Dictionary:
	var architecture: GFArchitecture = GFArchitecture.new()
	var runtime: GFPlatformRuntime = GFPlatformRuntime.new()
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var utility: GamePlatformUtility = GamePlatformUtility.new()
	var configured: bool = utility.configure_adapter(adapter)
	await architecture.register_utility(GFPlatformRuntime, runtime)
	await architecture.register_utility(GFSignalUtility, signal_utility)
	await architecture.register_utility(GamePlatformUtility, utility)
	await architecture.init()
	return {
		"architecture": architecture,
		"configured": configured,
		"utility": utility,
	}


func _create_pending_platform_utility_setup(
	adapter: GamePlatformAdapter
) -> Dictionary:
	var runtime: GFPlatformRuntime = GFPlatformRuntime.new()
	var signal_utility: GFSignalUtility = GFSignalUtility.new()
	var utility: GamePlatformUtility = GamePlatformUtility.new()
	var configured: bool = utility.configure_adapter(adapter)
	utility.init()
	var prepared: bool = adapter.prepare()
	var registered: bool = runtime.register_adapter(adapter)
	utility.set("_runtime", runtime)
	utility.set("_signals", signal_utility)
	utility.set("_adapter_registered", registered)
	utility.call("_bind_runtime_signals")
	return {
		"configured": configured,
		"prepared": prepared,
		"registered": registered,
		"runtime": runtime,
		"signal_utility": signal_utility,
		"utility": utility,
	}


func _dispose_pending_platform_utility_setup(
	setup: Dictionary,
	dispose_utility: bool = true
) -> void:
	var utility: GamePlatformUtility = _get_platform_utility(setup)
	if dispose_utility and utility != null:
		utility.dispose()
	var runtime_value: Variant = setup.get("runtime")
	if runtime_value is GFPlatformRuntime:
		var runtime: GFPlatformRuntime = runtime_value
		runtime.dispose()
	var signal_value: Variant = setup.get("signal_utility")
	if signal_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = signal_value
		signal_utility.dispose()


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


	## 记录由 GF dispatch 路由的测试剪贴板请求。
	## @param text: 要写入的纯文本。
	## @return: 非空文本返回 true。
	func _write_text_to_clipboard(text: String) -> bool:
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


class DelayedInitializationPlatformAdapter extends FakePlatformAdapter:
	var initialize_started: bool = false


	func _initialize(_options: Dictionary) -> void:
		initialize_started = true
		call_deferred(&"_complete_on_next_frame")


	func _complete_on_next_frame() -> void:
		var _completed: bool = _complete_initialization(create_runtime_context())


class PendingInitializationPlatformAdapter extends FakePlatformAdapter:
	func _initialize(_options: Dictionary) -> void:
		pass


class EventSink extends RefCounted:
	var events: Array[GFPlatformLifecycleEvent] = []


	## 收集平台生命周期事件。
	## @param event: 待收集的平台生命周期事件。
	func capture(event: GFPlatformLifecycleEvent) -> void:
		events.append(event)


class ResultSink extends RefCounted:
	var results: Array[GFPlatformBridgeResult] = []


	## 收集平台请求终态。
	## @param result: 待收集的平台请求终态。
	func capture(result: GFPlatformBridgeResult) -> void:
		results.append(result)


class PendingClipboardPlatformAdapter extends FakePlatformAdapter:
	var _pending_clipboard_handle: GFPlatformRequestHandle = null


	func _dispatch(
		request: GFPlatformBridgeRequest,
		handle: GFPlatformRequestHandle
	) -> bool:
		if (
			request != null
			and request.contract_id == CONTRACT_CLIPBOARD
			and request.method_id == METHOD_CLIPBOARD_WRITE
		):
			_pending_clipboard_handle = handle
			return true
		return super._dispatch(request, handle)


	func complete_clipboard_write() -> bool:
		var handle: GFPlatformRequestHandle = _pending_clipboard_handle
		_pending_clipboard_handle = null
		if handle == null:
			return false
		return _succeed_request(
			handle,
			{&"written": true},
			&"written"
		)


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


class HeadlessLocalPlatformAdapter extends DelayedClipboardLocalAdapter:
	func _get_display_server_name() -> String:
		return "headless"
