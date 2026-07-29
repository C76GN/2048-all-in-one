## GameShaderAnimationDriver: 为项目自有 CanvasItem shader 提供可暂停的时间源。
##
## Godot 的内置 TIME 会在窗口失焦后继续推进，重新聚焦时会产生视觉跳变。
## 该节点仅在目标可见、应用聚焦且动效启用时累计时间，并可在静态策略下
## 临时卸载 ShaderMaterial，避免 reduced-motion / shader-off 仍产生片元开销。
class_name GameShaderAnimationDriver
extends Node


# --- 常量 ---

const DEFAULT_PARAMETER_NAME: StringName = &"animation_time"
const _MAX_TIME_SECONDS: float = 3600.0


# --- 私有变量 ---

var _target: CanvasItem = null
var _shader_material: ShaderMaterial = null
var _parameter_name: StringName = DEFAULT_PARAMETER_NAME
var _animation_time: float = 0.0
var _animation_enabled: bool = true
var _application_focused: bool = true
var _detach_material_when_disabled: bool = true


# --- 生命周期方法 ---

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_refresh_processing()


func _process(delta: float) -> void:
	if not _should_advance():
		return
	_animation_time = fmod(_animation_time + maxf(delta, 0.0), _MAX_TIME_SECONDS)
	_write_animation_time()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_application_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_application_focused(true)


# --- 公共方法 ---

## 绑定目标和 shader 时间参数。可重复调用以同步主题切换后的材质。
## @param target: 持有目标 ShaderMaterial 的画布节点。
## @param parameter_name: 驱动动画时间的 shader 参数名。
func configure(
	target: CanvasItem,
	parameter_name: StringName = DEFAULT_PARAMETER_NAME
) -> GameShaderAnimationDriver:
	if is_instance_valid(_target) and _target.visibility_changed.is_connected(
		_on_target_visibility_changed
	):
		_target.visibility_changed.disconnect(_on_target_visibility_changed)
	_target = target
	_parameter_name = parameter_name
	if is_instance_valid(_target):
		if _target.material is ShaderMaterial:
			_shader_material = _target.material
		if not _target.visibility_changed.is_connected(_on_target_visibility_changed):
			var _connection: int = _target.visibility_changed.connect(
				_on_target_visibility_changed
			)
	_write_animation_time()
	_refresh_processing()
	return self


## 确保已缓存的 ShaderMaterial 回到目标节点，供主题 Profile 原位更新。
func restore_material() -> ShaderMaterial:
	if not is_instance_valid(_target):
		return null
	if _target.material is ShaderMaterial:
		_shader_material = _target.material
	elif is_instance_valid(_shader_material):
		_target.material = _shader_material
	_write_animation_time()
	return _shader_material


## 同步目标当前持有的材质，适用于主题切换或测试替换材质。
func capture_current_material() -> ShaderMaterial:
	if is_instance_valid(_target) and _target.material is ShaderMaterial:
		_shader_material = _target.material
	_write_animation_time()
	return _shader_material


## 切换动态/静态策略；静态策略默认卸载材质并禁用目标处理。
## @param enabled: 是否启用持续 shader 动画。
## @param detach_material_when_disabled: 禁用时是否从目标节点卸载材质。
func set_animation_enabled(
	enabled: bool,
	detach_material_when_disabled: bool = true
) -> void:
	_animation_enabled = enabled
	_detach_material_when_disabled = detach_material_when_disabled
	if not is_instance_valid(_target):
		_refresh_processing()
		return
	if enabled:
		var _restored_material: ShaderMaterial = restore_material()
		_target.process_mode = Node.PROCESS_MODE_INHERIT
	elif detach_material_when_disabled:
		var _captured_material: ShaderMaterial = capture_current_material()
		_target.material = null
		_target.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh_processing()


## 显式同步应用聚焦状态；公开入口也便于无窗口回归测试。
## @param focused: 应用当前是否拥有输入焦点。
func set_application_focused(focused: bool) -> void:
	_application_focused = focused
	_refresh_processing()


func is_animation_enabled() -> bool:
	return _animation_enabled


func is_application_focused() -> bool:
	return _application_focused


func get_animation_time() -> float:
	return _animation_time


func get_shader_material() -> ShaderMaterial:
	return _shader_material


# --- 私有/辅助方法 ---

func _on_target_visibility_changed() -> void:
	_refresh_processing()


func _refresh_processing() -> void:
	set_process(_should_advance())


func _should_advance() -> bool:
	return (
		_animation_enabled
		and _application_focused
		and is_instance_valid(_target)
		and _target.is_visible_in_tree()
		and is_instance_valid(_shader_material)
	)


func _write_animation_time() -> void:
	if is_instance_valid(_shader_material):
		_shader_material.set_shader_parameter(_parameter_name, _animation_time)
