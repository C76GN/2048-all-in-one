## ModeRuleProof: 用一行静态数值关系提示当前模式的核心规则。
##
## 组件刻意不重复模式名、规则标题或结果说明；完整语义由相邻的模式卡承担，
## 这里仅保留无需动效也能读懂的输入、运算关系与结果。
class_name ModeRuleProof
extends VBoxContainer


# --- 私有变量 ---

var _descriptor: ModeRuleProofDescriptor = null
var _style_utility: GameUiStyleUtility = null


# --- @onready 变量 (节点引用) ---

@onready var _source_a_plate: PanelContainer = %SourceAPlate
@onready var _source_a_value: Label = %SourceAValue
@onready var _source_a_tag: Label = %SourceATag
@onready var _operator_label: Label = %OperatorLabel
@onready var _source_b_plate: PanelContainer = %SourceBPlate
@onready var _source_b_value: Label = %SourceBValue
@onready var _source_b_tag: Label = %SourceBTag
@onready var _result_plate: PanelContainer = %ResultPlate
@onready var _result_value: Label = %ResultValue
@onready var _result_tag: Label = %ResultTag
@onready var _accent_bar: ColorRect = %AccentBar


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_values()
	_apply_style()


# --- 公共方法 ---

## 绑定当前规则的紧凑示例。保留 mode_config 参数以兼容既有调用，但不显示模式名。
## @param descriptor: 与当前规则集对应、只属于导航展示层的样张描述。
## @param _mode_config: 兼容参数；组件不再从中读取重复的模式名称。
## @param style_utility: 父控制器注入的主题静态样式服务；允许为空。
func present(
	descriptor: ModeRuleProofDescriptor,
	_mode_config: GameModeConfig,
	style_utility: GameUiStyleUtility
) -> void:
	_descriptor = descriptor
	_style_utility = style_utility
	if not is_instance_valid(_descriptor) or not _descriptor.is_valid_descriptor():
		visible = false
		return
	visible = true
	if is_node_ready():
		_update_values()
		_apply_style()


func get_descriptor() -> ModeRuleProofDescriptor:
	return _descriptor


# --- 私有/辅助方法 ---

func _update_values() -> void:
	if not is_node_ready() or not is_instance_valid(_descriptor):
		return
	_source_a_value.text = _descriptor.source_a
	_source_a_tag.text = _descriptor.source_a_tag
	_operator_label.text = _descriptor.operator_symbol
	_source_b_value.text = _descriptor.source_b
	_source_b_tag.text = _descriptor.source_b_tag
	_result_value.text = _descriptor.result
	_result_tag.text = _descriptor.result_tag



func _apply_style() -> void:
	if not is_node_ready() or not is_instance_valid(_style_utility):
		return
	_style_utility.style_label(_source_a_value, GameUiStyleUtility.TextRole.NUMERIC, 26)
	_style_utility.style_label(_source_b_value, GameUiStyleUtility.TextRole.NUMERIC, 26)
	_style_utility.style_label(_result_value, GameUiStyleUtility.TextRole.NUMERIC, 28)
	_style_utility.style_label(_source_a_tag, GameUiStyleUtility.TextRole.MUTED, 9)
	_style_utility.style_label(_source_b_tag, GameUiStyleUtility.TextRole.MUTED, 9)
	_style_utility.style_label(_result_tag, GameUiStyleUtility.TextRole.MUTED, 9)
	_style_utility.style_label(_operator_label, GameUiStyleUtility.TextRole.SECONDARY, 20)
	for plate: PanelContainer in [_source_a_plate, _source_b_plate]:
		_style_utility.style_panel_container(
			plate,
			GameUiStyleUtility.SurfaceRole.FIELD,
			GameUiStyleUtility.BorderRole.DEFAULT,
			1
		)
	_style_utility.style_panel_container(
		_result_plate,
		GameUiStyleUtility.SurfaceRole.FIELD,
		GameUiStyleUtility.BorderRole.SELECTED,
		1
	)

	var result_style: StyleBox = _result_plate.get_theme_stylebox("panel")
	if result_style is StyleBoxFlat:
		var flat_style: StyleBoxFlat = result_style
		_accent_bar.color = flat_style.border_color
	else:
		_accent_bar.color = _result_value.get_theme_color("font_color")


## 模式卡仍以同一份规则词汇表生成一行差异文案；样张自身不显示该文案。
static func _get_formula_fallback(ruleset_id: StringName) -> String:
	match ruleset_id:
		&"gameplay.classic": return "Equal values double"
		&"gameplay.fibonacci": return "Adjacent sequence terms add"
		&"gameplay.lucas_fibonacci": return "Bridge terms form a Lucas value"
		&"gameplay.progressive": return "High merges expand the spawn pool"
		&"gameplay.step_by_step": return "One cell per command"
		&"gameplay.ratio": return "Cross-family tiles resolve by quotient"
	return "Rule proof"
