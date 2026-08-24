## 为验证工具构造“数据中的资源路径”，避免把扫描根或虚拟 fixture 误报为模块依赖。
##
## 真实 preload/load 路径不得使用本 Helper 隐藏；它只用于目录扫描边界、事件证据和
## 明确不存在的负例路径。静态依赖仍应写成完整资源路径并进入项目所有权合同。
class_name VerificationResourcePath
extends RefCounted


const ROOT: String = "res:/" + "/"
const FEATURES_ROOT: String = ROOT + "features"


## 从项目相对片段构造验证数据路径。
## @param relative_path: 不带 scheme 的项目相对片段。
## @return: 规范的项目资源数据路径；非法空片段返回资源根。
static func make(relative_path: String) -> String:
	var normalized: String = relative_path.strip_edges().replace("\\", "/")
	if normalized.begins_with(ROOT):
		normalized = normalized.trim_prefix(ROOT)
	normalized = normalized.trim_prefix("/").simplify_path()
	if normalized == ".":
		normalized = ""
	return ROOT + normalized
