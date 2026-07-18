## BoardDiscoveryRecord: 一个已发现棋盘拓扑身份的严格玩家进度记录。
class_name BoardDiscoveryRecord
extends Resource


# --- 公共变量 ---

var board_key: String = ""
var topology_id: StringName = &""
var content_fingerprint: String = ""
var discovered_at: int = 0
var cell_count: int = 0


# --- 公共方法 ---

## 从当前拓扑创建首次发现记录。
## @param topology: 已通过业务校验的棋盘拓扑。
## @param p_discovered_at: 首次发现 Unix 时间戳。
static func create(topology: BoardTopology, p_discovered_at: int) -> BoardDiscoveryRecord:
	if (
		not is_instance_valid(topology)
		or not topology.get_validation_report().is_ok()
		or p_discovered_at <= 0
	):
		return null
	var record: BoardDiscoveryRecord = BoardDiscoveryRecord.new()
	record.board_key = topology.get_stable_key()
	record.topology_id = topology.topology_id
	record.content_fingerprint = topology.get_content_fingerprint()
	record.discovered_at = p_discovered_at
	record.cell_count = topology.get_cell_count()
	return record


## 从当前严格 schema 恢复记录。
## @param data: 完整持久化字典。
static func from_dict(data: Dictionary) -> BoardDiscoveryRecord:
	if not _has_strict_shape(data):
		return null
	var record: BoardDiscoveryRecord = BoardDiscoveryRecord.new()
	record.board_key = GFVariantData.get_option_string(data, "board_key")
	record.topology_id = StringName(GFVariantData.get_option_string(data, "topology_id"))
	record.content_fingerprint = GFVariantData.get_option_string(data, "content_fingerprint")
	record.discovered_at = GFVariantData.get_option_int(data, "discovered_at")
	record.cell_count = GFVariantData.get_option_int(data, "cell_count")
	if (
		record.topology_id == &""
		or record.content_fingerprint.length() != 16
		or record.board_key != "%s@%s" % [record.topology_id, record.content_fingerprint]
		or record.discovered_at <= 0
		or record.cell_count <= 0
	):
		return null
	return record


## 导出严格持久化字典。
func to_dict() -> Dictionary:
	return {
		"board_key": board_key,
		"topology_id": String(topology_id),
		"content_fingerprint": content_fingerprint,
		"discovered_at": discovered_at,
		"cell_count": cell_count,
	}


# --- 私有/辅助方法 ---

static func _has_strict_shape(data: Dictionary) -> bool:
	return (
		data.size() == 5
		and GFVariantData.get_option_value(data, "board_key") is String
		and GFVariantData.get_option_value(data, "topology_id") is String
		and GFVariantData.get_option_value(data, "content_fingerprint") is String
		and GFVariantData.get_option_value(data, "discovered_at") is int
		and GFVariantData.get_option_value(data, "cell_count") is int
	)
