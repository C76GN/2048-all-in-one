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

const CAPABILITY_STORAGE_LOCAL: StringName = &"platform.storage.local"
const CAPABILITY_HTTP: StringName = &"platform.http"
const CAPABILITY_AUDIO: StringName = &"platform.audio"
const CAPABILITY_LIFECYCLE: StringName = &"platform.lifecycle"
const CAPABILITY_SAFE_AREA: StringName = &"display.safe_area"
const CAPABILITY_WINDOW_RESIZE: StringName = &"display.window_resize"
const CAPABILITY_POINTER: StringName = &"input.pointer"
const CAPABILITY_TOUCH: StringName = &"input.touch"
const CAPABILITY_COMPATIBILITY_RENDERER: StringName = &"renderer.gl_compatibility"


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
			String(CONTRACT_LIFECYCLE),
			String(CONTRACT_SDK_BRIDGE),
		]),
		context
	)


## 重新采集并发布平台上下文。
func refresh_context() -> bool:
	return _publish_context(create_runtime_context())


## 接收由平台宿主转发的 Godot 通知。
## @param _what: Godot 通知标识。
func handle_notification(_what: int) -> void:
	pass


func get_contract_descriptor() -> Dictionary:
	var configured_adapter_id: StringName = get_adapter_id()
	var descriptor_adapter_id: StringName = (
		configured_adapter_id if configured_adapter_id != &"" else adapter_id
	)
	var contract_ids: PackedStringArray = get_contract_ids()
	if contract_ids.is_empty():
		contract_ids = PackedStringArray([
			String(CONTRACT_RUNTIME_CONTEXT),
			String(CONTRACT_LIFECYCLE),
			String(CONTRACT_SDK_BRIDGE),
		])
	var context: GFPlatformRuntimeContext = (
		get_context() if configured_adapter_id != &"" else create_runtime_context()
	)
	var capability_ids: PackedStringArray = PackedStringArray()
	if context != null and context.capabilities != null:
		capability_ids = context.capabilities.capabilities.duplicate()
	return {
		"adapter_id": descriptor_adapter_id,
		"contract_ids": contract_ids,
		"enabled": is_available() and get_state() not in [State.FAILED, State.SHUTDOWN],
		"capabilities": capability_ids,
		"metadata": {
			"platform_id": context.platform_id if context != null else &"unknown",
		},
	}


# --- 可重写钩子 / 虚方法 ---

## 默认项目 adapter 明确拒绝未实现的 SDK 调用。
func _dispatch(
	_request: GFPlatformBridgeRequest,
	handle: GFPlatformRequestHandle
) -> bool:
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
