## GameClockUtility: 项目 wall-clock 时间 Adapter。
##
## GFTimeUtility 负责游戏 delta、缩放和暂停；本 Module 只集中处理系统时间戳、
## 短文件名 tick 和用户可读日期格式。
class_name GameClockUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 公共方法 ---

func get_unix_timestamp() -> int:
	return int(Time.get_unix_time_from_system())


func get_tick_msec() -> int:
	return Time.get_ticks_msec()


## @param timestamp: Unix 时间戳，秒。
func format_datetime(timestamp: int) -> String:
	return format_datetime_value(timestamp)


## @param timestamp: Unix 时间戳，秒。
static func format_datetime_value(timestamp: int) -> String:
	if timestamp <= 0:
		return ""
	return Time.get_datetime_string_from_unix_time(timestamp).replace("T", " ")
