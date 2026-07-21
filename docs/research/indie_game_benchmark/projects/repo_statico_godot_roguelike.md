# statico/godot-roguelike-example 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/statico/godot-roguelike-example) |
| 固定版本 | [`5fa12fd3206df9ce42284cf7aab6b41b69b7fca6`](https://github.com/statico/godot-roguelike-example/tree/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6) |
| 提交日期 | 2026-01-28 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\statico-godot-roguelike` |
| 许可证 | [根 LICENSE](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/LICENSE) 为代码 MIT；[Pixel Operator 字体](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/assets/fonts/pixel_operator/LICENSE.txt) 为 CC0；README 指明 Dawnlike 美术另有许可证 |
| 研究方式 | 2026-07-22 静态阅读；未导入 Godot、未运行项目或资源脚本 |

这是最接近当前技术栈的网格肉鸽参考。其 `Action -> ActionResult -> effects/messages`、能量回合、awaitable modal 与调试内容浏览器值得借鉴；但世界单例、表现 await 混入领域流程、全图扫描、RNG 所有权和无存档都是反例。当前项目/GF 已覆盖其多数基础能力，只应提炼动作结果语义与内容调试 UX。

## 玩法与架构

README 将回合动作、能量、BSP 地图、行为树、FOV、背包装备、D20、状态/饥饿、CSV 数据与调试工具列为功能，同时明确保存、任务与经济等尚缺。[README 功能/缺口](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/README.md)。项目注册多个 autoload 单例并采用整数像素缩放，[项目设置](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/project.godot#L22-L66)。

`BaseAction` 产出 `ActionResult`，后者携带 effects 和 messages，[动作接口](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/actions/base_action.gd#L1-L12)、[结果对象](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/actions/action_result.gd#L1-L16)。这是良好的语义切口。不过 `World` 单例拥有地图、角色、行动推进、视野、消息和效果，并在一条同步流程内推进玩家/怪物/环境，[世界流程](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/world.gd#L5-L251)，责任过重。

## 特效、Shader、动效与音效

未发现自定义 Shader 或音频播放。视觉反馈使用 Tween 和程序化节点：投射物时长随距离变化，旋转与缩放并行，爆炸播放完后释放。[投射物/爆炸](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/visual_effects.gd#L9-L69)。

问题在于 `World` 处理区域效果时扫描地图，并直接 `await` 可视爆炸，[区域效果](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/world.gd#L307-L364)。这让无头模拟、快进、回放和领域测试依赖表现是否完成。没有对象池证据，高频 Sprite/粒子动态创建会产生分配压力。

## UI/UX 与功能设计

modal 管理器维护栈、淡入淡出，并把确认、方向选择和背包选择包装为可 `await` 的请求，[modal 栈](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/modals.gd#L6-L105)。这能把多步交互写得线性清楚；但直接访问 `/root/Game/UI` 是场景耦合。内容/地图/物品/sprite explorer 很适合内部调试和内容制作，不应与发布 UI 混在一起。

## 性能、确定性与风险

路径搜索限制为 15 步，可防止无界搜索，但使用 `Array.pop_front()` 并复制路径，[路径搜索](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/pathfinding.gd#L4-L140)，频繁调用时会产生搬移与分配。区域效果流程多次全图扫描。`Dice` 集中 RNG 是好起点，[骰子 RNG](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/src/dice.gd#L1-L80)，但种子初始化和共享流没有形成完整的运行 seed 所有权。缺少保存/恢复、回放、权威领域测试、音频与平台适配。

资产许可证必须逐项判断：代码 MIT 与字体 CC0 不代表 Dawnlike 图集可随意复制。本报告不复制任何代码或素材。

## 可借鉴机制（只借思想）

1. 让一次动作返回标准化的 `state_changes + semantic_effects + messages + time_cost`，表现与日志消费同一结果。
2. 把能量回合调度做成可确定重放的 turn phase，而不是 await 表现节点。
3. 内部内容浏览器支持按 id、标签、来源、许可证和主题筛选 tile/效果。
4. modal 用路由/请求对象表达，但调用方不能依赖绝对节点路径。

## 当前项目对比与 GF 映射

当前项目已有 `GFTurnFlowSystem`、动作队列、确定性 RNG、SaveGraph、回放、资产 session、对象池、UI router 与 diagnostics，已经修复该样例的大部分结构缺口。优先借鉴 ActionResult 分类和内容 explorer，避免重复实现框架已有能力。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 标准化 ActionResult | gameplay | `GFTurnFlowSystem`、`GFActionQueueSystem` | effects 只描述语义，不持节点 |
| 能量/阶段调度 | gameplay | `GFTurnFlowSystem` | 表现 await 不进入领域推进 |
| awaitable modal | UI | `GFUIRouterUtility`、`GFSignalUtility` | 禁止绝对场景路径 |
| seed 所有权 | gameplay/session | `GFSeedUtility` | 生成/战斗/表现流分离 |
| 高频效果复用 | board presentation | `GFObjectPoolUtility` | 用 profile 决定池容量 |
| 内容浏览器 | diagnostics/asset library | GF 资产目录、content package/session | 显示许可证与来源元数据 |

## 证据边界

仅覆盖固定提交的默认分支，项目自述为不完整样例。未初始化额外依赖、未打开 Godot；代码、字体和 Dawnlike 美术按各自许可证分别处理。
