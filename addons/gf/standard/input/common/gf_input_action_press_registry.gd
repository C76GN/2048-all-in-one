# GFInputActionPressRegistry: 标准输入模块内部 InputMap 动作按压聚合器。
#
# 多个虚拟输入源可共享同一个 InputMap 动作；只有最后一个 owner 释放后才真正释放动作。
extends RefCounted


# --- 私有变量 ---

static var _action_owners: Dictionary = {}


# --- 公共方法 ---

## 以 owner 身份按下动作。
## [br]
## @api framework_internal
## [br]
## @layer standard/input
## [br]
## @param action_id: InputMap 动作名。
## [br]
## @param owner_id: 当前按压来源的稳定 ID。
## [br]
## @param strength: 动作强度。
static func press(action_id: StringName, owner_id: String, strength: float = 1.0) -> void:
	if action_id == &"" or owner_id.is_empty():
		return

	var normalized_strength: float = _normalize_strength(strength)
	if normalized_strength <= 0.0:
		release(action_id, owner_id)
		return

	var owners: Dictionary = _get_or_create_action_owners(action_id)
	owners[owner_id] = normalized_strength
	Input.action_press(action_id, _get_max_strength(owners))


## 释放指定 owner 的动作按压。
## [br]
## @api framework_internal
## [br]
## @layer standard/input
## [br]
## @param action_id: InputMap 动作名。
## [br]
## @param owner_id: 当前按压来源的稳定 ID。
static func release(action_id: StringName, owner_id: String) -> void:
	if action_id == &"" or owner_id.is_empty():
		return

	var owners: Dictionary = _get_action_owners(action_id)
	if owners.is_empty():
		return

	var _removed_owner: bool = owners.erase(owner_id)
	if owners.is_empty():
		var _removed_action: bool = _action_owners.erase(action_id)
		Input.action_release(action_id)
		return

	Input.action_press(action_id, _get_max_strength(owners))


## 释放指定 owner 持有的所有动作。
## [br]
## @api framework_internal
## [br]
## @layer standard/input
## [br]
## @param owner_id: 当前按压来源的稳定 ID。
static func release_owner(owner_id: String) -> void:
	if owner_id.is_empty():
		return

	for action_key: Variant in _action_owners.keys():
		var action_id: StringName = _variant_to_action_id(action_key)
		if action_id != &"":
			release(action_id, owner_id)


# --- 私有/辅助方法 ---

static func _get_or_create_action_owners(action_id: StringName) -> Dictionary:
	var owners: Dictionary = _get_action_owners(action_id)
	if owners.is_empty() and not _action_owners.has(action_id):
		owners = {}
		_action_owners[action_id] = owners
	return owners


static func _get_action_owners(action_id: StringName) -> Dictionary:
	var value: Variant = _action_owners.get(action_id)
	if value is Dictionary:
		var owners: Dictionary = value
		return owners
	return {}


static func _get_max_strength(owners: Dictionary) -> float:
	var result: float = 0.0
	for strength_value: Variant in owners.values():
		var strength: float = 0.0
		if strength_value is float:
			strength = strength_value
		elif strength_value is int:
			var strength_int: int = strength_value
			strength = float(strength_int)
		else:
			continue
		result = maxf(result, _normalize_strength(strength))
	return result


static func _normalize_strength(strength: float) -> float:
	if is_nan(strength) or is_inf(strength):
		return 0.0
	return clampf(strength, 0.0, 1.0)


static func _variant_to_action_id(value: Variant) -> StringName:
	if value is StringName:
		var action_id: StringName = value
		return action_id
	if value is String:
		var action_text: String = value
		return StringName(action_text)
	return &""
