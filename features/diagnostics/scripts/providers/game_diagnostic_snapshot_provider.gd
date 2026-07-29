## GameDiagnosticSnapshotProvider: 把项目只读采集函数适配为 GF 惰性诊断 Provider。
class_name GameDiagnosticSnapshotProvider
extends GFDiagnosticSnapshotProvider


# --- 私有变量 ---

var _collector: Callable


# --- 公共方法 ---

## 配置稳定 Provider 身份及其同步、有界、只读采集函数。
func configure_collector(
	p_provider_id: StringName,
	collector: Callable,
	options: Dictionary = {}
) -> GameDiagnosticSnapshotProvider:
	var _configured: GFDiagnosticSnapshotProvider = configure(
		p_provider_id,
		options
	)
	_collector = collector
	return self


# --- 可重写钩子 ---

func _collect_snapshot(
	_request: Dictionary = {}
) -> GFDiagnosticProviderResult:
	if not _collector.is_valid():
		return GFDiagnosticProviderResult.failed(
			&"collector_unavailable",
			"Project diagnostic collector is unavailable."
		)
	var value: Variant = _collector.call()
	if not value is Dictionary:
		return GFDiagnosticProviderResult.failed(
			&"invalid_collector_result",
			"Project diagnostic collector must return a Dictionary."
		)
	return GFDiagnosticProviderResult.succeeded(value)
