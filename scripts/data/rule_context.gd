## RuleContext: 用于向规则传递游戏上下文和收集规则输出的强类型数据对象。
##
## RuleSystem 负责创建上下文并在规则执行后统一派发上下文中记录的业务输出。
class_name RuleContext
extends RefCounted


# --- 公共变量 ---

## 当前棋盘的逻辑数据模型。
var grid_model: GridModel

## 本次移动的数据。仅在移动触发的规则中有效，其他触发器中为 null。
var move_data: MoveData

## 随机数工具，由 RuleSystem 注入。
var seed_utility: GFSeedUtility

## 规则请求生成的新方块。
var spawn_requests: Array[SpawnData] = []

## 规则请求增加的分数。
var score_delta: int = 0

## 规则请求增加的击杀数量。
var monsters_killed: int = 0


# --- 公共方法 ---

## 获取指定分支的确定性随机数生成器。
func get_rng(branch_id: String) -> RandomNumberGenerator:
	if not is_instance_valid(seed_utility):
		return RandomNumberGenerator.new()

	return seed_utility.get_branched_rng(branch_id)


## 记录一个生成请求，由 RuleSystem 在本轮规则执行后派发。
func request_spawn(spawn_data: SpawnData) -> void:
	if not is_instance_valid(spawn_data):
		return

	spawn_requests.append(spawn_data)


## 记录分数变化。
func add_score(amount: int) -> void:
	score_delta += amount


## 记录怪物击杀数量。
func add_monster_kill(amount: int = 1) -> void:
	monsters_killed += max(amount, 0)


## 清空运行时输出，避免下一条规则重复派发上一条规则的结果。
func clear_runtime_outputs() -> void:
	spawn_requests.clear()
	score_delta = 0
	monsters_killed = 0
