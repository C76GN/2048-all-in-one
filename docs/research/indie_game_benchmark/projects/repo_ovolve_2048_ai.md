# ovolve/2048-AI 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/ovolve/2048-AI) |
| 固定版本 | [`226be513371ce2493843b2485c280e2389ef7dad`](https://github.com/ovolve/2048-AI/tree/226be513371ce2493843b2485c280e2389ef7dad) |
| 提交日期 | 2020-10-30 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\ovolve-2048-ai` |
| 许可证 | [LICENSE.txt](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/LICENSE.txt)，顶层 MIT；捆绑 Hammer/Clear Sans 的独立来源边界不够清楚 |
| 研究方式 | 2026-07-22 静态阅读；未运行网页、外部 widget 或 AI |

该仓库把原版 2048 扩展为提示与自动运行，是“辅助功能走同一移动入口”的直接样例。迭代加深 alpha-beta、平滑度/单调性/空格/最大值启发式具有可解释性；但搜索在主线程、停止时间不是硬 deadline，且代码含全局变量、旧外部 widget 和来源边界不清的捆绑资产，不宜复制。

## 玩法与架构

棋盘仍是固定 4×4。`Grid` 同时承担格子、随机生成、移动模拟、克隆和评价特征，[生成与克隆](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/grid.js#L32-L129)、[移动与电脑回合](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/grid.js#L162-L240)。`clone()` 内对 `newGrid` 缺少局部声明，[克隆实现](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/grid.js#L100-L110)，可能泄漏为全局变量，是维护风险。

AI 的评价函数组合平滑度、单调性、空格和最大 tile，[评价项](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/ai.js#L5-L21)。玩家节点求最大值，电脑节点把最不利的生成格作为对手并做候选剪枝，[搜索节点](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/ai.js#L24-L118)。这不是原游戏 90/10 随机生成的精确 expectimax，而是偏保守的 adversarial 模型，应在产品中明确提示其含义。

## 特效、Shader、动效与音效

无 Shader 和音效；沿用原版 CSS transform、appear/pop 与 DOM 重建。actuator 根据上一位置和合并来源生成 class，[tile 表现](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/html_actuator.js#L10-L75)，另显示 hint/run 控件，[辅助控件](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/html_actuator.js#L141-L146)。自动运行以 `setTimeout` 按动画延时递归触发，[自动运行](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/game_manager.js#L11-L26)，没有生命周期取消或后台暂停模型。

## UI/UX 与功能设计

提示和自动运行最终都调用与玩家相同的 `move`，这是值得保留的边界。[管理器移动入口](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/game_manager.js#L65-L96)。然而 UI 只给方向，不解释为何推荐、预计收益或计算是否过时。外部 Twitter widget/analytics 依赖旧全局脚本，[外部集成](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/html_actuator.js#L108-L140)，增加离线、隐私与供应链风险。

## 性能、风险与缺失

迭代加深以 `minSearchTime` 约 100 ms 为下限，每完成一层才检查耗时，[迭代加深](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/ai.js#L126-L140)、[默认时间](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/js/application.js#L1-L6)。因此某一深度可超出预算，并阻塞输入反馈目标。还存在 `Math.random()`、固定棋盘、全局对象、无缓存上限/取消、无存档/撤销/回放和缺少系统测试。

顶层 MIT 不能自动证明捆绑的压缩 Hammer 与 Clear Sans 可无条件复制；本报告只借思想，不使用代码、字体或素材。

## 可借鉴机制（只借思想）

1. 提示、自动演示、玩家输入全部生成同一种领域命令。
2. 用“空格、单调性、相邻差异、最大 tile 位置”构成可解释提示文案，而非只给神谕式箭头。
3. 搜索采用硬 deadline、cancellation token 与过期 snapshot 校验；超过 50 ms 则异步或降级。
4. 明确区分随机期望模型与最坏情况模型，让评价结果可比较。

## 当前项目对比与 GF 映射

当前项目已具备动作队列、统一输入、确定性和回放，能更安全地承载辅助器。建议建立 project-owned `analysis` feature，仅读取不可变 snapshot；自动演示仍提交标准移动命令。不要引入旧浏览器依赖或第三方资产。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 提示/自动演示共用命令入口 | analysis + gameplay | `GFInputMappingUtility`、`GFTurnFlowSystem` | AI 不直接改 BoardState |
| 硬时间预算与取消 | analysis | `GFClock`、项目任务控制 | 结果需校验 snapshot id |
| 可解释形状指标 | analysis + UI | diagnostics、`GFSignalUtility` | 指标不是权威规则 |
| 独立随机模拟 | analysis | `GFSeedUtility` 派生流 | 不推进游戏 RNG |
| 辅助器 UI 路由 | UI | `GFUIRouterUtility` | 无外部 widget/analytics 全局依赖 |

## 证据边界

仅分析固定提交；未运行站点。仓库顶层许可证结论不延伸到未单独注明来源的字体/第三方压缩库。
