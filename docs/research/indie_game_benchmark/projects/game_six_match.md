# Six Match 深度产品分析

研究日期：2026-07-22（Asia/Shanghai）
类型：受限步数 Match-3 / 长局生存 / 小关谜题
证据：作者 itch.io 页面、作者开发日志、作者页面嵌入的实机视频；未下载或运行游戏。

## 产品与核心循环

玩家不是任意交换两枚棋子，而是移动“Mr Swap-With-Coins”并与沿途硬币换位；必须在 6 步内形成匹配。官方页同时提供可持续数周、自动保存的 Survival Mode，以及清空棋盘的短小 Puzzle Mode。实际实机 [00:42](https://www.youtube.com/watch?v=mZ8gwjzTJkA&t=42s) 显示 7×7 彩色硬币网格、带数字 `6` 的玩家棋子、棋盘下方行动/帮助区和分数，核心规则无需文字教程即可从空间关系读出。

## 表现：特效、Shader、动效

- 像素硬币用红/黄/青/蓝与内部条纹或圆点区分，角色用高对比白色数字表达剩余步数。
- 棋盘外使用暗绿棋盘格，主棋盘边缘与 UI 保持低亮度，焦点集中在可交换对象。
- 官方 2022 “Puzzles and Polish” 日志确认 UI 大改、删除 skull、加入 dice-coin；2017 “Fanfares” 日志确认匹配和破坏反馈做过专门的声音强化。未发现 Shader 实现资料。

## 音效

作者明确记录“匹配更有 fanfare、破坏更有 punch”，说明声音按语义事件分层，而非一个通用点击声。当前未独立试听音轨，不能评价响度、频谱或连续连锁的混音上限。

## UI/UX

- Survival 的 3 次免费提示、之后按需 Help、无解时生成 bomb，构成逐步撤掉辅助的教学曲线。
- Puzzle 中 Space/Z 为 undo、X 为 redo；功能与当前项目确定性历史天然相容。
- 桌面版支持可缩放窗口，作者明确希望它能像手机游戏一样以小窗运行；PC 棋盘为 7×7，移动端曾使用 6×8，说明布局按设备重排而非简单缩放。

## 玩法变体与功能设计

同一移动规则支撑长局生存和短关谜题；扑克手牌奖励、宝石到底收集、逐步加入新机制形成内容深度。作者还记录提示 AI 会穷举并证明棋盘是否仍可形成匹配，这是罕见的“可证明提示/死局检测”产品能力。

## 性能线索

官方文件约 26–42 MB，支持 Windows/macOS/Android；开发日志提到 Unity 版本、安全更新和平台维护成本，但没有运行时基准。穷举提示存在潜在 CPU 风险，作者把自动提示改为按键触发可视为节流策略；具体搜索规模和帧耗未公开。

## 与当前项目比较及 GF 映射

| 发现 | 当前项目判断 | GF / 所有者 |
| --- | --- | --- |
| 同核规则同时支持生存与谜题 | 当前模式多，但缺关卡目标层；可借鉴 | 模式注册表、`GFTurnFlowSystem`；关卡目标/奖励归 gameplay |
| 可证明的提示与死局检测 | 当前有结束判定，无教学提示系统 | 复用确定性 BoardTopology；搜索器是项目 Utility，不应进入 GF |
| Puzzle undo/redo | 当前已完整实现 | 直接复用 `GFCommandHistoryUtility`，防止重复历史 |
| 移动/破坏声分层 | 当前正式 SFX 只有 6 个，值得深化 | 扩展 `GFAudioEvent`/`GFAudioBank` 语义与并发上限 |
| 小窗/移动重排 | 当前已有响应式 HUD 与安全区 | 继续用现有布局/输入映射；增加竖屏 QA 矩阵 |

## 可借鉴点、风险与证据限制

P0 借鉴“剩余步数直接附着主棋子”和死局前的可解释提示；P1 用同一规则做 10–20 个短谜题，验收回放能逐步复现提示结论。不要照搬硬币、扑克奖励或提示算法源码；官方页面未声明可复用许可证。视频上传名为 robotacid、itch 作者名为 st33d；其作为官方 itch 嵌入视频记录，但别据此推断代码归属。

## 一手来源

- [st33d：Six Match itch.io](https://st33d.itch.io/six-match)
- [Puzzles and Polish 开发日志](https://st33d.itch.io/six-match/devlog/470255/puzzles-and-polish)
- [No Free Rides：穷举提示说明](https://st33d.itch.io/six-match/devlog/9964/no-free-rides)
- [robotacid：Six Match 实机视频](https://www.youtube.com/watch?v=mZ8gwjzTJkA)
