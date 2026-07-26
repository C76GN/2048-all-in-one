## Boot: 极轻量启动首帧壳。
##
## 只负责保持原生启动构图、驱动一个低成本进度扫条，并在线程中加载正式启动编排器。
## GF、主题、场景预载和玩法视觉资源都不得在本脚本中静态引用，否则会重新阻塞首帧。
class_name Boot
extends Control


# --- 常量 ---

const _RUNTIME_SCRIPT_PATH: String = "res://app/scripts/boot_runtime.gd"
const _PULSE_WIDTH: float = 56.0
const _PULSE_SPEED: float = 150.0
const _PROGRESS_FOLLOW_SPEED: float = 5.0
const _PROGRESS_FINISH_SECONDS: float = 0.10
const _DEFAULT_STAGE_MESSAGE: String = "准备启动"


# --- 导出变量 ---

## 视觉验收工具可关闭正式启动编排，仅保留可控的静态进度壳。
@export var auto_start_runtime: bool = true


# --- 私有变量 ---

var _elapsed_seconds: float = 0.0
var _runtime_started: bool = false
var _load_failed: bool = false
var _target_progress: float = 0.0
var _display_progress: float = 0.0
var _stage_message: String = _DEFAULT_STAGE_MESSAGE


# --- @onready 变量 ---

@onready var _startup_pulse: ColorRect = %StartupPulse
@onready var _progress_fill: ColorRect = %ProgressFill
@onready var _progress_clip: Control = %PulseClip
@onready var _stage_label: Label = %StageLabel
@onready var _progress_percent_label: Label = %ProgressPercentLabel


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_progress_text()
	if not auto_start_runtime:
		set_process(false)
		set_runtime_progress(0.62, "准备视觉资源")
		call_deferred(&"_set_display_progress", 0.62)
		return
	if DisplayServer.get_name() == "headless":
		_start_runtime(ResourceLoader.load(_RUNTIME_SCRIPT_PATH, "GDScript"))
		return
	var request_error: Error = ResourceLoader.load_threaded_request(
		_RUNTIME_SCRIPT_PATH,
		"GDScript",
		true
	)
	if request_error != OK:
		_fail_runtime_load("无法请求启动编排器：%s" % error_string(request_error))
		return
	set_process(true)


func _process(delta: float) -> void:
	_elapsed_seconds += delta
	_update_progress_fill(delta)
	_update_startup_pulse()
	if _runtime_started or _load_failed:
		return

	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		_RUNTIME_SCRIPT_PATH,
		progress
	)
	if not progress.is_empty():
		var load_progress_value: Variant = progress[0]
		if load_progress_value is float:
			var load_progress: float = load_progress_value
			_target_progress = maxf(_target_progress, load_progress * 0.08)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_start_runtime()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_runtime_load("启动编排器加载失败。")


# --- 公共方法 ---

static func are_dev_tools_enabled() -> bool:
	return OS.has_feature("with_dev_tools")


## 接收正式启动编排器进度；静态启动壳始终保留，不发生页面替换。
## @param value: 正式启动流程的归一化目标进度。
## @param message: 当前阶段文案；空字符串保留上一阶段，避免快速回退为默认文案。
func set_runtime_progress(value: float, message: String = "") -> void:
	_target_progress = maxf(_target_progress, clampf(value, 0.0, 1.0))
	if not message.strip_edges().is_empty():
		_stage_message = message.strip_edges()
	_update_progress_text()


## 返回整张启动壳的退出 Tween，供 BootRuntime 在入口场景已预热后等待。
## @param duration_seconds: 启动壳淡出的持续时间。
func create_runtime_outro(duration_seconds: float) -> Tween:
	_target_progress = 1.0
	var tween: Tween = create_tween()
	var progress: MethodTweener = tween.tween_method(
		_set_display_progress,
		_display_progress,
		1.0,
		_PROGRESS_FINISH_SECONDS
	)
	var _progress_curve: Tweener = progress.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var fade: PropertyTweener = tween.tween_property(
		self,
		"modulate:a",
		0.0,
		maxf(duration_seconds, 0.01)
	)
	var _curve: Tweener = fade.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tween


# --- 私有/辅助方法 ---

func _start_runtime(loaded_resource: Resource = null) -> void:
	var runtime_resource: Resource = loaded_resource
	if runtime_resource == null:
		runtime_resource = ResourceLoader.load_threaded_get(_RUNTIME_SCRIPT_PATH)
	if not runtime_resource is Script:
		_fail_runtime_load("启动编排器资源类型不是 Script。")
		return
	var runtime_script: Script = runtime_resource
	var runtime: Control = Control.new()
	runtime.name = "BootRuntime"
	runtime.set_script(runtime_script)
	_set_full_rect(runtime)
	_runtime_started = true
	add_child(runtime)


func _update_startup_pulse() -> void:
	if not is_instance_valid(_startup_pulse) or not is_instance_valid(_progress_fill):
		return
	var fill_width: float = _progress_fill.size.x
	_startup_pulse.visible = fill_width > 1.0
	if fill_width <= 1.0:
		return
	var travel_distance: float = fill_width + _PULSE_WIDTH
	var travel: float = fposmod(_elapsed_seconds * _PULSE_SPEED, travel_distance)
	_startup_pulse.position.x = travel - _PULSE_WIDTH
	_startup_pulse.modulate.a = 0.28 + sin(_elapsed_seconds * 4.0) * 0.08


func _update_progress_fill(delta: float) -> void:
	if not is_instance_valid(_progress_fill):
		return
	_set_display_progress(move_toward(
		_display_progress,
		_target_progress,
		delta * _PROGRESS_FOLLOW_SPEED
	))


func _set_display_progress(value: float) -> void:
	_display_progress = clampf(value, 0.0, 1.0)
	if not is_instance_valid(_progress_fill):
		return
	var available_width: float = 0.0
	if is_instance_valid(_progress_clip):
		available_width = maxf(_progress_clip.size.x, 0.0)
	_progress_fill.size.x = floorf(available_width * _display_progress)
	_update_progress_text()


func _fail_runtime_load(message: String) -> void:
	_load_failed = true
	_target_progress = 1.0
	_stage_message = "启动失败"
	_update_progress_text()
	if is_instance_valid(_startup_pulse):
		_startup_pulse.color = Color(0.72, 0.28, 0.24, 0.72)
	if is_instance_valid(_progress_fill):
		_progress_fill.color = Color(0.72, 0.28, 0.24, 0.86)
	push_error("[Boot] %s" % message)


func _update_progress_text() -> void:
	if is_instance_valid(_stage_label):
		_stage_label.text = _stage_message
	if is_instance_valid(_progress_percent_label):
		_progress_percent_label.text = "%d%%" % roundi(_display_progress * 100.0)


func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
