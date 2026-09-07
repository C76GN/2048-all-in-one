# 2048 All In One 活跃路线图

本文只记录尚未完成、已获采纳的工作。当前实现事实以代码和可执行配置为准，长期契约以 [`docs/readme.md`](./readme.md) 的权威层级为准，明确不做的范围以 [`.gf/project_contract.json`](../.gf/project_contract.json) 为准。完成项应从本页删除，而不是累积成项目历史。

## 优先级

- **P0**：影响数据正确性、主流程可达性、输入等价或发布可信度，完成前阻断发布。
- **P1**：已采纳的产品垂直切片；必须保持确定性、账号隔离和跨端输入契约。
- **P2**：只有测量或真实平台证据证明收益后才实施的优化。

## P0：外部发布门禁

### P0-01 在正式工具链复跑目标平台产物

- **当前状态**：项目已锁定 GF 11.0.0 stable 正式发布快照，`addons/gf/plugin.cfg` 与 `.gf/vendor.lock.json` 一致且离线 vendor 校验通过；源码与自动门禁已升级到 report schema 5 / build identity 4。正式预设使用精确资源闭包；根包同一轮请求 engine 与 game_data，四路 barrier 收敛后只启动一次 Godot，首错终止且迟到回调失效；两个大资源各自按 4 MiB 顺序读取，跨资源最多并发 2，同路径请求复用在途 Promise。启动时间线、按实测包字节加权的单调进度、DPR backing-store 上限、微信默认 `MINIMAL`/Shader 关闭和保存 debounce 均已有项目侧实现与自动测试。本轮正式候选已通过隔离产物门禁：build ID `bd0754137f76c7dcbe374e2b9a57bb875b1265e47beb9f503eb4d1972be5cc44`，主包 / engine / game_data / 总包分别为 105,577 / 8,904,251 / 6,874,296 / 15,884,124 bytes；资源闭包 identity 为 `142564146f7280e732f228ca759d337c9de731a1ed1e93afd644a92a23c30a48`，artifact manifest 为 `e384a19de705d2d9fbbd65d9fa6dca952477416186ec64ab34855ac7a8cf5da5`。同运行时代码的候选已在微信模拟器进入完整主菜单，日志确认双包同轮请求、四路 barrier 与分块读取；一次刷新中 engine.start_begin → engine.start_resolved 约 19.1 秒，另有 117 ms 目录刷新告警，尚不能认为启动性能达标。官方 automator 的 systemInfo 与 evaluate 均返回 timeout waiting for automator response，因此玩家手势与长时游玩、帧时、首反馈、峰值内存、音频、前后台恢复和重启存档仍待 Android/iOS 真机签字。
- **结果**：由 `tools/check_platform_readiness.ps1` 完成真实 Web release export；由同一事务核心分别生成 `toolchain_smoke` 与 `full_game_release_candidate`。正式候选必须通过字体闭包、包内无完整字体引用、精确 release 资源闭包、双分包白名单、engine/game_data 并发请求与四路启动屏障、4 MiB 分块读取、DPR policy、各包与总包预算及 schema 5 原子报告校验。`resource_closure` 必须绑定 policy/tool/closure SHA-256、完整依赖扫描终态与审计计数；build identity 4 必须再绑定闭包、coordinator、实际双包字节权重、超时、首错优先、单次启动、有界时间线、字体、GF/Godot、工具与输入快照。微信 release 禁用 ICU，并由 Boot/Composition Root 在 GF 架构创建前调用唯一平台启动 Utility 注册随包 en/zh Translation。
- **边界**：静态配置扫描不得冒充成功产物；临时验证不得修改项目 release 输出或把生成物提交为规范。
- **验收**：环境报告中的 `web_export.status` 为 `passed`、临时产物已清理；本轮微信候选以 schema 5 报告保存 build identity 4、资源闭包、CLI/skill、包体、字体与工具证据，并通过隔离产物验证。随后取得微信开发者工具以及 Android/iOS 真机的启动、玩家输入、长时运行、性能、内存、音频、前后台与重启存档终态后才能关闭本项；历史模拟器结果不得替代本轮签字。

## P1：目标设备证据

### P1-01 补齐真机性能与表现预算

- **当前状态**：项目已有 `GFMetricSeries` 驱动的 6 模式 × 3 拓扑 checkpoint 基准、经典 4×4 同步完整回合分阶段基准、生命周期 plateau、回放 `GFExecutionBudget` 和三档截图矩阵。真实玩法采样在玩家显式同意后，分别记录帧时以及“项目接收有效抽象移动输入 → 可见状态提交后匹配的 `RenderingServer.frame_post_draw`”；触控包含 virtual pulse 与 PlayerInputSystem 轮询，Action execute 或音频启动不单独结束视觉指标。只有平台、输入、视口、布局、棋盘和渲染档精确匹配且每项至少 120 个真实样本时才评估。当前仍没有目标 Windows、Web、微信 Android/iOS 或低端移动设备的合格实测结果；headless 与共享开发机结果只用于阻止数量级回退。
- **结果**：在目标 Windows、Web、微信 Android/iOS 和低端移动设备采集端到端首个已绘制反馈、帧时间、全屏背景 Shader、长回放定位与页面切换的 P50/P95/P99，并记录并发读取 WASM/PCK 时的峰值内存与 memory warning。
- **边界**：平台、渲染档位、样本量和截断状态必须进入报告；目标表与实测值分开，不把 headless 耗时当成玩家帧预算。
- **验收**：精确矩阵的 P95 帧时上限为桌面 16.667 ms、Web 20 ms、微信和普通移动 25 ms、低端移动 33.3 ms；真实输入到已绘制首反馈 P95 小于 50 ms。不合格项附带同 seed、同主题、同视口和同渲染档的前后证据。

## P2：证据驱动优化

### P2-01 棋盘表现热点优化

- **触发条件**：目标设备 profile 证明节点刷新、分配或绘制成为 P95/P99 瓶颈。
- **候选方向**：可见窗口更新、脏单元刷新、表现对象池容量调优和低端静态退化。
- **边界**：不改变领域模型、canonical hash 或回放顺序；优化前后使用同一 seed 语料验证。

### P2-03 视觉与音频调优

- **触发条件**：截图矩阵、对比度检查、响度测量或目标设备 profile 提供具体缺口。
- **候选方向**：收敛 CMYK 半调纸媒色板、布局级字体覆盖和等权卡片密度，降低同时运动层数，调整语义音效响度、混音与并发；新增 display font 必须先验证中文覆盖。
- **边界**：[`docs/visual_style.md`](./visual_style.md) 是视觉权威；同源多格式音频不重复做语义评审。

## 完成定义

一个条目只有在以下条件同时满足后才从 Roadmap 删除：

1. Feature 所有权、Interface 与 Adapter Seam 和 [`docs/architecture.md`](./architecture.md) 一致。
2. 失败、空态、取消、超限和账号切换等边界有聚焦测试。
3. 键盘、手柄、触摸和目标布局的相关路径已验证。
4. schema、翻译、route、资源目录和规范文档在同一批次更新。
5. 定向验证与完整安全验证均通过，或真实外部工具链阻塞已记录。
6. 修改 `addons/gf` 不属于项目完成条件；通用 GF 问题只按 [`docs/ai_maintenance.md`](./ai_maintenance.md) 的 issue-first 流程跟踪。
