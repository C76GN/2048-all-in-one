## DiscoveryProgressChangedData: 图鉴 SaveGraph 提交成功后的发现进度事件。
class_name DiscoveryProgressChangedData
extends RefCounted


# --- 常量 ---

const KIND_TILE: StringName = &"tile"
const KIND_BOARD: StringName = &"board"


# --- 公共变量 ---

var changed_kind: StringName = &""
var changed_key: String = ""
var tile_composition_count: int = 0
var board_topology_count: int = 0
var max_observed_tile_value: int = 0


# --- Godot 生命周期方法 ---

func _init(
	p_changed_kind: StringName = &"",
	p_changed_key: String = "",
	p_tile_composition_count: int = 0,
	p_board_topology_count: int = 0,
	p_max_observed_tile_value: int = 0
) -> void:
	changed_kind = p_changed_kind
	changed_key = p_changed_key
	tile_composition_count = p_tile_composition_count
	board_topology_count = p_board_topology_count
	max_observed_tile_value = p_max_observed_tile_value


# --- 公共方法 ---

func is_valid() -> bool:
	return (
		changed_kind in [KIND_TILE, KIND_BOARD]
		and not changed_key.is_empty()
		and tile_composition_count >= 0
		and board_topology_count >= 0
		and max_observed_tile_value >= 0
	)
