## GameDiagnosticSnapshotProvider: 把项目只读采集函数适配为 GF 惰性诊断 Provider。
class_name GameDiagnosticSnapshotProvider
extends GFDiagnosticSnapshotProvider


# --- 私有变量 ---

var _collector_owner_ref: WeakRef = null


# --- 公共方法 ---

## 配置稳定 Provider 身份及其同步、有界、只读采集函数。
## @param p_provider_id: 稳定 Provider 标识。
## @param collector_owner: 提供强类型采集入口的项目诊断 Utility。
## @param options: GF Provider 时长预算与目录元数据。
func configure_collector(
	p_provider_id: StringName,
	collector_owner: GameDiagnosticsUtility,
	options: Dictionary = {}
) -> GameDiagnosticSnapshotProvider:
	var _configured: GFDiagnosticSnapshotProvider = configure(
		p_provider_id,
		options
	)
	_collector_owner_ref = (
		weakref(collector_owner)
		if collector_owner != null
		else null
	)
	return self


# --- 可重写钩子 ---

func _collect_snapshot(
	_request: Dictionary = {}
) -> GFDiagnosticProviderResult:
	var collector_owner_value: Object = (
		_collector_owner_ref.get_ref()
		if _collector_owner_ref != null
		else null
	)
	if not collector_owner_value is GameDiagnosticsUtility:
		return GFDiagnosticProviderResult.failed(
			&"collector_unavailable",
			"Project diagnostic collector is unavailable."
		)
	var collector_owner: GameDiagnosticsUtility = collector_owner_value
	return GFDiagnosticProviderResult.succeeded(
		collector_owner.collect_diagnostic_snapshot(provider_id)
	)
