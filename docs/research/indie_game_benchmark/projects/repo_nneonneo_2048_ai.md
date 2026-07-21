# nneonneo/2048-ai 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/nneonneo/2048-ai) |
| 固定版本 | [`41e298f4571a9505e421e3a19af7a1cb372a368c`](https://github.com/nneonneo/2048-ai/tree/41e298f4571a9505e421e3a19af7a1cb372a368c) |
| 提交日期 | 2026-03-18 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\nneonneo-2048-ai` |
| 许可证 | [LICENSE](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/LICENSE)，MIT |
| 研究方式 | 2026-07-22 静态阅读；未编译、未加载动态库、未运行浏览器控制 |

该仓库是“标准 4×4 2048 的极致分析器”基线，而不是通用玩法架构。64 位 bitboard、65,536 行查表、expectimax 和转置缓存非常适合提示、自动演示或离线评估；它的固定尺寸、原生动态库和无硬取消边界，与当前项目的稀疏/可变拓扑和多平台目标不兼容。

## 玩法与架构

一个棋盘编码为 64 位整数，每格用 4 bit 表示指数，天然限制为 4×4 且单格最大指数 15。[bitboard 定义](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.h#L4-L16)。核心预计算 65,536 种行状态的移动结果和启发式分数，再通过转置实现纵向操作，[查表与启发式预计算](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.cpp#L70-L185)、[常数查表移动](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.cpp#L188-L240)。

expectimax 在玩家节点最大化，在机会节点按 90/10 的 2/4 概率遍历空格；转置缓存复用局面评估，并根据空格数量动态调整深度。[机会节点与缓存](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.cpp#L271-L385)、[动态深度与计数](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.cpp#L388-L405)。启发式主要奖励空格、单调性和高值边角，惩罚相邻差异。

## 特效、Shader、动效、音效与 UI/UX

仓库本身没有游戏表现、Shader、音效或产品 UI；Python 层只提供 CLI、手动模式和浏览器控制适配。顶层四个候选移动可并行计算，[线程入口](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.py#L31-L46)，主循环把最佳方向发送到浏览器或终端，[控制循环](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/2048.py#L55-L120)。动态库封装直接加载编译产物并做参数封送，[原生桥接](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/ailib.py#L1-L47)；本次研究没有执行该路径。

## 性能、风险与缺失

固定 4×4 下，bitboard 和行表可显著降低每节点成本；仓库还暴露搜索节点、深度和缓存命中等 instrumentation，适合作为性能预算示范。README 声称每秒千万级移动，但本报告未运行 benchmark，因此只记录为作者声明，不作为本地验证事实。[README 性能说明](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/README.md)。

主要风险：固定拓扑/值上限；原生库影响 Web、微信、iOS 等可移植性；搜索没有显式 cancellation token 或严格毫秒 deadline；提示若读写主游戏 RNG 会破坏回放；浏览器控制调试接口不应进入生产。它也没有可解释建议、无障碍、存档或玩法测试层。

## 可借鉴机制（只借思想）

1. 把 AI 作为只读 `BoardSnapshot -> AnalysisResult` 服务，而不是第二套规则实现。
2. 标准 4×4 可启用专用快路径；其他拓扑回退到通用模拟器，两者用同一组黄金局面验证等价。
3. 转置键必须包含拓扑、规则集、目标值与随机模型，不能只含 tile 数组。
4. 结果应带方向、预计收益、搜索深度、节点数、耗时和置信解释；设置硬 deadline 与取消。
5. 离线分析使用复制的 RNG/状态，绝不推进权威游戏随机流。

## 当前项目对比与 GF 映射

当前项目的优势是确定性命令历史、可变/稀疏拓扑、回放和平台覆盖；它缺少的可能是可预算的提示/分析服务与标准局面的高速评估。建议仅做项目自有可选 feature，不让 GF 或本仓库原生实现成为权威规则源。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 只读提示/分析服务 | 新的 project-owned `analysis` feature | diagnostics/任务取消能力；`GFClock` 计时 | 不修改棋盘或 RNG |
| 标准 4×4 快路径 | gameplay 内部策略 | 无需新增 GF API | 必须与通用实现黄金测试等价 |
| 转置缓存 | analysis | GF diagnostics 记录命中率 | 生命周期和内存上限显式化 |
| AI 自动演示 | navigation/gameplay | `GFInputMappingUtility`、`GFTurnFlowSystem` | 仍通过同一命令入口 |
| 搜索随机模型 | analysis | `GFSeedUtility` 派生独立流 | 不共享权威 stream |

## 证据边界

仅静态分析固定提交。没有编译 C++、加载 `ailib` 或操作浏览器。MIT 允许参考，但当前建议只复用算法思想。
