# GF 能力映射与项目使用审计

审计日期：2026-07-22  
依据：GF 9.0.1 固定 vendor、`.gf/project_contract.json`、运行时代码静态检索与 `gf_ai_project.py` API/能力目录查询。此审计只记录研究发现，不修改 `addons/gf` 或游戏代码。

## 已正确复用的机制

| 边界 | 静态证据 | 结论 |
| --- | --- | --- |
| 输入 | 运行时代码未发现直接 `Input.is_action_*`；HUD 与触摸手势通过 `GFVirtualInputSource` 写入抽象动作，主输入由 `GFInputMappingUtility` 消费 | 合规；新增教程、AI 提示或自动回放继续走抽象动作，不注入 Godot `InputMap` 旁路 |
| 场景 | 运行时代码未发现 `change_scene_to_*` 或 `reload_current_scene`；路由由 `SceneRouterSystem`/`GFSceneUtility` 承担 | 合规；新挑战页和结果页应注册 UI route 或场景意图 |
| Shader | 运行时代码未发现直接调用 `set_shader_parameter()`；[棋盘反馈](../../../features/themes/scripts/utilities/game_board_feedback_utility.gd) 先经 `GFShaderParameterUtility` 校验契约，再让 Tween 改变已经确认的材质属性 | 合规；竞品中的冲击、危险或连锁 Shader 可作为主题 Profile，不需要新全局 Shader 管理器 |
| 音频 | 正式运行时未直接创建 `AudioStreamPlayer`；[主题 Utility](../../../features/themes/scripts/utilities/game_theme_utility.gd) 通过 `GFAudioBank` 与语义事件播放 | 合规；GF 已支持 BGM、ambient、SFX 上限、crossfade、parameter/state/switch，自适应音频应先用现有 API |
| 玩家存档 | 玩家统计、书签、回放、图鉴、成就和自定义棋盘进入统一 SaveGraph | 合规；每日挑战和局内构筑应新增严格 section/provider，而非直接 `FileAccess` |
| 时间与随机 | 玩法层使用 `GameClockUtility`/GF clock 和确定性 seed；直接 `Time.get_ticks_*` 只在 Boot/显式 QA 工具中出现 | 合规；每日挑战可由日期解析出公开 seed，但回合结果仍只消费冻结后的 seed |
| 表现生命周期 | 单方块 Tween 由 [Tile](../../../features/gameplay/scripts/components/tile.gd) 返回，移动批次由 [GameBoardAnimationUtility](../../../features/gameplay/scripts/utilities/game_board_animation_utility.gd) 接入 GF 命名 Action Queue | 不是重复造队列；保留现有取消、阻断与实时重定向语义 |
| 作者工具文件 | `AssetSourceExclusionIndex` 直接读写 JSON，但它属于素材评审/作者工具索引，不是玩家数据 | 边界合理；不应强行塞进玩家 SaveGraph |

## 项目级深化点

### A1：棋盘表现参数仍分散在脚本常量中

[Tile](../../../features/gameplay/scripts/components/tile.gd) 固定保存移动、生成、合并、成长和退场时长，以及合并/转化闪色；[GameBoardController](../../../features/gameplay/scripts/controllers/game_board_controller.gd) 固定保存棋盘 intro 时长；[GameBoardFeedbackUtility](../../../features/themes/scripts/utilities/game_board_feedback_utility.gd) 固定保存生成、合并、转化色和多组冲击时长/强度，而现有 [GameBoardFeedbackProfile](../../../features/themes/scripts/data/game_board_feedback_profile.gd) 只资源化 Shake 与 Haptic。

这不构成 GF 误用，但造成三项真实成本：主题无法完整改变反馈语言；减少动态只能在多个脚本分支处理；竞品研究得到的节奏参数难以 A/B 或做低端设备降级。建议由项目新增单一棋盘 motion/feedback Profile，主题持有颜色、时长、幅度和启用开关；现有 `GFActionQueueSystem`、`GFShaderParameterUtility`、`GFShakeUtility` 与 `GFHapticUtility` 继续拥有机制。

### A2：虚拟动作“按下—延迟—释放”重复两次

[HUD `_inject_hud_action`](../../../features/gameplay/scripts/ui/hud.gd#L644) 与 [触摸 `_inject_touch_action`](../../../features/gameplay/scripts/controllers/board_world_viewport_controller.gd#L719) 都维护 token、调用 `GFVirtualInputSource.press()`、创建暂停期间可运行的 `SceneTreeTimer`、通过 `GFSignalUtility.connect_once()` 释放。

精确 API 检查确认当前 `GFVirtualInputSource` 只提供 `press/release/clear`，没有 one-shot pulse。重复逻辑应收敛为项目 gameplay 内的小型输入脉冲 Adapter 或纯 helper；动作含义和 hold 时长仍由调用端传入。只有出现多个项目都需要且生命周期语义稳定时，才把 `pulse()` 作为 GF 反馈候选。

### A3：扩建 Tween 的所有权需要回归验证

[GameBoardController `_animate_expansion`](../../../features/gameplay/scripts/controllers/game_board_controller.gd#L868) 创建局部 Tween，不保存句柄；`_expansion_token` 只递增，当前源码未发现消费点。节点销毁会终止绑定 Tween，因此尚不能据此判定泄漏，但连续扩建/恢复/切换场景时可能出现多个布局 Tween 竞争。

建议先加研究驱动的回归用例：连续触发两次扩建和一次实时重定向后，所有格子 scale 回到 `Vector2.ONE`，池中节点无动画残留，命名棋盘队列空闲。若失败，修复应在项目 `GameBoardAnimationUtility` 或 Controller 的显式句柄所有权内完成，不修改 GF。

## GF 发现性反馈候选

能力目录查询结果与精确 API 查询存在落差：

| 查询 | capability-search | 已安装精确 API | 判断 |
| --- | --- | --- | --- |
| `shader` | 无结果 | `GFShaderParameterUtility`、`GFRenderWarmupUtility` 位于 `gf.standard.display` | 目录关键词/主类缺口，不是运行时缺口 |
| `haptic` | 无结果 | `GFHapticUtility`、`GFHapticPreset`、`GFHapticBackend` 位于 `gf.extension.feedback` | 目录关键词/跨包发现性缺口 |
| `virtual list` | 无结果 | `GFVirtualListModel` 位于 `gf.standard.ui` | UI capability 的关键词/主类覆盖不足 |
| `accessibility` / `reduced motion` / `colorblind` | 无结果 | 输入、焦点、文本适配、主题和设置机制分别存在，但没有一个声明式产品策略 API | 先由项目组合；待至少两个项目出现相同稳定契约再判断框架能力 |
| `leaderboard` | 命中 `platform-adapters` | `GFInstaller`、存储/网络 backend、异步终态 | 正确：GF 只提供边界，线上权威与排行规则属于项目/服务端 |

建议先为 GF 能力目录补充 display/feedback/UI 的关键词和 `primary_classes`，让未来代理能先发现现有机制。accessibility 不宜直接新增“大而全 Utility”；本项目应先实现减少动态、高对比、震动开关和输入提示策略，沉淀后再反馈可复用契约。

## 不建议的重复实现

后续竞品灵感落地时，以下做法会与现有机制重复或破坏边界：

- 为每日挑战另写随机数、回合日志或存档文件；应复用 seed、回放和 SaveGraph。
- 为新 VFX 建第二套全局 Tween/队列管理器；应复用命名 Action Queue 与现有棋盘表现 Adapter。
- 为新音色直接放置全局 `AudioStreamPlayer`；应扩展语义事件、bank、state/switch 或主题包。
- 为关卡/模式写硬编码场景分支；应继续用模式注册表、规则资源和内容目录。
- 在 gameplay/UI 直接调用平台排行榜、成就或云存档 SDK；应经过 `platform_runtime` 的项目 Adapter。
- 因一个游戏的遗物、敌人、教程或评分规则而新增 GF Model/System；这些首先是项目业务 Feature。
