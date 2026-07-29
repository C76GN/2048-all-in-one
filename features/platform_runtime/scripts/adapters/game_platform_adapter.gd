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
const CONTRACT_CLIPBOARD: StringName = &"platform.clipboard"

const METHOD_RUNTIME_CONTEXT_QUERY: StringName = &"query"
const METHOD_CLIPBOARD_WRITE: StringName = &"write_text"

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
			String(CONTRACT_CLIPBOARD),
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


## 把已校验文本写入平台剪贴板。
##
## Godot 或 SDK 调用只能由 `_dispatch()` 经此受保护钩子抵达，项目调用方不得
## 绕过 GFPlatformRuntime 直接调用平台 API。
## @param _text: 已本地化、可直接复制的非空纯文本。
## @return: 平台接受写入时返回 true。
func _write_text_to_clipboard(_text: String) -> bool:
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
	if (
		request != null
		and request.contract_id == CONTRACT_CLIPBOARD
		and request.method_id == METHOD_CLIPBOARD_WRITE
	):
		var text: String = GFVariantData.get_option_string(
			request.payload,
			&"text"
		)
		if text.is_empty():
			return _fail_request(
				handle,
				&"invalid_clipboard_text",
				"剪贴板写入文本不能为空。"
			)
		if not _write_text_to_clipboard(text):
			return _fail_request(
				handle,
				&"clipboard_write_failed",
				"当前平台未能接受剪贴板写入请求。"
			)
		return _succeed_request(
			handle,
			{&"written": true},
			&"written"
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
		_make_clipboard_contract_descriptor(),
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


static func _make_clipboard_contract_descriptor() -> GFPlatformContractDescriptor:
	var request_fields: Array[GFSchemaField] = [
		GFSchemaField.new().configure(
			&"text",
			GFSchemaField.ValueType.STRING,
			{
				"required": true,
				"allow_null": false,
			}
		),
	]
	var request_schema: GFDictionarySchema = GFDictionarySchema.new().configure(
		&"platform_clipboard_write_request",
		request_fields,
		{"allow_extra_fields": false}
	)
	var result_fields: Array[GFSchemaField] = [
		GFSchemaField.new().configure(
			&"written",
			GFSchemaField.ValueType.BOOL,
			{
				"required": true,
				"allow_null": false,
			}
		),
	]
	var result_schema: GFDictionarySchema = GFDictionarySchema.new().configure(
		&"platform_clipboard_write_result",
		result_fields,
		{"allow_extra_fields": false}
	)
	var method: GFPlatformContractMethodDescriptor = (
		GFPlatformContractMethodDescriptor.new().configure(
			METHOD_CLIPBOARD_WRITE,
			{
				"request_schema": request_schema,
				"result_schema": result_schema,
				"required_capability_ids": PackedStringArray([
					String(CAPABILITY_CLIPBOARD_WRITE),
				]),
				"max_request_bytes": 16_384,
				"max_result_bytes": 256,
				"max_concurrent_requests": 1,
				"supports_cancellation": false,
				"sensitive_fields": PackedStringArray(["text"]),
			}
		)
	)
	var methods: Array[GFPlatformContractMethodDescriptor] = [method]
	return GFPlatformContractDescriptor.new().configure(
		CONTRACT_CLIPBOARD,
		"1.0.0",
		methods
	)
