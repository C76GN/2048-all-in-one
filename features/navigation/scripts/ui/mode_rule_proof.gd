## ModeRuleProof: 把模式规则展示成静态可读的数字印刷样张。
##
## 输入、运算关系和结果始终同时存在；动效只用于内容切换反馈，关闭动效时
## 不会损失任何规则信息。
class_name ModeRuleProof
extends VBoxContainer


# --- 常量 ---

const _ACCENT_COLORS: Array[Color] = [
	Color(0.29411766, 0.7411765, 0.77254903, 1.0),
	Color(0.8745098, 0.29411766, 0.6039216, 1.0),
	Color(0.9372549, 0.81960785, 0.3647059, 1.0),
]


# --- 私有变量 ---

var _descriptor: ModeRuleProofDescriptor = null
var _style_utility: GameUiStyleUtility = null


# --- @onready 变量 (节点引用) ---

@onready var _kicker_label: Label = %ProofKickerLabel
@onready var _proof_number_label: Label = %ProofNumberLabel
@onready var _mode_name_label: Label = %ProofModeNameLabel
@onready var _formula_label: Label = %ProofFormulaLabel
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
@onready var _outcome_label: Label = %OutcomeLabel
@onready var _accent_bar: ColorRect = %AccentBar


# --- Godot 生命周期方法 ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_text()
	_apply_style()


# --- 公共方法 ---

## 绑定一张导航层样张；mode_config 仅提供模式名称，规则解释来自 descriptor。
## @param descriptor: 与当前规则集对应、只属于导航展示层的样张描述。
## @param mode_config: 当前已解析的玩法模式配置，仅用于读取本地化模式名称。
## @param style_utility: 父控制器注入的主题静态样式服务；允许为空。
func present(
	descriptor: ModeRuleProofDescriptor,
	mode_config: GameModeConfig,
	style_utility: GameUiStyleUtility
) -> void:
	_descriptor = descriptor
	_style_utility = style_utility
	if not is_instance_valid(_descriptor) or not _descriptor.is_valid_descriptor():
		visible = false
		return
	visible = true
	if is_node_ready():
		_mode_name_label.text = (
			tr(mode_config.mode_name)
			if is_instance_valid(mode_config)
			else tr("UI_ERROR")
		)
		_update_text()
		_apply_style()


func get_descriptor() -> ModeRuleProofDescriptor:
	return _descriptor


# --- 私有/辅助方法 ---

func _update_text() -> void:
	if not is_node_ready():
		return
	_kicker_label.text = _translated_format("MODE_PROOF_KICKER", "RULE PROOF")
	if not is_instance_valid(_descriptor):
		return
	_proof_number_label.text = _translated_format(
		"MODE_PROOF_NUMBER_FORMAT",
		"PROOF %s"
	) % _descriptor.proof_number
	_formula_label.text = _translated_text(
		_descriptor.formula_key,
		_get_formula_fallback(_descriptor.ruleset_id)
	)
	_source_a_value.text = _descriptor.source_a
	_source_a_tag.text = _descriptor.source_a_tag
	_operator_label.text = _descriptor.operator_symbol
	_source_b_value.text = _descriptor.source_b
	_source_b_tag.text = _descriptor.source_b_tag
	_result_value.text = _descriptor.result
	_result_tag.text = _descriptor.result_tag
	_outcome_label.text = _translated_text(
		_descriptor.outcome_key,
		_get_outcome_fallback(_descriptor.ruleset_id)
	)
	var accent_index: int = clampi(int(_descriptor.accent_role), 0, _ACCENT_COLORS.size() - 1)
	_accent_bar.color = _ACCENT_COLORS[accent_index]


func _apply_style() -> void:
	if not is_node_ready() or not is_instance_valid(_style_utility):
		return
	_style_utility.style_label(_kicker_label, GameUiStyleUtility.TextRole.MUTED, 13)
	_style_utility.style_label(_proof_number_label, GameUiStyleUtility.TextRole.NUMERIC, 13)
	_style_utility.style_label(
		_mode_name_label,
		GameUiStyleUtility.TextRole.DISPLAY,
		26,
		true
	)
	_style_utility.style_label(_formula_label, GameUiStyleUtility.TextRole.SECONDARY, 15)
	_style_utility.style_label(_source_a_value, GameUiStyleUtility.TextRole.NUMERIC, 24)
	_style_utility.style_label(_source_b_value, GameUiStyleUtility.TextRole.NUMERIC, 24)
	_style_utility.style_label(_result_value, GameUiStyleUtility.TextRole.NUMERIC, 28)
	_style_utility.style_label(_source_a_tag, GameUiStyleUtility.TextRole.MUTED, 11)
	_style_utility.style_label(_source_b_tag, GameUiStyleUtility.TextRole.MUTED, 11)
	_style_utility.style_label(_result_tag, GameUiStyleUtility.TextRole.MUTED, 11)
	_style_utility.style_label(_operator_label, GameUiStyleUtility.TextRole.DISPLAY, 24)
	_style_utility.style_label(_outcome_label, GameUiStyleUtility.TextRole.SECONDARY, 14)
	for plate: PanelContainer in [_source_a_plate, _source_b_plate]:
		_style_utility.style_panel_container(
			plate,
			GameUiStyleUtility.SurfaceRole.FIELD,
			GameUiStyleUtility.BorderRole.DEFAULT,
			1
		)
	_style_utility.style_panel_container(
		_result_plate,
		GameUiStyleUtility.SurfaceRole.SELECTED,
		GameUiStyleUtility.BorderRole.SELECTED,
		2
	)


func _translated_text(key: StringName, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == String(key) else translated


func _translated_format(key: String, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == key else translated


static func _get_formula_fallback(ruleset_id: StringName) -> String:
	match ruleset_id:
		&"gameplay.classic": return "Equal values double"
		&"gameplay.fibonacci": return "Adjacent sequence terms add"
		&"gameplay.lucas_fibonacci": return "Bridge terms form a Lucas value"
		&"gameplay.progressive": return "High merges expand the spawn pool"
		&"gameplay.step_by_step": return "One cell per command"
		&"gameplay.ratio": return "Cross-family tiles resolve by quotient"
	return "Rule proof"


static func _get_outcome_fallback(ruleset_id: StringName) -> String:
	match ruleset_id:
		&"gameplay.classic": return "Two equal values merge into their double."
		&"gameplay.fibonacci": return "Adjacent Fibonacci values add into the next term."
		&"gameplay.lucas_fibonacci": return "F(n-1) and F(n+1) synthesize L(n)."
		&"gameplay.progressive": return "Merging 2048 adds 8 to the spawn pool."
		&"gameplay.step_by_step": return "Tiles move one cell; classic spawning places a new tile in a random empty cell."
		&"gameplay.ratio": return "Different families divide larger by smaller, with a minimum of 1."
	return "Select a mode to inspect its rule outcome."
