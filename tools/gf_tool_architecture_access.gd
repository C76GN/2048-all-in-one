## GfToolArchitectureAccess: 项目验证工具访问运行中 GF 架构的唯一入口。
##
## 玩家运行时仍只能由 Boot 访问全局 Gf。需要检查真实运行态的截图与验收工具
## 通过本窄 Interface 解析 Model、System 或 Utility，避免各工具自行按节点名和
## 动态方法拼接形成无法审计的架构旁路。
class_name GfToolArchitectureAccess
extends RefCounted


## 返回运行中 GF AutoLoad；仅供 verification Module 的工具生命周期使用。
static func get_autoload(root_node: Node) -> Node:
	if not is_instance_valid(root_node):
		return null
	return root_node.get_node_or_null("Gf")


## 从运行中 GF 架构解析一个 Model。
static func get_model(root_node: Node, type_script: Script) -> Variant:
	return _get_member(root_node, &"get_model", type_script)


## 从运行中 GF 架构解析一个 System。
static func get_system(root_node: Node, type_script: Script) -> Variant:
	return _get_member(root_node, &"get_system", type_script)


## 从运行中 GF 架构解析一个 Utility。
static func get_utility(root_node: Node, type_script: Script) -> Variant:
	return _get_member(root_node, &"get_utility", type_script)


# --- 私有/辅助方法 ---

static func _get_member(
	root_node: Node,
	method: StringName,
	type_script: Script
) -> Variant:
	if type_script == null:
		return null
	var gf_node: Node = get_autoload(root_node)
	if not is_instance_valid(gf_node):
		return null
	return gf_node.call(method, type_script)
