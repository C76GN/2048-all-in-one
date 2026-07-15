## GameUiController: 主题化游戏 UI 宿主，通过内部 GFController 连接 GF 架构。
##
## 适用于菜单、弹窗等 Control 派生节点。主题 Feature 拥有该表现层宿主，
## GFController 负责架构上下文和事件生命周期，主题 Utility 负责视觉与交互动效。
class_name GameUiController
extends Control


# --- 常量 ---

const _GAME_UI_MOTION_UTILITY_SCRIPT: Script = preload(
	"res://features/themes/scripts/utilities/game_ui_motion_utility.gd"
)
const _GAME_THEME_UTILITY_SCRIPT: Script = preload(
	"res://features/themes/scripts/utilities/game_theme_utility.gd"
)


# --- 私有变量 ---

var _gf_controller: GFController


# --- Godot 生命周期方法 ---

func _init() -> void:
	_gf_controller = GFController.new()
	_gf_controller.name = "GFController"
	add_child(_gf_controller, false, Node.INTERNAL_MODE_BACK)


func _enter_tree() -> void:
	call_deferred(&"_apply_default_ui_motion")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_ui_text()


# --- 获取方法 ---

## 获取当前 UI 所属架构；未初始化时返回 null。
func get_architecture_or_null() -> GFArchitecture:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_architecture_or_null()


## 通过类型获取 Model 实例。
## @param model_type: 要查找的 Model 脚本类型。
func get_model(model_type: Script) -> Object:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_model(model_type)


## 通过类型获取 System 实例。
## @param system_type: 要查找的 System 脚本类型。
func get_system(system_type: Script) -> Object:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_system(system_type)


## 通过类型获取 Utility 实例。
## @param utility_type: 要查找的 Utility 脚本类型。
func get_utility(utility_type: Script) -> Object:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.get_utility(utility_type)


# --- 命令与查询 ---

## 向架构发送命令。
## @param command: 要执行的命令对象。
func send_command(command: Object) -> Variant:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.send_command(command)


## 执行查询并返回结果。
## @param query: 要执行的查询对象。
func send_query(query: Object) -> Variant:
	if not is_instance_valid(_gf_controller):
		return null
	return _gf_controller.send_query(query)


# --- 事件系统 ---

## 注册类型事件监听器。
## @param event_type: 类型事件的脚本类型。
## @param listener: 显式的 GF 事件监听契约。
## @param priority: 监听器优先级。
func register_event(event_type: Script, listener: GFEventListener, priority: int = 0) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.register_event(event_type, listener, priority)


## 注销类型事件监听器。
## @param event_type: 类型事件的脚本类型。
## @param listener: 注册时使用的监听契约。
func unregister_event(event_type: Script, listener: GFEventListener) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.unregister_event(event_type, listener)


## 发送类型事件。
## @param event_instance: 要派发的事件对象。
func send_event(event_instance: Object) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.send_event(event_instance)


## 注册轻量级 StringName 事件监听器。
## @param event_id: 简单事件标识。
## @param listener: 显式的 GF 事件监听契约。
func register_simple_event(event_id: StringName, listener: GFEventListener) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.register_simple_event(event_id, listener)


## 注销轻量级 StringName 事件监听器。
## @param event_id: 简单事件标识。
## @param listener: 注册时使用的监听契约。
func unregister_simple_event(event_id: StringName, listener: GFEventListener) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.unregister_simple_event(event_id, listener)


## 发送轻量级 StringName 事件。
## @param event_id: 简单事件标识。
## @param payload: 可选事件载荷。
func send_simple_event(event_id: StringName, payload: Variant = null) -> void:
	if is_instance_valid(_gf_controller):
		_gf_controller.send_simple_event(event_id, payload)


# --- 虚方法 ---

## 更新 UI 文本，子类应在此实现本地化逻辑。
func _update_ui_text() -> void:
	pass


# --- 私有/辅助方法 ---

func _apply_default_ui_motion() -> void:
	if not is_inside_tree():
		return

	var motion_utility: GameUiMotionUtility = _get_ui_motion_utility()
	if not is_instance_valid(motion_utility):
		return

	var theme_utility: GameThemeUtility = _get_theme_utility()
	if is_instance_valid(theme_utility):
		var _theme_apply_count: int = theme_utility.apply_current_theme_to_tree(self)

	var _bound_count: int = motion_utility.bind_interactive_controls(self)
	var _intro_tween: Tween = motion_utility.play_panel_intro(self)


func _get_ui_motion_utility() -> GameUiMotionUtility:
	var utility_value: Object = get_utility(_GAME_UI_MOTION_UTILITY_SCRIPT)
	if utility_value is GameUiMotionUtility:
		var motion_utility: GameUiMotionUtility = utility_value
		return motion_utility
	return null


func _get_theme_utility() -> GameThemeUtility:
	var utility_value: Object = get_utility(_GAME_THEME_UTILITY_SCRIPT)
	if utility_value is GameThemeUtility:
		var theme_utility: GameThemeUtility = utility_value
		return theme_utility
	return null
