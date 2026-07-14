## 组合多个运行时任务的复合任务。
##
## [br]
## 任务组用于把多个 [GFRuntimeTask] 编排为顺序、等待全部或等待任一完成的流程。
## 子任务在组内部推进，不会单独注册到外层调度器；外层调度器只看到一个占用聚合后的任务。
## [br]
## @api public
## [br]
## @category runtime_handle
## [br]
## @since 6.0.0
class_name GFRuntimeTaskGroup
extends GFRuntimeTask


# --- 枚举 ---

## 子任务推进模式。
##
## [br]
## @api public
## [br]
## @category config
## [br]
## @since 6.0.0
enum Mode {
	## 按顺序执行，每次只推进一个子任务。
	SEQUENCE,
	## 同时推进所有子任务，全部完成后任务组完成。
	PARALLEL_ALL,
	## 同时推进所有子任务，任一完成后任务组完成。
	PARALLEL_RACE,
}


# --- 常量 ---

## 子任务已被其他调度器或任务组持有时的拒绝原因。
##
## [br]
## @api public
## [br]
## @since unreleased
const REJECTION_CHILD_SCHEDULED: StringName = &"group_child_scheduled"

## 并行任务组存在组内 requirement 冲突时的拒绝原因。
##
## [br]
## @api public
## [br]
## @since unreleased
const REJECTION_PARALLEL_REQUIREMENT_CONFLICT: StringName = &"group_parallel_requirement_conflict"


# --- 公共变量 ---

## 子任务列表。
##
## [br]
## @api public
## [br]
## @category state
## [br]
## @since 6.0.0
var tasks: Array[GFRuntimeTask] = []

## 子任务推进模式。
##
## [br]
## @api public
## [br]
## @category config
## [br]
## @since 6.0.0
var mode: Mode = Mode.SEQUENCE

## [member mode] 为 [enum Mode.PARALLEL_RACE] 时，首个子任务完成后是否中断其他子任务。
##
## [br]
## @api public
## [br]
## @category config
## [br]
## @since 6.0.0
var cancel_remaining_on_finish: bool = true


# --- 私有变量 ---

var _scheduler_ref: WeakRef = null
var _current_index: int = 0
var _completed_task_ids: Dictionary = {}


# --- Godot 生命周期方法 ---

## 创建运行时任务组。
##
## [br]
## @api public
## [br]
## @category lifecycle
## [br]
## @since 6.0.0
## [br]
## @param p_tasks: 初始子任务列表。
## [br]
## @param p_mode: 子任务推进模式。
func _init(p_tasks: Array[GFRuntimeTask] = [], p_mode: Mode = Mode.SEQUENCE) -> void:
	super._init()
	mode = p_mode
	for task: GFRuntimeTask in p_tasks:
		var _add_task_result: GFRuntimeTaskGroup = add_task(task)


# --- 公共方法 ---

## 添加子任务，并把子任务 requirement 合并到任务组。
##
## [br]
## @api public
## [br]
## @category config
## [br]
## @since 6.0.0
## [br]
## @param task: 要添加的子任务。
## [br]
## @return 当前任务组。
func add_task(task: GFRuntimeTask) -> GFRuntimeTaskGroup:
	if is_scheduled():
		push_warning("[GFRuntimeTaskGroup] 已调度任务组不能修改子任务。")
		return self
	if task == null:
		return self
	if task.is_scheduled():
		push_warning("[GFRuntimeTaskGroup] 已调度子任务不能加入任务组。")
		return self
	if tasks.has(task):
		return self
	if mode != Mode.SEQUENCE and _would_create_parallel_requirement_conflict(task):
		push_warning("[GFRuntimeTaskGroup] 并行任务组不能包含占用相同 requirement 的子任务。")
		return self
	tasks.append(task)
	_rebuild_requirements_unchecked()
	return self


## 移除子任务并重建任务组 requirement。
##
## [br]
## @api public
## [br]
## @category config
## [br]
## @since 6.0.0
## [br]
## @param task: 要移除的子任务。
## [br]
## @return 成功移除时返回 true。
func remove_task(task: GFRuntimeTask) -> bool:
	if is_scheduled():
		push_warning("[GFRuntimeTaskGroup] 已调度任务组不能修改子任务。")
		return false
	if task == null or not tasks.has(task):
		return false
	tasks.erase(task)
	rebuild_requirements()
	return true


## 重建任务组 requirement 聚合。
##
## [br]
## @api public
## [br]
## @category config
## [br]
## @since 6.0.0
func rebuild_requirements() -> void:
	if is_scheduled():
		push_warning("[GFRuntimeTaskGroup] 已调度任务组不能重建 requirements。")
		return
	_rebuild_requirements_unchecked()


## 返回当前子任务聚合后的占用对象副本。
##
## [br]
## @api public
## [br]
## @category query
## [br]
## @since 6.0.0
## [br]
## @return 仍然有效的占用对象副本。
func get_requirements() -> Array[Object]:
	if not is_scheduled():
		_rebuild_requirements_unchecked()
	return super.get_requirements()


## 返回子任务副本。
##
## [br]
## @api public
## [br]
## @category query
## [br]
## @since 6.0.0
## [br]
## @return 子任务副本。
func get_tasks() -> Array[GFRuntimeTask]:
	var result: Array[GFRuntimeTask] = []
	for task: GFRuntimeTask in tasks:
		if task != null:
			result.append(task)
	return result


## 初始化任务组。
##
## [br]
## @api public
## [br]
## @category lifecycle
## [br]
## @since 6.0.0
## [br]
## @param scheduler: 当前调度器。
func initialize(scheduler: GFRuntimeTaskScheduler) -> void:
	_scheduler_ref = weakref(scheduler) if scheduler != null else null
	_current_index = 0
	_completed_task_ids.clear()
	if mode == Mode.SEQUENCE:
		_initialize_sequence_child()
		return
	for task: GFRuntimeTask in get_tasks():
		_initialize_child(task)


## 按帧推进任务组。
##
## [br]
## @api public
## [br]
## @category lifecycle
## [br]
## @since 6.0.0
## [br]
## @param delta: 帧间隔秒数。
func tick(delta: float) -> void:
	if mode == Mode.SEQUENCE:
		_tick_sequence(delta, false)
		return
	_tick_parallel(delta, false)


## 按物理帧推进任务组。
##
## [br]
## @api public
## [br]
## @category lifecycle
## [br]
## @since 6.0.0
## [br]
## @param delta: 物理帧间隔秒数。
func physics_tick(delta: float) -> void:
	if mode == Mode.SEQUENCE:
		_tick_sequence(delta, true)
		return
	_tick_parallel(delta, true)


## 判断任务组是否已经完成。
##
## [br]
## @api public
## [br]
## @category lifecycle
## [br]
## @since 6.0.0
## [br]
## @return 任务组已完成时返回 true。
func is_finished() -> bool:
	if tasks.is_empty():
		return true
	if mode == Mode.SEQUENCE:
		return _current_index >= tasks.size()
	if mode == Mode.PARALLEL_RACE:
		return not _completed_task_ids.is_empty()
	return _completed_task_ids.size() >= get_tasks().size()


## 结束任务组。
##
## [br]
## @api public
## [br]
## @category lifecycle
## [br]
## @since 6.0.0
## [br]
## @param interrupted: 为 true 时表示任务组被其他任务或调度器取消。
func end(interrupted: bool) -> void:
	if interrupted:
		_cancel_open_children(true)
	elif mode == Mode.PARALLEL_RACE:
		_cancel_open_children(cancel_remaining_on_finish)
	_scheduler_ref = null


# --- 框架内部方法 ---

## 返回任务组调度前拒绝原因。
##
## [br]
## 调度前会重新检查子任务所有权、嵌套子任务调度条件，以及并行模式下的组内
## requirement 冲突，避免后续子任务变更绕过 add_task() 的即时校验。
## [br]
## @api framework_internal
## [br]
## @category lifecycle
## [br]
## @since unreleased
## [br]
## @return 调度拒绝原因；为空表示可调度。
func get_schedule_rejection_reason() -> StringName:
	var parent_reason: StringName = super.get_schedule_rejection_reason()
	if parent_reason != &"":
		return parent_reason
	for task: GFRuntimeTask in get_tasks():
		if task.is_scheduled() or task.has_initialized():
			return REJECTION_CHILD_SCHEDULED
		var child_reason: StringName = task.get_schedule_rejection_reason()
		if child_reason != &"":
			return child_reason
	if mode != Mode.SEQUENCE and _has_parallel_requirement_conflict():
		return REJECTION_PARALLEL_REQUIREMENT_CONFLICT
	_rebuild_requirements_unchecked()
	return &""


# --- 私有/辅助方法 ---

func _tick_sequence(delta: float, use_physics: bool) -> void:
	if _current_index >= tasks.size():
		return
	var task: GFRuntimeTask = tasks[_current_index]
	if task == null:
		_current_index += 1
		_initialize_sequence_child()
		return
	_initialize_child(task)
	if use_physics:
		task.physics_tick(delta)
	else:
		task.tick(delta)
	if task.is_finished():
		_finish_child(task, false)
		_current_index += 1
		_initialize_sequence_child()


func _tick_parallel(delta: float, use_physics: bool) -> void:
	for task: GFRuntimeTask in get_tasks():
		if _is_child_completed(task):
			continue
		_initialize_child(task)
		if use_physics:
			task.physics_tick(delta)
		else:
			task.tick(delta)
		if task.is_finished():
			_finish_child(task, false)
			if mode == Mode.PARALLEL_RACE:
				_cancel_open_children(cancel_remaining_on_finish)
				return


func _initialize_sequence_child() -> void:
	if _current_index >= tasks.size():
		return
	var task: GFRuntimeTask = tasks[_current_index]
	if task != null:
		_initialize_child(task)


func _initialize_child(task: GFRuntimeTask) -> void:
	if task == null or _is_child_completed(task) or task.has_initialized():
		return
	task.mark_scheduled()
	task.initialize(_get_scheduler_or_null())
	task.mark_initialized()


func _finish_child(task: GFRuntimeTask, interrupted: bool) -> void:
	if task == null or _is_child_completed(task):
		return
	_completed_task_ids[task.get_instance_id()] = true
	task.end(interrupted)
	task.mark_unscheduled()


func _cancel_open_children(interrupted: bool) -> void:
	for task: GFRuntimeTask in get_tasks():
		if task == null or _is_child_completed(task):
			continue
		if task.is_scheduled() or task.has_initialized():
			_finish_child(task, interrupted)


func _is_child_completed(task: GFRuntimeTask) -> bool:
	return task != null and _completed_task_ids.has(task.get_instance_id())


func _get_scheduler_or_null() -> GFRuntimeTaskScheduler:
	if _scheduler_ref == null:
		return null
	var scheduler: Variant = _scheduler_ref.get_ref()
	if scheduler is GFRuntimeTaskScheduler:
		return scheduler
	return null


func _rebuild_requirements_unchecked() -> void:
	var aggregate_requirements: Array[Object] = []
	for task: GFRuntimeTask in tasks:
		if task == null:
			continue
		for requirement: Object in task.get_requirements():
			if not aggregate_requirements.has(requirement):
				aggregate_requirements.append(requirement)
	_replace_requirements_unchecked(aggregate_requirements)


func _has_parallel_requirement_conflict() -> bool:
	var owners_by_requirement_id: Dictionary = {}
	for task: GFRuntimeTask in tasks:
		if task == null:
			continue
		for requirement: Object in task.get_requirements():
			if requirement == null or not is_instance_valid(requirement):
				continue
			var requirement_id: int = requirement.get_instance_id()
			if owners_by_requirement_id.has(requirement_id):
				return true
			owners_by_requirement_id[requirement_id] = task
	return false


func _would_create_parallel_requirement_conflict(next_task: GFRuntimeTask) -> bool:
	for next_requirement: Object in next_task.get_requirements():
		if next_requirement == null or not is_instance_valid(next_requirement):
			continue
		for task: GFRuntimeTask in tasks:
			if task != null and task.has_requirement(next_requirement):
				return true
	return false
