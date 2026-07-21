# Shattered Pixel Dungeon 深度研究

## 快照与结论

| 字段 | 值 |
|---|---|
| 一手来源 | [GitHub 仓库](https://github.com/00-Evan/shattered-pixel-dungeon) |
| 固定版本 | [`7b8b845a76fe76c6b7c031ae9e570852411f56db`](https://github.com/00-Evan/shattered-pixel-dungeon/tree/7b8b845a76fe76c6b7c031ae9e570852411f56db) |
| 提交日期 | 2026-03-19 |
| 本地只读副本 | `E:\_workspace\Godot Project\_research\2048-benchmark\repos\shattered-pixel-dungeon` |
| 许可证 | [LICENSE.txt](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/LICENSE.txt)，GPL-3.0；资产仍需逐项来源审计 |
| 研究方式 | 2026-07-22 静态阅读；未运行 Gradle、平台包、服务模块或游戏 |

Shattered Pixel Dungeon 展示了长期迭代后的精品网格肉鸽能力：多端模块、可变 UI 模式、手柄虚拟指针、固定/每日 seed、挑战组合、丰富音频和对象复用。对当前项目最有价值的是“seed 作为产品功能”和“响应式信息架构”，而不是庞大的静态领域状态或线程等待表现的 actor scheduler。

## 玩法与架构

README 确认 Android、iOS、Desktop 的正式发行与官方 blog，[一手说明](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/README.md#L1-L20)。Gradle 将 `SPD-classes`、`core`、Android/iOS/Desktop 与 updates/news service 分模块，[模块边界](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/settings.gradle#L1-L17)，是项目自有平台/服务适配器的好参考。

Actor scheduler 在原版基础上加入类别 priority、浮点近整数修正、稳定 id 和同步 add/remove；同一 time 时按 `actPriority` 决定先后。[时间精度与优先级](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/actors/Actor.java#L37-L88)、[调度与并发](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/actors/Actor.java#L242-L325)。这解决了部分顺序/精度问题，但 actor thread 仍等待 sprite movement，规则与表现有耦合，不应移植到当前确定性 turn flow。

## Seed、玩法变体与持久化

run seed 支持随机、自定义文本和按 UTC 日期生成的 daily；每日 seed 放到用户可输入范围之外。[seed 初始化](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/Dungeon.java#L206-L254)。每层 seed 从 run seed 按 depth/branch 派生，[层级 seed](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/Dungeon.java#L414-L430)。自定义 seed、daily 与 replay 状态进入存档，并和版本、挑战、英雄、深度、生成器、快捷栏等一起保存。[存档元数据](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/Dungeon.java#L601-L696)。

九种挑战用 bitmask 组合，如禁食、禁甲、黑暗、冠军敌人和强化 Boss，[挑战表](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/Challenges.java#L27-L68)。自定义 seed/daily 在通关后解锁，daily 会阻止同日重复 run 并明确区分 replay，[开始页规则](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/scenes/HeroSelectScene.java#L639-L755)。这是一套成熟的“先学会基础，再开放可复现高阶玩法”节奏。

## 特效、Shader、动效与音效

未发现以现代材质为主的 Shader 体系；反馈依靠 sprite、fade/hardlight、投射物、粒子、漂字和镜头震动。Ripple、SpellSprite、Emitter、floorEmitter 与状态文字均 recycle，[表现对象复用](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/scenes/GameScene.java#L1185-L1224)。flash 明确切到 render thread，避免 actor thread 直接绘制，[flash 边界](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/scenes/GameScene.java#L1459-L1472)。

音频由区域、紧张态、Boss 和 finale 音乐，以及点击、脚步、材质命中、生命警报、道具、陷阱、施法等大量语义音效构成。[音乐表](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/Assets.java#L114-L151)、[音效表](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/Assets.java#L153-L225)。部分动作组合多次延迟爆破声或轻微随机 pitch，形成材质与强度层次；只能借分类/节奏思想，不能复制音频资产。

## UI/UX 与性能

UI 明确区分移动竖屏、移动横屏和完整桌面模式，考虑 safe insets、密度、整数 zoom 与独立 UI camera。[响应式基线](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/scenes/PixelScene.java#L64-L151)。手柄右摇杆有 20% deadzone、非线性灵敏度、屏幕边缘平移与独立 cursor，[虚拟指针](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/scenes/PixelScene.java#L211-L280)。背包根据横竖屏改变列数，并在放不下时逐像素收缩 slot，[背包自适应](https://github.com/00-Evan/shattered-pixel-dungeon/blob/7b8b845a76fe76c6b7c031ae9e570852411f56db/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/windows/WndBag.java#L90-L128)。

性能意识体现在离开游戏场景清 texture cache、对象复用、按可见性更新和分平台模块。但大型静态 `Dungeon`、大量内容类、线性 actor 选择与线程同步提高了测试和维护成本。seed 可复现不等于完整 command replay；存档虽含 seed，却未展示像 Brogue 那样的逐回合 OOS 校验。

## 可借鉴机制（只借思想）

1. 将 seed 产品化：可复制文本、重复 run、每日局、资格标记与分享入口。
2. 用小而正交的挑战 modifier 组合复玩性；每项明确影响、奖励与排行榜资格。
3. 横屏/竖屏/桌面是不同信息布局，不是等比缩放；手柄指针提供完整无鼠标路径。
4. 音频按语义和强度分 bank，合并值/连锁/危险可选材质层与轻微 cosmetic pitch。
5. 高频 VFX 复用，退出场景按资产组释放缓存；建立预算与降级等级。

## 当前项目对比与 GF 映射

当前项目已有 seed、回放、主题、资产 library、tile catalog、achievements 和平台 runtime，但仍应检查 seed 是否有可分享 UX、是否支持 daily/weekly challenge、桌面/移动布局是否真正重排、手柄能否访问全部界面。领域线程不得等待动画；复用只能在表现侧。

| 发现/建议 | 项目归属 | GF 能力候选 | 边界 |
|---|---|---|---|
| 可分享/custom/daily seed | gameplay/progress/navigation | `GFSeedUtility`、SaveGraph、`GFClock` | 日期用 UTC；资格写入存档 |
| 正交挑战 modifiers | gameplay/content | content packages、`GFTurnFlowSystem` | modifier 顺序与冲突需测试 |
| 三种 UI 信息架构 | UI/settings | `GFViewportUtility`、`GFUIRouterUtility` | 不以缩放替代重排 |
| 手柄虚拟指针 | platform input adapter | `GFInputMappingUtility`、pointer utility | 与鼠标/触摸焦点等价 |
| 语义音频 bank | feedback/themes | `GFAudioUtility` | pitch 随机走 cosmetic stream |
| VFX/资产复用释放 | presentation/asset library | `GFObjectPoolUtility`、asset load session/content package | 按场景 session 管生命周期 |
| actor 顺序思想 | gameplay | `GFTurnFlowSystem` | 不复制线程等待 sprite 模型 |

## 许可证与证据边界

GPL-3.0 代码只用于思想研究，未复制实现。根许可证不能替代对音乐、音效、字体和图像的逐项来源审计；本报告不建议复用任何素材。
