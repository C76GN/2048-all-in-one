# 28 项深度样本对比矩阵

更新时间：2026-07-22（Asia/Shanghai）

本矩阵把单项目报告压缩为产品决策视图。每行只采用固定提交源码、许可证、作者/发行商页面或已实际观察并记录时间点的视频；“当前差距”均以[项目能力基线](./project_baseline.md)和[GF 映射审计](./gf_mapping_audit.md)为准。评分不是“游戏好坏”，而是该样本对当前项目某个决策的证据强度。

## 开放源码固定版本样本（10 项）

| 深度样本 | 最强一手证据与可借鉴模式 | 相对当前项目 | GF 与项目边界 | 综合判断 |
| --- | --- | --- | --- | --- |
| [gabrielecirulli/2048](./projects/repo_gabrielecirulli_2048.md) | `previousPosition`、`mergedFrom`、新生状态与 `score_delta` 让表现消费一次移动的语义结果；100–200 ms 的位移/pop 构成经典手感基线 | 当前规则、拓扑、确定性、回放和主题均为超集；`TurnResult` 已类型化移动、合并、生成、转化与汇总，经典节奏仍需持续做跨档位回归 | `GFTurnFlowSystem` 提交规则，`GFActionQueueSystem` 消费表现；项目拥有 `TurnResult` 和节奏 Profile | **P0 基线已采用**：借动作结果和因果节拍，不借 DOM 重建、裸 JSON 存档或 `Math.random()` |
| [danqing/2048](./projects/repo_danqing_2048.md) | 尺寸、合并规则、主题正交选择；三合一/Fibonacci 把变体规则和分阶段动画显式表达 | 当前已有 6 模式和 3×3–8×8/稀疏拓扑，广度更强；组合兼容性解释和资源化测试仍可深化 | 内容资源、UI route、turn/action queue 已足够；组合规则和平衡归项目 | **P1 深化**：做模式×尺寸×主题兼容矩阵，不在控制器继续堆分支 |
| [2048-in-react](./projects/repo_mateuszsokola_2048_react.md) | 稳定 tile ID 暴露表现身份的重要性；重复 reducer、timer 和事件边界反向证明方向不变量与快速输入测试的必要性 | 当前已有命名视觉队列和输入策略，但未见稳定身份、buffer/block/retarget 与 reduced-motion 的联合回归矩阵 | `GFInputMappingUtility`、`GFPointerGestureUtility`、`GFActionQueueSystem` 提供机制；项目定义手势死区和拥塞策略 | **P0 测试证据**：借稳定身份与不变量，不借重复方向逻辑、深拷贝或表现 timer 驱动领域 |
| [2048.cpp](./projects/repo_plibither8_2048_cpp.md) | 移动数、最佳局面、救援和文本模式提供不依赖颜色的状态表达 | 当前统计、历史和 UI 更完整；仍缺救援资格语义和单色/非色彩冗余的端到端验收 | SaveGraph、信号和 turn flow 可复用；救援规则、资格与文案归项目 | **P1/P2 产品点**：统计与冗余编码可借；直接终端 IO、全局状态和非确定随机不可借 |
| [nneonneo/2048-ai](./projects/repo_nneonneo_2048_ai.md) | bitboard、查表、缓存与 snapshot 模拟证明提示可作为只读、有预算的分析消费者 | 当前有确定性状态与诊断底座，但没有 project-owned、可取消、有 deadline 的提示服务 | `GFExecutionBudget`、GF clock/seed/diagnostics 管生命周期与预算；评估模型和解释归项目 | **P1 实验**：先做通用模拟器的只读提示；固定 4×4 原生快路径只能作为可选优化 |
| [ovolve/2048-AI](./projects/repo_ovolve_2048_ai.md) | hint、autoplay 和玩家操作共用移动入口；空格、单调性等指标可解释，但迭代加深也暴露超时/过期结果风险 | 当前同一命令/回放底座可承载，缺解释型提示、snapshot 新鲜度和取消验收 | 输入、turn flow、异步终态、UI route 复用 GF；模型、文案和自动演示策略归项目 | **P1/P2 分层**：先提示后自动演示；禁止 AI 直接改 Board 或消费业务 RNG |
| [statico Godot roguelike example](./projects/repo_statico_godot_roguelike.md) | `ActionResult = state_changes + effects + messages + time_cost` 与内容浏览器展示了动作语义和作者工具方向 | 当前 feature ownership、资产目录和 action queue 更强；统一无 Node 的结果 DTO 与可按来源/许可筛选的浏览器尚未证实 | turn/action queue、UI router、asset metadata/content package 可复用；规则效果和工具视图归项目 | **P0/P1 结构证据**：借 ActionResult 与工具思想，不借全局单例、表现 await 领域或全图扫描 |
| [BrogueCE](./projects/repo_brogue_ce.md) | gameplay/cosmetic 双 RNG、版本化 recording、逐回合 OOS 校验、固定 seed catalog、快进/headless 与 dirty-cell 刷新均有固定提交证据 | 当前已有 seed、命令历史、回放、诊断、预热与池化；仍缺 RNG 隔离审计、首 divergence 定位和 seed catalog CI | GF seed/clock/command history/SaveGraph/diagnostics 足够；canonical hash、规则版本和产品化 seed 归项目 | **P0 确定性基线**：思想强，AGPL 代码与 CC-BY-SA tiles 均不复制；dirty-cell 仅在 profiling 证明收益后采用 |
| [Pixel Dungeon](./projects/repo_watabou_pixel_dungeon.md) | 粒子、震动、漂字、区域音效和状态文案组成语义 feedback recipe；横竖屏重排、快捷栏与表现对象 recycle 形成移动端基线 | 当前 Shader/主题技术与真实响应式重排已经更完整；仍需补 feedback recipe 覆盖、声音层次、跨输入布局验收和池耗尽降级 | `GFAudioUtility`、action queue、对象池、主题/设置机制可复用；事件语义、混音、布局验收和预算归项目 | **P0 表现基线**：先补语义组合与降级，不把“更多 Shader”当作质量代理 |
| [Shattered Pixel Dungeon](./projects/repo_shattered_pixel_dungeon.md) | custom/daily seed、正交 challenges、三类布局、手柄虚拟指针、语义音频与对象生命周期把 seed 和跨端体验产品化 | 当前已有 custom seed、回放/书签、真实响应式重排与可变棋盘；缺 daily、完整资格模型、挑战组合和跨布局/手柄端到端证据 | Seed/Clock/SaveGraph/content/turn/input/UI 机制已有；挑战日历、资格、布局验收与服务端权威归项目 | **P1 产品主线**：daily 与挑战最值得借；GPL 代码和素材只作行为证据 |

## 商业/作者公开样本（10 项）

这组不推断源码实现。表现与交互判断同时链接[实机视频观察台账](./videos.md)；功能声明以各报告中的作者、发行商或官方设计资料为准。未公开代码、Shader、音频和素材一律按不可复用处理。

| 深度样本 | 最强一手证据与可借鉴模式 | 相对当前项目 | GF 与项目边界 | 综合判断 |
| --- | --- | --- | --- | --- |
| [Twinfold](./projects/game_twinfold.md) | 让可合并对象、敌人、空洞与技能共享微型网格；常驻成长阈值和 Undo 把每次滑动同时变成经济、路径与战斗决定 | 当前有更强的规则/历史底座，但没有敌人、局内技能 build 或代价选择；Haptic 已有机制、设置里却没有关闭项 | turn flow、确定性 seed、action queue、command history、Haptic 可复用；敌人、技能、平衡归项目 | **P1 垂直切片**：先做单敌人/单技能并验证撤销与回放，不复制角色、图形或声音 |
| [Six Match](./projects/game_six_match.md) | 同一三消内核承载 survival 与有限步 puzzle；提示有预算，帮助资源耗尽后转化为炸弹，且 puzzle 支持 undo/redo | 当前模式多但缺关卡目标和限步层；已有结束判定、command history 与 custom board 可直接复用 | BoardTopology/turn flow/history 提供机制；目标、搜索提示和奖励归项目 | **P1 低风险内容**：用小型关卡包验证目标层，不再建历史系统 |
| [Pawnbarian](./projects/game_pawnbarian.md) | 卡牌改变网格移动语法，行动前铺出红色威胁格；两步回合预算让风险与行动经济一眼可见 | 当前反馈更偏“动作完成后”，缺敌方意图/受影响格预览和局内动作选择 | turn flow、Recipe/Capability、拓扑查询、Shader 参数工具可复用；牌、敌人和 overlay 语义归项目 | **P0 可读性 / P1 玩法**：先把后果预览做成无副作用查询，再试验卡牌规则 |
| [Dicey Dungeons](./projects/game_dicey_dungeons.md) | 角色与 episode 有控制地重写核心规则；敌方意图、tooltip、渐进教程和动画/资源档位降低学习与设备门槛 | 当前 6 模式横向广但缺纵向目标、构筑与完整 onboarding；表现强度/预热已有，缺正式档位矩阵 | 模式资源、turn flow、UI router/focus/text fitter、asset load/action queue 可复用；episode 内容归项目 | **P0 教学 / P1 内容**：以少量策划关卡解释模式，不引入不可信运行时脚本 |
| [Luck be a Landlord](./projects/game_luck_be_a_landlord.md) | 单一 spin 通过符号池、物品和连锁形成 build；周期房租制造短期目标；官方声明屏幕阅读器剪贴板输出、色盲和可配置控制 | 当前规则多但局内选择少；焦点/文本/设置机制已有，完整屏幕阅读语义与色觉产品模式缺失 | seed/turn/action queue、SaveGraph、输入/文本机制可复用；符号经济、目标节奏、可访问性语义归项目 | **P0 可访问性 / P1 build**：先做 canonical 状态摘要和小型选择层，不复制符号、文字或音效 |
| [Into the Breach](./projects/game_into_the_breach.md) | 官方 GDC 复盘强调低数值、少菜单、单屏可读；所有敌方攻击、作用格与目标先公开，玩家回合无 hit/miss 随机 | 当前确定性、撤销和回放很适合预测，但没有敌人/障碍模式、bonus objective 或常驻回合目标 | turn flow/history/seed/action queue 可复用；意图生成、任务和 overlay 数据归 gameplay/UI | **P0 设计原则**：任何新战术层先证明后果可完全预览、原因可解释，再增加复杂度 |
| [Shotgun King](./projects/game_shotgun_king.md) | 行动前显示射程/散布/命中区；CRT 视觉提供 shaderless fallback；官方列出可访问性、翻译和自定义翻译 | 当前 Shader/预热与中英基础更强，但缺正式低档、高对比/减少动态与翻译包许可边界；局内双方卡牌选择缺失 | Shader/Render Warmup、input、SaveGraph/content package 可复用；设置、卡牌、翻译审核归项目 | **P0 降级 / P1 build**：质量门槛是关掉 Shader 后仍可读，不引入未审核模组脚本 |
| [Shogun Showdown](./projects/game_shogun_showdown.md) | 单轴站位、朝向和“先编排攻击牌、后按顺序执行”把时机变成核心；舞台式局部光效保持焦点 | 当前稀疏拓扑/action queue 是技术基础，但 action queue 不是玩家卡牌系统；缺朝向、敌方节奏和局内解锁 | turn flow/action queue/SaveGraph/Shader Utility 可复用；队列内容、合法性、平衡和意图 UI 归项目 | **P1 原型**：只做可回放的两槽计划队列，避免把业务卡牌上移 GF |
| [Backpack Hero](./projects/game_backpack_hero.md) | 位置、邻接和朝向本身就是 build；背包构筑与敌方意图同屏；官方页声明拖放/旋转、互动教程和字幕 | 当前可变/自定义棋盘可承载空间配方，但缺局内物品选择、敌方意图和完整 tutorial/subtitle 验收 | board editor、input、UI/text、SaveGraph 可复用；物品索引、邻接配方、教程和城镇进度归项目 | **P1 空间实验**：先用 3–5 个独立原创配方验证邻接，不复制物品、图标或文字 |
| [Cobalt Core](./projects/game_cobalt_core.md) | 单轴横移同时承担规避和对准；三船员混合牌组、分叉升级、daily challenge 与可调难度形成 run 身份；横移母题贯穿 UI/战斗转场 | 当前方向滑动与 custom seed 很强，但没有 daily、局内 build 或分叉升级；音频机制强而 BGM/ambient 内容浅 | turn/seed/SaveGraph/action queue/audio state/switch/crossfade 可复用；卡组、升级、daily 资格和音乐语义归项目 | **P1 产品参考**：先做 daily + 单次升级选择，避免先建通用卡牌框架 |

## 追加轮次 A：合并、摆放与空间构筑（4 项）

本组的画面判断同时链接 [R2-A 官方视频台账](./videos_round_02.md)，产品与设计动机以各报告中的开发者/发行商页面为准。

| 深度样本 | 最强一手证据与可借鉴模式 | 相对当前项目 | GF 与项目边界 | 综合判断 |
| --- | --- | --- | --- | --- |
| [Dorfromantik](./projects/game_r2_dorfromantik.md) | 有限六角地块、边缘相容、任务和分数把“下一块放哪里”变成公开的空间预算；Quick/Hard/Custom 说明同一核心可用资源量与压力调档 | 当前确定性、历史和可变拓扑更强，但没有放置型回合、有限生成队列或边缘相容/得分预演 | 有限队列、边缘语义、任务和计分归项目；先在现有正交 `BoardTopology` 做原创切片，不能暗引未声明的 `gf.standard.spatial` | **P1 规则实验**：借有限资源、公开下一项和落点预演，不复制六角内容、美术或任务 |
| [Stacklands](./projects/game_r2_stacklands.md) | 拖放、堆叠与配方把内容组织、生产和 build 压缩到同一桌面，单次拖动同时表达选择与组合 | 当前 Recipe/Capability、SaveGraph 和确定性基础更强，但没有局内拖放堆叠或生产经济；不值得先建通用卡牌框架 | `GFDragDropUtility` 只拥有拖拽会话、落点和命中结果；堆叠合法性、配方、计时、经济、历史和 UI 均归项目 | **P1/P2 空间构筑证据**：补强最小 build 与空间配方，不复制卡牌、配方和经济 |
| [Wilmot Works It Out](./projects/game_r2_wilmot_works_it_out.md) | 60+ 拼图、7 个房间、20+ 装饰与 Marathon 形成“解题—陈列”进度；开发反思主动删除不服务核心的升级和角色机制 | 当前自定义棋盘、历史和图鉴完整，但没有策划关卡课程、顺序目录或以空间陈列表达完成度 | `GFLevelCatalog` 可评估用于 pack、排序和前后关卡；谜题状态、解锁、完成条件、陈列和进度归项目并进入 SaveGraph | **P1 内容深化**：优先验证原创关卡包和清晰课程，不额外叠加升级系统 |
| [Freshly Frosted](./projects/game_r2_freshly_frosted.md) | 144 个手工谜题逐步引入分流、推送、合并、复制、随机和传送；正向语音引导与柔和视听共同降低压力 | 当前模式广度和表现机制更强，但没有手工课程、设备链顺序验收或语音—字幕共享的教学语义 | Turn Flow/Action Queue 只编排确定性步骤，`GFLevelCatalog` 只组织目录；设备逻辑、课程和旁白内容归项目 | **P0 教学 / P1 关卡**：借渐进课程、因果时序和多通道引导，不复制设备、声音或视觉 |

## 追加轮次 B：小网格战术、紧凑肉鸽与克制表现（4 项）

本组的画面判断同时链接 [R3-B 官方视频台账](./videos_round_03.md)；同一创作者谱系只用于比较设计演化，不当作独立来源多样性。

| 深度样本 | 最强一手证据与可借鉴模式 | 相对当前项目 | GF 与项目边界 | 综合判断 |
| --- | --- | --- | --- | --- |
| [GUNCHO](./projects/game_r3_guncho.md) | 弹巢格与战场方向一一对应；开发者曾让相机旋转连带改变弹巢理解，随后收敛为明确左右旋转，证明玩法参照系必须稳定 | 项目已有模型坐标、独立 HUD 和视口变换；真正缺的是方向、预览与 UI 指示跨相机/布局的联合回归，不是新坐标系统 | 玩法方向、资源语义和相机映射归项目；复用输入、Viewport 与 Turn Flow。未声明的 `GFGridTransform2D` 不能静默成为依赖 | **P0 回归证据 / P1 战术**：补强参照系不变量和单敌人切片，不新增平行空间层 |
| [Card Crawl Adventure](./projects/game_r3_card_crawl_adventure.md) | 路径式卡牌选择、短局 roguelite 和 weekly competition 把“草拟路径—查看后果—确认”与轮换挑战结合 | 当前每回合是一条已提交移动命令；已有历史/回放但没有多格草稿事务，daily/资格也仍是缺口 | 路径合法性、投影增量和原子提交归项目；拖动会话可复用 `GFDragDropUtility`。`gf.standard.spatial` 未声明，先用 `BoardTopology` 邻接纯查询 | **P0 预演 / P1 挑战补证**：补强后果预览、daily/weekly 与资格，不另立“路径系统”建议 |
| [Dungeons of Dreadrock](./projects/game_r3_dungeons_of_dreadrock.md) | 100 个手工关卡、短时段和俯视单屏把复杂度放进关卡顺序，而非常驻 HUD 或系统堆叠 | 当前拓扑、历史和编辑基础适合谜题，但没有正式课程、关卡选择或已掌握进度 | `GFLevelCatalog` 只负责 pack、排序和 next/previous；目标、死局、教学、解锁和完成记录归项目 | **P0 上手 / P1 内容**：直接补强有限步关卡包与渐进教程，不复制机关或关卡 |
| [Tinyfolks](./projects/game_r3_tinyfolks.md) | 职业、武器、遗物、城镇建筑、生物群系和怪物用稳定小型界面形成短局 build；Google Play 的开发者声明不收集或共享数据 | 当前缺局内选择和短局目标，但已有 Recipe、内容目录和统一 Profile；本地诊断尚缺公开隐私契约 | GF domain 组件不能替代项目职业、经济、城镇和平衡；SaveGraph 只承载严格 section，诊断默认本地、可关闭/清除 | **P1 build / P2 隐私补证**：先做 3 个原创选择，不建通用 RPG 系统，不用极简画风代替性能数据 |

## 跨样本结论

| 决策主题 | 多源证据 | 当前项目判断 | 下一层验证 |
| --- | --- | --- | --- |
| 动作与表现边界 | 原版 2048、statico、Pixel Dungeon、Freshly Frosted | action queue 与 typed `TurnResult` 已落地；后续只扩展同一结果模型并声明链式语义次序，不新建平行 DTO，也不让表现反推模拟 | 同一命令在正常、无表现、快进三种消费者下 canonical state 一致；链式预览与结算次序一致 |
| 随机与回放 | BrogueCE、两套 2048 AI、Shattered Pixel Dungeon、Dorfromantik | gameplay branch、规则指纹、逐回合 checkpoint 和首个 OOS 已落地；缺完整多平台 seed catalog、cosmetic 多配置等价矩阵与公开有限资源 queue | 改 cosmetic seed/关闭表现不改 canonical hash；queue/cursor 可撤销、回放；CI 报告首个分歧命令 |
| 变体与内容 | danqing、Shattered Pixel Dungeon、Dreadrock、Tinyfolks | 模式和拓扑已资源化；局内选择、挑战组合、手工课程、关卡目标与兼容性说明不足 | 新增 modifier 不改移动控制器；首包关卡有稳定目录/掌握状态；冲突组合开局前可解释地阻止 |
| 反馈品质 | 原版 2048、Pixel Dungeon 系列、GUNCHO、Freshly Frosted | Shader/队列机制强，语义层级、音频层次、旁白等价通道、减少动态和低端降级不足 | 移动、合并、里程碑、危险、无效、失败在各设置下可区分；短反馈后回到静态可判断局面 |
| 多端 UX | 原版 2048、2048-in-react、Stacklands、Tinyfolks | 输入抽象、三种快速输入策略、焦点和真实布局重排均已存在；缺 burst、safe area、拖放替代、触控尺寸与完整控制器路径的统一端到端矩阵 | 窄屏/横屏/键鼠/触屏/手柄完成同一任务；拖放有取消/焦点等价；主操作无需滚动或隐含手势 |
| 提示与自动化 | nneonneo、ovolve、Dorfromantik、Card Crawl Adventure | 状态与命令底座可复用；分析服务、解释、deadline/cancel、新鲜度和多格草稿投影是项目缺口 | 提示/路径草稿只读、取消零副作用、超时有界、旧 snapshot 丢弃；自动演示仍走标准命令入口 |
| 性能 | BrogueCE、Pixel Dungeon 系列、statico、Tinyfolks | 预热、对象池和预算已声明；缺按平台/规模/表现档位的实测矩阵，像素/极简风不能替代数据 | 记录 P50/P95 首反馈、帧时与内存；池耗尽/Shaderless/无表现路径安全退化 |

## GF 总结

- **已有且应优先复用**：turn flow、命名 action queue、确定性 seed/clock、command history、SaveGraph、Shader 参数校验、渲染预热、对象池、语义音频、输入映射、手势、异步预算与 diagnostics。
- **项目级缺口**：快速输入与参照系回归、教程/手工课程、有限资源队列、daily/资格、挑战内容、提示模型、屏幕阅读语义、响应式端到端验收，以及跨平台性能实测矩阵。`TurnResult`、逐回合 OOS、基础 seed corpus、反馈 recipe、减少动态和 VFX 档位已落地。
- **GF 反馈候选仅限发现性**：若能力目录搜不到 object pool、Shader、command history、execution budget、virtual list、haptic 或 grid path preview，应补关键词/`primary_classes` 与包选择信息，不能据此重造运行时 API。`gf.standard.spatial` 当前未声明；accessibility 先在项目组合并验证稳定契约。
- **明确不采用**：第三方全局状态、直接平台 SDK、裸文件存档、非确定随机、表现层反写规则、因单个游戏内容而向 GF 添加业务模型，以及任何许可证不兼容或来源不明的代码/素材。
