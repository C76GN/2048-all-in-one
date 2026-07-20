## GamePlatformUtility: 项目平台选择与 Godot 通知边界。
##
## GFPlatformRuntime 拥有 adapter 注册、契约路由、请求终态、超时和生命周期序号；
## 本 Utility 只选择项目默认 adapter，并把 Godot 通知转交给它。
class_name GamePlatformUtility
extends GFUtility


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
var _runtime: GFPlatformRuntime = null
var _context: GFPlatformRuntimeContext = null
var _relay: _GamePlatformLifecycleRelay = null
var _relay_attach_serial: int = 0
var _initialized: bool = false


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFPlatformRuntime]


func init() -> void:
	ignore_pause = true
	ignore_time_scale = true
	_initialized = true
	if _adapter == null:
		_adapter = LocalPlatformAdapter.new()


func ready() -> void:
	if not _adapter.prepare():
		push_error("[GamePlatformUtility] 默认平台 adapter 配置失败。")
		return
	_runtime = _resolve_platform_runtime()
	if _runtime == null:
		push_error("[GamePlatformUtility] GFPlatformRuntime 未注册。")
		return
	_bind_runtime_signals()
	if not _runtime.register_adapter(_adapter):
		push_error("[GamePlatformUtility] 平台 adapter 注册失败：%s。" % _adapter.adapter_id)
		return
	var completion: GFAsyncCompletion = _runtime.initialize_adapter(_adapter.adapter_id)
	if completion.is_pending():
		var _completion_connected: int = completion.completed.connect(
			_on_adapter_initialization_completed,
			CONNECT_ONE_SHOT
		)
	else:
		_on_adapter_initialization_completed(completion)
	_ensure_lifecycle_relay()


func dispose() -> void:
	_relay_attach_serial += 1
	_unbind_runtime_signals()
	if _runtime != null and _adapter != null:
		var _adapter_removed: bool = _runtime.unregister_adapter(
			_adapter.adapter_id,
			true
		)
	_adapter = null
	_runtime = null
	_context = null
	_initialized = false
	if is_instance_valid(_relay):
		_relay.queue_free()
	_relay = null


# --- 公共方法 ---

## 仅允许在 init() 前注入平台适配器，供平台启动层和测试使用。
## @param adapter: 项目选择的平台适配器。
func configure_adapter(adapter: GamePlatformAdapter) -> bool:
	if _initialized:
		push_error("[GamePlatformUtility] 平台适配器只能在 init() 前配置。")
		return false
	if adapter == null:
		return false
	_adapter = adapter
	return true


func get_runtime_context() -> GFPlatformRuntimeContext:
	return _context.duplicate_context() if _context != null else null


func refresh_runtime_context() -> GFPlatformRuntimeContext:
	if _adapter == null or not _adapter.refresh_context():
		return null
	return get_runtime_context()


## 查询当前平台是否声明指定能力。
## @param capability_id: 待查询的稳定能力 ID。
func has_capability(capability_id: StringName) -> bool:
	return (
		_runtime != null
		and _adapter != null
		and _runtime.has_capability(capability_id, _adapter.adapter_id)
	)


## 通过 GFPlatformRuntime 发起平台 SDK bridge 请求。
## @param request: 规范平台桥接请求。
func invoke_bridge(request: GFPlatformBridgeRequest) -> GFPlatformRequestHandle:
	if _runtime == null or _adapter == null:
		return null
	return _runtime.invoke(request, _adapter.adapter_id)


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
	var _sdk_bridge_contract: Dictionary = builder.add_contract(CONTRACT_SDK_BRIDGE, {
		"required": false,
	})
	if _adapter != null:
		var descriptor: Dictionary = _adapter.get_contract_descriptor()
		var _adapter_entry: Dictionary = builder.add_adapter(
			_adapter.adapter_id,
			&"",
			descriptor
		)
	return builder.get_report()


func get_debug_snapshot() -> Dictionary:
	return {
		"context": _context.to_dict() if _context != null else {},
		"relay_attached": is_instance_valid(_relay) and _relay.is_inside_tree(),
		"bridge_contract": get_bridge_contract_report(),
		"runtime": _runtime.get_debug_snapshot() if _runtime != null else {},
	}


## 供平台宿主主动转发 Godot 生命周期通知。
## @param what: Godot 通知常量。
func forward_platform_notification(what: int) -> void:
	if _adapter != null:
		_adapter.handle_notification(what)


# --- 私有/辅助方法 ---

func _resolve_platform_runtime() -> GFPlatformRuntime:
	var value: Object = get_utility(GFPlatformRuntime)
	if value is GFPlatformRuntime:
		var runtime: GFPlatformRuntime = value
		return runtime
	return null


func _bind_runtime_signals() -> void:
	if _runtime == null:
		return
	if not _runtime.context_changed.is_connected(_on_runtime_context_changed):
		var _context_connected: int = _runtime.context_changed.connect(
			_on_runtime_context_changed
		)
	if not _runtime.lifecycle_event.is_connected(_on_runtime_lifecycle_event):
		var _lifecycle_connected: int = _runtime.lifecycle_event.connect(
			_on_runtime_lifecycle_event
		)


func _unbind_runtime_signals() -> void:
	if _runtime == null:
		return
	if _runtime.context_changed.is_connected(_on_runtime_context_changed):
		_runtime.context_changed.disconnect(_on_runtime_context_changed)
	if _runtime.lifecycle_event.is_connected(_on_runtime_lifecycle_event):
		_runtime.lifecycle_event.disconnect(_on_runtime_lifecycle_event)


func _on_adapter_initialization_completed(completion: GFAsyncCompletion) -> void:
	if completion == null or not completion.is_successful():
		var error: String = completion.get_error() if completion != null else "missing completion"
		push_error("[GamePlatformUtility] 平台 adapter 初始化失败：%s。" % error)
		return
	_publish_current_context()


func _publish_current_context() -> void:
	if _runtime == null or _adapter == null:
		_context = null
		return
	_context = _runtime.get_context(_adapter.adapter_id)
	if _context != null:
		context_changed.emit(_context.duplicate_context())


func _on_runtime_context_changed(
	adapter_id: StringName,
	context: GFPlatformRuntimeContext
) -> void:
	if _adapter == null or adapter_id != _adapter.adapter_id or context == null:
		return
	_context = context.duplicate_context()
	context_changed.emit(_context.duplicate_context())


func _on_runtime_lifecycle_event(
	adapter_id: StringName,
	event: GFPlatformLifecycleEvent
) -> void:
	if _adapter == null or adapter_id != _adapter.adapter_id or event == null:
		return
	lifecycle_event_received.emit(event.duplicate_event())


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
	if not is_instance_valid(relay_variant) or not relay_variant is Node:
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
