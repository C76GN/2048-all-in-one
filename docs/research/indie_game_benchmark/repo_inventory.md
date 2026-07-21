# GitHub 固定版本仓库清单（第一批：10 个深度样本）

## 范围与状态

- 检查日期：2026-07-22
- 深度报告：10/10 完成；2048/合并类 6 个，网格肉鸽 4 个。
- 获取边界：第三方仓库只位于项目外 `E:\_workspace\Godot Project\_research\2048-benchmark\repos\`；项目仓库内只写研究报告。
- 获取方式：`GIT_LFS_SKIP_SMUDGE=1`，浅克隆、blob filter、`--no-recurse-submodules`，随后 detached HEAD 固定提交；未初始化 submodule。
- 执行边界：未构建、未安装依赖、未运行游戏/测试/脚本、未加载动态库、未导入 Godot 项目。
- 复用边界：仅提炼机制与产品思想；未复制第三方代码、字体、图像、音频、文字或其他素材；未修改 `addons/gf`。

## 固定版本与许可证台账

| # | 项目与一手来源 | 固定提交 / 日期 | 本地目录名 | 许可证结论 | 深度报告 |
|---:|---|---|---|---|---|
| 1 | [gabrielecirulli/2048](https://github.com/gabrielecirulli/2048) | [`478b6ec`](https://github.com/gabrielecirulli/2048/tree/478b6ec346e3787f589e4af751378d06ded4cbbc) / 2024-10-24 | `gabrielecirulli-2048` | [MIT](https://github.com/gabrielecirulli/2048/blob/478b6ec346e3787f589e4af751378d06ded4cbbc/LICENSE.txt) | [报告](projects/repo_gabrielecirulli_2048.md) |
| 2 | [danqing/2048](https://github.com/danqing/2048) | [`6f89eab`](https://github.com/danqing/2048/tree/6f89eab8f3e5e044f66c381095a9f5402bacaab5) / 2018-03-09 | `danqing-2048` | [MIT](https://github.com/danqing/2048/blob/6f89eab8f3e5e044f66c381095a9f5402bacaab5/LICENSE) | [报告](projects/repo_danqing_2048.md) |
| 3 | [plibither8/2048.cpp](https://github.com/plibither8/2048.cpp) | [`ad931d9`](https://github.com/plibither8/2048.cpp/tree/ad931d991e27819463dbd3d27a05411ea3cee061) / 2024-06-24 | `plibither8-2048-cpp` | [MIT](https://github.com/plibither8/2048.cpp/blob/ad931d991e27819463dbd3d27a05411ea3cee061/LICENSE) | [报告](projects/repo_plibither8_2048_cpp.md) |
| 4 | [nneonneo/2048-ai](https://github.com/nneonneo/2048-ai) | [`41e298f`](https://github.com/nneonneo/2048-ai/tree/41e298f4571a9505e421e3a19af7a1cb372a368c) / 2026-03-18 | `nneonneo-2048-ai` | [MIT](https://github.com/nneonneo/2048-ai/blob/41e298f4571a9505e421e3a19af7a1cb372a368c/LICENSE) | [报告](projects/repo_nneonneo_2048_ai.md) |
| 5 | [ovolve/2048-AI](https://github.com/ovolve/2048-AI) | [`226be51`](https://github.com/ovolve/2048-AI/tree/226be513371ce2493843b2485c280e2389ef7dad) / 2020-10-30 | `ovolve-2048-ai` | 顶层 [MIT](https://github.com/ovolve/2048-AI/blob/226be513371ce2493843b2485c280e2389ef7dad/LICENSE.txt)；捆绑 Hammer/Clear Sans 需另审 | [报告](projects/repo_ovolve_2048_ai.md) |
| 6 | [mateuszsokola/2048-in-react](https://github.com/mateuszsokola/2048-in-react) | [`4c27093`](https://github.com/mateuszsokola/2048-in-react/tree/4c27093929b4293c2c873b3ed75b18671b5be6cb) / 2026-04-07 | `mateuszsokola-2048-react` | [MIT](https://github.com/mateuszsokola/2048-in-react/blob/4c27093929b4293c2c873b3ed75b18671b5be6cb/LICENSE) | [报告](projects/repo_mateuszsokola_2048_react.md) |
| 7 | [statico/godot-roguelike-example](https://github.com/statico/godot-roguelike-example) | [`5fa12fd`](https://github.com/statico/godot-roguelike-example/tree/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6) / 2026-01-28 | `statico-godot-roguelike` | 代码 [MIT](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/LICENSE)；Pixel Operator [CC0](https://github.com/statico/godot-roguelike-example/blob/5fa12fd3206df9ce42284cf7aab6b41b69b7fca6/assets/fonts/pixel_operator/LICENSE.txt)；Dawnlike 另有条款 | [报告](projects/repo_statico_godot_roguelike.md) |
| 8 | [tmewett/BrogueCE](https://github.com/tmewett/BrogueCE) | [`7f52dd9`](https://github.com/tmewett/BrogueCE/tree/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76) / 2026-06-28 | `broguecommunity-broguece` | 代码 [AGPL-3.0](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/LICENSE.txt)；tiles [CC-BY-SA-4.0](https://github.com/tmewett/BrogueCE/blob/7f52dd93b7fa553dd6e354ccd44229a3c22d8a76/bin/assets/LICENSE.txt) | [报告](projects/repo_brogue_ce.md) |
| 9 | [watabou/pixel-dungeon](https://github.com/watabou/pixel-dungeon) | [`ca458a2`](https://github.com/watabou/pixel-dungeon/tree/ca458a28f053612973d5d6059dae5f6f2ca4fcb7) / 2015-10-01 | `watabou-pixel-dungeon` | [GPL-3.0](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/LICENSE.txt)；素材逐项确认；PD-classes 未纳入 | [报告](projects/repo_watabou_pixel_dungeon.md) |
| 10 | [00-Evan/shattered-pixel-dungeon](https://github.com/00-Evan/shattered-pixel-dungeon) | [`7b8b845`](https://github.com/00-Evan/shattered-pixel-dungeon/tree/7b8b845a76fe76c6b7c031ae9e570852411f56db) / 2026-03-19 | `shattered-pixel-dungeon` | [GPL-3.0](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/LICENSE.txt)；资产仍逐项确认 | [报告](projects/repo_shattered_pixel_dungeon.md) |

许可证统计：7 个样本的顶层代码许可证为 MIT；2 个为 GPL-3.0；1 个为 AGPL-3.0。这个统计只描述根代码许可，不把第三方字体、tile、音乐或其他资产自动归入同一结论。

## 入选理由

| 样本类型 | 项目 | 用于回答的问题 |
|---|---|---|
| 经典手感基线 | gabrielecirulli/2048 | 最小玩法闭环、100–200 ms 位移/合并节奏、动作元数据如何驱动表现 |
| 规则矩阵 | danqing/2048 | 尺寸 × 合并规则 × 主题如何产品化，三合一/Fibonacci 如何说明 |
| 功能/文本可读性 | 2048.cpp | 存读档、统计、键盘效率、无视觉资产时如何保持信息可读 |
| 高性能分析 | nneonneo/2048-ai | bitboard、行查表、expectimax、转置缓存与分析 instrumentation |
| 提示/自动演示 | ovolve/2048-AI | AI 与玩家共用命令入口、可解释形状启发式、时间预算风险 |
| 测试与输入反例 | 2048-in-react | 稳定 tile id、组件测试、快速输入、全局手势和方向重复的陷阱 |
| 同技术栈肉鸽 | Godot roguelike example | ActionResult、能量回合、awaitable modal、调试内容浏览器与 Godot 反例 |
| 确定性/回放标杆 | BrogueCE | gameplay/cosmetic RNG 分流、回放 OOS、seed catalog、dirty tile 刷新 |
| 反馈词汇基线 | Pixel Dungeon | 粒子/声音/镜头/快捷栏组合、横竖屏、对象复用 |
| 长期精品演进 | Shattered Pixel Dungeon | custom/daily seed、挑战组合、多端 UI、手柄、语义音频、资产生命周期 |

## 快速对比矩阵

符号：`强` 表示有直接源码证据且相对成熟；`中` 表示存在但有明显边界；`弱/无` 表示固定提交中缺失或不适合作为基线。

| 项目 | 规则/变体 | 确定性/回放 | VFX/动效 | 音频 | UI/输入 | 性能策略 | 当前项目最值得借鉴 |
|---|---|---|---|---|---|---|---|
| gabrielecirulli/2048 | 弱：经典固定 4×4 | 弱：`Math.random` | 中：CSS 位移/pop | 无 | 中：键盘+滑动 | 弱：整盘 DOM 重建 | 动作结果元数据、经典节奏 |
| danqing/2048 | 强：3 尺寸×3 规则 | 弱 | 中：tile action queue | 无 | 强：规则设置与主题 | 中：小棋盘 SpriteKit | 正交规则选择、三合一反馈 |
| 2048.cpp | 中：可变尺寸/救援 | 弱 | 无：ANSI 文本 | 无 | 中：多键位/统计 | 中：轻量但有值复制 | 统计与无色彩冗余信息 |
| nneonneo/2048-ai | 固定 4×4 分析 | 中：模拟规则明确 | 无 | 无 | 弱：CLI/控制适配 | 强：bitboard/查表/缓存 | 只读提示服务、可预算分析 |
| ovolve/2048-AI | 固定 4×4 + AI | 弱 | 中：沿用原版 | 无 | 中：hint/auto | 中：迭代加深但会超时 | 同命令入口、可解释指标 |
| 2048-in-react | 弱：固定规则 | 弱 | 中：CSS/glow | 无 | 中：跨端但事件边界有缺陷 | 弱：重复 reducer/JSON clone | 稳定 id、输入回归测试 |
| Godot roguelike example | 强：肉鸽系统样例 | 弱：seed ownership 不完整 | 中：Tween/粒子 | 无 | 中：modal/调试工具 | 弱：全图扫描、无池 | ActionResult 与内容 explorer |
| BrogueCE | 强：地牢/variant | 强：双 RNG、recording、seed CI | 强：光色/flare/字符反馈 | 无证据 | 强：ASCII/tile/回放控制 | 强：固定网格/dirty cell | RNG 分流、OOS、seed catalog |
| Pixel Dungeon | 强：完整 run 内容 | 弱：未见 seed/replay | 强：粒子/震动/漂字 | 强：语义音效 | 强：横竖屏/快捷栏 | 中：recycle/FOV | feedback recipe、快捷动作带 |
| Shattered Pixel Dungeon | 强：9 challenge + daily | 中强：seed 产品化，非命令回放 | 强：粒子/flash/复用 | 强：区域/强度音频 | 强：三布局/手柄 | 强：缓存释放/对象复用 | seed UX、挑战、多端信息架构 |

## 跨项目高置信发现

1. **领域动作先产出语义结果，表现后消费。** 原版 2048 的 `previousPosition/mergedFrom`、Godot 样例的 `ActionResult`、Pixel Dungeon 的事件反馈都指向同一边界。当前项目应形成统一 `MoveOutcome`，包含移动、合并、生成、分数、连锁、胜负和受影响格，而不是让动画比较两份棋盘猜事件。
2. **业务与表现随机必须完全分流。** BrogueCE 给出最强一手证据；Pixel Dungeon 也反向显示共享随机 API 的风险。当前项目需验证粒子、音高、闪烁、主题装饰不会改变回放。
3. **可重现性本身是玩法。** Brogue 的 seed/catalog/recording 与 Shattered 的 custom/daily seed 都说明，seed 不应只留在 diagnostics，而应可复制、分享、重复挑战，并携带规则版本和资格。
4. **精品反馈依赖语义组合，而不依赖重 Shader。** 研究样本普遍没有复杂 Shader，但 pop、颜色、漂字、光照、音效、镜头和节拍组合仍能形成高品质。当前项目可先补齐 feedback recipes，再决定哪些效果需要 shader。
5. **横竖屏/桌面需要信息重排。** Pixel Dungeon 与 Shattered 都定义不同最小尺寸和布局；简单等比缩放会牺牲触达与信息层级。
6. **高频表现对象应复用，领域对象不因此池化。** Pixel Dungeon 系列的 emitter/ripple/status recycle 支持这一点；对象池只归表现层，不进入存档或命令历史。
7. **规则变体要正交、可说明、可测试。** danqing 的模式矩阵与 Shattered 的 challenge bitmask 都比在移动控制器不断加分支更可扩展。
8. **AI 必须是有预算的只读消费者。** 两个 AI 仓库证明高速评估的价值，也暴露固定 4×4、主线程阻塞、随机流和原生平台风险。

## GF 能力路由摘要

| 研究主题 | 优先复用/映射的 GF 能力 | 项目自有职责 |
|---|---|---|
| 回合与动作阶段 | `GFTurnFlowSystem`、`GFActionQueueSystem` | 2048 lane compose、规则变体、`MoveOutcome` |
| 确定 RNG / daily seed | `GFSeedUtility`、`GFClock` | run seed UX、资格、规则版本、cosmetic 派生流 |
| 撤销/书签/回放 | `GFCommandHistoryUtility`、`GFSaveGraph` | canonical hash、OOS 报告、seed catalog 测试 |
| 输入与手势/手柄 | `GFInputMappingUtility`、`GFPointerGestureUtility` | 项目平台 adapter、死区、buffering 策略 |
| UI 与 modal | `GFUIRouterUtility`、`GFSignalUtility`、`GFViewportUtility` | 横竖屏/桌面信息架构、规则说明 |
| 音频 | `GFAudioUtility` | 2048 语义音频 bank、主题映射、可访问性 |
| VFX 与动画 | action queue、GF shader 参数、`GFObjectPoolUtility` | 棋盘反馈 recipe、reduced-motion、池预算 |
| 资产与内容 | GF asset load session、content packages/catalog | tile/effect catalog、来源/许可证元数据 |
| AI/诊断 | GF diagnostics、`GFClock` | project-owned analysis feature、deadline/cancel、解释结果 |
| 平台与服务 | GF platform runtime adapter | daily 分享/商店/服务的项目适配，不扩展 GF 业务语义 |

## 后续复核规则

- 更新报告时先记录新 SHA，再比较差异；不得直接把 `main`/`master` 当固定证据。
- 对 README 的性能/胜率声明标记“作者声明”，除非在安全、可控条件下另做本地验证。本批没有运行任何 benchmark。
- 根许可证不自动覆盖第三方依赖或素材；每个被考虑复用的资产必须有独立来源、作者、许可证与归属记录。
- AGPL/GPL/CC-BY-SA 样本默认只借产品/机制思想；任何实现级复用必须先做单独法律审查。
- 第三方副本和素材永不进入当前项目 git；本清单中的本地路径仅为研究缓存位置。
