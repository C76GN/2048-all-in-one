# 官方实机视频观察索引

观察日期：2026-07-22（Asia/Shanghai）
范围：首轮 10 个、追加轮次 A 4 个和追加轮次 B 4 个由开发者或发行商上传/在官方产品页嵌入的视频，覆盖合并解谜、摆放、空间构筑、网格肉鸽与相邻精品独立游戏。未下载完整视频、代码或游戏素材，未运行第三方程序。

## 观察方法与计数口径

- 9 条使用浏览器打开官方产品页及其视频，暂停到具体画面并读取播放器 `currentTime`；Dicey Dungeons 另由作者发布日志定位 Launch Trailer，再检查 YouTube 自动生成的每秒预览板。下列时间取整后写入可复核的 YouTube `t=` 链接。
- 只把画面中实际可见的棋盘、战斗 HUD、操作反馈或转场写成观察事实；玩法解释另由同一作者/发行商的产品页和开发日志支持。
- 首轮共记录 **10 个官方视频、11 个时间点**，每个视频至少一个记录点直接显示实机玩法或实机场景。Dicey 的时间点精度为预览板的约 1 秒粒度，其余为播放器 `currentTime`；二者精度差异在条目中保留。
- 全部轮次合计 **18 个官方视频、19 个时间点**。本研究没有独立捕获音轨，故视频条目不对音质、响度、并发或动态混音作事实判断。

## 增量轮次索引

- [R2-A：4 个合并、摆放与空间构筑官方视频](./videos_round_02.md)：Freshly Frosted、Dorfromantik、Stacklands、Wilmot Works It Out；4 个可点击时间点。
- [R3-B：4 个小网格战术与紧凑肉鸽官方视频](./videos_round_03.md)：GUNCHO、Card Thief、Dungeons of Dreadrock、Tinyfolks；4 个可点击时间点。

## 01. Twinfold — Release Trailer

- 上传者：Kenny Sun（开发者）；[作者官网](https://kennysun.com/twinfold/)发布同一产品与视频。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=2MV6hmWWwm4)；观察点：[00:50](https://www.youtube.com/watch?v=2MV6hmWWwm4&t=50s)。
- 实机观察：狭长不规则网格中两个 `512` 金像、两名敌人与黑色空洞共存；顶部显示 `3168 / 4096` 成长进度，底部只有 `Undo` 与少量技能槽。敌人、目标物、危险地形靠轮廓和高对比色分层。
- 对当前项目：最值得验证的是“合并对象与威胁共享棋盘”以及 Undo 常驻，而非复制角色或技能。结算继续走确定性回合、现有命令历史与 `GFActionQueueSystem`；敌人/技能属于项目 gameplay。
- 限制：单个观察点不足以量化滑动 easing、粒子、震动或性能；触觉支持来自作者页而非画面。

## 02. Six Match — Six Match

- 上传者：robotacid；该视频由作者 st33d 的 [itch.io 官方产品页](https://st33d.itch.io/six-match)嵌入，作为一手产品视频使用。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=mZ8gwjzTJkA)；观察点：[00:42](https://www.youtube.com/watch?v=mZ8gwjzTJkA&t=42s)。
- 实机观察：`7 × 7` 彩色硬币式棋盘中央有标记为 `6` 的玩家格；底部保留帮助/牌状按钮与分数，绝大部分空间让给棋盘。颜色、数字与圆形图案共同区分状态。
- 对当前项目：可借鉴“移动玩家格完成六连”的单规则变体、穷举提示与棋盘尺寸响应式策略。输入、撤销/重做、确定性模拟继续复用现有能力；提示求解器属于项目玩法层。
- 限制：观察帧不支持音频、匹配爆破时长或提示算法性能结论；这些分别以官方 devlog 明示或待实测。

## 03. Pawnbarian — Pawnbarian Trailer

- 上传者：j4nw（开发者）；[开发者官网](https://j4nw.com/pawnbarian/)与 [press kit](https://j4nw.com/pawnbarian/presskit)提供产品资料。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=IKr-AxVk7_8)；观察点：[00:42](https://www.youtube.com/watch?v=IKr-AxVk7_8&t=42s)。
- 实机观察：`5 × 5` 棋盘上敌人与玩家同处，角落格覆盖红色危险提示；左侧可见 `Deck / Discard`，底部三张棋子移动牌和生命心形。行动资源、威胁和空间结果在承诺操作前并列。
- 对当前项目：危险格预览和因果解释比增加模式数量更优先。回合顺序复用 `GFTurnFlowSystem`，输入走 `GFInputMappingUtility`，卡牌/敌人规则由项目拥有。
- 限制：不能由该帧判断触屏、手柄焦点、云存档或攻击音效；跨平台输入支持来自官方 press kit。

## 04. Dicey Dungeons — Launch Trailer

- 上传者：Terry Cavanagh（开发者）；作者的 [正式发布日志](https://terrycavanagh.itch.io/dicey-dungeons/devlog/94826/dicey-dungeons-is-out-now)嵌入该视频并说明其包含探索、敌人、策略与骰子。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=E2AdLWsRuHg)；观察点：[约 00:24](https://www.youtube.com/watch?v=E2AdLWsRuHg&t=24s)。
- 实机观察：紫色战斗界面中玩家与敌人分处两侧，底部出现多枚骰子，中央装备牌带点数/放置槽；角色、资源与可操作装备用舞台聚光和色块分层。
- 对当前项目：可借鉴“统一基础输入容器，再由角色/Episode 改写规则”，以及 tooltip、敌方预览、动画速度与资源档。分别映射现有 UI、Action Queue、Shader Profile/预热和设置系统。
- 限制：该帧来自 YouTube 每秒预览板，时间精度约 1 秒，能验证 HUD 内容但不能量化拖放、攻击动效或声音；后者仍以官方日志或未来实测为准。

## 05. Luck be a Landlord — v1.0 Release Date Trailer

- 上传者：TrampolineTales（开发者）；[作者产品页](https://trampolinetales.com/lbal)与 [itch.io](https://trampolinetales.itch.io/luck-be-a-landlord)发布产品资料。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=JcbKTeJ6uXU)；观察点：[00:42](https://www.youtube.com/watch?v=JcbKTeJ6uXU&t=42s)。
- 实机观察：橙色舞台中是 `5` 列滚轴式符号网格，水果等像素符号处于旋转/结算画面；左下金币为 `27`，右下用超大的 `SPIN` 按钮承载主要动作。复杂 build 被压缩为单次明确承诺。
- 对当前项目：值得借鉴的是“单主动作 + 结算前后状态清楚”和符号多通道编码。随机结果必须继续使用冻结 seed 与回放；屏幕阅读输出、色觉替代和可重映射输入属于项目级可访问性策略。
- 限制：单帧不能证明旋转节奏、奖励音效或随机分布；Godot、读屏与控制支持来自作者文字。

## 06. Into the Breach — Advance Edition Update Trailer!

- 上传者：Jay Ma（开发团队成员/官方视频来源）；[Subset Games 官方页](https://www.subsetgames.com/itb.html)发布产品和更新入口。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=e8DCsU8MJxE)；观察点：[00:40](https://www.youtube.com/watch?v=e8DCsU8MJxE&t=40s)。
- 实机观察：等距小棋盘中央发生局部爆炸；左栏三名单位/驾驶员，顶部有 `End Turn`、`Undo Move`、`Reset Turn`、`Unit Order`、`Info`，右栏为“Victory in 4 turns”和奖励目标，电网资源常驻。
- 对当前项目：行动预告、短局目标和 bonus objective 可形成一个最小挑战切片。预演和实际结算必须共用确定性规则；历史、seed、回放与 SaveGraph 均复用现有机制。
- 限制：无法由片尾观察点量化特效峰值或音频；等距像素风也不是性能达标证据。

## 07. Shotgun King: The Final Checkmate — Official v1.5 Trailer

- 上传者：PUNKCAKE Délicieux（开发商）；[官方 itch.io](https://punkcake.itch.io/shotgun-king)列出版本、兼容性和视频资料。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=Kpnp4YPHYI0)；观察点：[00:42](https://www.youtube.com/watch?v=Kpnp4YPHYI0&t=42s)。
- 实机观察：黑王在棋盘上瞄准霰弹枪，左栏常驻 `POWER 4`、`RANGE 3–5`、`ARC 55°`，右栏是 `SOULS`；射向和散布范围在格网上直接表达。画面覆盖 CRT/扫描线、色偏与暗角风格。
- 对当前项目：高代价动作应有可关闭的空间预览；全屏风格 Shader 必须有低档/无 Shader 退路。实现继续使用 `GFShaderParameterUtility`、`GFRenderWarmupUtility` 与项目 settings/themes，不建第二套 Shader 管理器。
- 限制：官方披露部分集成显卡有图形瑕疵并提供 shaderless fallback，但没有硬件与帧率数据；不能外推具体性能。

## 08. Shogun Showdown — Release Date Trailer

- 上传者：Goblinz Publishing（发行商）；[发行商产品页](https://goblinzstudio.com/game/shogun-showdown/)和 [开发者 itch.io](https://roboatino.itch.io/shogunshowdown)提供一手说明。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=Y1sJu_B1NFY)；观察点：[00:42](https://www.youtube.com/watch?v=Y1sJu_B1NFY&t=42s)。
- 实机观察：角色进入火把照明的洞窟/首领空间，中央石像、白色角色聚光、背景剪影和底部绿色分段计量形成舞台式入场。信息被主动收束到角色与前方目标。
- 对当前项目：可参考“空间参照系稳定、反馈沿核心方向运动”和局部光效层次；行动队列的业务真相留在 gameplay，`GFActionQueueSystem` 只负责编排/生命周期。
- 限制：该记录点是实机场景入场，不展示攻击牌编排；相关玩法结论来自官方产品文字，音频和性能未实测。

## 09. Backpack Hero — 1.0 Launch Trailer

- 上传者：TheJaspel（开发者）；[官方 itch.io](https://thejaspel.itch.io/backpack-hero)及 [开发日志](https://thejaspel.itch.io/backpack-hero/devlog)提供产品迭代资料。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=5Xdo0OJYVw4)；观察点：[00:29](https://www.youtube.com/watch?v=5Xdo0OJYVw4&t=29s)。
- 实机观察：左侧聚光格状背包内摆放剑、食物、木块等对象；底部玩家 `55/55`，右侧敌人为 `3/19` 与 `30/30`，头顶有伤害意图，底部 `End Turn` 常驻。空间整理与战斗预测同屏完成。
- 对当前项目：可在棋盘编辑器试验轻量“相邻构件配方”，但不要引入完整库存。拖放/旋转需走抽象输入和焦点路径，保存/撤销复用现有历史与 SaveGraph。
- 限制：视频帧不能证明拖动吸附、旋转手感、tooltip 完整度或邻接计算成本；这些需运行实测或官方文字佐证。

## 10. Cobalt Core — Launch Trailer

- 上传者：Brace Yourself Games（发行商）；[发行商官方页](https://braceyourselfgames.com/cobalt-core/)与 [开发团队官网](https://rocketrat.games/)提供产品和团队资料。
- 观察日期：2026-07-22（Asia/Shanghai）。
- 视频：[YouTube](https://www.youtube.com/watch?v=OE8_dfMhlfo)；观察点：[00:41](https://www.youtube.com/watch?v=OE8_dfMhlfo&t=41s)、[01:32](https://www.youtube.com/watch?v=OE8_dfMhlfo&t=92s)。
- 实机观察：00:41 是蓝色水平拖影/擦除转场；01:32 为实际战斗，敌我飞船沿单一横轴对齐，顶部意图/箭头提示攻击位置，底部是手牌及分段生命/护盾。转场和玩法共享“水平移动”母题。
- 对当前项目：每日挑战正好填补已确认缺口，可先做“日期公开 seed + 固定规则 + 本地可验证回放”，再考虑平台排行。转场/反馈复用项目 motion Profile、Action Queue 和现有 Shader 校验机制。
- 限制：无法从视频判断具体 Shader、牌组模拟性能或音乐自适应；音乐署名来自团队官网，本轮未试听。

## 横向结论

首轮 10 条与两份增量台账共同验证了六个可迁移模式：行动前公开后果；主目标与撤销常驻；下一资源和局部约束留在同一视野；表现结束后快速回到静态可判断局面；相机/HUD 不改变玩法参照系；视觉风格拥有低特效/无 Shader 退路。它们应优先落为当前项目的提示、可访问性、有限资源变体、关卡课程、轮换挑战和统一 motion/feedback Profile，而不是复制题材、角色、卡牌、音色或素材。
