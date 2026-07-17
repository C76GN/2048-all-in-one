## GFTestCase: 为直接构造的 GF 模块提供确定性的测试生命周期清理。
class_name GFTestCase
extends GutTest


# --- 私有变量 ---

var _tracked_systems: Array[GFSystem] = []
var _tracked_nodes: Array[Node] = []


# --- GUT 生命周期方法 ---

func after_each() -> void:
	for index: int in range(_tracked_systems.size() - 1, -1, -1):
		var system: GFSystem = _tracked_systems[index]
		if system == null:
			continue
		system.dispose()
		system.release_dependencies()
	_tracked_systems.clear()

	for index: int in range(_tracked_nodes.size() - 1, -1, -1):
		var node: Node = _tracked_nodes[index]
		if is_instance_valid(node):
			node.free()
	_tracked_nodes.clear()


# --- 保护方法 ---

## 登记由测试直接构造、未交给 GFArchitecture 托管的 System。
## @param system: 当前测试拥有的 GF System。
func track_gf_system(system: GFSystem) -> void:
	if system != null and not _tracked_systems.has(system):
		_tracked_systems.append(system)


## 登记由测试直接构造且未进入场景树的 Node。
## @param node: 当前测试拥有、需要在 after_each 中立即释放的节点。
func track_test_node(node: Node) -> void:
	if is_instance_valid(node) and not _tracked_nodes.has(node):
		_tracked_nodes.append(node)
