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
const CONTRACT_CLIPBOARD: StringName = GamePlatformAdapter.CONTRACT_CLIPBOARD

const METHOD_CLIPBOARD_WRITE: StringName = GamePlatformAdapter.METHOD_CLIPBOARD_WRITE

const CAPABILITY_STORAGE_LOCAL: StringName = GamePlatformAdapter.CAPABILITY_STORAGE_LOCAL
const CAPABILITY_HTTP: StringName = GamePlatformAdapter.CAPABILITY_HTTP
const CAPABILITY_AUDIO: StringName = GamePlatformAdapter.CAPABILITY_AUDIO
const CAPABILITY_LIFECYCLE: StringName = GamePlatformAdapter.CAPABILITY_LIFECYCLE
const CAPABILITY_SAFE_AREA: StringName = GamePlatformAdapter.CAPABILITY_SAFE_AREA
const CAPABILITY_WINDOW_RESIZE: StringName = GamePlatformAdapter.CAPABILITY_WINDOW_RESIZE
const CAPABILITY_POINTER: StringName = GamePlatformAdapter.CAPABILITY_POINTER
const CAPABILITY_TOUCH: StringName = GamePlatformAdapter.CAPABILITY_TOUCH
const CAPABILITY_COMPATIBILITY_RENDERER: StringName = GamePlatformAdapter.CAPABILITY_COMPATIBILITY_RENDERER
const CAPABILITY_CLIPBOARD_WRITE: StringName = GamePlatformAdapter.CAPABILITY_CLIPBOARD_WRITE


# --- 私有变量 ---

var _adapter: GamePlatformAdapter = null
var _runtime: GFPlatformRuntime = null
var _signals: GFSignalUtility = null
var _context: GFPlatformRuntimeContext = null
var _relay: _GamePlatformLifecycleRelay = null
var _relay_attach_serial: int = 0
var _clipboard_request_serial: int = 0
var _initialized: bool = false
var _adapter_registered: bool = false
var _accepting_runtime_work: bool = false
var _ready_error: String = ""
var _activation_scope: GFAsyncScope = null
var _activation_completion: GFAsyncCompletion = null
var _adapter_initialization: GFAsyncCompletion = null
var _activation_cleanup: Callable = Callable()


# --- GF 生命周期方法 ---

func get_required_utilities() -> Array[Script]:
	return [GFPlatformRuntime, GFSignalUtility]


func init() -> void:
	ignore_pause = true
	ignore_time_scale = true
	_initialized = true
	_adapter_registered = false
	_accepting_runtime_work = false
	_ready_error = ""
	_activation_scope = null
	_activation_completion = null
	_adapter_initialization = null
	_activation_cleanup = Callable()
	if _adapter == null:
		_adapter = LocalPlatformAdapter.new()


func ready() -> void:
	if not _adapter.prepare():
		_ready_error = "默认平台 adapter 配置失败。"
		push_error("[GamePlatformUtility] %s" % _ready_error)
		return
	_runtime = _resolve_platform_runtime()
	_signals = _resolve_signal_utility()
	if _runtime == null:
		_ready_error = "GFPlatformRuntime 未注册。"
		push_error("[GamePlatformUtility] %s" % _ready_error)
		return
	if _signals == null:
		_ready_error = "GFSignalUtility 未注册。"
		push_error("[GamePlatformUtility] %s" % _ready_error)
		return
	_bind_runtime_signals()
	if not _runtime.register_adapter(_adapter):
		_ready_error = "平台 adapter 注册失败：%s。" % _adapter.adapter_id
		push_error("[GamePlatformUtility] %s" % _ready_error)
		return
	_adapter_registered = true


## 等待 GFPlatformRuntime 给当前 Adapter 形成唯一初始化终态后才开放架构。
## @param scope: 当前架构 activation 的协作取消作用域。
func begin_activation(scope: GFAsyncScope) -> GFAsyncCompletion:
	var completion: GFAsyncCompletion = GFAsyncCompletion.new()
	if scope == null:
		var _failed_scope: bool = completion.fail(
			"Platform activation scope is unavailable."
		)
		return completion
	var _bound: bool = completion.bind_cancel_token(scope)
	if not completion.is_pending():
		return completion
	if not _ready_error.is_empty():
		var _failed_ready: bool = completion.fail(_ready_error)
		return completion
	if _runtime == null or _adapter == null or not _adapter_registered:
		var _failed_registration: bool = completion.fail(
			"Platform adapter is not registered."
		)
		return completion

	_activation_scope = scope
	_activation_completion = completion
	_adapter_initialization = _runtime.initialize_adapter(_adapter.adapter_id)
	if _adapter_initialization == null:
		var _failed_handle: bool = completion.fail(
			"Platform adapter initialization returned no completion."
		)
		_clear_activation_tracking()
		return completion
	_activation_cleanup = Callable(
		self,
		"_cancel_pending_activation"
	).bind(&"platform_activation_cancelled")
	var _cleanup_registered: bool = scope.register_cleanup(_activation_cleanup)
	if _adapter_initialization.is_completed():
		_settle_adapter_activation(_adapter_initialization, completion)
		return completion
	var connection: GFSignalConnection = _signals.connect_once(
		_adapter_initialization.completed,
		Callable(self, "_on_adapter_initialization_completed").bind(completion),
		self
	)
	if connection == null or not connection.is_active():
		_unregister_activation_cleanup()
		if _adapter_initialization != null and _adapter_initialization.is_pending():
			var _cancelled_initialization: bool = _adapter_initialization.cancel(
				&"activation_observer_unavailable"
			)
		if completion.is_pending():
			var _failed_connection: bool = completion.fail(
				"Platform adapter initialization completion could not be observed."
			)
		_clear_activation_tracking()
	return completion


## 停止转发宿主通知并拒绝新的平台请求。
## @param scope: 当前架构 quiesce 的协作取消作用域。
func begin_quiesce(scope: GFAsyncScope) -> GFAsyncCompletion:
	var completion: GFAsyncCompletion = GFAsyncCompletion.new()
	if scope == null:
		var _failed_scope: bool = completion.fail(
			"Platform quiesce scope is unavailable."
		)
		return completion
	var _bound: bool = completion.bind_cancel_token(scope)
	if not completion.is_pending():
		return completion
	_accepting_runtime_work = false
	_relay_attach_serial += 1
	_release_lifecycle_relay()
	_cancel_pending_activation(&"platform_quiescing")
	_unbind_runtime_signals()
	var _succeeded: bool = completion.succeed()
	return completion


func dispose() -> void:
	_accepting_runtime_work = false
	_relay_attach_serial += 1
	_cancel_pending_activation(&"platform_disposed")
	_unbind_runtime_signals()
	if _runtime != null and _adapter != null and _adapter_registered:
		var _adapter_removed: bool = _runtime.unregister_adapter(
			_adapter.adapter_id,
			true
		)
	_adapter_registered = false
	_adapter = null
	_runtime = null
	_signals = null
	_context = null
	_clipboard_request_serial = 0
	_initialized = false
	_ready_error = ""
	_clear_activation_tracking()
	_release_lifecycle_relay()


func release_dependencies() -> void:
	_runtime = null
	_signals = null
	super.release_dependencies()


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
	if not _accepting_runtime_work or _adapter == null or not _adapter.refresh_context():
		return null
	return get_runtime_context()


## 当前宿主没有可提交的渲染帧时返回 true；上下文未就绪时采取保守值。
func is_headless_runtime() -> bool:
	if _context == null:
		return true
	return GFVariantData.get_option_bool(_context.metadata, "headless", false)


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
	if not _accepting_runtime_work or _runtime == null or _adapter == null:
		return null
	return _runtime.invoke(request, _adapter.adapter_id)


## 通过 GFPlatformRuntime 执行用户主动请求的剪贴板写入。
## @param text: 已本地化、可直接复制的非空纯文本。
## @return: 唯一终态平台请求句柄；Utility 尚未 ready 时返回 null。
func copy_text_to_clipboard(text: String) -> GFPlatformRequestHandle:
	if not _accepting_runtime_work or _runtime == null or _adapter == null:
		return null
	_clipboard_request_serial += 1
	var request: GFPlatformBridgeRequest = GFPlatformBridgeRequest.new().configure(
		StringName("game_clipboard_%d" % _clipboard_request_serial),
		CONTRACT_CLIPBOARD,
		METHOD_CLIPBOARD_WRITE,
		{&"text": text}
	)
	return _runtime.invoke(request, _adapter.adapter_id)


func get_bridge_contract_report() -> Dictionary:
	return GFPlatformAdapterConformance.inspect(
		_adapter,
		make_adapter_conformance_options()
	)


## 返回项目平台 Adapter 必须满足的 GF 静态契约。
static func make_adapter_conformance_options() -> Dictionary:
	return {
		"required_contract_ids": PackedStringArray([
			String(CONTRACT_RUNTIME_CONTEXT),
			String(CONTRACT_CLIPBOARD),
		]),
		"required_contract_versions": {
			String(CONTRACT_RUNTIME_CONTEXT): "1.0.0",
			String(CONTRACT_CLIPBOARD): "1.0.0",
		},
		"required_capability_ids": PackedStringArray([
			String(CAPABILITY_LIFECYCLE),
			String(CAPABILITY_STORAGE_LOCAL),
		]),
		"required_methods": {
			String(CONTRACT_RUNTIME_CONTEXT): PackedStringArray([
				String(GamePlatformAdapter.METHOD_RUNTIME_CONTEXT_QUERY),
			]),
			String(CONTRACT_CLIPBOARD): PackedStringArray([
				String(METHOD_CLIPBOARD_WRITE),
			]),
		},
		"require_descriptors": true,
	}


func get_debug_snapshot() -> Dictionary:
	return {
		"context": _context.to_dict() if _context != null else {},
		"accepting_runtime_work": _accepting_runtime_work,
		"adapter_registered": _adapter_registered,
		"relay_attached": is_instance_valid(_relay) and _relay.is_inside_tree(),
		"bridge_contract": get_bridge_contract_report(),
		"runtime": _runtime.get_debug_snapshot() if _runtime != null else {},
	}


## 供平台宿主主动转发 Godot 生命周期通知。
## @param what: Godot 通知常量。
func forward_platform_notification(what: int) -> void:
	if _accepting_runtime_work and _adapter != null:
		_adapter.handle_notification(what)


# --- 私有/辅助方法 ---

func _resolve_platform_runtime() -> GFPlatformRuntime:
	var value: Object = get_utility(GFPlatformRuntime)
	if value is GFPlatformRuntime:
		var runtime: GFPlatformRuntime = value
		return runtime
	return null


func _resolve_signal_utility() -> GFSignalUtility:
	var value: Object = get_utility(GFSignalUtility)
	if value is GFSignalUtility:
		var signal_utility: GFSignalUtility = value
		return signal_utility
	return null


func _bind_runtime_signals() -> void:
	if _runtime == null or _signals == null:
		return
	var _context_connection: GFSignalConnection = _signals.connect_signal(
		_runtime.context_changed,
		Callable(self, "_on_runtime_context_changed"),
		self
	)
	var _lifecycle_connection: GFSignalConnection = _signals.connect_signal(
		_runtime.lifecycle_event,
		Callable(self, "_on_runtime_lifecycle_event"),
		self
	)


func _unbind_runtime_signals() -> void:
	if _signals != null:
		_signals.disconnect_owner(self)


func _on_adapter_initialization_completed(
	initialization: GFAsyncCompletion,
	activation: GFAsyncCompletion
) -> void:
	_settle_adapter_activation(initialization, activation)


func _settle_adapter_activation(
	initialization: GFAsyncCompletion,
	activation: GFAsyncCompletion
) -> void:
	if initialization == null or activation == null:
		return
	if initialization != _adapter_initialization or activation != _activation_completion:
		return
	_unregister_activation_cleanup()
	if not activation.is_pending():
		_clear_activation_tracking()
		return
	if initialization.is_successful():
		_publish_current_context()
		if _context == null:
			var _failed_context: bool = activation.fail(
				"Platform adapter initialized without a runtime context."
			)
		else:
			_accepting_runtime_work = true
			_ensure_lifecycle_relay()
			var _succeeded: bool = activation.succeed(_context.duplicate_context())
	elif initialization.is_cancelled():
		var _cancelled: bool = activation.cancel(
			initialization.get_cancel_reason(),
			initialization.get_metadata()
		)
	else:
		var _failed: bool = activation.fail(
			initialization.get_error(),
			initialization.get_metadata()
		)
	_clear_activation_tracking()


func _cancel_pending_activation(reason: StringName) -> void:
	var initialization: GFAsyncCompletion = _adapter_initialization
	var activation: GFAsyncCompletion = _activation_completion
	_unregister_activation_cleanup()
	if initialization != null and initialization.is_pending():
		var _initialization_cancelled: bool = initialization.cancel(reason)
	# 底层 completion 的 owner-bound observer 可能已经被作用域取消或断开；
	# 外层架构 activation 必须独立保证唯一终态，不能依赖信号仍然可达。
	if activation != null and activation.is_pending():
		var _activation_cancelled: bool = activation.cancel(reason)
	_clear_activation_tracking()


func _unregister_activation_cleanup() -> void:
	if _activation_scope != null and _activation_cleanup.is_valid():
		_activation_scope.unregister_cleanup(_activation_cleanup)
	_activation_cleanup = Callable()


func _clear_activation_tracking() -> void:
	_unregister_activation_cleanup()
	_activation_scope = null
	_activation_completion = null
	_adapter_initialization = null


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
	if (
		not _accepting_runtime_work
		or _adapter == null
		or adapter_id != _adapter.adapter_id
		or context == null
	):
		return
	_context = context.duplicate_context()
	context_changed.emit(_context.duplicate_context())


func _on_runtime_lifecycle_event(
	adapter_id: StringName,
	event: GFPlatformLifecycleEvent
) -> void:
	if (
		not _accepting_runtime_work
		or _adapter == null
		or adapter_id != _adapter.adapter_id
		or event == null
	):
		return
	lifecycle_event_received.emit(event.duplicate_event())


func _ensure_lifecycle_relay() -> void:
	if not _accepting_runtime_work or is_instance_valid(_relay):
		return
	var tree: SceneTree = _get_scene_tree_value(Engine.get_main_loop())
	if tree == null:
		return
	_relay = _GamePlatformLifecycleRelay.new()
	_relay.name = "GamePlatformLifecycleRelay"
	_relay.platform_utility = self
	_relay_attach_serial += 1
	call_deferred("_attach_relay_to_root", _relay, _relay_attach_serial)


func _release_lifecycle_relay() -> void:
	if is_instance_valid(_relay):
		_relay.platform_utility = null
		_relay.queue_free()
	_relay = null


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
