# 独立游戏竞品与灵感候选目录

更新时间：2026-07-22（Asia/Shanghai）  
阶段：初筛候选池（99 项；尚不等同于深度分析）

## 收录口径与安全边界

- 候选覆盖 2048/合并解谜、网格肉鸽、牌组/骰子/库存混合策略，以及可提供高密度交互或精品表现参考的小众解谜游戏。
- 每项至少连接到一个原作者仓库、作者/工作室官网、作者 itch.io 页面或开发者可控制的官方商店页面。商店页只能证明公开产品信息；源码、性能和设计动机仍需仓库、开发日志或实机视频补证。
- 本轮仅做网页侧初筛，没有下载、构建或运行任何第三方程序。后续若分析仓库，只允许下载到 `E:\_workspace\Godot Project\_research\2048-benchmark`，必须固定完整 commit，并逐项记录代码、素材和依赖许可证。
- “未见公开代码”只表示本轮列出的候选源未提供源码，不推断作者从未公开过代码。所有未明确授权的代码、Shader、音频和美术按不可复用处理。
- 即使仓库采用 MIT 等宽松许可证，也不能默认其中素材、商标和第三方依赖同样授权；GPL、AGPL、NGPL 或复合许可项目仅做行为与架构观察，除非后续完成逐文件许可证审计。
- 当前项目只比较和记录，不修改游戏代码或 `addons/gf`。GF 映射关注能力边界，不把项目规则、内容语义或视觉风格上移到框架。

证据状态说明：`已核-A` 表示原始源码仓库/许可证入口已定位；`已核-B` 表示作者、工作室或官方商店页面已定位。日期是本轮页面复核日期，不代表页面发布日期。

## 覆盖统计

| 分组 | 数量 | 研究价值 |
| --- | ---: | --- |
| 2048 与合并解谜 | 18 | 滑动、生成、连锁、合并反馈、移动端手势与轻量留存 |
| 网格肉鸽与紧凑战术 | 33 | 回合编排、威胁预览、确定性、程序化内容、信息密度 |
| 牌组/骰子/库存混合策略 | 18 | 构筑、组合、元进度、局内解释与反馈层级 |
| 精品小众解谜 | 18 | 教学、撤销、状态可读性、动效克制、关卡工具与无障碍 |
| 追加轮次 A：合并、摆放与空间构筑 | 12 | 有限资源、承诺前预览、拖放/重排、短局终点与空间配方 |
| **合计** | **99** | 超过 60 项初筛门槛，并保留可追溯的增量轮次 |

来源分布：首轮 87 项含原作者源码托管 14 项（GitHub 13、GitLab 1）、作者/工作室官网或官方开发日志 31 项、作者 itch.io 21 项、官方商店页 21 项；追加轮次 A 的 12 项均由作者、开发者或发行商可控制页面复核。完整增量检索与证据限制见 [R2-A 搜寻台账](./round_02_search.md)。

## A. 2048 与合并解谜（1–18）

| # | 候选（类别 / 平台） | 一手来源 | 代码/许可证 | 初筛理由 | 建议深挖维度 | 证据日期 / 状态 |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | 2048（原型 / Web） | [GitHub：gabrielecirulli/2048](https://github.com/gabrielecirulli/2048) | 开放：MIT；素材与商标另审 | 事实基线；可校准四向滑动、合并顺序、生成和胜负流程 | 输入到反馈延迟、DOM/CSS 动效、状态机、移动端适配、确定性测试 | 2026-07-22 / 已核-A |
| 2 | 2048-AI（AI/基准 / Web、CLI） | [GitHub：nneonneo/2048-ai](https://github.com/nneonneo/2048-ai) | 开放：MIT；依赖另审 | 提供高吞吐自动游玩与启发式搜索参照，可用于难度和回放验证思路 | 搜索启发式、批量模拟、性能剖析、种子复现、AI 演示模式 | 2026-07-22 / 已核-A |
| 3 | 2048.c（极简实现 / 终端） | [GitHub：mevdschee/2048.c](https://github.com/mevdschee/2048.c) | 开放：MIT | 小体量实现适合核对最小规则内核与平台无关性 | 棋盘表示、移动压缩、随机生成边界、低端设备预算、测试夹具 | 2026-07-22 / 已核-A |
| 4 | 2048-cli（终端表现 / 桌面） | [GitHub：Frost-Phoenix/2048-cli](https://github.com/Frost-Phoenix/2048-cli) | 开放：MIT；以固定 commit 的 LICENSE 为准 | 纯文本环境仍能建立方向、层级和状态反馈，可反推无特效降级方案 | 键盘 UX、颜色降级、可访问性、撤销/重开、状态序列化 | 2026-07-22 / 已核-A |
| 5 | danqing/2048（原生客户端 / iOS） | [GitHub：danqing/2048](https://github.com/danqing/2048) | 开放：MIT；平台素材另审 | 原生触控实现可与 Web/Godot 手势路径比较 | 手势阈值、原生布局、生命周期、触觉、动画打断和恢复 | 2026-07-22 / 已核-A |
| 6 | Threes!（数字合并 / 移动端） | [官网：Threes!](https://asherv.com/threes/) | 当前源未见公开代码；商业素材不可复用 | 受限生成规则和可预览下一张牌提高计划性，是 2048 最重要的机制对照 | 下一块预告、部分滑动预览、音符式数字音效、个性化牌面、教程 | 2026-07-22 / 已核-B |
| 7 | Suika Game（物理合并 / Switch、移动端） | [官网：Suika Game](https://suikagame.jp/) | 当前源未见公开代码；商业素材不可复用 | 将离散合并替换为物理堆叠，展示“相同升级链、不同空间压力” | 物理可读性、碰撞性能、危险线反馈、连锁镜头、软萌音画 | 2026-07-22 / 已核-B |
| 8 | Triple Town（邻接合并 / Web、移动端） | [Spry Fox 官方玩法说明](https://support.spryfox.com/hc/en-us/articles/219104828-How-to-play-Triple-Town) | 当前源未见公开代码；商业素材不可复用 | 三消合并与永久障碍/敌人结合，适合研究局面演化和空间经济 | 邻接检测、连锁升级、熊的威胁表达、任务/商店、长局存档 | 2026-07-22 / 已核-B |
| 9 | Twenty（实时数字合并 / Web） | [作者官网：Twenty](https://www.increpare.com/game/twenty.html) | 当前源未见明确代码许可；按不可复用处理 | 把数字合并转为实时压力，能暴露节奏、抓取与容错设计 | 拖拽吸附、实时节拍、拥挤预警、失败软化、音效节奏 | 2026-07-22 / 已核-B |
| 10 | Twinfold（合并肉鸽 / iOS、Android） | [作者官网：Twinfold](https://kennysun.com/twinfold) | 当前源未见公开代码；商业素材不可复用 | 将 2048 滑动与技能、敌人、生命资源结合，是最直接的混合玩法标杆 | 敌我同盘回合、技能冷却、合并伤害、威胁预览、短局构筑 | 2026-07-22 / 已核-B |
| 11 | Six Match（滑动三消 / Web、移动端） | [作者 itch.io：Six Match](https://st33d.itch.io/six-match) | 当前源未见明确代码许可；按不可复用处理 | 角色自身作为可移动棋子，把换位、匹配和回合风险压在小网格中 | 合法步提示、角色位置语义、连锁反馈、触控精度、局面救济 | 2026-07-22 / 已核-B |
| 12 | Merge & Blade（合并 + 自动战斗 / PC、Xbox） | [Steam 官方商店页](https://store.steampowered.com/app/1446930/Merge__Blade/) | 当前源未见公开代码；商业素材不可复用 | 合并阶段与战斗阶段交替，适合研究玩法层切换和阵容可视化 | 阶段编排、单位升级、自动战斗信息密度、元进度、性能预算 | 2026-07-22 / 已核-B |
| 13 | You Must Build A Boat（滑动匹配 + RPG / PC、移动端） | [Steam 官方商店页](https://store.steampowered.com/app/290890/You_Must_Build_A_Boat/) | 当前源未见公开代码；商业素材不可复用 | 横向匹配与自动前进冒险同步，代表高节奏“操作—结果”闭环 | 并行信息流、连击音频、任务节拍、可读性优先级、持续进度 | 2026-07-22 / 已核-B |
| 14 | 10000000（滑动匹配 + RPG / PC、移动端） | [Steam 官方商店页](https://store.steampowered.com/app/227580/10000000/) | 当前源未见公开代码；商业素材不可复用 | 小屏中同时呈现跑酷战斗、资源和匹配盘，适合研究紧凑 HUD | 匹配到战斗映射、资源反馈、屏幕分区、暂停恢复、长线升级 | 2026-07-22 / 已核-B |
| 15 | Grindstone（路径合并/连线 / 多平台） | [Capybara Games 官方资料页](https://press.capybaragames.com/sheet.php?p=grindstone) | 当前源未见公开代码；商业素材不可复用 | 强烈的链式路径、命中停顿和颜色层级，是“爽感可读性”标杆 | 路径预览、逐击节奏、相机/震屏、粒子与 Shader、颜色无障碍 | 2026-07-22 / 已核-B |
| 16 | Flowstone Saga（掉落拼图 + RPG / PC） | [Impact Gameworks 官网游戏页](https://impactgameworks.com/games/) | 当前源未见公开代码；商业素材不可复用 | 拼图操作直接驱动战斗，适合比较模式规则与共用战斗反馈边界 | 拼图战斗节拍、敌方意图、教程、技能修饰、UI 与音频层级 | 2026-07-22 / 已核-B |
| 17 | Little Alchemy 2（组合发现 / Web、移动端） | [官网：Little Alchemy 2](https://littlealchemy2.com/) | 当前源未见公开代码；商业素材不可复用 | 非空间合并强调发现、收藏和组合知识图谱，可启发图鉴与提示系统 | 配方图、拖放反馈、重复结果、搜索/筛选、云存档、内容工具 | 2026-07-22 / 已核-B |
| 18 | High Rise（空间合并 / Android、iOS） | [Google Play 官方商店页](https://play.google.com/store/apps/details?id=com.SMPL.HighRise) | 当前源未见公开代码；商业素材不可复用 | 把方块合并扩展到等距城市轮廓，兼具空间规划与舒缓表现 | 等距选取、层高遮挡、柔和动效、触觉/音效、移动端性能 | 2026-07-22 / 已核-B |

## B. 网格肉鸽与紧凑战术（19–51）

| # | 候选（类别 / 平台） | 一手来源 | 代码/许可证 | 初筛理由 | 建议深挖维度 | 证据日期 / 状态 |
| ---: | --- | --- | --- | --- | --- | --- |
| 19 | Hoplite（六角格肉鸽 / Android、iOS） | [Google Play 官方商店页](https://play.google.com/store/apps/details?id=com.magmafortress.hoplite) | 当前源未见公开代码；商业素材不可复用 | 极小规则集用威胁格、朝向与技能制造高决策密度 | 威胁覆盖、一步一反馈、六角输入、技能冷却、每日挑战 | 2026-07-22 / 已核-B |
| 20 | 868-HACK（极简网格肉鸽 / PC、移动端） | [Steam 官方商店页](https://store.steampowered.com/app/274700/868HACK/) | 当前源未见公开代码；商业素材不可复用 | 资源、敌人生成和关卡出口都浓缩在单屏，适合信息经济研究 | 图标语言、确定性与随机性、敌人队列、风险预告、音频提示 | 2026-07-22 / 已核-B |
| 21 | Cinco Paus（未知信息肉鸽 / PC、iOS） | [Steam 官方商店页](https://store.steampowered.com/app/923470/Cinco_Paus/) | 当前源未见公开代码；商业素材不可复用 | 以反复试验揭示法杖效果，能启发局内知识积累和重玩差异 | 未知属性揭示、笔记式 UI、失败学习、局间记忆、文本本地化 | 2026-07-22 / 已核-B |
| 22 | Imbroglio（牌组即地图 / iOS） | [App Store 官方商店页](https://apps.apple.com/us/app/imbroglio/id969264934) | 当前源未见公开代码；商业素材不可复用 | 玩家构筑的地砖同时定义移动、攻击和升级，是内容复用典范 | 地图构筑、旋转/升级、状态图标、角色差异、触控浏览 | 2026-07-22 / 已核-B |
| 23 | Corrypt（推箱 + 持久世界 / PC、iOS） | [作者 itch.io：Corrypt](https://smestorp.itch.io/corrypt) | 当前源未见明确代码许可；按不可复用处理 | 推箱规则被全局变化持续重写，适合研究状态持久化和规则反转 | 世界状态、不可逆选择、存档安全、教学惊喜、低保真表现 | 2026-07-22 / 已核-B |
| 24 | Zaga-33（单屏肉鸽 / PC、移动端） | [作者 itch.io：Zaga-33](https://smestorp.itch.io/zaga-33) | 当前源未见明确代码许可；按不可复用处理 | 极小盘面与极少资源形成快速重开循环，可校准短局密度 | 一屏信息、重开摩擦、敌人节拍、随机生成、公平性测试 | 2026-07-22 / 已核-B |
| 25 | ENYO（钩拉战术 / Android、iOS） | [Google Play 官方商店页](https://play.google.com/store/apps/details?id=com.tinytouchtales.enyo) | 当前源未见公开代码；商业素材不可复用 | 无直接攻击，靠钩拉、盾撞和环境互动建立强位置语义 | 攻击预览、位移链、陷阱反馈、教程关卡、回合撤销 | 2026-07-22 / 已核-B |
| 26 | Maze Machina（滑动网格战术 / iOS、Android） | [App Store 官方商店页](https://apps.apple.com/ca/app/maze-machina/id1481339646) | 当前源未见公开代码；商业素材不可复用 | 整盘滑动与角色/地砖能力结合，是 2048 输入模型的直接变体 | 全盘移动解析、意图预览、角色动效、局面重置、日常模式 | 2026-07-22 / 已核-B |
| 27 | Pawnbarian（棋子牌组肉鸽 / Web、PC、移动端） | [作者 itch.io：Pawnbarian Classic](https://j4nw.itch.io/pawnbarian-classic) | 当前源未见明确代码许可；按不可复用处理 | 用棋类走法卡替代传统攻击，规则熟悉但组合新颖 | 合法格高亮、牌面到棋盘映射、敌方意图、触控、无障碍 | 2026-07-22 / 已核-B |
| 28 | Dungeon Deathball（运动战术肉鸽 / PC） | [作者 itch.io：Dungeon Deathball](https://crowbarska.itch.io/deathball) | 当前源未见明确代码许可；按不可复用处理 | 把护送、投球和敌人控制压缩在小格战场，目标反馈明确 | 目标路线、推拉碰撞、队伍状态、慢动作命中、关卡节奏 | 2026-07-22 / 已核-B |
| 29 | Lost For Swords（牌组即地牢 / PC、Web） | [作者 itch.io：Lost For Swords](https://maxbytes.itch.io/lost-for-swords) | 当前源未见明确代码许可；按不可复用处理 | 抽到的卡组成空间地图，适合研究内容、布局和风险的统一模型 | 牌库生成地图、装备耐久、路径规划、信息揭示、局内构筑 | 2026-07-22 / 已核-B |
| 30 | Rift Wizard（法术构筑肉鸽 / PC） | [Steam 官方商店页](https://store.steampowered.com/app/1271280/Rift_Wizard/) | 当前源未见公开代码；商业素材不可复用 | 大规模法术组合仍维持网格战术清晰度，可研究内容扩展架构 | 技能标签、范围预览、日志、组合爆发性能、存档/种子 | 2026-07-22 / 已核-B |
| 31 | Rift Wizard 2（法术构筑肉鸽 / PC） | [Steam 官方商店页](https://store.steampowered.com/app/2058570/Rift_Wizard_2/) | 当前源未见公开代码；商业素材不可复用 | 续作可观察同一核心的反馈、内容和可用性迭代路径 | 前后代差异、召唤物反馈、状态检索、构筑发现、性能 | 2026-07-22 / 已核-B |
| 32 | Desktop Dungeons: Rewind（探索解谜肉鸽 / PC） | [开发者官网](https://www.desktopdungeons.net/) | 当前源未见公开代码；商业素材不可复用 | 未探索格既是地图也是回复资源，代表可计算的探索经济 | 黑雾揭示、伤害预测、神祇/道具信息、撤销边界、关卡解法 | 2026-07-22 / 已核-B |
| 33 | Into the Breach（确定性战术 / PC、主机、移动端） | [Subset Games 官网](https://subsetgames.com/itb.html) | 当前源未见公开代码；商业素材不可复用 | 敌方意图完全可见，将一回合塑造成可读的网格解谜 | 攻击预览、推撞链、时间轴、撤销、屏幕震动、手柄焦点 | 2026-07-22 / 已核-B |
| 34 | Shattered Pixel Dungeon（传统肉鸽 / 多平台） | [GitHub：00-Evan/shattered-pixel-dungeon](https://github.com/00-Evan/shattered-pixel-dungeon) | 开放：GPL-3.0；素材与依赖逐项审计 | 成熟移动端肉鸽，长期更新形成大量 UI、存档和兼容性经验 | 触控菜单、日志、存档迁移、种子挑战、内容注册、性能 | 2026-07-22 / 已核-A |
| 35 | Pixel Dungeon（传统肉鸽 / Android） | [GitHub：watabou/pixel-dungeon](https://github.com/watabou/pixel-dungeon) | 开放：GPL-3.0；素材与依赖逐项审计 | 可与其衍生项目对照，观察核心系统如何被长期扩展 | 最小系统边界、生成算法、移动端 UI、存档版本、分支差异 | 2026-07-22 / 已核-A |
| 36 | Brogue Community Edition（传统肉鸽 / 桌面） | [GitHub：tmewett/BrogueCE](https://github.com/tmewett/BrogueCE) | 开放：AGPL-3.0；仅观察，逐文件审计 | 以颜色、粒子式字符和环境模拟建立强烈系统反馈 | 光照/颜色、环境连锁、生成公平性、回放种子、键盘 UX | 2026-07-22 / 已核-A |
| 37 | Dungeon Crawl Stone Soup（传统肉鸽 / 桌面、Web） | [GitHub：crawl/crawl](https://github.com/crawl/crawl) | 复合许可：主程序以 GPL-2.0+ 为主，素材/文件另有条款；仅观察 | 大型长期项目可研究内容注册、自动探索与信息检索扩展性 | 自动化输入、战斗日志、Web Tiles、模组数据、性能和存档 | 2026-07-22 / 已核-A |
| 38 | NetHack（传统肉鸽 / 多平台） | [GitHub：NetHack/NetHack](https://github.com/NetHack/NetHack) | 自定义 NetHack General Public License；仅观察并逐条复核 | 极深交互规则适合分析“发现性”与边缘状态处理 | 命令发现、对象检查、消息历史、存档恢复、规则测试 | 2026-07-22 / 已核-A |
| 39 | Angband（传统肉鸽 / 多平台） | [GitHub：angband/angband](https://github.com/angband/angband) | 复合/历史许可；固定 commit 后核对 COPYING 与逐文件声明 | 长期跨平台代码库可提供前端分离和内容数据化参照 | 平台前端、对象知识库、配置、存档兼容、生成性能 | 2026-07-22 / 已核-A |
| 40 | Cogmind（机械构筑肉鸽 / PC） | [开发者官网](https://www.gridsagegames.com/cogmind/) | 当前源未见公开代码；商业素材不可复用 | 机器部件、ASCII/tiles 与高信息 UI 结合，反馈系统极成熟 | 部件损伤、战斗日志、粒子/终端 Shader、音频层、信息筛选 | 2026-07-22 / 已核-B |
| 41 | Caves of Qud（系统型肉鸽 / PC） | [开发者 itch.io：Caves of Qud](https://freeholdgames.itch.io/cavesofqud) | 当前源未见公开代码；商业素材不可复用 | 大量状态、能力和世界模拟仍需保持检索性，适合内容架构研究 | 能力搜索、状态解释、程序生成、模组接口、存档迁移 | 2026-07-22 / 已核-B |
| 42 | Jupiter Hell（3D 网格肉鸽 / PC） | [ChaosForge 官方资料页](https://chaosforge.org/presskit/jupiter_hell) | 当前源未见公开代码；商业素材不可复用 | 把离散回合翻译成顺滑 3D 动作观感，直接关联动效与音频目标 | 动画接力、镜头、枪声音层、意图可读性、渲染降级 | 2026-07-22 / 已核-B |
| 43 | DRL（DoomRL，网格肉鸽 / 桌面） | [GitHub：chaosforgeorg/doomrl](https://github.com/chaosforgeorg/doomrl) | 代码 GPL-2.0；美术 CC-BY-SA-4.0；依赖另审，仅观察 | 可与 Jupiter Hell 对照同一理念从 2D 到 3D 的迁移 | 回合核心、输入队列、音效映射、资源许可拆分、平台抽象 | 2026-07-22 / 已核-A |
| 44 | Golden Krone Hotel（光影肉鸽 / PC） | [开发者官网](https://www.goldenkronehotel.com/) | 当前源未见公开代码；商业素材不可复用 | 日夜/吸血鬼形态把光照变成战术资源，视觉与规则高度统一 | 光照危险区、形态切换、颜色语义、教程、内容节奏 | 2026-07-22 / 已核-B |
| 45 | Tangledeep（职业构筑肉鸽 / PC、Switch） | [Impact Gameworks 官网](https://tangledeep.com/games/) | 当前源未见公开代码；商业素材不可复用 | 丰富职业和宠物系统可帮助辨别通用框架与项目内容边界 | 职业数据、技能树、宠物 AI、像素特效、存档与手柄 UI | 2026-07-22 / 已核-B |
| 46 | HyperRogue（非欧几何肉鸽 / 多平台） | [GitHub：zenorogue/hyperrogue](https://github.com/zenorogue/hyperrogue) | 开放：GPL-2.0；素材与依赖逐项审计，仅观察 | 非欧网格迫使相机、邻接和路径提示摆脱常规方格假设 | 网格抽象、投影 Shader、相机、输入、生成和性能 | 2026-07-22 / 已核-A |
| 47 | The Ground Gives Way（极简传统肉鸽 / PC） | [作者官网与手册](https://www.thegroundgivesway.com/manual/) | 当前源未见公开代码；商业素材不可复用 | 短流程、清晰物品取舍和内置手册适合研究低门槛传统肉鸽 | 帮助系统、装备比较、快捷键、死亡复盘、短局节奏 | 2026-07-22 / 已核-B |
| 48 | Path of Achra（构筑肉鸽 / PC） | [作者 itch.io：Path of Achra](https://ulfsire.itch.io/path-of-achra) | 当前源未见明确代码许可；按不可复用处理 | 高组合构筑配合自动触发，适合分析复杂规则的解释方式 | 触发链日志、技能标签、构筑预览、自动战斗、性能上限 | 2026-07-22 / 已核-B |
| 49 | Infra Arcana（恐怖肉鸽 / 桌面） | [GitLab：martin-tornqvist/ia](https://gitlab.com/martin-tornqvist/ia) | 开放：AGPL-3.0+；素材/依赖另审，仅观察 | 理智、视野和音响塑造不可见威胁，适合氛围反馈研究 | 视野 Shader、环境音、恐惧状态、日志、生成和存档 | 2026-07-22 / 已核-A |
| 50 | Crown Trick（回合战术肉鸽 / PC、主机） | [开发者 itch.io：Crown Trick](https://nextstudios.itch.io/crowntrick) | 当前源未见公开代码；商业素材不可复用 | 敌我同步回合配合高规格 2D 表现，适合研究回合动画队列 | 行动队列、敌方意图、像素特效、Boss 电报、手柄 UI | 2026-07-22 / 已核-B |
| 51 | Crypt of the NecroDancer（节拍网格肉鸽 / 多平台） | [Steam 官方商店页](https://store.steampowered.com/app/247080/Crypt_of_the_NecroDancer/) | 当前源未见公开代码；商业素材不可复用 | 将每回合绑定节拍，是音频、输入窗口和可访问性的重要标杆 | 节拍同步、延迟校准、错拍反馈、音乐分层、非节拍辅助模式 | 2026-07-22 / 已核-B |

## C. 牌组、骰子与库存混合策略（52–69）

| # | 候选（类别 / 平台） | 一手来源 | 代码/许可证 | 初筛理由 | 建议深挖维度 | 证据日期 / 状态 |
| ---: | --- | --- | --- | --- | --- | --- |
| 52 | Slice & Dice（骰子构筑肉鸽 / PC、移动端） | [作者 itch.io：Slice & Dice](https://tann.itch.io/slice-dice) | 当前源未见明确代码许可；按不可复用处理 | 六面骰即角色动作集，重掷与锁定形成清晰的风险管理 | 骰面编辑、重掷动效、敌方意图、状态 tooltip、海量模式 | 2026-07-22 / 已核-B |
| 53 | Dicey Dungeons（骰子牌组肉鸽 / 多平台） | [开发者官网](https://diceydungeons.com/) | 当前源未见公开代码；商业素材不可复用 | 鲜明节目包装把重复战斗变成角色化章节，音画层级突出 | 骰子投放、设备槽、角色主题、音乐、教程与无障碍 | 2026-07-22 / 已核-B |
| 54 | Luck Be a Landlord（老虎机构筑 / PC、移动端） | [作者 itch.io](https://trampolinetales.itch.io/luck-be-a-landlord) | 当前源未见明确代码许可；按不可复用处理 | 用单次旋转展示大量触发链，是合并连锁反馈的强参照 | 触发排序、收益飞字、符号 tooltip、音效堆叠、性能合批 | 2026-07-22 / 已核-B |
| 55 | Balatro（扑克构筑肉鸽 / 多平台） | [开发者官网](https://localthunk.com/) | 当前源未见公开代码；商业素材不可复用 | 清晰计分拆解、CRT 风格和 Joker 组合让复杂乘区易于理解 | 计分时间轴、数字动效、牌面 Shader、组合解释、控制器焦点 | 2026-07-22 / 已核-B |
| 56 | Backpack Hero（库存构筑肉鸽 / PC、主机） | [开发者 itch.io](https://thejaspel.itch.io/backpack-hero) | 当前源未见公开代码；商业素材不可复用 | 物品邻接、朝向和空间本身构成构筑，适合启发网格能力组合 | 拖放/旋转、邻接预览、库存验证、组合触发、存档 | 2026-07-22 / 已核-B |
| 57 | Backpack Battles（库存自动战斗 / PC） | [开发者 itch.io](https://playwithfurcifer.itch.io/backpack-battles) | 当前源未见公开代码；商业素材不可复用 | 异步对战把库存布局与战斗复盘结合，可研究可解释性 | 配方发现、布局命中区、战斗日志、回放、赛季数据边界 | 2026-07-22 / 已核-B |
| 58 | Shogun Showdown（时间轴战术构筑 / PC、主机） | [作者 itch.io](https://roboatino.itch.io/shogunshowdown) | 当前源未见明确代码许可；按不可复用处理 | 左右一维战场通过行动队列产生高密度规划，适合时间轴参考 | 队列预览、位置交换、命中停顿、升级卡、手柄输入 | 2026-07-22 / 已核-B |
| 59 | Shotgun King（棋类构筑肉鸽 / PC、主机） | [开发者 itch.io](https://punkcake.itch.io/shotgun-king) | 当前源未见明确代码许可；按不可复用处理 | 熟悉的棋盘规则结合散射、装填和双向升级，教学成本低 | 弹道预览、敌方回合、装填音效、规则卡、难度变体 | 2026-07-22 / 已核-B |
| 60 | Wildfrost（牌组肉鸽 / 多平台） | [官网](https://www.wildfrostgame.com/) | 当前源未见公开代码；商业素材不可复用 | 倒计时敌我行动与高质量卡面动效可启发回合预告 | 计数器、牌面状态、队伍重排、击中动画、信息层级 | 2026-07-22 / 已核-B |
| 61 | Ring of Pain（环形地牢牌组 / 多平台） | [官网](https://ringofpain.com/) | 当前源未见公开代码；商业素材不可复用 | 环形卡牌把前进、战斗和选择统一为左右比较 | 环形布局、左右预览、危险数值、转场、触控与手柄 | 2026-07-22 / 已核-B |
| 62 | Peglin（弹珠构筑肉鸽 / 多平台） | [Red Nexus Games 官方资料页](https://rednexus.games/press/) | 当前源未见公开代码；商业素材不可复用 | 实时物理轨迹与回合制构筑结合，可观察预测不确定性的表达 | 瞄准轨迹、碰撞性能、多球特效、伤害结算、触觉/音频 | 2026-07-22 / 已核-B |
| 63 | Spin Hero（转轮构筑肉鸽 / PC） | [Steam 官方商店页](https://store.steampowered.com/app/2917350/Spin_Hero/) | 当前源未见公开代码；商业素材不可复用 | 用转轮位置和符号组合驱动战斗，与合并项目的格槽语义相近 | 转轮停靠、触发链、符号升级、敌方预告、动效节拍 | 2026-07-22 / 已核-B |
| 64 | Die in the Dungeon（骰面背包构筑 / Web、PC） | [作者 itch.io：原型](https://alarts.itch.io/die-in-the-dungeon) | 当前源未见明确代码许可；按不可复用处理 | 骰子类型、点数和摆放位置共同定义动作，易与网格构筑比较 | 槽位规则、骰面颜色、投放反馈、组合解释、局间升级 | 2026-07-22 / 已核-B |
| 65 | Solitairica（纸牌战斗肉鸽 / PC、移动端） | [Steam 官方商店页](https://store.steampowered.com/app/463980/Solitairica/) | 当前源未见公开代码；商业素材不可复用 | 接龙合法性直接产出战斗资源，展示传统规则的战斗化改造 | 合法牌提示、资源飞行、技能栏、移动端布局、存档 | 2026-07-22 / 已核-B |
| 66 | Meteorfall: Krumit’s Tale（网格牌组肉鸽 / PC、移动端） | [Steam 官方商店页](https://store.steampowered.com/app/1073320/Meteorfall_Krumits_Tale/) | 当前源未见公开代码；商业素材不可复用 | 3×3 牌格同时承担抽牌、资源和路线选择，与当前项目空间接近 | 牌格补充、拖动/点击、资源预览、角色动画、移动端 UX | 2026-07-22 / 已核-B |
| 67 | Fights in Tight Spaces（牌组战术 / PC、主机） | [Ground Shatter 官网](https://www.groundshatter.com/home) | 当前源未见公开代码；商业素材不可复用 | 攻击预览、推撞与电影化动作结合，代表“先算清、再演好” | 预览与执行分层、相机、动作队列、碰撞链、跳过动画 | 2026-07-22 / 已核-B |
| 68 | Tactical Breach Wizards（网格战术解谜 / PC） | [Steam 官方商店页](https://store.steampowered.com/app/1043810/Tactical_Breach_Wizards/) | 当前源未见公开代码；商业素材不可复用 | 高自由撤销和行动预演降低试错成本，适合研究沙盘式回合 UX | 时间线撤销、敌人意图、推撞预览、对话节奏、关卡目标 | 2026-07-22 / 已核-B |
| 69 | Loop Hero（自动战斗 + 地图构筑 / 多平台） | [Steam 官方商店页](https://store.steampowered.com/app/1282730/Loop_Hero/) | 当前源未见公开代码；商业素材不可复用 | 玩家通过地块塑造自动循环，适合研究间接控制和长线资源反馈 | 循环节奏、速度控制、地块组合、自动战斗日志、元进度 | 2026-07-22 / 已核-B |

## D. 精品小众解谜（70–87）

| # | 候选（类别 / 平台） | 一手来源 | 代码/许可证 | 初筛理由 | 建议深挖维度 | 证据日期 / 状态 |
| ---: | --- | --- | --- | --- | --- | --- |
| 70 | Baba Is You（规则改写推箱 / 多平台） | [作者官网](https://www.hempuli.com/Baba/) | 当前源未见公开代码；商业素材不可复用 | 把规则句子变成棋盘对象，是规则可视化与组合爆炸的标杆 | 规则解析、冲突优先级、撤销栈、关卡验证、编辑器 | 2026-07-22 / 已核-B |
| 71 | Patrick’s Parabox（递归推箱 / PC、主机） | [官方资料页](https://www.patricksparabox.com/press/) | 当前源未见公开代码；商业素材不可复用 | 递归空间通过连续缩放保持可读，值得研究相机与状态映射 | 嵌套坐标、相机缩放、撤销、关卡教学、视觉连续性 | 2026-07-22 / 已核-B |
| 72 | A Monster’s Expedition（开放式推箱 / 多平台） | [官网](https://www.monsterexpedition.com/) | 当前源未见公开代码；商业素材不可复用 | 开放岛屿结构以环境和路径自然引导，不依赖繁重菜单 | 空间教学、岛屿解锁、镜头、环境音、提示与恢复 | 2026-07-22 / 已核-B |
| 73 | Bonfire Peaks（立体推箱 / 多平台） | [官网](https://bonfirepeaks.com/) | 当前源未见公开代码；商业素材不可复用 | 等距体素、火焰和克制转场形成精致但不干扰解题的表现 | 深度遮挡、选格、火焰 Shader、撤销动效、手柄焦点 | 2026-07-22 / 已核-B |
| 74 | Snakebird（网格路径解谜 / PC、移动端） | [开发者 itch.io](https://noumenongames.itch.io/snakebird) | 当前源未见明确代码许可；按不可复用处理 | 重力、身体占格和目标顺序产生高难度但状态透明的谜题 | 身体跟随、重力结算、失败恢复、撤销、触控输入 | 2026-07-22 / 已核-B |
| 75 | Stephen’s Sausage Roll（网格推滚解谜 / PC） | [Steam 官方商店页](https://store.steampowered.com/app/353540/Stephens_Sausage_Roll/) | 当前源未见公开代码；商业素材不可复用 | 多面烹饪状态与角色/叉子朝向形成严密状态空间 | 多面状态可视化、旋转输入、撤销、关卡拓扑、教学 | 2026-07-22 / 已核-B |
| 76 | Cosmic Express（路径规划解谜 / 多平台） | [开发者 itch.io](https://draknek.itch.io/cosmic-express) | 当前源未见明确代码许可；按不可复用处理 | 单条列车路径同时受容量、顺序和不可交叉约束，适合预览 UX | 路径绘制、合法性反馈、撤销、关卡选择、触控精度 | 2026-07-22 / 已核-B |
| 77 | Railbound（轨道拼接解谜 / 多平台） | [Afterburn 官网](https://afterburn.games/railbound/) | 当前源未见公开代码；商业素材不可复用 | 拼接轨道、车厢顺序与精致低干扰动画结合，产品完成度高 | 轨道连接提示、运行预演、失败回退、关卡导航、触觉 | 2026-07-22 / 已核-B |
| 78 | Golf Peaks（卡牌移动解谜 / 多平台） | [开发者 itch.io](https://afterburn.itch.io/golf-peaks) | 当前源未见明确代码许可；按不可复用处理 | 卡牌把移动距离和地形动作显式化，适合小屏单手交互 | 卡牌预览、等距落点、地形反馈、撤销、移动端布局 | 2026-07-22 / 已核-B |
| 79 | Can of Wormholes（网格推箱解谜 / PC） | [开发者官网](https://www.muntedfinger.com/canofwormholes/) | 当前源未见公开代码；商业素材不可复用 | 用可交互提示系统拆解复杂机制，是“不给答案的帮助”参照 | 分层提示、状态回放、机制教学、撤销、关卡工具 | 2026-07-22 / 已核-B |
| 80 | Isles of Sea and Sky（开放式推箱 / PC） | [Steam 官方商店页](https://store.steampowered.com/app/1233070/Isles_of_Sea_and_Sky/) | 当前源未见公开代码；商业素材不可复用 | 将推箱关卡嵌入探索、收集与能力解锁，可研究模式外层 | 世界地图、能力门、收集反馈、存档、像素特效与音频 | 2026-07-22 / 已核-B |
| 81 | Void Stranger（推箱/元叙事 / PC） | [开发者 itch.io 与开发日志](https://system-erasure.itch.io/void-stranger/devlog) | 当前源未见明确代码许可；按不可复用处理 | 极简双色画面承载大量状态与元层变化，表现成本控制突出 | 双色可读性、秘密反馈、重开/存档语义、音频、输入陷阱 | 2026-07-22 / 已核-B |
| 82 | ElecHead（平台解谜 / PC、主机） | [作者作品页](https://namatakahashi.notion.site/en) | 当前源未见公开代码；商业素材不可复用 | 单一导电规则通过像素电光和即时音效获得强反馈 | 导电状态、屏幕闪光安全、像素特效、音频同步、教学 | 2026-07-22 / 已核-B |
| 83 | Mosa Lina（系统型解谜 / PC） | [作者 itch.io](https://stuffedwombat.itch.io/mosa-lina) | 当前源未见明确代码许可；按不可复用处理 | 随机工具与开放解法鼓励即兴，适合研究可重玩解谜 | 工具随机、物理交互、失败重开、局面种子、生成公平性 | 2026-07-22 / 已核-B |
| 84 | Gorogoa（画框拼接解谜 / 多平台） | [发行商官方游戏页](https://www.annapurnainteractive.com/en/games/gorogoa) | 当前源未见公开代码；商业素材不可复用 | 缩放、叠放和画框转场无缝连接，是界面即玩法的表现标杆 | 拖放命中、跨框动画、缩放、音景、提示与移动端适配 | 2026-07-22 / 已核-B |
| 85 | A Good Snowman Is Hard To Build（推滚解谜 / 多平台） | [Steam 官方商店页](https://store.steampowered.com/app/316610/A_Good_Snowman_Is_Hard_To_Build/) | 当前源未见公开代码；商业素材不可复用 | 三段雪球大小规则易懂，温和包装和低压力恢复值得借鉴 | 状态轮廓、推滚动效、环境音、撤销、无障碍与触控 | 2026-07-22 / 已核-B |
| 86 | Sokobond（化学推箱 / PC、移动端） | [官网](https://www.sokobond.com/) | 当前源未见公开代码；商业素材不可复用 | 化学键把领域知识转成空间约束，适合研究主题化规则教学 | 键连接可视化、知识渐进、撤销、关卡选择、文本最小化 | 2026-07-22 / 已核-B |
| 87 | Opus Magnum（机器构造解谜 / PC） | [Zachtronics 官网](https://www.zachtronics.com/opus-magnum/) | 当前源未见公开代码；商业素材不可复用 | 可编程机械臂、循环执行和多指标评分可启发回放与优化挑战 | 时间轴、单步执行、回放导出、性能指标、关卡编辑/验证 | 2026-07-22 / 已核-B |

## E. 追加轮次 A：合并、摆放与空间构筑（88–99）

本组与前 87 项及既有深度报告完成名称、系列和产品 URL 去重。它有意保留同类横向聚类：Dorfromantik、Pan'orama、TerraScape 用于比较地块摆放语法；Mini Metro 与 Mini Motorways 用于比较同一工作室的线路设计演进。两组都只算作品候选，不把同源作品数误当来源多样性。

| # | 候选（类别 / 平台） | 一手来源 | 代码/许可证 | 初筛理由 | 建议深挖维度 | 证据日期 / 状态 |
| ---: | --- | --- | --- | --- | --- | --- |
| 88 | Dorfromantik（六角地块摆放 / PC、Switch） | [Toukana 官方 press kit](https://www.toukana.com/dorfromantik/presskit) | 当前源未见公开代码；商业素材不可复用 | 有限牌堆、边缘匹配、任务和高分把舒缓摆放转成持续取舍 | 下一牌预告、合法边界、完美边奖励、月度挑战、长地图可读性 | 2026-07-22 / 已核-B |
| 89 | ISLANDERS（空间计分建造 / 多平台） | [官方系列站](https://playislanders.com/) | 当前源未见公开代码；商业素材不可复用 | 建筑位置直接决定邻接分数，用很少资源形成可预演的短局城市解谜 | 邻接分数、岛屿轮换、撤销边界、相机遮挡、低干扰 HUD | 2026-07-22 / 已核-B |
| 90 | Stacklands（卡牌堆叠合成 / PC、macOS、Switch） | [Sokpop 作者 itch.io](https://sokpop.itch.io/stacklands) | 当前源未见公开代码；商业素材不可复用 | 卡牌同时承担资源、单位、配方、计时与空间对象，拖放即可触发生产或战斗 | 堆叠命中、配方解释、暂停拖动、拥挤场景、速度档与控制器 | 2026-07-22 / 已核-B |
| 91 | Wilmot Works It Out（拼块整理 / PC、macOS、Switch） | [Finji 官方产品页](https://finji.co/games/wwio/) | 当前源未见公开代码；商业素材不可复用 | 不展示盒面答案，让形状、颜色和局部图案承担发现；完成内容又转成家居陈列 | 拼块吸附、错误容忍、缩放、额外块、完成仪式、低压力进度 | 2026-07-22 / 已核-B |
| 92 | Mini Metro（线路空间构筑 / 多平台） | [开发者官网](https://dinopoloclub.com/games/mini-metro/) | 当前源未见公开代码；商业素材不可复用 | 画线、拆线与有限列车/车厢把持续增长压缩成清楚的网络图 | 路线编辑、拥堵预警、动态音频、每日挑战、色觉模式、多输入 | 2026-07-22 / 已核-B |
| 93 | Mini Motorways（道路空间构筑 / PC、Switch、Apple Arcade） | [开发者官网](https://dinopoloclub.com/games/mini-motorways/) | 当前源未见公开代码；商业素材不可复用 | 可反复重画道路，并用有限桥梁、环岛和高速公路应对实时增长 | 路径绘制、暂停编辑、拥堵反馈、地图变体、长局性能、触控/手柄 | 2026-07-22 / 已核-B |
| 94 | Pan'orama（六角地块城市拼图 / PC） | [开发者/发行商 Steam 页](https://store.steampowered.com/app/1730250/Panorama/) | 当前源未见公开代码；商业素材不可复用 | 地块牌堆与特殊建筑把景观拼接、得分和能力组合在同一层 | 地块连锁、建筑能力、永久 perk、控制器、景观动效、程序地图 | 2026-07-22 / 已核-B |
| 95 | TerraScape（建筑牌摆放 / PC） | [Bitfall Studios 作者 itch.io](https://bitfallstudios.itch.io/terrascapegame) | 当前源未见公开代码；商业素材不可复用 | 建筑对地形与邻居产生正负影响，得分再解锁新牌组 | 影响范围、牌组选择、任务/程序地图、榜资格、相机 | 2026-07-22 / 已核-B |
| 96 | Cloud Gardens（种植摆放 / PC、Xbox、Switch） | [Noio 开发者 press kit](https://www.noio.nl/cloud-gardens-presskit/) | 当前源未见公开代码；商业素材不可复用 | 种子位置与废墟道具共同驱动植物覆盖，把空间优化包装成低压力景观 | 生长可读性、照片模式、关卡/沙盒、植被性能、环境音、编辑器 | 2026-07-22 / 已核-B |
| 97 | Townscaper（程序化块放置玩具 / Web、多平台） | [作者可控 Web 版本](https://oskarstalberg.com/Townscaper/) | 当前源未见公开代码；商业素材不可复用 | 单次点击由不规则网格和邻域规则自动生成房屋、桥、拱门或花园 | 邻域规则、结果预览、撤销、配色、生成动画、分享与低端降级 | 2026-07-22 / 已核-B |
| 98 | Terra Nil（生态恢复建造 / PC、Switch、移动端） | [Free Lives 官方产品页](https://www.terranil.com/) | 当前源未见公开代码；商业素材不可复用 | 设施摆放用于恢复生态，最终还要回收设施，形成分阶段的“留下更少”闭环 | 影响半径、阶段转换、生态覆盖、回收、教学、植被/水体性能 | 2026-07-22 / 已核-B |
| 99 | Freshly Frosted（传送带空间解谜 / 多平台） | [QAG 官方产品页](https://www.qag.io/freshly-frosted.html) | 当前源未见公开代码；商业素材不可复用 | 144 个手工关卡以传送带、分流、推送、合并、复制、随机和传送逐步扩展同一语法 | 路径预演、连续模拟、错误反馈、渐进课程、正向旁白、音景 | 2026-07-22 / 已核-B |

## 深度分析排队建议

初筛不预判最终结论。首批应优先覆盖机制距离、表现标杆、开源可验证性和平台差异，避免只研究同一类型：

1. **直接机制对照**：2048、Threes!、Twinfold、Maze Machina、Triple Town。
2. **回合与可读性标杆**：Hoplite、Into the Breach、ENYO、Shogun Showdown、Fights in Tight Spaces。
3. **表现与音频标杆**：Grindstone、Balatro、Dicey Dungeons、Jupiter Hell、Crypt of the NecroDancer。
4. **系统/源码证据标杆**：2048-AI、Shattered Pixel Dungeon、Brogue CE、DCSS、HyperRogue。
5. **教学与撤销标杆**：Baba Is You、Patrick’s Parabox、Can of Wormholes、Railbound、A Monster’s Expedition。

这 25 项构成首轮深挖池；最终计入“深度分析”的项目仍必须满足方法文档中的完整报告字段和证据要求。

## 后续证据补齐清单

- 为首轮深挖池逐项补充固定 commit/版本、许可证文件路径、官方开发日志和可复核实机视频时间戳。
- 对仅有官方商店页的候选，补作者官网或开发日志；找不到时明确降低结论等级，不能把商店文案扩写成实现事实。
- 对复合许可仓库建立代码、素材、字体、音频、依赖五类清单；未经逐项确认不提取实现。
- 每个深度报告都与当前项目基线和 GF 9.0.1 能力做“可借鉴 / 已有深化 / 不适配 / 框架反馈候选”四分法比较。
