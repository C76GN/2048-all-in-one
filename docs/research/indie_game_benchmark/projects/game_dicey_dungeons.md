# Dicey Dungeons 深度产品分析

研究日期：2026-07-22（Asia/Shanghai）
类型：骰子分配 / 牌组构筑肉鸽
证据：作者 itch.io、官方开发日志与作者上传的发布视频；未下载或运行游戏。

## 产品与核心循环

玩家每回合掷骰，把点数分配给带数值条件的装备。官方页确认 6 个角色拥有显著不同的玩法：例如 Robot 是 blackjack 式 push-your-luck，Inventor 每战拆一件装备做 gadget，Witch 使用法术系统。程序生成地牢与角色 Episode 把同一骰子语法变成大量规则实验。

## 表现：特效、Shader、动效

- 2018 v0.11 开发日志明确记录全面换入 Marlowe Dobbe 的美术、Chipzel 的音乐与音效；v0.15 又加入场景动画背景、角色动画、4K 纹理切换、状态 tooltip、敌人行动预览和动画速度控制。
- 官方发布日志嵌入的 Launch Trailer 在 [约 00:24](https://www.youtube.com/watch?v=E2AdLWsRuHg&t=24s) 显示紫色战斗界面：玩家/敌人分处画面两侧，底部可见骰子，中央装备牌带点数/放置槽。该时间点由 YouTube 每秒预览板复核，能支持“骰子 → 装备槽”的 HUD 层级，但不能量化拖放动画或 easing。
- v0.17 日志还明确提到攻击、Robot error 等新 VFX，说明反馈按事件类型而非统一爆闪处理。

## 音效

官方团队把音乐与音效都交给 Chipzel，并在 v0.11 首次整合、v0.17 继续加入 audio touches。未独立试听，不能评价实际动态范围、事件并发或移动端音量平衡。

## UI/UX

- tooltip、敌方行动预览与动画速度设置直接降低规则学习成本；v0.16 的教程目标是“不打断正常操作，只在需要时弹出小提示”。
- 角色差异通过同一可读的“骰子 → 装备槽”交互表达，减少模式切换时重新学习 UI。
- itch 页声明多语言；项目基线已有中英文本与统一字体，但尚缺情境教程和减少动态策略。

## 玩法变体与功能设计

Episode 是规则改写器：v0.15 计划为 6 角色各 6 个 Episode，v0.17 的 Parallel Universe 甚至重写全部状态效果与装备。这个结构展示了如何以可组合规则产生内容，而不是复制场景。官方还记录模组数据逐步迁入表格与脚本解释器；本项目不应照搬通用脚本执行，尤其要守住信任边界。

## 性能线索

v0.5 作者公开做过优化，称 profiler 中某些情境帧时间最高改善 500%；该表述缺硬件、基线和绝对值，只能作为“持续 profiling”证据。v0.15 提供 4K 纹理自动检测/开关与动画速度控制，说明资源档位是显式产品功能。不可把百分比直接套用本项目预算。

## 与当前项目比较及 GF 映射

| 发现 | 当前项目判断 | GF / 所有者 |
| --- | --- | --- |
| 角色 + Episode 改写核心规则 | 当前 6 模式横向广，缺纵向目标/构筑 | 模式注册表、turn flow；角色/episode 是项目业务 |
| 敌方意图、tooltip、渐进教程 | 当前确认缺完整 onboarding | UI route/focus/text fitter 可复用；教程状态归 navigation/gameplay |
| 动画速度/4K 资源档位 | 当前有强度设置方向和 Shader 预热，缺完整降级矩阵 | settings/display/asset load；档位策略归 themes |
| 数据驱动内容 | 当前规则资源化已合规 | 继续用资源目录与 content package；不引入不可信运行时脚本 |
| 事件化音频/VFX | 当前机制有、素材层浅 | `GFAudioEvent`、Action Queue、Shader Profile；深化内容即可 |

## 可借鉴点、风险与证据限制

P0 是情境提示、行动预览和动画强度/速度档；P1 是用“挑战条款”改写现有模式。不要引入可执行模组语言或复制角色、装备、图像、音频。视频观察点只支持战斗 HUD 的静态层级；教程流程、动画速度、4K 与性能仍以官方日志为据，音频未独立试听。

## 一手来源

- [Dicey Dungeons itch.io](https://terrycavanagh.itch.io/dicey-dungeons)
- [v0.11：新美术、音乐与音效](https://diceydungeons.com/blog/2018/08/06/version-11.html)
- [v0.15：Episode、动画背景、4K、tooltip 与动画速度](https://diceydungeons.com/blog/2018/12/25/version-15.html)
- [v0.17：状态规则、VFX 与音频改进](https://diceydungeons.com/blog/2019/05/20/version-17.html)
- [Terry Cavanagh：发布日志（嵌入 Launch Trailer）](https://terrycavanagh.itch.io/dicey-dungeons/devlog/94826/dicey-dungeons-is-out-now)
- [Terry Cavanagh：Dicey Dungeons Launch Trailer](https://www.youtube.com/watch?v=E2AdLWsRuHg)
