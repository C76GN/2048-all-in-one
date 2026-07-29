## GamePlatformAdapter: 项目平台 SDK 的 GF adapter 基类。
##
## 项目只定义稳定契约与能力 ID；状态、请求句柄、超时和生命周期序号由
## GFPlatformAdapter / GFPlatformRuntime 统一管理。
class_name GamePlatformAdapter
extends GFPlatformAdapter


# --- 常量 ---

const CONTRACT_RUNTIME_CONTEXT: StringName = &"platform.runtime_context"
const CONTRACT_LIFECYCLE: StringName = &"platform.lifecycle"
const CONTRACT_SDK_BRIDGE: StringName = &"platform.sdk_bridge"

const METHOD_RUNTIME_CONTEXT_QUERY: StringName = &"query"

const CAPABILITY_STORAGE_LOCAL: StringName = &"platform.storage.local"
const CAPABILITY_HTTP: StringName = &"platform.http"
const CAPABILITY_AUDIO: StringName = &"platform.audio"
const CAPABILITY_LIFECYCLE: StringName = &"platform.lifecycle"
const CAPABILITY_SAFE_AREA: StringName = &"display.safe_area"
const CAPABILITY_WINDOW_RESIZE: StringName = &"display.window_resize"
const CAPABILITY_POINTER: StringName = &"input.pointer"
const CAPABILITY_TOUCH: StringName = &"input.touch"
const CAPABILITY_COMPATIBILITY_RENDERER: StringName = &"renderer.gl_compatibility"
const CAPABILITY_CLIPBOARD_WRITE: StringName = &"platform.clipboard.write"


# --- 公共变量 ---

var adapter_id: StringName = &"platform.adapter.base"


# --- 公共方法 ---

func is_available() -> bool:
	return false


func create_runtime_context() -> GFPlatformRuntimeContext:
	return GFPlatformRuntimeContext.new().configure(&"unknown", {
		"adapter_id": adapter_id,
		"display_name": "Unknown platform",
	})


## 在注册到 GFPlatformRuntime 前冻结 adapter 身份与契约。
func prepare() -> bool:
	if not is_available() or get_state() != GFPlatformAdapter.State.CREATED:
		return false
	var context: GFPlatformRuntimeContext = create_runtime_context()
	if context == null:
		return false
	return configure(
		adapter_id,
		context.platform_id,
		PackedStringArray([
			String(CONTRACT_RUNTIME_CONTEXT),
		]),
		_make_contract_descriptors(),
		context
	)


## 重新采集并发布平台上下文。
func refresh_context() -> bool:
	return _publish_context(create_runtime_context())


## 接收由平台宿主转发的 Godot 通知。
## @param _what: Godot 通知标识。
func handle_notification(_what: int) -> void:
	pass


func get_bridge_report_descriptor() -> Dictionary:
	var configured_adapter_id: StringName = get_adapter_id()
	var descriptor_adapter_id: StringName = (
		configured_adapter_id if configured_adapter_id != &"" else adapter_id
	)
	var contract_ids: PackedStringArray = get_contract_ids()
	if contract_ids.is_empty():
		contract_ids = PackedStringArray([
			String(CONTRACT_RUNTIME_CONTEXT),
		])
	var context: GFPlatformRuntimeContext = (
		get_context() if configured_adapter_id != &"" else create_runtime_context()
	)
	var capability_ids: PackedStringArray = PackedStringArray()
	if context != null and context.capabilities != null:
		capability_ids = context.capabilities.capabilities.duplicate()
	var descriptor_entries: Array[Dictionary] = []
	if configured_adapter_id != &"":
		for descriptor: GFPlatformContractDescriptor in get_contract_descriptors():
			descriptor_entries.append(descriptor.to_dict())
	return {
		"adapter_id": descriptor_adapter_id,
		"contract_ids": contract_ids,
		"enabled": is_available() and get_state() not in [State.FAILED, State.SHUTDOWN],
		"capabilities": capability_ids,
		"metadata": {
			"platform_id": context.platform_id if context != null else &"unknown",
			"contract_descriptors": descriptor_entries,
		},
	}


## 把玩家主动请求的文本写入平台剪贴板。
## @param _text: 已本地化、可直接复制的纯文本。
## @return: 平台确认写入成功时返回 true；不支持或失败时返回 false。
func copy_text_to_clipboard(_text: String) -> bool:
	return false


# --- 可重写钩子 / 虚方法 ---

## 默认项目 adapter 明确拒绝未实现的 SDK 调用。
func _dispatch(
	request: GFPlatformBridgeRequest,
	handle: GFPlatformRequestHandle
) -> bool:
	if (
		request != null
		and request.contract_id == CONTRACT_RUNTIME_CONTEXT
		and request.method_id == METHOD_RUNTIME_CONTEXT_QUERY
	):
		var context: GFPlatformRuntimeContext = get_context()
		return _succeed_request(
			handle,
			context.to_dict() if context != null else {}
		)
	return _fail_request(
		handle,
		&"unsupported",
		"当前平台适配器不支持该 SDK 桥接请求。"
	)


# --- 受保护方法 ---

## 向 GF 平台运行时发布生命周期事件。
## @param event: 待发布的规范平台生命周期事件。
func emit_lifecycle_event(event: GFPlatformLifecycleEvent) -> bool:
	return _publish_lifecycle_event(event)


# --- 私有/辅助方法 ---

static func _make_contract_descriptors() -> Array[GFPlatformContractDescriptor]:
	return [
		_make_contract_descriptor(
			CONTRACT_RUNTIME_CONTEXT,
			METHOD_RUNTIME_CONTEXT_QUERY
		),
	]


static func _make_contract_descriptor(
	contract_id: StringName,
	method_id: StringName,
	required_capabilities: PackedStringArray = PackedStringArray()
) -> GFPlatformContractDescriptor:
	var method: GFPlatformContractMethodDescriptor = (
		GFPlatformContractMethodDescriptor.new().configure(
			method_id,
			{
				"required_capability_ids": required_capabilities,
				"max_request_bytes": 4096,
				"max_result_bytes": 4096,
				"max_concurrent_requests": 1,
				"supports_cancellation": false,
			}
		)
	)
	var methods: Array[GFPlatformContractMethodDescriptor] = [method]
	return GFPlatformContractDescriptor.new().configure(
		contract_id,
		"1.0.0",
		methods
	)
