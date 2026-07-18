# 2048 All In One 持续推进路线图

本文档面向维护者和后续 AI，用来把项目从“可玩的 gf 示例”持续推进成“高完成度、稳定、能展示 GF Framework 8.x 能力的独立小游戏样板”。

## 当前事实

- Godot 版本目标：`project.godot` 声明 `config/features=PackedStringArray("4.7", "Forward Plus")`。
- GF Framework 版本：`addons/gf/plugin.cfg` 为 `8.1.0`。
- GF AutoLoad：`project.godot` 中 `Gf="*uid://dftf1eh06apl0"`，与 `addons/gf/kernel/core/gf.gd.uid` 匹配。
- GF 扩展启用：`gf.action_queue`、`gf.asset_metadata`、`gf.capability`、`gf.content_package`、`gf.domain`、`gf.feedback`、`gf.save`、`gf.turn_based`。
- GF 源码状态：当前仓库为 `.gf/vendor.lock.json` 精确锁定的 vendored GF 8 源码状态；`.gf/packages.lock.json` 可能暂时不存在，不再把旧 GF 5.1 lockfile 状态当作当前事实。
- GF 包管理器：GF 8 使用 Godot 原生 CLI，入口为 `res://addons/gf/kernel/package/gf_package_cli.gd`。恢复包管理器安装流时，应重新生成 `.gf/packages.lock.json` 并再启用 installed 包数量强校验。
- GF 下载缓存、运行日志、本地用户数据和导出产物已由 `.gitignore` 忽略，不应提交。
- 当前文档：已有 `README.md`、`docs/ai_maintenance.md`、`docs/coding_style.md`、`docs/architecture.md`、`docs/validation.md` 和本文档。
- 当前测试：`tests/gut/` 静态计数为 34 个 `test_*.gd` 文件，其中 30 个顶层测试脚本、4 个测试替身；共有 237 个 `test_` 用例。由于历史上 Godot/GUT 可能写出巨大用户目录日志，默认不直接运行裸 Godot 或 GUT。
- 安全测试入口：`tools/run_gut_safe.ps1` 已提供临时用户目录、临时日志、默认用户日志增长监控、超时和日志大小上限；2026-07-18 已用 Godot 4.7.1 在 GF 8.1.0 上完成完整隔离 GUT 验证，完整结果以 `docs/validation.md` 为准。
- 当前项目脚本中有 46 处显式继承 `res://addons/gf/...`，这是为了规避升级后 Godot class cache 对 `GF...` 类名解析不稳定的风险。
- 当前脚本已清理掉 `get_model/get_system/get_utility(...) as ...`、显式 class cast、隐式变量类型和缺失返回类型等高频旧写法；维护测试已禁止用 GUT `assert_eq` 对比空数组来判断问题列表，并约束业务脚本中的 `GFBindableProperty.get_value()`、`Dictionary.get()` 自定义对象结果、资源加载/复制结果、`StyleBoxFlat` 专属 API 调用、typed `@onready` / 运行时节点查找收窄、已知高风险返回值调用和项目协程调用。剩余稳定性重点转向更细的 `unsafe_method_access` / `unsafe_property_access`。

## 长期自动推进目标提示词

如果需要让 AI 长时间持续推进本项目，可以直接使用下面这段目标：

```text
请把当前仓库持续推进成一个高完成度、稳定、审美统一、能展示 GF Framework 8.x 能力的 Godot 4.7 2048 独立小游戏示例。你需要一轮接一轮地自主选择最高价值的小切片推进，不要只停留在分析。

总体原则：
1. 优先遵守项目文档：docs/ai_maintenance.md、docs/coding_style.md、docs/roadmap.md、docs/architecture.md、docs/validation.md、docs/visual_style.md、docs/save_model.md。
2. 优先利用当前 vendored GF 8 源码和已启用扩展能力，减少项目重复实现。新增或恢复包管理器安装流前先说明价值、检查 `.gf/packages.lock.json`、`project.godot`、`README.md` 和 `docs/roadmap.md` 是否需要同步。
3. 不直接运行裸 Godot/GUT；如需测试，只能使用 tools/run_gut_safe.ps1，并设置较短超时和日志上限，避免默认用户目录生成巨大日志。
4. 每个小切片都要保持可回滚、可验证、可解释。不要大范围机械改写，不要修改无关文件，不要提交临时分析文件。
5. 改 .gd 时同步考虑测试；改存档、回放、书签、设置时同步 docs/save_model.md；改 UI/视觉时同步 docs/visual_style.md；改 GF 包状态时同步包锁、README 和路线图。

持续推进优先级：
1. 工程稳定性：清理 Godot 4.7 静态警告、维护安全 GUT、固定 GF 8 源码/包状态、避免巨大日志和解析错误。
2. GF 利用率：输入、命令历史、状态机、UI 路由、动作队列、存储、设置、资源注册和未来 save/content/debug 包的合理接入。
3. 游戏完成度：新游戏、继续、撤销/重做、胜利/失败、书签、回放、统计、设置、模式说明、错误反馈、正式/调试面板隔离。
4. 视觉与交互：严格围绕 CMYK 半调纸媒游戏风格，修正背景、方块、菜单、弹层、响应式布局、焦点状态、动效节奏和可读性；主题和音效主题必须资源化并能在设置页一键切换。
5. 文档与示例价值：让 README、维护文档、架构文档、验证文档和测试共同解释这个项目如何作为 GF 示例。

执行方式：
- 先快速读取当前 git status 和相关文档，确认最近改动和风险。
- 选择一个最小可完成的小切片，给出简短计划后直接实现。
- 修改前先说明将改哪些文件；修改后运行不启动 Godot的静态检查和 GF package status。需要 GUT 时使用安全脚本。
- 如果一个方向完成，就继续挑下一个最高价值方向，不要等待用户继续下令。
- 最终只在目标真实完成或连续多轮遇到同一个外部阻塞时才停止；否则持续推进。
```

## 已安装 GF 包

根包：

- `gf.extension.action_queue`
- `gf.extension.content_package`
- `gf.extension.domain`
- `gf.standard.deterministic`
- `gf.standard.input`
- `gf.standard.state_machine`
- `gf.standard.ui`

依赖包：

- `gf.kernel`
- `gf.standard.base`
- `gf.standard.assets`
- `gf.standard.audio`
- `gf.standard.config`
- `gf.standard.diagnostics`
- `gf.standard.state`
- `gf.standard.storage`

暂不作为核心示例深用：

- `gf.standard.debug`

原因：debug 包需要保持接入边界清晰，避免只是为了“装更多包”而增加维护面。`gf.save` 已通过 `GameSaveGraphUtility` 深入接入统计、书签和回放的统一事务图，边界以 `docs/save_model.md` 为准。

## 安全验证命令

这些命令不启动 Godot，适合每轮改动后优先运行：

```powershell
git diff --check -- .gitignore .gf/packages.lock.json project.godot addons/gf scripts resources scenes tests README.md docs/ai_maintenance.md docs/coding_style.md docs tools
```

```powershell
godot --headless --path . --script res://addons/gf/kernel/package/gf_package_cli.gd -- status --json
```

检查 `status --json` 输出时，优先确认：`ok=true`、`issue_count=0`、`orphan_packages=[]`、`lockfile_verify.ok=true`。如果 `.gf/packages.lock.json` 不存在，`installed_count` 可能为 `0`，这只说明当前 GF 源码是手动 vendored 状态，不代表项目无法运行。不要继续使用旧 Python 包管理命令。

只有通过 `tools/run_gut_safe.ps1` 这样的隔离脚本，才运行 GUT。不要直接使用默认用户目录或裸 Godot/GUT 命令。

## 第一阶段：工程稳定性

目标：让项目在 GF 8.x、Godot 4.7 和严格 GDScript warning 设置下保持可维护。

1. 维护“安全运行 Godot/GUT”的本地脚本。
   - 问题：默认 Godot 用户目录曾生成巨大日志文件。
   - 当前状态：`tools/run_gut_safe.ps1` 已提供临时 user data/log 路径、超时、日志大小上限和默认日志增长上限；Godot 4.7 stable 与 GF 8.1.0 下安全 GUT 已覆盖 27 个顶层测试脚本、219 个测试。
   - 结果目标：后续默认通过该脚本运行 GUT，且默认用户目录不产生大日志。
   - 验证：切换 Godot 可执行文件或升级版本后，用低上限参数重新运行烟雾测试。

2. 清理 Godot 4.7 静态警告。
   - 重点：`unsafe_call_argument`、`unsafe_cast`、`unsafe_method_access`、`unsafe_property_access`、`return_value_discarded`、`missing_await`、隐式类型。
   - 做法：按文件逐个处理，不用大范围机械改写。
   - 验证：Godot 编辑器警告数量下降；若不能启动 Godot，则记录待验证项。

3. 固化 GF 包状态。
	- 检查 `.gf/packages.lock.json`、`project.godot` 的 `gf/extensions/enabled`、项目实际 GF 引用是否一致。
	- 当前已知：`gf.action_queue` 已启用，匹配 lockfile 的 `enable_extension`。
	- 验证：package status `ok=true`、`issue_count=0`、`lockfile_verify.ok=true`、`orphan_packages=[]`；`test_gf_package_validation.gd` 静态检查 lockfile、`project.godot`、`.gitignore` 的 GF 包管理和本地生成产物约束。

4. 决定 GF addon 物理目录策略。
	- 当前状态：`addons/gf/**` 是由 `.gf/vendor.lock.json` 精确锁定的完整 GF 8 源码，package lockfile 可能暂时不存在。
	- 当前状态补充：项目运行依赖 vendored 源码和 `project.godot` 启用扩展；包管理器状态需要等恢复 lockfile 后再作为强约束。
	- 选项 A：保留完整源码，便于示例项目探索 GF 能力。
	- 选项 B：按 lockfile 精简，只提交实际安装包文件，体现包管理器最小依赖。
	- 建议：先保留完整源码，等安全测试和 README 更新完成后再评估精简。

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
   - 涉及：`ProjectResourceCatalogUtility`、`GameModeCatalogUtility`、`GameUiRouterUtility`、`GFResourceRegistry`、`GFResourceResolverUtility`、`GFAssetUtility`。
   - 问题：模式目录和 UI 路由目录相似，容易重复注册、缓存、校验和错误输出。
   - 当前状态：项目级资源目录 Adapter 已提炼，保留两个业务入口，但共享注册、解析、缓存和 asset group 逻辑。
   - 验证：模式注册表和 UI 路由注册表测试继续通过，并能捕获缺失路径。

4. 存档 Module 深化。
   - 涉及：`GameSaveGraphUtility`、`GameSaveSectionData`、`SaveSystem`、`BookmarkSystem`、`CustomBoardSystem`、`ReplaySystem`、`GFSaveGraphUtility`、`GFSaveScope`、`GFSaveDataSource`、`GFStorageUtility`。
   - 问题：最高分、设置、书签、玩家棋盘、回放分属不同入口，持久化语义需要更统一。
   - 当前状态：统计、书签、玩家棋盘和回放已迁移为四个 Feature-owned section，由项目级 SaveGraph 原子保存；设置保持独立生命周期。旧 SaveSlot Adapter 和时间戳 Resource 集合已删除。
   - 存储契约：Binary Variant 类型保真、GF storage metadata、checksum、严格 Profile/section schema、UUID v7 稳定身份，不提供旧格式运行时双读。
   - 验证：跨架构重载、单文件约束、后期 section 失败全图回滚、schema 拒绝和保存失败内存回滚均有聚焦测试。

5. Installer ownership 固化。
   - 涉及：`GameArchitectureInstaller`、`gf.domain`、`gf.action_queue`。
   - 当前状态：项目 Installer 不再手动绑定 `GFLevelUtility`、`GFQuestUtility`、`GFActionQueueSystem`；这些 Module 由对应 GF 扩展 Installer 装配。
   - 验证：`test_architecture_installer_validation.gd` 静态检查项目 Installer 不重复绑定扩展 owned Module。

## 第三阶段：游戏完成度

目标：从功能样例变成完整小游戏。

1. 自定义与超大棋盘基础。
   - 当前状态：`BoardTopology` 已取代固定二维数组，矩形、十字和带空洞自定义棋盘共用稀疏状态、连续 lane、生成、判负、预览、撤销、书签、回放和统计键；玩家编辑器已支持绘制、擦除、预设、规范化、连通提示、GF 局部撤销历史和 SaveGraph 模板目录。棋盘表现已拆为独立世界画布与屏幕空间 HUD，支持完整聚焦、鼠标/触控板/双指缩放平移、单指抽象动作移动、可见区域查询、GF 对象池窗口化和低缩放细节裁剪。玩法页已有桌面、紧凑横屏、竖屏三种布局及 GF 物理安全区适配，移动 HUD 默认只显示分数、步数和最大方块。
   - 下一步：把诊断测试工具迁移到独立调试窗口或编辑器入口，并保持正式导出禁用。
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
   - GF `progress` SaveGraph section 保存单一 `stats` 真源并严格校验 schema；普通倍增类模式已定义 2048 目标，目标上下文已写入 `GameStatusModel`、完整状态快照和书签，首次达成目标时会给出 HUD 提示和非强制弹层，结算统计以“本局曾达成目标”为准，模式选择页和游戏结束菜单已展示游玩次数、最佳步数、最大方块、平均表现、目标达成情况和最近一局摘要。

5. 设置体验。
   - 语言、音量、视觉主题、音效主题、动画强度、视觉效果强度、棋盘辅助显示。
   - 设置页应继续通过 GF 设置 Utility 与 UI 绑定，不直接散落到各菜单；OptionButton 条目写入应复用 `GFItemListBinder`，书签/回放列表刷新应复用 `GFRepeaterBinder`。
   - 当前已接入 `appearance/theme_id` 和 `audio/sound_theme_id`；`ProjectContentCatalogUtility` 统一构建 GF 内容目录，`GameThemeCatalogUtility` 从 manifest 生成轻量描述符，`GameThemeUtility` 按需加载并事务激活。视觉与音效主题是可自由组合的独立设置轴。

## 第四阶段：视觉与交互打磨

目标：统一为柔和、独立游戏质感的扁平肌理风，避免刺眼、粗糙和马赛克噪点。

1. 建立视觉规范和主题系统文档。
   - 记录色板、字体、噪点强度、背景层级、方块色阶、按钮状态、动效原则。
   - 当前状态：`docs/visual_style.md` 已建立；主题包以独立资源键和 manifest 描述符发布，目录校验与资源级 `GFValidationReport` 阻止无效主题进入运行时，声音银行由 GF 挂载令牌管理。

2. 棋盘与方块。
   - 保持方块颜色来自配置资源，不在表现层硬编码覆盖用户预期。
   - 统一生成、移动、合并、转化动效，现有 Tween 通过 `BoardTweenBatchAction` 进入 `GFActionQueueSystem` 的等待、暂停、完成与取消生命周期，再由 `GameBoardFeedbackUtility` 和 `GFShakeUtility` 协调附加反馈。
   - 方块基础纹理由 `TileDefinition.visual_family_id` 固定身份家族，Recipe 能力只增加边缘小标记；禁止按数值轮换身份纹理或叠加多张全幅图案。

3. 菜单和弹层。
   - 检查模式选择、主菜单、设置、暂停、游戏结束、回放列表在 1280x720、1920x1080、窄屏下不重叠。
   - 所有按钮和列表项需要稳定焦点状态。

4. 测试面板隔离。
   - 测试工具只能在编辑器/调试态出现。
   - 正式体验中不要暴露测试控件，也不要让测试工具污染回放。

## 第五阶段：文档和示例价值

目标：让这个仓库能被其他项目当成 GF 8.x 示例阅读。

1. 更新 `README.md`。
   - 写明 GF 8.x、包管理器、vendored 源码状态、启用扩展。
   - 修正“直接继承 GFController”的表述，因为当前项目脚本使用显式路径继承。

2. 更新 `docs/ai_maintenance.md`。
   - 加入 GF package manager 工作流。
   - 清理或复核“当前临时框架补丁”记录，确认 GF 8 是否已经包含对应修复。

3. 新增架构文档。
   - 建议：`docs/architecture.md`。
   - 重点讲 Model/System/Utility/Controller/UI 的职责、事件流、资源目录、持久化策略。

4. 维护验证文档。
   - 文件：`docs/validation.md`。
   - 记录安全运行 Godot/GUT 的脚本、包锁验证、静态检查命令和当前验证缺口。

## 深化机会清单

1. `GameArchitectureInstaller` 仍是高耦合装配点。
   - 问题：注册顺序、dev 工具、项目 Utility 实例化集中在一个文件，接口偏宽。
   - 方向：按“运行时基础设施 / UI / 玩法 / 调试”分组内部函数，或提取小的装配 Module，但不要增加额外外部接口。
   - 收益：提高 locality，后续接入 debug 包或 save graph 时风险更低。

2. `GameUiMotionUtility` 和视觉测试已经成形，视觉规范已文档化。
   - 问题：资源和场景还没有完全围绕 `docs/visual_style.md` 收敛。
   - 方向：继续让主题内容包描述符、背景 shader、tile scheme、菜单场景和视觉测试围绕文档收敛。
   - 收益：后续 AI 不会反复把风格改歪。

3. SaveGraph 运维体验可以继续加深。
   - 当前状态：统计、书签、玩家棋盘和回放已统一到 Feature-owned section，GF SaveGraph 负责图级事务，旧并行实现已删除。
   - 方向：在不放宽严格 schema 的前提下，为损坏存档增加面向玩家的隔离、导出诊断和显式重置流程。
   - 收益：让 checksum 或未来版本拒绝不只出现在日志中，同时保持运行时无隐式降级。

4. 包锁和物理源码目录存在策略差异。
   - 问题：当前是完整 GF 8 源码 vendored 状态，但 `.gf/packages.lock.json` 可能暂时不存在。
   - 方向：继续保留完整源码，或恢复 GF 8 原生包管理 lockfile 后按 installed 包收敛，二选一并在 README 中说明。
   - 收益：减少未来维护者对“哪些包真的在用”的误解。

## 下一轮建议

优先级最高的下一步：

1. 把测试工具迁移出玩家三栏布局，建立独立调试窗口或编辑器工具入口，并保持正式导出禁用。
2. 让棋盘编辑器复用可缩放视口、触控仲裁与移动端安全区契约，完成手机端自定义棋盘绘制。
3. 按 `docs/visual_style.md` 审计背景 shader、tile scheme 和菜单场景，把散落颜色逐步收敛成资源化规则。
4. 持续完善 `asset_library`：新增素材必须登记稳定 `asset.*` key、授权元数据和审计报告，再接入主题或玩法。
5. 在稳定棋盘键和平台 Adapter 基础上推进图鉴、成就与排行榜。
