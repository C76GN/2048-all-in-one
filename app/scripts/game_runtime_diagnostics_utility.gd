## GameRuntimeDiagnosticsUtility: GF 10 发布态诊断临时适配。
##
## GFDiagnosticsUtility 把 Console 视为可选能力，但当前版本通过严格
## get_utility() 探测，未安装 Console 时会产生依赖缺失错误。本适配只把该探测
## 收窄到当前 Architecture 的无报错 local lookup；其余初始化与诊断行为仍由
## GFDiagnosticsUtility 完整拥有。上游修复可选依赖查询后应删除本脚本。
class_name GameRuntimeDiagnosticsUtility
extends GFDiagnosticsUtility


# --- 私有/辅助方法 ---

func _get_console_utility() -> GFConsoleUtility:
	var architecture: GFArchitecture = _get_architecture_or_null()
	if architecture == null:
		return null
	var utility: Object = architecture.get_local_utility(GFConsoleUtility)
	if utility is GFConsoleUtility:
		var console_utility: GFConsoleUtility = utility
		return console_utility
	return null
