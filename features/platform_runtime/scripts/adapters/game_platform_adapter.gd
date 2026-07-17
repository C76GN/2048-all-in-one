## GamePlatformAdapter: 项目平台 SDK 的最小适配器契约。
##
## 业务层只依赖 GF 的平台上下文、能力集、生命周期事件和桥接请求，不直接依赖
## Steam、微信或浏览器 SDK。具体平台接入只需替换该适配器。
class_name GamePlatformAdapter
extends RefCounted


# --- 信号 ---

signal lifecycle_event_emitted(event: GFPlatformLifecycleEvent)


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


## 接收由平台宿主转发的 Godot 通知。
## @param _what: Godot 通知标识。
func handle_notification(_what: int) -> void:
	pass


## 执行平台 SDK bridge 请求。
## @param request: 平台无关的 bridge 请求。
func execute_bridge(request: GFPlatformBridgeRequest) -> GFPlatformBridgeResult:
	var safe_request: GFPlatformBridgeRequest = request
	if safe_request == null:
		safe_request = GFPlatformBridgeRequest.new().configure(
			&"invalid_request",
			CONTRACT_SDK_BRIDGE,
			&"unknown"
		)
	return GFPlatformBridgeResult.new().configure_failure(
		safe_request,
		"当前平台适配器不支持该 SDK 桥接请求。",
		&"unsupported"
	)


func get_contract_descriptor() -> Dictionary:
	var context: GFPlatformRuntimeContext = create_runtime_context()
	var capability_ids: PackedStringArray = PackedStringArray()
	if context != null and context.capabilities != null:
		capability_ids = context.capabilities.capabilities.duplicate()
	return {
		"adapter_id": adapter_id,
		"contract_ids": PackedStringArray([
			String(CONTRACT_RUNTIME_CONTEXT),
			String(CONTRACT_LIFECYCLE),
		]),
		"enabled": is_available(),
		"capabilities": capability_ids,
		"metadata": {
			"platform_id": context.platform_id if context != null else &"unknown",
		},
	}


func close() -> void:
	pass


# --- 受保护方法 ---

## 向平台 Utility 发布生命周期事件。
## @param event: 已规范化的平台生命周期事件。
func emit_lifecycle_event(event: GFPlatformLifecycleEvent) -> void:
	if event == null:
		return
	lifecycle_event_emitted.emit(event)
