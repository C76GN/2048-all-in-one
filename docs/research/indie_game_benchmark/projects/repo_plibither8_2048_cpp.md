# plibither8/2048.cpp 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/plibither8/2048.cpp) |
| 固定版本 | [`ad931d991e27819463dbd3d27a05411ea3cee061`](https://github.com/plibither8/2048.cpp/tree/ad931d991e27819463dbd3d27a05411ea3cee061) |
| 提交日期 | 2024-06-24 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\plibither8-2048-cpp` |
| 许可证 | [LICENSE](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/LICENSE)，MIT |
| 研究方式 | 2026-07-22 静态阅读；未构建、未运行 |

这是命令行 2048 的“功能面基线”：可变棋盘、存档/读档、最佳分、移动数与统计、跨平台按键别名都已具备。它证明即使没有图形效果，持久局面和可读统计也能形成留存价值；但手写文本存档、随机源和大量值拷贝不适合当前项目。

## 玩法与架构

代码按 `gameboard`、`game`、`input`、`graphics`、`save/load`、`score/statistics` 拆分，边界比单文件终端游戏清楚。`GameBoard` 持有尺寸和二维数据，但若干 API 按值传递整个棋盘或元组，[头文件接口](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/headers/gameboard.hpp#L12-L45)，既增加复制，也模糊谁拥有状态。

移动实现先折叠再移位，四个方向各自遍历，并提供空格、可移动性和生成。[折叠/更新](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/gameboard.cpp#L206-L305)、[方向移动](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/gameboard.cpp#L313-L405)。游戏在失败后提供“随机移除 tile 继续”的非经典容错机制，[结束后继续](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/game.cpp#L50-L94)，这可视为一次可定价/有限次数的救援机制原型。

## 特效、Shader、动效与音效

无 Shader、帧动画或音频。视觉由 ANSI 颜色、Unicode 边框、数字对齐和状态文本组成。输入支持方向键、WASD、Vim，以及保存和菜单命令，[输入声明](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/headers/game-input.hpp#L14-L50)。这提醒我们：色彩并非唯一通道，边框、数字、标签和文本状态也应独立可读。

## UI/UX 与功能设计

界面持续展示当前分、最佳分、移动数，并允许从游戏内保存或返回菜单。[状态呈现](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/game-graphics.cpp#L131-L190)。README 将跨平台终端、继续游戏、高分/状态保存列为主要能力，[README](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/README.md)。优势是信息密度高、键盘效率好；缺少触屏、动画、声音、无障碍设置、撤销与回放。

## 持久化、性能与风险

存档把棋盘等信息写入自定义文本文件，[写入流程](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/saveresource.cpp#L23-L59)，读档依靠逐段解析和 `stoi`，尺寸上限与格式校验分散，还留有 TODO。[读档解析](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/src/loadresource.cpp#L27-L125)。先删除旧文件再写新文件没有事务保障，文件名路径也需要更严格的信任边界。

性能上，终端刷新和小棋盘成本很低；真正风险是按值传递棋盘、四方向重复循环、随机设备散落以及缺少可重复 benchmark。随机生成和“移除 tile”使用非持久 seed，无法重放。没有发现系统性的领域单测。

## 可借鉴机制（只借思想）

1. 将移动数、最高分、局面统计视为长期反馈，而非只显示当前分。
2. 评估“失败后有限救援”作为明确规则变体；必须写入回放、成就与排行榜资格元数据。
3. 保留方向键/WASD/Vim 的键盘效率和不依赖色彩的文本冗余。
4. 可变棋盘必须通过统一 lane/topology 算法实现，避免四方向复制。

## 当前项目对比与 GF 映射

当前项目的 SaveGraph、确定性历史、可变拓扑、UI 和主题都更成熟；不应回退到自定义文本文件或按值传递状态。可以借鉴的是“移动数/最佳局面/救援记录”的持续统计，以及纯文本诊断视图。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 移动数、高分、局面统计 | progress/diagnostics | `GFSignalUtility`、SaveGraph 节点 | 统计由领域事件派生，不读 UI |
| 失败后救援变体 | gameplay | `GFTurnFlowSystem`、`GFCommandHistoryUtility` | 影响资格的规则需显式标记 |
| 多键位别名 | input | `GFInputMappingUtility` | 不在 gameplay 读取平台按键 |
| 版本化持久化 | persistence | `GFSaveGraph` / `GameSaveGraphUtility` | 不直接文件 IO，不先删后写 |
| 大棋盘复制与遍历优化 | gameplay | 项目拓扑缓存；必要时 GF diagnostics | 先 profile，再优化 |

## 证据边界

只分析固定提交。MIT 允许参考；未复制源代码。README 中“abandoned AI”不计入可用能力。
