# Brogue: Community Edition 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/tmewett/BrogueCE) |
| 固定版本 | [`7f52dd93b7fa553dd6e354ccd44229a3c22d8a76`](https://github.com/tmewett/BrogueCE/tree/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76) |
| 提交日期 | 2026-06-28 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\broguecommunity-broguece` |
| 许可证 | [根 LICENSE.txt](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/LICENSE.txt) 为 AGPL-3.0；[tiles 许可证](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/bin/assets/LICENSE.txt) 为 CC-BY-SA-4.0 |
| 研究方式 | 2026-07-22 静态阅读；未编译、未运行测试/种子目录或回放 |

BrogueCE 对当前项目最重要的不是具体怪物或地牢规则，而是三条工程纪律：业务 RNG 与表现 RNG 分流；把输入事件、seed、版本和每回合 RNG 校验串成可诊断回放；用固定 seed 目录做生成回归。其 C 全局状态、强 copyleft 代码与 ShareAlike tile 均不可直接引入。

## 玩法与架构

这是单人、回合制、程序化地牢探索游戏，提供 ASCII/图形 tile 切换。命令行还暴露指定 seed、查看/非交互查看 recording、终端/图形模式、规则 variant 与 seed catalog，[启动参数](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/platform/main.c#L25-L50)；README 说明 `G` 可切换图形 tile，[README](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/README.md#L50-L62)。

平台层支持 SDL2、curses、web/null 等后端，领域层以固定网格、全局 `rogue` 状态和大量 C 模块组织。客观时间通过每个 creature 的 `ticksUntilTurn` 与环境 tick 取最小值推进，[时间调度](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Time.c#L2368-L2405)。规则丰富、数据局部性好，但全局可变状态和编译期 variant 不适合作为当前 feature ownership 模板。

## 确定性、存档与回放

同一个 seed 同时初始化两套独立状态：`RNG_SUBSTANTIVE` 用于业务，`RNG_COSMETIC` 用于表现；只有业务流计入随机调用统计。[双 RNG](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Math.c#L160-L190)。按钮高亮、动态颜色和回放取输入时主动切到 cosmetic stream，[表现 RNG 示例](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Buttons.c#L31-L52)、[快进回放分流](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Recordings.c#L1337-L1346)。

回放记录按键/鼠标事件与修饰键，[事件格式](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Recordings.c#L96-L130)，文件头带 recording version、seed、回合数和长度，并拒绝不兼容版本。[回放初始化](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Recordings.c#L463-L534)。每回合从业务 RNG 取校验值检测 OOS，[RNG check](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Recordings.c#L575-L606)。`compare_seed_catalog.py` 对固定 seeds 生成结果做 diff，[种子回归](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/test/compare_seed_catalog.py#L6-L36)。

## 特效、Shader、动效与音效

没有现代 Shader 管线；主要以字符/tile、前后景颜色、动态照明、闪光和短暂停顿塑造反馈。flare 保存生成回合、半径/色彩系数并逐帧衰减，快进/真彩模式可跳过等待，[flare 动画](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Light.c#L289-L404)。这是一种低素材但高语义的 VFX：危险、命中、火焰和可见性都先改变光色。

固定提交中未定位到音频子系统，听觉反馈不构成可借鉴样例。静态观察不排除其他发行包装层存在音频。

## UI/UX 与功能设计

ASCII 与 tile 双视图兼顾可读性、审美和低配/终端；回放 UI 支持暂停、变速、逐回合、跳转回合、全知观察，[回放帮助](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/brogue/Recordings.c#L609-L630)。指定 seed、显示 seed、自动探索/路径和 null 后端使分享、复现和测试都很强。问题是命令很多、信息密度高，首次上手成本大；当前 2048 项目只应引入可渐进显示的诊断能力。

## 性能、风险与缺失

固定数组和 Dijkstra cost/distance map 适合小型地牢。SDL 软件渲染只重绘 `needsRefresh` tile，[脏格刷新](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/src/platform/tiles.c#L610-L733)，是网格局部更新的直接证据。风险在于 C 全局状态、手工内存/文件、平台条件编译和强 copyleft；现代触屏、可访问性、声音与 GPU shader 不是其优势。

## 可借鉴机制（只借思想）

1. 为每个 run 派生 `gameplay_rng` 与 `cosmetic_rng`；任何粒子、音高、闪烁都不得推进业务流。
2. 回放保存 schema/规则版本、seed、命令流、周期状态摘要；首次 divergence 报告回合、命令和摘要。
3. 建立固定 seed catalog，验证生成、开局和 N 步后的 canonical hash。
4. 提供“正常播放 / 快进 / 无表现 headless”三种消费者，领域结果必须相同。
5. 棋盘只刷新 dirty cells，但先通过 profiler 证明收益。

## 当前项目对比与 GF 映射

当前项目已有 replay/bookmarks、确定 RNG、诊断与多平台适配，最值得检查的是表现随机是否彻底隔离、回放是否能在第一次 OOS 自动定位、是否有 seed catalog CI。Brogue 的输入 recording 可补强当前的 command history，但不应替代 SaveGraph snapshot/迁移。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 业务/表现双 RNG | gameplay + feedback | `GFSeedUtility` | cosmetic stream 永不写业务状态 |
| 回放版本/命令/OOS 摘要 | replays/diagnostics | `GFCommandHistoryUtility`、SaveGraph、`GFClock` | hash 只含 canonical state |
| seed catalog CI | gameplay tests | `GFSeedUtility` + diagnostics | 固定规则版本与平台无关序列 |
| 快进/headless | replays | `GFTurnFlowSystem`、action queue | 跳过表现，不跳规则阶段 |
| dirty cell 刷新 | board presentation | diagnostics；必要时对象池 | profile 后采用，不污染领域 |
| 平台后端 | platform_runtime | GF platform adapter | 不复制条件编译平台层 |

## 许可证与证据边界

AGPL-3.0 代码与 CC-BY-SA-4.0 tiles 仅供思想研究；不复制实现、数据、文字或素材。固定提交之外的发行包未纳入结论。
