## GamePlatformUtility: 项目统一平台运行时边界。
##
## 对外提供稳定的平台上下文、能力查询、生命周期事件和 SDK bridge。平台差异由
## GamePlatformAdapter 隔离，业务代码不读取 OS feature 或直接调用平台 SDK。
class_name GamePlatformUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 信号 ---

signal context_changed(context: GFPlatformRuntimeContext)
signal lifecycle_event_received(event: GFPlatformLifecycleEvent)


# --- 常量 ---

const CONTRACT_RUNTIME_CONTEXT: StringName = GamePlatformAdapter.CONTRACT_RUNTIME_CONTEXT
const CONTRACT_LIFECYCLE: StringName = GamePlatformAdapter.CONTRACT_LIFECYCLE
const CONTRACT_SDK_BRIDGE: StringName = GamePlatformAdapter.CONTRACT_SDK_BRIDGE

const CAPABILITY_STORAGE_LOCAL: StringName = GamePlatformAdapter.CAPABILITY_STORAGE_LOCAL
const CAPABILITY_HTTP: StringName = GamePlatformAdapter.CAPABILITY_HTTP
const CAPABILITY_AUDIO: StringName = GamePlatformAdapter.CAPABILITY_AUDIO
const CAPABILITY_LIFECYCLE: StringName = GamePlatformAdapter.CAPABILITY_LIFECYCLE
const CAPABILITY_SAFE_AREA: StringName = GamePlatformAdapter.CAPABILITY_SAFE_AREA
const CAPABILITY_WINDOW_RESIZE: StringName = GamePlatformAdapter.CAPABILITY_WINDOW_RESIZE
const CAPABILITY_POINTER: StringName = GamePlatformAdapter.CAPABILITY_POINTER
const CAPABILITY_TOUCH: StringName = GamePlatformAdapter.CAPABILITY_TOUCH
const CAPABILITY_COMPATIBILITY_RENDERER: StringName = GamePlatformAdapter.CAPABILITY_COMPATIBILITY_RENDERER


# --- 私有变量 ---

var _adapter: GamePlatformAdapter = null
var _context: GFPlatformRuntimeContext = null
var _lifecycle_sequence: int = 0
var _relay: _GamePlatformLifecycleRelay = null
var _relay_attach_serial: int = 0
var _initialized: bool = false


# --- GF 生命周期方法 ---

func init() -> void:
	ignore_pause = true
	ignore_time_scale = true
	_initialized = true
	if _adapter == null:
		_adapter = LocalPlatformAdapter.new()
	_bind_adapter()
	var _initial_context: GFPlatformRuntimeContext = refresh_runtime_context()
	_ensure_lifecycle_relay()


func ready() -> void:
	_ensure_lifecycle_relay()


func dispose() -> void:
	_relay_attach_serial += 1
	_unbind_adapter()
	if _adapter != null:
		_adapter.close()
	_adapter = null
	_context = null
	_lifecycle_sequence = 0
	_initialized = false
	if is_instance_valid(_relay):
		_relay.queue_free()
	_relay = null


# --- 公共方法 ---

## 仅允许在 init() 前注入平台适配器，供平台启动层和测试使用。
## @param adapter: 待注入的平台适配器。
func configure_adapter(adapter: GamePlatformAdapter) -> bool:
	if _initialized:
		push_error("[GamePlatformUtility] 平台适配器只能在 init() 前配置。")
		return false
	if adapter == null:
		return false
	_adapter = adapter
	return true


func get_runtime_context() -> GFPlatformRuntimeContext:
	if _context == null:
		return null
	return _context.duplicate_context()


func refresh_runtime_context() -> GFPlatformRuntimeContext:
	if _adapter == null:
		_context = null
		return null
	_context = _adapter.create_runtime_context()
	if _context != null:
		context_changed.emit(_context.duplicate_context())
	return get_runtime_context()


## 查询当前平台是否声明指定能力。
## @param capability_id: 平台能力标识。
func has_capability(capability_id: StringName) -> bool:
	return _context != null and _context.has_capability(capability_id)


## 通过当前适配器执行平台 SDK bridge 请求。
## @param request: 平台无关的 bridge 请求。
func execute_bridge(request: GFPlatformBridgeRequest) -> GFPlatformBridgeResult:
	if _adapter != null:
		return _adapter.execute_bridge(request)
	return GamePlatformAdapter.new().execute_bridge(request)


func get_bridge_contract_report() -> Dictionary:
	var builder: GFBridgeContractReport = GFBridgeContractReport.new().configure(
		"Game platform bridge coverage",
		{"feature": "platform_runtime"}
	)
	var _runtime_contract: Dictionary = builder.add_contract(CONTRACT_RUNTIME_CONTEXT, {
		"required": true,
	})
	var _lifecycle_contract: Dictionary = builder.add_contract(CONTRACT_LIFECYCLE, {
		"required": true,
		"capabilities": PackedStringArray([String(CAPABILITY_LIFECYCLE)]),
	})
	if _adapter != null:
		var descriptor: Dictionary = _adapter.get_contract_descriptor()
		var _adapter_entry: Dictionary = builder.add_adapter(
			GFVariantData.get_option_string_name(descriptor, "adapter_id"),
			&"",
			descriptor
		)
	return builder.get_report()


func get_debug_snapshot() -> Dictionary:
	return {
		"context": _context.to_dict() if _context != null else {},
		"lifecycle_sequence": _lifecycle_sequence,
		"relay_attached": is_instance_valid(_relay) and _relay.is_inside_tree(),
		"bridge_contract": get_bridge_contract_report(),
	}


## 供无场景树测试和平台宿主主动转发生命周期通知。
## @param what: Godot 通知标识。
func forward_platform_notification(what: int) -> void:
	if _adapter != null:
		_adapter.handle_notification(what)


# --- 私有/辅助方法 ---

func _bind_adapter() -> void:
	if _adapter == null:
		return
	if not _adapter.lifecycle_event_emitted.is_connected(_on_adapter_lifecycle_event):
		var _connect_result: int = _adapter.lifecycle_event_emitted.connect(
			_on_adapter_lifecycle_event
		)


func _unbind_adapter() -> void:
	if _adapter == null:
		return
	if _adapter.lifecycle_event_emitted.is_connected(_on_adapter_lifecycle_event):
		_adapter.lifecycle_event_emitted.disconnect(_on_adapter_lifecycle_event)


func _on_adapter_lifecycle_event(event: GFPlatformLifecycleEvent) -> void:
	if event == null:
		return
	_lifecycle_sequence += 1
	var published_event: GFPlatformLifecycleEvent = event.duplicate_event()
	published_event.sequence = _lifecycle_sequence
	if (
		published_event.is_type(GFPlatformLifecycleEvent.TYPE_WINDOW_RESIZED)
		or published_event.is_type(GFPlatformLifecycleEvent.TYPE_SAFE_AREA_CHANGED)
	):
		var _refreshed_context: GFPlatformRuntimeContext = refresh_runtime_context()
	lifecycle_event_received.emit(published_event)


func _ensure_lifecycle_relay() -> void:
	if is_instance_valid(_relay):
		return
	var tree: SceneTree = _get_scene_tree_value(Engine.get_main_loop())
	if tree == null:
		return
	_relay = _GamePlatformLifecycleRelay.new()
	_relay.name = "GamePlatformLifecycleRelay"
	_relay.platform_utility = self
	_relay_attach_serial += 1
	call_deferred("_attach_relay_to_root", _relay, _relay_attach_serial)


func _attach_relay_to_root(relay_variant: Variant, attach_serial: int) -> void:
	if not is_instance_valid(relay_variant):
		return
	if not relay_variant is Node:
		return
	var relay: Node = relay_variant
	if attach_serial != _relay_attach_serial or relay != _relay:
		relay.queue_free()
		return
	if relay.is_queued_for_deletion() or relay.is_inside_tree():
		return
	var tree: SceneTree = _get_scene_tree_value(Engine.get_main_loop())
	if tree == null:
		_relay = null
		relay.queue_free()
		return
	tree.root.add_child(relay)


func _get_scene_tree_value(value: Variant) -> SceneTree:
	if value is SceneTree:
		var tree: SceneTree = value
		return tree
	return null


# --- 内部类 ---

class _GamePlatformLifecycleRelay extends Node:
	var platform_utility: GamePlatformUtility = null

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _notification(what: int) -> void:
		if platform_utility != null:
			platform_utility.forward_platform_notification(what)
