# danqing/2048 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/danqing/2048) |
| 固定版本 | [`6f89eab8f3e5e044f66c381095a9f5402bacaab5`](https://github.com/danqing/2048/tree/6f89eab8f3e5e044f66c381095a9f5402bacaab5) |
| 提交日期 | 2018-03-09 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\danqing-2048` |
| 许可证 | [LICENSE](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/LICENSE)，MIT |
| 研究方式 | 2026-07-22 静态阅读；未构建、未运行 |

这是十个仓库中最直接展示“棋盘尺寸 × 合并规则 × 主题”产品矩阵的 2048 变体。默认分支提供 3×3/4×4/5×5、2 的幂/3 的幂/Fibonacci 与三套主题，[README](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/README.md)。它对当前项目的价值主要是规则说明、设置后重开的交互和连续三合一反馈；架构上的全局状态、SpriteKit 与规则耦合则不应照搬。

## 玩法与架构

`M2GameManager` 驱动移动、合并、胜负与生成；“3 的幂”模式允许三个同值 tile 顺次合并，5×5 的 2 幂模式在一次有效移动后生成两个 tile。[主循环与变体分支](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/State/M2GameManager.m#L88-L210)。`M2Grid` 提供二维格、方向遍历、可用位置和生成入口，[网格职责](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Sprite%20Kit/M2Grid.m#L20-L109)。

模块表面上采用 MVC，但 `M2Tile` 同时持有规则动作队列、SpriteKit 节点和动画，`M2GlobalState` 又把模式、尺寸、主题和时间集中为全局状态。这会让规则单测、回放和扩展拓扑困难。README 提到的 AI 位于另一个未固定的 `AI` 分支，本报告不将其视为当前提交能力。

## 特效、Shader、动效与音效

- 无自定义 Shader；tile 由圆角形状和文字程序化绘制，利于主题换色与清晰缩放。[tile 创建](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Sprite%20Kit/M2Tile.m#L30-L70)
- tile 内维护 pending action 队列，分别表现移动、二合一和三合一。[动作队列与合并](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Sprite%20Kit/M2Tile.m#L85-L151)
- 合并后采用约 1.3 倍 pop，再回到正常比例；删除和生成也通过时序动作完成。[pop/删除](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Sprite%20Kit/M2Tile.m#L194-L214)
- 未发现音频播放或音频资产，声音反馈缺失。

## UI/UX 与功能设计

设置页把每个尺寸、模式和主题作为明确选项，并为非经典规则提供说明；修改关键设置前说明会重新开始。[设置选项与重开提示](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Controller/M2SettingsViewController.m#L45-L55)、[重开确认](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Controller/M2SettingsViewController.m#L100-L114)。主题通过语义协议提供背景、棋盘、分数、按钮、字体和 tile 色，而非散落硬编码。[主题协议](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Appearance/M2Theme.h#L11-L56)。控制器在打开设置时暂停，并通过截图遮罩与淡入淡出维持场景连续性。[控制器覆盖层](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048/Controller/M2ViewController.m#L115-L193)。

UI 测试覆盖主题/模式/尺寸切换与滑动主路径，但没有发现对三合一、Fibonacci、生成数量和边界条件的权威领域单测。[UI 测试](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/m2048UITests/m2048UITests.swift#L33-L127)。

## 性能、风险与缺失

小棋盘 SpriteKit 节点量低，动作队列也避免同一 tile 动画互相覆盖；但状态与渲染对象耦合、全局单例、`arc4random_uniform` 生成、缺少版本化存档/撤销/回放，会阻断确定性。变体被写成核心流程分支，模式增加后复杂度近似乘法增长。没有音频、Shader、可访问性或规则级回归测试。

## 可借鉴机制（只借思想）

1. 将模式、尺寸、主题明确分成三个正交选择轴，并在 UI 中展示组合会改变哪些规则。
2. 规则切换若会破坏当前局面，先解释并要求重开确认。
3. 对多阶段合并建立语义步骤队列，让连续三合一仍能读出“先靠拢、再吸附、最后 pop”。
4. 主题接口使用语义 token，而不是组件内部直接写颜色。

## 当前项目对比与 GF 映射

当前项目已有主题、可变拓扑、tile catalog、动作队列、确定性和存档回放，架构更完整。可优先验证的差距是：是否有清晰的“模式 × 尺寸 × 主题”选择与冲突说明；是否能仅通过规则资源新增 Fibonacci/三合一，而不修改移动控制器；多合并动画是否仍保持因果可读。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 模式/尺寸/主题正交配置 | gameplay + settings + themes | GF 内容包/资产目录、`GFUIRouterUtility` | 规则组合需有兼容性校验 |
| 三合一/Fibonacci 规则策略 | `gameplay` 项目实现 | `GFTurnFlowSystem`、`GFActionQueueSystem` | GF 不承载 2048 业务规则 |
| 多阶段合并反馈 | 棋盘表现 utility | `GFActionQueueSystem` | 动画失败不可回滚领域状态 |
| 语义主题 token | themes | GF 资产加载 session / shader 参数 | 不复制原配色素材 |
| 确定生成与重开 | gameplay/navigation | `GFSeedUtility`、`GFUIRouterUtility` | 禁止平台随机 API |

## 证据边界

仅分析固定提交的默认分支；未拉取 README 所述 AI 分支。MIT 允许参考，但本报告未复制源码或美术。
