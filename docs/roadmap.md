# 2048 All In One 持续推进路线图

本文档面向维护者和后续 AI，用来把项目从“可玩的 gf 示例”持续推进成“高完成度、稳定、能展示 GF Framework 9.x 能力的独立小游戏样板”。

## 当前事实

- Godot 版本目标：`project.godot` 声明 `config/features=PackedStringArray("4.7", "Forward Plus")`。
- GF Framework 精确版本：运行时只读取 `addons/gf/plugin.cfg`；路线图不复制补丁版本。
- GF AutoLoad：`project.godot` 中 `Gf="*uid://dftf1eh06apl0"`，与 `addons/gf/kernel/core/gf.gd.uid` 匹配。
- GF 扩展启用集合以 `project.godot` 的 `gf/extensions/enabled` 为准，路线图不维护副本。
- GF 源码状态：当前仓库为 `.gf/vendor.lock.json` 精确锁定的 vendored GF 9 源码状态；`.gf/packages.lock.json` 可能暂时不存在，不再把旧 GF 5.1 lockfile 状态当作当前事实。
- GF 包管理器：GF 9 使用 Godot 原生 CLI，入口为 `res://addons/gf/kernel/package/gf_package_cli.gd`。恢复包管理器安装流时，应重新生成 `.gf/packages.lock.json` 并再启用 installed 包数量强校验。
- GF 下载缓存、运行日志、本地用户数据和导出产物已由 `.gitignore` 忽略，不应提交。
- 文档入口与权威层级见 `docs/readme.md`；本路线图不复制 Feature 清单、包清单或最近验证数字。
- 测试脚本数、用例数、断言数、LSP 文件数和运行时类数是易变生成状态，以 `tools/run_gut_safe.ps1`、`build/gdscript_lsp_diagnostics.json` 和 `.gf/godot_exit_leak_baseline.json` 的实际输出为准。
- 安全测试入口 `tools/run_gut_safe.ps1` 提供临时用户目录、临时日志、默认用户日志增长监控、超时和日志大小上限；不要直接运行裸 Godot/GUT。
- 项目脚本可以按当前代码规范显式路径继承 GF 基类；具体引用数量不是架构契约，不在路线图中维护。
- 当前脚本已清理掉 `get_model/get_system/get_utility(...) as ...`、显式 class cast、隐式变量类型和缺失返回类型等高频旧写法；维护测试已禁止用 GUT `assert_eq` 对比空数组来判断问题列表，并约束业务脚本中的 `GFBindableProperty.get_value()`、`Dictionary.get()` 自定义对象结果、资源加载/复制结果、`StyleBoxFlat` 专属 API 调用、typed `@onready` / 运行时节点查找收窄、已知高风险返回值调用和项目协程调用。剩余稳定性重点转向更细的 `unsafe_method_access` / `unsafe_property_access`。

## 权威事实来源

- 所需与可选 GF 包以 `.gf/project_contract.json` 为准。
- 实际启用扩展以 `project.godot` 为准。
- 精确 GF 版本以 `addons/gf/plugin.cfg` 为准，vendor 完整性以 `.gf/vendor.lock.json` 为准。
- 包管理器安装状态只在 `.gf/packages.lock.json` 存在时由原生 CLI 校验。
- 项目结构与 Feature 所有权分别以 `gf_project_profile.json` 和 `docs/architecture.md` 为准。

路线图只记录尚未完成的产品与工程目标；AI 工作方式由 `docs/ai_maintenance.md` 约束，不在这里复制提示词。

## 安全验证命令

先运行不启动 Godot 的文本检查：

```powershell
git diff --check -- .gitignore .gf project.godot export_presets.cfg gf_project_profile.json addons/gf app features shared tests README.md docs tools
```

GF 包状态命令会启动 headless Godot，应与纯文本检查分开执行：

```powershell
godot --headless --path . --script res://addons/gf/kernel/package/gf_package_cli.gd -- status --json
```

检查 `status --json` 输出时，优先确认：`ok=true`、`issue_count=0`、`orphan_packages=[]`、`lockfile_verify.ok=true`。如果 `.gf/packages.lock.json` 不存在，`installed_count` 可能为 `0`，这只说明当前 GF 源码是手动 vendored 状态，不代表项目无法运行。不要继续使用旧 Python 包管理命令。

只有通过 `tools/run_gut_safe.ps1` 这样的隔离脚本，才运行 GUT。不要直接使用默认用户目录或裸 Godot/GUT 命令。

## 第一阶段：工程稳定性

目标：让项目在 GF 9.x、Godot 4.7 和严格 GDScript warning 设置下保持可维护。

1. 维护“安全运行 Godot/GUT”的本地脚本。
   - 问题：默认 Godot 用户目录曾生成巨大日志文件。
   - 当前状态：`tools/run_gut_safe.ps1` 已提供临时 user data/log 路径、超时、日志大小上限和默认日志增长上限；最近一次结果必须读取命令输出，不在路线图复制测试数量。
   - 结果目标：后续默认通过该脚本运行 GUT，且默认用户目录不产生大日志。
   - 验证：切换 Godot 可执行文件或升级版本后，用低上限参数重新运行烟雾测试。

2. 清理 Godot 4.7 静态警告。
   - 重点：`unsafe_call_argument`、`unsafe_cast`、`unsafe_method_access`、`unsafe_property_access`、`return_value_discarded`、`missing_await`、隐式类型。
   - 做法：按文件逐个处理，不用大范围机械改写。
   - 验证：Godot 编辑器警告数量下降；若不能启动 Godot，则记录待验证项。

GF 包与 vendor 治理已经成为维护契约，不再列作待决 Roadmap：项目保留 `.gf/vendor.lock.json` 锁定的只读 vendor，通用修改经上游发布后回流；若未来恢复 Package Manager 安装流，再生成 `.gf/packages.lock.json` 并启用对应强校验。

## 第二阶段：GF 利用率提升

目标：减少项目自造基础设施，优先展示已安装 GF 包的深模块能力。

1. 输入 Module 深化。
   - 涉及：`PlayerInputSystem`、`ReplayInputSystem`、`resources/input/*.tres`、`GFInputMappingUtility`。
   - 问题：玩家输入、回放输入、一次性输入清理语义容易分散。
   - 方向：让输入语义集中在 GF 输入资源和少量项目 Adapter 中，减少系统之间对输入时序的隐性约定。
   - 验证：`test_gameplay_input_mapping.gd` 覆盖键盘缓冲、消费和清理语义。

2. 对局 Session Module 深化。
   - 涉及：`GameInitSystem`、`GamePlayController`、`GFLevelUtility`、`GFCommandHistoryUtility`。
   - 问题：新游戏、回放、撤销、动作队列清理存在跨模块生命周期约束。
   - 方向：把“2048 当前对局”的接口整理成稳定 Module，内部继续使用 GFLevelUtility，不把关卡进度语义泄漏到调用方。
   - 验证：session 元数据、命令历史清理、动作队列清理都有聚焦测试。

3. 资源目录 Module 深化。
   - 涉及：`ProjectResourceCatalogUtility`、`GameModeCatalogUtility`、`TileCatalogUtility`、`AchievementCatalogUtility`、`GameUiRouterUtility`、`GFResourceRegistry`、`GFResourceResolverUtility`、`GFAssetUtility`。
   - 问题：模式目录和 UI 路由目录相似，容易重复注册、缓存、校验和错误输出。
   - 当前状态：项目级资源目录 Adapter 已提炼；模式、方块定义、成就定义和 UI 路由保留各自业务入口，但共享注册、解析、缓存和 asset group 逻辑。
   - 验证：模式、方块定义、成就定义和 UI 路由注册表测试继续通过，并能捕获缺失路径与重复稳定 ID。

4. 存档 Module 深化。
   - 涉及：`GameSaveGraphUtility`、`GameSaveSectionData`、`ProgressStatsSystem`、`BookmarkSystem`、`CustomBoardSystem`、`AchievementSystem`、`ReplaySystem`、`GFSaveGraphUtility`、`GFSaveScope`、`GFSaveDataSource`、`GFStorageUtility`。
   - 问题：最高分、设置、书签、玩家棋盘、回放分属不同入口，持久化语义需要更统一。
   - 当前状态：统计、书签、玩家棋盘、方块/棋盘发现进度、成就和回放已迁移为六个 Feature-owned section，由项目级 SaveGraph 原子保存；设置保持独立生命周期。旧 SaveSlot Adapter 和时间戳 Resource 集合已删除。
   - 存储契约：Binary Variant 类型保真、GF storage metadata、checksum、严格 Profile/section schema、UUID v7 稳定身份，不提供旧格式运行时双读。
   - 验证：跨架构重载、单文件约束、后期 section 失败全图回滚、schema 拒绝和保存失败内存回滚均有聚焦测试。

5. Installer ownership 固化。
   - 涉及：`GameArchitectureInstaller`、`gf.domain`、`gf.action_queue`。
   - 当前状态：项目 Installer 不再手动绑定 `GFLevelUtility`、`GFQuestUtility`、`GFActionQueueSystem`；这些 Module 由对应 GF 扩展 Installer 装配。
   - 验证：`test_architecture_installer_validation.gd` 静态检查项目 Installer 不重复绑定扩展 owned Module。

## 第三阶段：游戏完成度

目标：从功能样例变成完整小游戏。

1. 自定义与超大棋盘基础。
   - 当前状态：`BoardTopology` 已取代固定二维数组，矩形、十字和带空洞自定义棋盘共用稀疏状态、连续 lane、生成、判负、预览、撤销、书签、回放和统计键；玩家编辑器已支持绘制、擦除、预设、规范化、连通提示、GF 局部撤销历史和 SaveGraph 模板目录，并通过独立 GF 输入上下文消费撤销/重做快捷键。编辑画布现使用稳定世界尺寸、共享视口变换算法、GF 指针手势与坐标换算，支持桌面缩放平移、单指连续绘制、双指缩放平移以及桌面/紧凑横屏/安全区竖屏布局。棋盘表现已拆为独立世界画布与全屏 HUD 覆盖层，支持完整聚焦、鼠标/触控板/双指以及键盘/手柄缩放平移、单指或屏幕方向键抽象动作移动、可见区域查询、GF 对象池窗口化和低缩放细节裁剪。分数、提示和动作分布在屏幕边缘；开发实验台已迁移到 diagnostics feature 拥有的独立 Window。
   - 当前进展：稳定拓扑键、规范化方块组合身份、严格发现 section 和响应式图鉴 Route 已完成；目录条目按视觉家族归档并复用正式方块表现。成就已通过资源目录、类型化领域事件、GF Quest 运行时投影和独立 SaveGraph section 接入，并能从历史统计与发现高水位回填。
   - 当前进展：`ProgressStatsSystem` 已只从严格 `GameResultRecordedData` 建立有界本地排行榜，并按模式、稳定拓扑键和规则集身份隔离分组；调试、回放续玩、书签恢复、撤销/重做、自定义棋盘和手动 seed 会以不可变 reason code 失格。该榜只是离线参考，不是线上权威证明。
   - 下一步：通过显式 bridge contract 接入 Steam 与微信 Adapter，由平台或服务端重新校验并裁决线上结果。
   - 契约：见 `features/gameplay/docs/board_topology.md`，不得重新引入 `grid_size` 作为逻辑唯一真源。

2. 核心流程完整化。
   - 新游戏、继续、撤销、重做、胜利、失败、重开、返回主菜单。
   - 当前状态：撤销和重做已通过 `GFCommandHistoryUtility` 接入玩家输入、流程事件和不可用反馈；重做使用 redo 栈，不在项目层维护第二套历史。无效移动会给出短暂 HUD 提示但不污染命令历史。目标达成弹层会展示当前目标、分数、步数和最大方块，继续挑战不结束对局。
   - 加入更细的无法移动、胜利继续游玩等反馈。

3. 多模式体验完整化。
   - 每个模式显示规则摘要、推荐棋盘大小、最佳成绩、最近成绩。
   - 模式配置校验错误需要面向维护者清晰输出。

4. 统计和成就感。
   - 按模式记录最高分、最大方块、最佳步数、游戏次数。
   - GF `progress` SaveGraph section 严格保存 `stats`、有界规范结果和资格过滤后的本地排行榜；普通倍增类模式已定义 2048 目标，目标上下文已写入 `GameStatusModel`、完整状态快照和书签，首次达成目标时会给出 HUD 提示和非强制弹层，结算统计以“本局曾达成目标”为准，模式选择页和游戏结束菜单已展示游玩次数、最佳步数、最大方块、平均表现、目标达成情况、最近一局摘要和当前配置的本地榜。
   - `AchievementCatalogUtility` 通过 GF Resource Registry 管理定义，`AchievementSystem` 从规范统计/发现 section 计算幂等高水位，先保存 `achievements` section 再投影到 `GFQuestUtility`；主菜单已提供响应式成就 Route。平台同步尚未接入，不能把 Steam 或微信状态当成本地真源。

5. 设置体验。
   - 语言、音量、视觉主题、音效主题、动画强度、视觉效果强度、棋盘辅助显示。
   - 设置页应继续通过 GF 设置 Utility 与 UI 绑定，不直接散落到各菜单；OptionButton 条目写入应复用 `GFItemListBinder`，书签/回放列表刷新应复用 `GFRepeaterBinder`。
   - 当前已接入 `appearance/theme_id` 和 `audio/sound_theme_id`；`ProjectContentCatalogUtility` 统一构建 GF 内容目录，`GameThemeCatalogUtility` 从 manifest 生成轻量描述符，`GameThemeUtility` 通过 `GFAssetLoadSession` 完整预加载、提交独立资源组并事务激活。视觉与音效主题是可自由组合的独立设置轴。

## 第四阶段：视觉与交互打磨

目标：统一为柔和、独立游戏质感的扁平肌理风，避免刺眼、粗糙和马赛克噪点。

1. 建立视觉规范和主题系统文档。
   - 记录色板、字体、噪点强度、背景层级、方块色阶、按钮状态、动效原则。
   - 当前状态：`docs/visual_style.md` 已建立；主题包以独立资源键和 manifest 描述符发布，目录校验与资源级 `GFValidationReport` 阻止无效主题进入运行时，声音银行由 GF 挂载令牌管理。

2. 棋盘与方块。
   - 保持方块颜色来自配置资源，不在表现层硬编码覆盖用户预期。
   - 统一生成、移动、合并、转化动效，现有 Tween 通过 `BoardTweenBatchAction` 进入 `GameBoardAnimationUtility` 管理的 GF 命名队列，并提供缓冲、动画期间阻断、实时重定向三种设置，再由 `GameBoardFeedbackUtility` 和 `GFShakeUtility` 协调附加反馈。
   - 方块基础纹理由 `TileDefinition.visual_family_id` 固定身份家族，Recipe 能力只增加边缘小标记；禁止按数值轮换身份纹理或叠加多张全幅图案。

3. 菜单和弹层。
   - 检查模式选择、主菜单、设置、暂停、游戏结束、回放列表在 1280x720、1920x1080、窄屏下不重叠。
   - 所有按钮和列表项需要稳定焦点状态。

4. 测试面板隔离。
   - 测试工具只能在编辑器/调试态出现。
   - 正式体验中不要暴露测试控件，也不要让测试工具污染回放。
   - 当前状态：完成。玩法场景不再实例化 diagnostics 资源或预留右栏；`GameplayBoardReadyData` 建立单向上下文事件，`TestToolUtility` 通过 GF 输入、控制台和信号能力管理独立 `GameplayDiagnosticsWindow`。

## 第五阶段：文档和示例价值

目标：让这个仓库能被其他项目当成 GF 9.x 示例阅读。

1. 更新 `README.md`。
   - 写明 GF 9.x、包管理器、vendored 源码状态、启用扩展。
   - 修正“直接继承 GFController”的表述，因为当前项目脚本使用显式路径继承。

2. 更新 `docs/ai_maintenance.md`。
   - 加入 GF package manager 工作流。
   - 保持 `addons/gf` 只读；上游问题先进入 GitHub issue，并以 issue 作为唯一协作与验收记录。经授权的实现只在独立 `gf-pr` 工作区的非 `main` 分支完成并通过 GF 测试；发布后记录精确 source commit、发布版本和本项目 vendor 采用结果。

3. 新增架构文档。
   - 建议：`docs/architecture.md`。
   - 重点讲 Model/System/Utility/Controller/UI 的职责、事件流、资源目录、持久化策略。

4. 维护验证文档。
   - 文件：`docs/validation.md`。
   - 记录安全运行 Godot/GUT 的脚本、包锁验证、静态检查命令和当前验证缺口。

## 深化机会清单

1. `GameArchitectureInstaller` 已按运行时基础、内容与玩法、表现、输入平台、状态导航、进度和玩法系统完成内部装配分组。
   - 约束：外部仍只暴露 `install_bindings()`，各组保持严格依赖注册顺序，dev 工具仍由显式构建 feature 最后安装。
   - 后续只有在某组能够独立删除、测试和复用时才提取 Feature Installer，禁止为缩短文件而增加浅层接口。

2. `GameUiMotionUtility` 和视觉测试已经成形，视觉规范已文档化。
   - 问题：资源和场景还没有完全围绕 `docs/visual_style.md` 收敛。
   - 方向：继续让主题内容包描述符、背景 shader、tile scheme、菜单场景和视觉测试围绕文档收敛。
   - 收益：后续 AI 不会反复把风格改歪。

3. SaveGraph 运维体验可以继续加深。
   - 当前状态：统计、书签、玩家棋盘、发现进度、成就和回放已统一到 Feature-owned section，GF SaveGraph 负责图级事务，旧并行实现已删除。
   - 方向：在不放宽严格 schema 的前提下，为损坏存档增加面向玩家的隔离、导出诊断和显式重置流程。
   - 收益：让 checksum 或未来版本拒绝不只出现在日志中，同时保持运行时无隐式降级。

4. 包锁和物理源码目录存在策略差异。
   - 问题：当前是完整 GF 9 源码 vendored 状态，但 `.gf/packages.lock.json` 可能暂时不存在。
   - 方向：继续保留完整源码，或恢复 GF 9 原生包管理 lockfile 后按 installed 包收敛，二选一并在 README 中说明。
   - 收益：减少未来维护者对“哪些包真的在用”的误解。

## 下一轮建议

优先级最高的下一步：

1. 为现有本地成就与本地排行榜定义平台 bridge contract，并分别实现 Steam 与微信 Adapter。线上排行榜只接收可验证、比赛合格的规范结果；本地 SaveGraph 不承担服务端权威证明。
2. 按 `docs/visual_style.md` 审计背景 shader、tile scheme 和菜单场景，把散落颜色逐步收敛成资源化规则。
3. 持续完善 `asset_library`：新增素材必须登记稳定 `asset.*` key、授权元数据和审计报告，再接入主题或玩法。
