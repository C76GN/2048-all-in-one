## ProjectRequiredBinding: 必需项目绑定的失败关闭边界。
##
## GFBindBuilder 负责执行注册；本 helper 负责让项目 Installer 消费其 bool 终态，
## 并在首个失败时同时终结候选架构和 Installer scope。
class_name ProjectRequiredBinding
extends RefCounted


## 执行一个必需 singleton 绑定，并把 false 收敛为项目安装失败。
## @param binding: 已配置来源与可选 alias 的 GF 绑定声明。
## @param architecture: 当前尚未发布的候选架构。
## @param scope: 当前 Installer 的协作取消作用域。
## @param binding_kind: model、utility 或 system。
## @param target_script: 必需绑定的具体目标类型。
## @param alias_script: 可选的查询 alias；用于后置解析验证与精确失败诊断。
## @return 仅绑定成功且 scope 仍活动时返回 true。
static func bind_singleton(
	binding: GFBindBuilder,
	architecture: GFArchitecture,
	scope: GFAsyncScope,
	binding_kind: StringName,
	target_script: Script,
	alias_script: Script = null
) -> bool:
	if scope == null or scope.is_cancel_requested():
		return false

	var binding_succeeded: bool = false
	if binding != null:
		binding_succeeded = await binding.as_singleton()
	if binding_succeeded:
		if scope.is_cancel_requested():
			return false
		if alias_script == null or _alias_resolves_to_target(
			architecture,
			binding_kind,
			target_script,
			alias_script
		):
			return true

	var target_name: String = _get_script_name(target_script)
	var alias_name: String = _get_script_name(alias_script) if alias_script != null else ""
	var kind_label: String = String(binding_kind)
	if alias_script != null:
		kind_label += " alias"
	var failure_reason: String = "[ProjectRequiredBinding] 必需 %s 绑定失败：%s" % [
		kind_label,
		target_name,
	]
	if not alias_name.is_empty():
		failure_reason += " -> %s" % alias_name
	failure_reason += "。"

	if architecture != null:
		architecture.fail_initialization(failure_reason)
	else:
		push_error(failure_reason)
	var _cancelled_scope: bool = scope.cancel(
		failure_reason,
		{
			"binding_kind": kind_label,
			"target": target_name,
			"alias": alias_name,
		}
	)
	return false


# --- 私有/辅助方法 ---

static func _alias_resolves_to_target(
	architecture: GFArchitecture,
	binding_kind: StringName,
	target_script: Script,
	alias_script: Script
) -> bool:
	if architecture == null or target_script == null or alias_script == null:
		return false

	var target_instance: Object = null
	var alias_instance: Object = null
	match binding_kind:
		&"model":
			target_instance = architecture.get_local_model(target_script, false)
			alias_instance = architecture.get_local_model(alias_script, false)
		&"utility":
			target_instance = architecture.get_local_utility(target_script, false)
			alias_instance = architecture.get_local_utility(alias_script, false)
		&"system":
			target_instance = architecture.get_local_system(target_script, false)
			alias_instance = architecture.get_local_system(alias_script, false)
		_:
			return false
	return target_instance != null and is_same(target_instance, alias_instance)


static func _get_script_name(script_cls: Script) -> String:
	if script_cls == null:
		return "<null>"
	var global_name: String = String(script_cls.get_global_name())
	if not global_name.is_empty():
		return global_name
	if not script_cls.resource_path.is_empty():
		return script_cls.resource_path
	return "<anonymous>"
