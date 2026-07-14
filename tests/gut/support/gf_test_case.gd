## GFTestCase: 为直接构造的 GF 模块提供确定性的测试生命周期清理。
class_name GFTestCase
extends GutTest


# --- 私有变量 ---

var _tracked_systems: Array[GFSystem] = []


# --- GUT 生命周期方法 ---

func after_each() -> void:
	for index: int in range(_tracked_systems.size() - 1, -1, -1):
		var system: GFSystem = _tracked_systems[index]
		if system == null:
			continue
		system.dispose()
		system.release_dependencies()
	_tracked_systems.clear()


# --- 保护方法 ---

## 登记由测试直接构造、未交给 GFArchitecture 托管的 System。
## @param system: 当前测试拥有的 GF System。
func track_gf_system(system: GFSystem) -> void:
	if system != null and not _tracked_systems.has(system):
		_tracked_systems.append(system)
