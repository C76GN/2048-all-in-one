## BoardTopologyReadyData: gameplay 发布给外部观察者的棋盘拓扑快照。
##
## 载荷只携带复制隔离的 BoardTopology，不暴露会话控制器或表现节点。
class_name BoardTopologyReadyData
extends GFPayload


# --- 公共变量 ---

var topology: BoardTopology:
	get:
		return _copy_topology(_topology)


# --- 私有变量 ---

var _topology: BoardTopology = null


# --- Godot 生命周期方法 ---

func _init(p_topology: BoardTopology = null) -> void:
	_topology = _copy_topology(p_topology)


# --- 私有/辅助方法 ---

static func _copy_topology(source: BoardTopology) -> BoardTopology:
	if not is_instance_valid(source):
		return null
	return BoardTopology.from_dict(source.to_dict())
