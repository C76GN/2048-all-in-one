## GameAccessibilitySummary: 字幕、棋盘摘要与平台辅助技术共享的只读语义结果。
class_name GameAccessibilitySummary
extends RefCounted


# --- 常量 ---

const SCHEMA_VERSION: int = 1
const KIND_BOARD: StringName = &"board"
const KIND_TURN: StringName = &"turn"


# --- 公共变量 ---

var sequence: int = 0
var kind: StringName = &""
var board_checksum: String = ""
var canonical_payload: Dictionary = {}
var announcement_text: String = ""
var subtitle_text: String = ""
var board_text: String = ""


# --- 公共方法 ---

func is_valid_summary() -> bool:
	return (
		sequence >= 0
		and kind in [KIND_BOARD, KIND_TURN]
		and board_checksum.length() == 64
		and not canonical_payload.is_empty()
		and GFVariantData.get_option_int(
			canonical_payload,
			&"schema_version",
			0
		) == SCHEMA_VERSION
		and GFVariantData.get_option_string_name(
			canonical_payload,
			&"kind"
		) == kind
		and not announcement_text.is_empty()
		and not subtitle_text.is_empty()
		and not board_text.is_empty()
	)


func duplicate_summary() -> GameAccessibilitySummary:
	var result: GameAccessibilitySummary = GameAccessibilitySummary.new()
	result.sequence = sequence
	result.kind = kind
	result.board_checksum = board_checksum
	result.canonical_payload = canonical_payload.duplicate(true)
	result.announcement_text = announcement_text
	result.subtitle_text = subtitle_text
	result.board_text = board_text
	return result


func to_dict() -> Dictionary:
	return {
		&"schema_version": SCHEMA_VERSION,
		&"sequence": sequence,
		&"kind": kind,
		&"board_checksum": board_checksum,
		&"canonical_payload": canonical_payload.duplicate(true),
		&"announcement_text": announcement_text,
		&"subtitle_text": subtitle_text,
		&"board_text": board_text,
	}
