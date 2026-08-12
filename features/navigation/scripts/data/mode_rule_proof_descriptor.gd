## ModeRuleProofDescriptor: 模式选择页的导航层规则样张描述。
##
## 它只拥有“如何向玩家解释一条已存在规则”的展示数据，不参与玩法判定，
## 也不会进入 GameModeConfig 或确定性指纹。
class_name ModeRuleProofDescriptor
extends Resource


# --- 枚举 ---

## 样张使用的套印强调色角色。
enum AccentRole {
	CYAN,
	MAGENTA,
	YELLOW,
}


# --- 导出变量 ---

## 对应 GameModeConfig.ruleset_id 的稳定规则集 ID。
@export var ruleset_id: StringName = &""

## 在模式索引中显示的稳定样张编号。
@export var proof_number: String = "00"

## 样张公式的翻译键。
@export var formula_key: StringName = &""

## 输入、关系与结果均是短小的数学/棋盘记号，不承载长句文案。
@export var source_a: String = ""
@export var source_a_tag: String = ""
@export var operator_symbol: String = "+"
@export var source_b: String = ""
@export var source_b_tag: String = ""
@export var result: String = ""
@export var result_tag: String = ""

## 对结果因果关系的翻译键；必须在静态终态中可见。
@export var outcome_key: StringName = &""

## 套印强调角色，只影响识别，不承担规则含义。
@export var accent_role: AccentRole = AccentRole.CYAN


# --- 公共方法 ---

## 判断描述是否具备构成一张静态可读样张的最低数据。
func is_valid_descriptor() -> bool:
	return (
		ruleset_id != &""
		and not proof_number.is_empty()
		and formula_key != &""
		and not source_a.is_empty()
		and not source_b.is_empty()
		and not result.is_empty()
		and outcome_key != &""
	)
