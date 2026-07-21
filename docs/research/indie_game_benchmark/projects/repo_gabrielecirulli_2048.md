# gabrielecirulli/2048 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/gabrielecirulli/2048) |
| 固定版本 | [`478b6ec346e3787f589e4af751378d06ded4cbbc`](https://github.com/gabrielecirulli/2048/tree/478b6ec346e3787f589e4af751378d06ded4cbbc) |
| 提交日期 | 2024-10-24 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\gabrielecirulli-2048` |
| 许可证 | [LICENSE.txt](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/LICENSE.txt)，MIT |
| 研究方式 | 2026-07-22 静态阅读；未构建、未运行、未加载第三方程序 |

这是最值得用来校准“经典 2048 手感最小闭环”的基线，而不是架构或确定性基线。它用极少模块完成移动、合并、分数、胜负、触摸与恢复，但 `Math.random()`、整盘 DOM 重建和表现层计时都不适合直接移植到当前 Godot/GF 项目。

## 玩法与架构

`GameManager` 通过构造参数注入输入、执行器和存储，领域状态仍保持得相对集中；启动时恢复存档，移动后先更新状态再交给 actuator 表现。[构造与恢复](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/game_manager.js#L1-L58)、[存储后执行表现](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/game_manager.js#L79-L109)。

移动流程按方向建立遍历顺序，每格寻找最远可达位置，相同值且本回合未合并的格子生成新 tile，并记录 `previousPosition`、`mergedFrom`，成功移动后才随机生成新格。[核心移动](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/game_manager.js#L129-L191)、[可移动性判定](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/game_manager.js#L238-L267)。这是清楚的规则闭环，但固定 4×4、没有规则配置层，也没有撤销/回放命令模型。

## 特效、Shader、动效与音效

- 无 Shader；视觉完全由 CSS、DOM class 与 transform 完成。
- actuator 每次使用 `requestAnimationFrame` 清空并重建 tile DOM，再根据 `previousPosition`、`mergedFrom` 和新生状态附加动画 class。[执行器](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/html_actuator.js#L10-L90)
- 位移过渡约 100 ms；新生与合并 pop 约 200 ms。[位移与缩放样式](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/style/main.scss#L22-L22)、[appear/pop 动画](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/style/main.scss#L429-L451)
- 分数增加量作为短暂 `+N` 单独呈现，胜负覆盖层与棋盘状态分离。[分数与覆盖层](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/html_actuator.js#L106-L138)
- 仓库未见音效系统或音频素材；听觉反馈是明确缺口。

## UI/UX 与功能设计

键盘同时支持方向键、WASD 与 Vim 键，触屏通过起止点计算主轴并设 10 px 阈值，重开输入也统一发事件。[键盘映射](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/keyboard_input_manager.js#L37-L69)、[滑动手势](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/keyboard_input_manager.js#L76-L127)。本地存储同时保存最高分和可恢复局面，并有内存后备实现。[存储适配](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/local_storage_manager.js#L21-L62)。

优点是输入反馈快、规则解释成本低、得分增量可感知；缺点是无撤销、重放、无障碍朗读、可配置棋盘/规则、声音、教学、统计或减少动态效果选项。

## 性能与可靠性

4×4 下整盘 DOM 重建成本可接受，但它把成本与棋盘面积、浏览器布局和动画 class 绑定，不能作为稀疏/大拓扑方案。新 tile 以 `Math.random()` 产生 90% 的 2 和 10% 的 4，[生成规则](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/js/game_manager.js#L69-L75)，无法按 seed 重现，也不能保障回放与撤销后的随机流一致。存档是无版本 JSON，没有迁移、校验或事务语义。

## 可借鉴机制（只借思想）

1. 将 `previous_position`、`merged_from`、`spawned`、`score_delta` 作为一次动作的语义结果，让表现层消费，而不是让动画反推棋盘差异。
2. 维持“有效移动才生成新 tile”的快速反馈闭环，并把合并、得分、生成、胜负按明确节拍排序。
3. 保留多输入等价映射和手势最小阈值，但交给统一输入层处理。
4. 用独立的分数增量反馈强化每次合并的因果感。

## 当前项目对比、风险与 GF 映射

当前项目已有可变/稀疏拓扑、确定性 RNG、撤销/书签/回放、主题、统一存档和动作队列，能力明显超集；不应复制该项目的 DOM 重建、随机数或存档方式。值得补强的是“动作结果元数据到表现层”的明确契约与经典 100–200 ms 节奏回归测试。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 语义动作结果驱动位移/合并/生成动画 | `gameplay` + 棋盘表现 utility | `GFTurnFlowSystem`、`GFActionQueueSystem` | 领域状态先提交；表现不得反写规则 |
| 确定性 90/10 生成 | `gameplay` | `GFSeedUtility` | 禁止 `randf()`/表现 RNG 影响业务流 |
| 键盘与手势等价命令 | 项目输入适配器 | `GFInputMappingUtility`、`GFPointerGestureUtility` | 手势阈值与死区可配置 |
| 分数增量、胜负覆盖层 | UI/feedback | `GFUIRouterUtility`、`GFSignalUtility` | 覆盖层路由不拥有游戏状态 |
| 存档/恢复 | persistence | `GFSaveGraph` / `GameSaveGraphUtility` | 不照搬裸 localStorage JSON |

## 证据边界

结论只覆盖固定提交的默认分支。许可证允许参考实现，但本报告只提炼机制；没有复制代码、样式或素材。
