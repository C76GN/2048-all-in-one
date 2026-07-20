## GameClockUtility: 项目 wall-clock 时间 Adapter。
##
## GFTimeUtility 负责游戏 delta、缩放和暂停；本 Module 共享 GFClock，并只补充
## 项目需要的秒级时间戳、短文件名 tick 和用户可读日期格式。
class_name GameClockUtility
extends "res://addons/gf/kernel/base/gf_utility.gd"


# --- 私有变量 ---

var _clock: GFClock = GFClock.new()


# --- 公共方法 ---

## 注入项目统一时钟；测试可使用 GFManualClock。
## @param clock: Composition Root 拥有的共享 GF 时钟。
func set_clock(clock: GFClock) -> bool:
	if clock == null:
		return false
	_clock = clock
	return true


func get_clock() -> GFClock:
	return _clock


func get_unix_timestamp() -> int:
	return _clock.get_unix_time_seconds()


func get_tick_msec() -> int:
	return _clock.get_monotonic_msec()


## @param timestamp: Unix 时间戳，秒。
func format_datetime(timestamp: int) -> String:
	return format_datetime_value(timestamp)


## @param timestamp: Unix 时间戳，秒。
static func format_datetime_value(timestamp: int) -> String:
	if timestamp <= 0:
		return ""
	return Time.get_datetime_string_from_unix_time(timestamp).replace("T", " ")
