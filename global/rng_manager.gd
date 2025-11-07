# global/rng_manager.gd

## RNGManager: 负责管理全局随机数生成器 (RNG) 的单例脚本。
##
## 这个单例保证了整个游戏应用中随机性来源的唯一性和可控性。
## 它允许游戏在启动时使用特定种子进行初始化，这对于复现问题或
## 创建可重复的挑战至关重要。
extends Node

# --- 私有变量 ---

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _current_seed: int = 0


# --- 公共方法 ---

## 初始化或重置随机数生成器。
## @param p_seed: 用于初始化RNG的种子。如果为0，则使用随机种子。
func initialize_rng(p_seed: int = 0) -> void:
	if p_seed == 0:
		_rng.randomize()
		_current_seed = _rng.seed
	else:
		_current_seed = p_seed
		_rng.seed = _current_seed
	print("RNG 已使用种子初始化: ", _current_seed)


## 获取当前游戏的种子。
## @return: 当前用于初始化RNG的种子。
func get_current_seed() -> int:
	return _current_seed


## 获取全局唯一的随机数生成器实例。
## @return: 全局的RandomNumberGenerator实例。
func get_rng() -> RandomNumberGenerator:
	return _rng


## 获取RNG的当前内部状态，用于保存。
## @return: RNG的内部状态值。
func get_state() -> int:
	return _rng.state


## 从一个状态值恢复RNG，用于加载/撤回。
## @param p_state: 要恢复的RNG状态值。
func set_state(p_state: int) -> void:
	_rng.state = p_state
