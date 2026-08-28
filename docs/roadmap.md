# 2048 All In One 活跃路线图

本文只记录尚未完成、已获采纳的工作。当前实现事实以代码和可执行配置为准，长期契约以 [`docs/readme.md`](./readme.md) 的权威层级为准，明确不做的范围以 [`.gf/project_contract.json`](../.gf/project_contract.json) 为准。完成项应从本页删除，而不是累积成项目历史。

## 优先级

- **P0**：影响数据正确性、主流程可达性、输入等价或发布可信度，完成前阻断发布。
- **P1**：已采纳的产品垂直切片；必须保持确定性、账号隔离和跨端输入契约。
- **P2**：只有测量或真实平台证据证明收益后才实施的优化。

## P0：外部发布门禁

### P0-01 在正式工具链复跑目标平台产物

- **当前状态**：当前工作站已由 `tools/export_wechat_minigame_release.ps1` 生成无 `platform_smoke` 的完整游戏候选。最终 build ID 为 `749f6ff3c9ea0c396dc8a9b3e82546312b4e924533063b7cce664189ce3ef0ce`；report schema 3 记录主包 88,331 bytes、engine 分包 8,901,332 bytes、game_data 分包 8,916,808 bytes、总包 17,906,471 bytes，全部预算与隔离门禁通过。正式预览计量为 17,693,596 bytes。微信模拟器已经启动横屏中文主菜单，main→game_data→engine、4 MiB chunk、PCK 探针、WASM 与 GF 均取得成功终态；当前唯一运行告警是内容目录同步刷新 116 ms。Android/iOS 真机矩阵、玩家手势与长时游玩、音频、前后台恢复和重启存档仍待签字。
- **结果**：由 `tools/check_platform_readiness.ps1` 完成真实 Web release export；由同一事务核心分别生成 `toolchain_smoke` 与 `full_game_release_candidate`。正式候选必须通过字体闭包、包内无完整字体引用、精确双分包白名单、main→game_data→engine 串行入口、4 MiB 分块读取、各包与总包预算及 schema 3 原子报告校验。微信 release 禁用 ICU，并由 Boot/Composition Root 在 GF 架构创建前调用唯一的平台启动 Utility，注册随包 en/zh Translation。
- **边界**：静态配置扫描不得冒充成功产物；临时验证不得修改项目 release 输出或把生成物提交为规范。
- **验收**：环境报告中的 `web_export.status` 为 `passed`、临时产物已清理；微信候选保存明确的 build identity、CLI/skill 版本、包体与字体证据。模拟器启动与 console 已完成，仍须取得 Android/iOS 真机、玩家输入、长时运行、音频、前后台与重启存档终态后才能关闭本项。

## P1：目标设备证据

### P1-01 补齐真机性能与表现预算

- **当前状态**：项目已有 `GFMetricSeries` 驱动的 6 模式 × 3 拓扑 checkpoint 基准、生命周期 plateau、回放 `GFExecutionBudget` 和三档截图矩阵；开发工具还提供显式同意后启动的真实玩法采样入口，以两条独立有界 `GFMetricSeries` 记录单调帧时与输入到首反馈，只有运行条件精确匹配且每项至少 120 个样本时才进入评估。当前仍没有目标 Windows、Web 或低端移动设备的合格实测结果，共享开发机结果只用于阻止数量级回退。
- **结果**：在目标 Windows、Web 和低端移动设备采集输入到首反馈、帧时间、全屏背景 Shader、长回放定位与页面切换的 P50/P95/P99。
- **边界**：平台、渲染档位、样本量和截断状态必须进入报告；目标表与实测值分开，不把 headless 耗时当成玩家帧预算。
- **验收**：核心操作符合 `.gf/project_contract.json` 的 60 FPS 与 50 ms 首反馈目标；不合格项附带同 seed、同主题、同视口的前后证据。

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
