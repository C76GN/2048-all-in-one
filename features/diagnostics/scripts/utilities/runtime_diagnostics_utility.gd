## RuntimeDiagnosticsUtility: 无调试 UI 的 GF 诊断聚合核心。
##
## `gf.action_queue` 会向 GFDiagnosticsUtility 发布运行时快照；普通玩家构建因此仍注册
## 聚合接口，但不触发 GFConsoleUtility 的可选查询。显式 `with_dev_tools` 构建会先注册
## Console，此时恢复 GFDiagnosticsUtility 的标准 ready 行为。
class_name RuntimeDiagnosticsUtility
extends GFDiagnosticsUtility


# --- 常量 ---

const _DEV_TOOLS_FEATURE: String = "with_dev_tools"


# --- GF 生命周期方法 ---

func ready() -> void:
	if OS.has_feature(_DEV_TOOLS_FEATURE):
		super.ready()
