## GameTextFormatUtility: 项目级文本格式化辅助工具。
##
## 负责集中处理翻译格式串缺失或占位符数量不匹配时的 fallback，
## 避免 UI 代码直接对不可信翻译结果执行 `%` 格式化。
class_name GameTextFormatUtility
extends RefCounted


# --- 公共方法 ---

## 使用格式串格式化值；当格式串不可用时回退到 fallback。
## @param template: 已翻译的格式串，通常来自 `tr(KEY)`。
## @param fallback: 项目内置的稳定格式串。
## @param values: 要填入格式串的值。
## @return: 格式化后的文本；若 template 不可用则使用 fallback。
static func format_template(template: String, fallback: String, values: Array) -> String:
	var expected_count: int = values.size()
	var effective_template: String = template
	if _count_format_placeholders(effective_template) != expected_count:
		effective_template = fallback

	if _count_format_placeholders(effective_template) != expected_count:
		return fallback
	return effective_template % values


# --- 私有/辅助方法 ---

static func _count_format_placeholders(template: String) -> int:
	var count: int = 0
	var index: int = 0
	while index < template.length():
		if template.substr(index, 1) != "%":
			index += 1
			continue

		if index + 1 < template.length() and template.substr(index + 1, 1) == "%":
			index += 2
			continue

		count += 1
		index += 1
	return count
