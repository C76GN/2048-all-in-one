# Pawnbarian 深度产品分析

研究日期：2026-07-22（Asia/Shanghai）
类型：5×5 国际象棋移动 / 战术解谜肉鸽
证据：开发者官网、presskit、FAQ 与开发者上传实机视频；未下载或运行游戏。

## 产品与核心循环

Pawnbarian 把棋子移动规则装进牌组：抽到的棋子牌决定本回合英雄如何移动/吃子，在 5×5 地牢中清掉敌人并避开其攻击。官方 presskit 确认 6 个角色、3 个主题地牢、累积难度 Chains、通关后无限模式，单局约 15–30 分钟。实机 [00:42](https://www.youtube.com/watch?v=IKr-AxVk7_8&t=42s) 显示棋盘危险格以红色角标铺开，左侧 Deck/Discard 可读，底部三张棋子牌是唯一主操作，生命用心形呈现。

## 表现：特效、Shader、动效

- 大量留白、有限色板、纸片式棋子与细小环境划痕让棋盘危险态保持突出；没有观察到需要复杂 Shader 才能成立的核心视觉。
- 红色危险角标与敌人朝向同时表达威胁，避免只靠攻击动画事后解释。
- 视频帧不足以确认 tween 曲线、屏幕震动或粒子预算；不应据截图反推实现。

## 音效

官方 presskit 明确列出 Aleksander Zabłocki 负责 music and sound，说明音频有专职所有者。当前未独立试听，无法评价具体落子、受击、升级的层级或移动端外放表现。

## UI/UX

- “棋盘 + 三张牌 + Deck/Discard”构成强任务页，辅助信息分区明确。
- 官网确认鼠标、键鼠、触控、完整手柄支持，且 Steam Deck Verified；这是当前项目跨平台输入提示值得对标的完成度。
- FAQ 承认 Spark Imp 死后触发很难事后沟通，说明即使规则确定，缺少因果回顾仍会被玩家认为是 bug。当前项目已有回放，适合增加事件原因标记而非另造日志系统。

## 玩法变体与功能设计

角色通过不同牌组/核心机制复用同一棋盘语法；地牢改变敌人组合，Chains 叠加难度，无限模式承接熟练玩家。平台采用 demo + 单次解锁/买断，明确拒绝广告与影响玩法的微交易。

## 性能线索

官方支持 Windows、Linux、macOS、Android、iOS 与 Steam Deck，但未公开帧时间或内存。固定 5×5、少量单位、无大面积常驻特效是移动/掌机友好的设计约束（D）。FAQ 显示跨平台云存档并不统一，移动端只有手动备份，这是产品能力限制而非性能结论。

## 与当前项目比较及 GF 映射

| 发现 | 当前项目判断 | GF / 所有者 |
| --- | --- | --- |
| 行动牌改变网格移动语法 | 适合验证“局内选择”，但不能破坏 2048 确定性 | `GFTurnFlowSystem`、Recipe/Capability、Action Queue；牌与敌人归项目 |
| 预先铺出全局危险格 | 当前主要反馈合并结果，局势预览较弱 | BoardTopology 查询 + 项目 overlay；Shader 参数走 `GFShaderParameterUtility` |
| 多输入完整支持 | 已有 GF 输入映射与焦点，需深化提示切换 | `GFInputMappingUtility` / focus；平台文案归 navigation/settings |
| 因果不清被误认 bug | 当前回放是优势，可增加事件原因 | 回放/诊断现有数据；原因语义归 gameplay，不新增 GF 日志 |

## 可借鉴点、风险与证据限制

优先做“下一步危险覆盖层”与回放中的原因标签，再考虑棋子式行动卡。所有预览必须来自同一确定性规则计算，不能另写近似 UI 模拟器。不要复制棋子角色、美术、音乐或具体敌人；官网提供的是产品资料而非再利用许可。

## 一手来源

- [j4nw：Pawnbarian 官网](https://j4nw.com/pawnbarian/)
- [Pawnbarian 官方 presskit](https://j4nw.com/pawnbarian/presskit)
- [Pawnbarian FAQ](https://j4nw.com/pawnbarian/faq)
- [j4nw：Pawnbarian Trailer](https://www.youtube.com/watch?v=IKr-AxVk7_8)
