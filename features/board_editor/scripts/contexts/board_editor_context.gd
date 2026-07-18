## BoardEditorContext: 管理棋盘编辑器局部 GF 架构与命令历史。
class_name BoardEditorContext
extends GFNodeContext


# --- 导出变量 ---

## 编辑器局部撤销与重做记录上限。
@export_range(1, 4096, 1) var history_limit: int = 128


# --- Godot 生命周期方法 ---

func _init() -> void:
	scope_mode = GFNodeContext.ScopeMode.SCOPED
	process_scoped_ticks = false
	strict_dependency_lookup = true


# --- GF 装配方法 ---

## 注册仅属于当前编辑器实例的命令历史。
## @param binder: 当前 scoped 架构的声明式绑定器。
## @param scope: 当前安装流程的可取消异步作用域。
func install_bindings(binder: Variant, scope: GFAsyncScope) -> void:
	if not binder is GFBinder:
		push_error("[BoardEditorContext] install_bindings 收到无效 Binder。")
		return

	var history: GFCommandHistoryUtility = GFCommandHistoryUtility.new()
	history.max_history_size = history_limit
	var typed_binder: GFBinder = binder
	var history_binding: GFBindBuilder = typed_binder.bind_utility(GFCommandHistoryUtility)
	history_binding = history_binding.from_instance(history)
	var registered: bool = await history_binding.as_singleton()
	if scope.is_cancel_requested():
		return
	if registered:
		return

	var scoped_architecture: GFArchitecture = get_architecture()
	if scoped_architecture != null:
		scoped_architecture.fail_initialization(
			"BoardEditorContext 无法注册局部 GFCommandHistoryUtility。"
		)


# --- 获取方法 ---

## 获取当前编辑器实例独占的命令历史。
## @return: scoped 架构完成初始化后返回局部历史，否则返回 null。
func get_history() -> GFCommandHistoryUtility:
	var utility_value: Object = get_local_utility(GFCommandHistoryUtility, true)
	if utility_value is GFCommandHistoryUtility:
		var history: GFCommandHistoryUtility = utility_value
		return history
	return null
