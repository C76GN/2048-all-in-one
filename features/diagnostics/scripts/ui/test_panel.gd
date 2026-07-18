## TestPanel: 一个动态的、由规则驱动的测试和调试工具面板。
##
## 该脚本负责管理测试面板的 UI 交互。它不再硬编码任何数值或定义，
## 而是通过外部数据来动态填充选项。它允许开发者在运行时手动生成
## 符合当前游戏模式规则的方块，或调整棋盘大小。
class_name TestPanel
extends "res://addons/gf/kernel/base/gf_controller.gd"


# --- 私有变量 ---

var _signal_utility: GFSignalUtility


# --- @onready 变量 (节点引用) ---

@onready var _pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var _pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var _value_option_button: OptionButton = %ValueOptionButton
@onready var _definition_option_button: OptionButton = %DefinitionOptionButton
@onready var _spawn_button: Button = %SpawnButton
@onready var _grid_size_spinbox: SpinBox = %GridSizeSpinBox
@onready var _reset_resize_button: Button = %ResetResizeButton
@onready var _live_expand_button: Button = %LiveExpandButton


# --- Godot 生命周期方法 ---

func _ready() -> void:
	_signal_utility = _get_signal_utility()
	if not is_instance_valid(_signal_utility):
		push_error("[TestPanel] 缺少 GFSignalUtility，测试控件无法连接。")
		return
	var _spawn_connection: GFSignalConnection = _signal_utility.connect_signal(
		_spawn_button.pressed,
		_on_spawn_button_pressed,
		self
	)
	var _reset_connection: GFSignalConnection = _signal_utility.connect_signal(
		_reset_resize_button.pressed,
		_on_reset_resize_button_pressed,
		self
	)
	var _expand_connection: GFSignalConnection = _signal_utility.connect_signal(
		_live_expand_button.pressed,
		_on_live_expand_button_pressed,
		self
	)
	var _definition_connection: GFSignalConnection = _signal_utility.connect_signal(
		_definition_option_button.item_selected,
		_on_definition_selected,
		self
	)


func _exit_tree() -> void:
	if is_instance_valid(_signal_utility):
		_signal_utility.disconnect_owner(self)
	_signal_utility = null
	super._exit_tree()


# --- 公共方法 ---

## 初始化并设置测试面板的所有选项。由 GamePlayController 在游戏开始时调用。
##
## @param options: 一个字典 {id: "name", ...} 用于填充方块定义下拉菜单。
func setup_panel(options: Dictionary) -> void:
	var option_ids: Array = options.keys()
	option_ids.sort()
	var items: Array[Dictionary] = []

	for option_id_value: Variant in option_ids:
		var option_id: int = _variant_to_int(option_id_value, 0)
		var option_name: String = GFVariantData.to_text(options[option_id_value], "")
		items.append(_make_option_item(option_name, option_id, option_id))

	_write_option_items(_definition_option_button, items)

	# 初始时，自动为第一个定义请求数值列表。
	if not option_ids.is_empty():
		_on_definition_selected(0)


## 更新“数值”下拉列表的内容。由 GamePlayController 在收到新数值时调用。
##
## @param values: 一个包含所有可选数值(int)的数组。
func update_value_options(values: Array[int]) -> void:
	var items: Array[Dictionary] = []
	for v: int in values:
		items.append(_make_option_item(str(v), v, v))
	_write_option_items(_value_option_button, items)


## 更新生成方块坐标选择器的上限值。
##
## @param bounds_size: 当前棋盘最小包围盒尺寸。
func update_coordinate_limits(bounds_size: Vector2i) -> void:
	var max_x: int = maxi(bounds_size.x - 1, 0)
	var max_y: int = maxi(bounds_size.y - 1, 0)
	_pos_x_spinbox.max_value = max_x
	_pos_y_spinbox.max_value = max_y

	# 同时限制当前值，防止因缩小棋盘导致值超出范围。
	_pos_x_spinbox.value = min(_pos_x_spinbox.value, max_x)
	_pos_y_spinbox.value = min(_pos_y_spinbox.value, max_y)


# --- 私有/辅助方法 ---

static func _variant_to_int(value: Variant, default_value: int) -> int:
	if value is int:
		return value
	if value is float:
		var float_value: float = value
		return int(float_value)
	return default_value


func _get_signal_utility() -> GFSignalUtility:
	var utility_value: Object = get_utility(GFSignalUtility, true)
	if utility_value is GFSignalUtility:
		var signal_utility: GFSignalUtility = utility_value
		return signal_utility
	return null


func _write_option_items(option: OptionButton, items: Array[Dictionary]) -> void:
	var _written_count: int = GFItemListBinder.write_items(option, items, {
		"text_key": &"text",
		"id_key": &"id",
		"metadata_key": &"metadata",
	})


static func _make_option_item(text: String, metadata: Variant, item_id: int) -> Dictionary:
	return {
		"text": text,
		"metadata": metadata,
		"id": item_id,
	}


# --- 信号处理函数 ---

## 响应“生成方块”按钮的点击事件。
func _on_spawn_button_pressed() -> void:
	if _value_option_button.item_count == 0:
		push_warning("[TestPanel] 没有可选的生成数值。")
		return
	if _definition_option_button.item_count == 0:
		push_warning("[TestPanel] 没有可选的方块定义。")
		return

	var pos: Vector2i = Vector2i(int(_pos_x_spinbox.value), int(_pos_y_spinbox.value))
	var value: int = _variant_to_int(
		GFItemListBinder.get_item_metadata(_value_option_button, _value_option_button.selected, 0),
		0
	)
	var option_id: int = _variant_to_int(
		GFItemListBinder.get_item_metadata(
			_definition_option_button,
			_definition_option_button.selected,
			0
		),
		0
	)

	send_event(TestSpawnPayload.new(pos, value, option_id))


## 响应“重置并调整大小”按钮的点击事件。
func _on_reset_resize_button_pressed() -> void:
	var new_size: int = int(_grid_size_spinbox.value)
	send_simple_event(EventNames.TEST_RESET_RESIZE_REQUESTED, new_size)


## 响应“游戏中扩建棋盘”按钮的点击事件。
func _on_live_expand_button_pressed() -> void:
	var new_size: int = int(_grid_size_spinbox.value)
	send_simple_event(EventNames.TEST_LIVE_EXPAND_REQUESTED, new_size)


## 当方块定义下拉菜单中的选项被改变时调用。
## @param index: 被选中项的索引。
func _on_definition_selected(index: int) -> void:
	if index < 0 or index >= _definition_option_button.item_count:
		return

	var option_id: int = _variant_to_int(
		GFItemListBinder.get_item_metadata(_definition_option_button, index, 0),
		0
	)
	send_simple_event(EventNames.TEST_VALUES_REQUESTED, option_id)
