# watabou/Pixel Dungeon 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/watabou/pixel-dungeon) |
| 固定版本 | [`ca458a28f053612973d5d6059dae5f6f2ca4fcb7`](https://github.com/watabou/pixel-dungeon/tree/ca458a28f053612973d5d6059dae5f6f2ca4fcb7) |
| 提交日期 | 2015-10-01 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\watabou-pixel-dungeon` |
| 许可证 | [LICENSE.txt](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/LICENSE.txt)，GPL-3.0；素材不可仅因根许可证而推定可复用 |
| 依赖边界 | README 要求另一个 [PD-classes](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/README.md#L15-L16)，本次未下载/运行，工具层证据不完整 |
| 研究方式 | 2026-07-22 静态阅读；未编译、未运行 APK 或依赖 |

原版 Pixel Dungeon 是“有限像素资产也能形成丰富反馈词汇”的优质基线：调度、粒子、镜头震动、音高变化、快捷栏、背包和方向适配构成紧凑移动端体验。它的全局 `Dungeon`、共享随机 API、表现阻塞 actor 和手写 Bundle 保存则不适合当前确定性架构。

## 玩法与架构

代码按 actors、items、levels、mechanics、scenes、sprites、effects、ui、windows 分包，内容扩展面清晰；核心状态集中在静态 `Dungeon`。`Actor` 用浮点 time 调度所有角色/blob/buff，反复扫描 actor 集合选最早者，并在角色 sprite 正移动时暂停领域推进。[Actor 时间与存储](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/actors/Actor.java#L34-L79)、[调度循环](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/actors/Actor.java#L158-L209)。能量/时间差形成不同速度角色，但表现状态影响规则线程，是确定性与 headless 测试风险。

`Dungeon` 负责 run、关卡、英雄、挑战、掉落、路径和存档。保存 Bundle 包含版本、英雄、深度、任务、统计、日志、快捷栏和物品识别状态，[保存图](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/Dungeon.java#L311-L438)；加载可恢复同一集合，[加载](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/Dungeon.java#L448-L548)。这是内容完整性样例，但版本字符串被读取后未用于显式迁移，异常还可能只把进度标为 unknown。

## 特效、Shader、动效与音效

无自定义 Shader 证据，主要靠 sprite 动画、粒子、色彩 hardlight/fade、漂浮文字和镜头震动。`GameScene` 按 terrain/ripples/plants/heaps/mobs/emitters/effects/gases/spells/status 分层，[场景分层](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/scenes/GameScene.java#L89-L164)。Ripple、SpellSprite、Emitter、FloatingText 都从 scene group recycle，[复用入口](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/scenes/GameScene.java#L491-L517)。

音频词汇很丰富：主题/地牢音乐和点击、脚步、水、命中、升级、死亡、陷阱、传送等语义音效集中登记，[音频资产表](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/Assets.java#L116-L166)。部分脚步、水和拾金音效随机 pitch，粒子、镜头震动和声音常组合成同一事件。例如英雄移动区分水声/脚步并随机水声 pitch，[英雄移动音效](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/actors/hero/Hero.java#L1226-L1235)。

## UI/UX 与功能设计

`PixelScene` 为横竖屏定义最小虚拟尺寸，根据密度选择整数 zoom，并使用单独 UI camera，[响应式像素布局](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/scenes/PixelScene.java#L41-L101)。Toolbar 将等待、搜索、查看、背包和双快捷槽放在固定触达带；长按等待/背包还有次级操作。[Toolbar](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/ui/Toolbar.java#L62-L140)。拾取物飞向栏位并缩小，200 ms 内解释“世界物体进入背包”。[拾取动效](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/ui/Toolbar.java#L322-L374)。

## 性能、确定性与风险

场景 group recycle 降低高频粒子/文字分配；FOV 后只更新可见对象，[可见性更新](https://github.com/watabou/pixel-dungeon/blob/ca458a28f053612973d5d6059dae5f6f2ca4fcb7/src/com/watabou/pixeldungeon/scenes/GameScene.java#L545-L553)。但 actor 每次线性扫描、静态全局状态和固定 `Level.LENGTH` 限制扩展。

更关键的是 gameplay 与 effects 都调用 `com.watabou.utils.Random`；本仓库未见独立 seed/表现流，且 Random 实现在缺失的 PD-classes 中，无法证明确定性隔离。保存也未显式保存 RNG 状态/seed，不能当作回放范例。GPL 代码与素材来源边界使其只适合思想研究。

## 可借鉴机制（只借思想）

1. 为合并、升级、危险、失败、拾取分别定义“动效 + 音效 + 镜头/文字”的语义 feedback recipe。
2. 快捷槽承担高频动作，长按打开解释或替代操作；2048 可用于撤销、提示、模式能力和目标查看。
3. 拾取飞行动画证明世界状态流向 UI，2048 可用于目标收集/资源奖励，但不阻塞领域回合。
4. 横竖屏使用不同最小信息架构，而不只缩放同一布局。
5. 高频短生命周期表现对象统一复用并设置容量/退化策略。

## 当前项目对比与 GF 映射

当前项目在 feature ownership、SaveGraph、确定性、回放与平台抽象上更强；Pixel Dungeon 提供的是内容反馈密度、快捷 UI 与音频分类参考。任何随机 pitch/粒子必须走 cosmetic stream。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| semantic feedback recipe | feedback/themes | `GFAudioUtility`、`GFActionQueueSystem`、shader params | 只消费已提交领域事件 |
| 高频粒子/漂字复用 | board presentation | `GFObjectPoolUtility` | 池耗尽时安全降级 |
| 横竖屏 UI 模式 | UI/settings | `GFViewportUtility`、`GFUIRouterUtility` | 保持相同命令语义 |
| 快捷动作带/长按 | UI/input | `GFPointerGestureUtility`、input mapping | 需键盘/手柄等价入口 |
| run 存档内容完整性 | persistence | `GFSaveGraph` | 增加 schema、seed、迁移和校验 |
| actor 能量思想 | gameplay | `GFTurnFlowSystem` | 不等待 sprite 结束推进规则 |

## 证据边界

缺失 PD-classes 意味着 Random、渲染和底层音频实现未完整审计。GPL-3.0 代码与来源未逐项确认的素材均不复制。
