# 玩家界面意图合同

本文档把玩家目标、页面首要对象与验收连接起来。材质、色彩和动效见 [visual_style.md](./visual_style.md)；GF 继续拥有路由、输入、列表和生命周期机制。

## 产品身份

玩家是一位合并解谜玩家：选择规则、规划移动、获得更高的数字，也可以保存棋盘、回顾过程和尝试自定义玩法。

棋盘是跨页面的共同对象。首套可切换风格采用首版印刷海报：骨色纸面、深墨字、套印色与规则牌块。首页以游戏标题和棋盘封面建立身份，模式页以可读的规则样例表达选择；页面名称和操作文字继续直接说明任务，印刷术语不成为额外操作。其他风格仍通过主题资源替换颜色、字体、轮廓与节拍。标题和导航分隔线、棋盘封面边缘的稀疏套准记号由 `GameUiPalette.print_marks_enabled` 控制；安静风格关闭这些装饰，数字与交互命中区域不受影响。

| 页面 | 玩家目标 | 首要对象 | 辅助结构 |
|---|---|---|---|
| 主菜单 | 开始或继续一局 | 大标题、棋盘封面与主动作 | 紧凑的收藏导航和系统入口 |
| 模式选择 | 理解差异并选择玩法 | 六张规则牌、当前选择与开始 | 棋盘规格和折叠高级设置 |
| 棋盘编辑器 | 创建可玩布局 | 可编辑棋盘 | 工具栏、历史与精确数值 |
| 玩法 | 规划移动并合并数字 | 权威棋盘 | 紧凑状态、暂停与可展开详情 |
| 方块图鉴 | 查看方块与发现关系 | 方块样本 | 筛选与比较 |
| 方块试验台 | 尝试方块配方 | 当前配方及结果 | 参数表单 |
| 回放 | 回顾关键过程 | 当前步骤与棋盘 | 时间带、标记与记录列表 |
| 书签 | 恢复保存的棋盘 | 棋盘缩略图 | 恢复、删除和明确确认 |
| 设置 | 调整偏好并确认效果 | 当前选项 | 类别、表单与局部预览 |

采用成熟、可预测的交互结构。桌面、触控、键盘和手柄表达同一任务；减少动态、错误、无障碍和危险确认保持清晰直接。

## UI Surface Intent Brief

新页面或中/大型结构改版在实现前记录短 Brief。局部文案、间距和 bug 修复不单独立项。Brief 说明目标与因果，不要求为了隐喻新增交互。

```yaml
id: navigation/mode-selection
owner: navigation
player_goal: 理解并选择一套玩法规则
player_role_or_fantasy: 合并解谜玩家
interaction_metaphor: 规则牌与开局票面
functional_mapping:
  - 选择模式 -> 更新当前规则与简短示例
  - 调整参数 -> 配置下一局
primary_object: 六项模式与当前选择
primary_action: 开始游戏
reading_order: [当前选择与开始, 六种规则样例, 可选参数]
states: [rest, focus, selected, disabled, loading, error]
input_equivalence: [mouse, keyboard, controller, touch]
causal_feedback: 选择 -> 示例与选中标记更新 -> 可开始
reduced_motion: 立即更新示例与静态选中标记
performance:
  first_feedback_ms: 50
  usable_before_ceremony: true
references: []
rejected_options:
  - 六项模式分页：增加翻页与隐藏选项
  - 独立大示例栏：重复当前信息并压缩操作区
acceptance_assertions:
  - 三秒内能指出当前规则和主动作
  - selected、focus、pressed 在静态图中可区分
  - 示例帮助理解实际规则而不增加必须阅读的装饰说明
capture_ids: []
```

Brief 不进入运行时领域资源。数据化表现由对应 Feature 的 presentation descriptor 拥有，`GameModeConfig` 等确定性配置只描述玩法真相。

## 页面合同

稳定的 Surface contract ID 用于截图与测试映射。ID 中的历史命名不要求玩家界面沿用相同措辞。

### 模式选择

Surface contract ID：`navigation/mode-selection`。

- 桌面以规则牌与开局票面并列；竖屏先露出当前选择与开始，再展开六种模式差异。
- 模式由同一种 descriptor 数据驱动，不创建六套定制场景。
- 六项同页完整呈现；每张规则牌直接显示 descriptor 给出的数值样例与简短说明。逐步模式用格位移动图表达一步一格，不能伪装成算术等式。
- 开局票面用紧凑棋盘规格控件与更显著的开始按钮组成动作行；自定义棋盘、种子和比赛信息进入高级设置。
- 紧凑横屏保留双栏。720px 竖屏使用两列规则牌，并把当前选择与开始置于牌阵之前；低于600px可改为单列。切换断点后保留焦点和可达滚动，减少动态直接替换示例。

### 回放

Surface contract ID：`replays/process-timeline`。

- 棋盘是主对象，时间带表示步骤、当前位置和关键 marker。
- 时间带可跳转，同时保留精确前后步、marker 文本和键盘/手柄路径。
- 大量记录使用 `GFVirtualListBinder`，界面只呈现已有能力，不暗示未支持的倍速。

### 书签

Surface contract ID：`bookmarks/frozen-proof-drawer`。

- 书签保存可恢复的棋盘状态，棋盘缩略图是主要浏览对象。
- 上限 16 条，继续使用 `GFRepeaterBinder`，不为视觉重构复制列表生命周期机制。
- 空状态说明如何保存棋盘；选中后明确提供恢复与删除，失败和确认保留直接文字与焦点。

### 主菜单

Surface contract ID：`navigation/main-menu`。

- 大标题与棋盘封面构成首页主体，开始是最显著的操作，继续保持独立次动作；六个收藏/历史入口集中成紧凑短栏，设置与退出降低视觉权重。
- 棋盘母题可对开始、历史、图鉴、试验台和设置做轻微语义响应，不创建隐藏玩法或导航谜题。
- 紧凑与竖屏保留至少240px的棋盘封面，不把它压成小图标；主动作优先可见，完整辅助导航保持可达。棋盘与实际游戏共享当前主题的字体、颜色和边框材质。
- 开场只做短反馈，输入接管与减少动态不额外延迟操作。切换风格只刷新表现，不重建正在选择的模式、棋盘规格或种子。

### 设置

Surface contract ID：`settings/calibration-task-page`。

- 类别栏与表单保持清晰，selected、focus、pressed 分离。
- 减少动态、高对比度和 Shader 可提供局部效果预览；预览不创建第二份设置真源。
- 音量以真实音频状态为准，进度与预览不伪造播放结果。

## 实现边界

- 使用 GF 路由、列表/表格、焦点、输入、资源会话和 typed operation；项目拥有页面目标、数据和视觉语义。
- 先确定首要对象、动作与阅读顺序，再选择 List、Grid、Card 或 Form；可靠的常规结构是允许的。
- UI 只消费权威结果，不重算合并、存档、回放或主题真相。
- 常规反馈使用 `GameUiMotionUtility`，颜色和 StyleBox 使用 `GameUiStyleUtility`，节拍归主题 profile。
- 主要交互首反馈目标为 50ms 内，动画不阻塞可执行操作。目标是验收标准，不代表未测量路径已经达到。

## 验收映射

Brief 的 `acceptance_assertions` 和 `capture_ids` 映射到：

1. GUT 的结构、状态、输入与减少动态回归。
2. `capture_visual_review.gd` 的真实路径关键帧。
3. `capture_ui_vfx_matrix.gd` 的多视口、焦点、触控与静态终态。
4. 路由工具的 ready、first post-draw 与 motion-settled；输入首反馈另行记录，页面打开时间不能替代。
5. 人工三秒首读：指出当前对象、当前选择和主要动作。

截图 manifest 记录适用的 Surface contract ID。自动结构通过不替代真实图像检查，矩阵中途失败时只认定已完成状态的部分证据。

## 外部参考与许可证

针对具体问题选择少量相关的成熟产品或官方设计指南，来源记入 [ui_motion_reference_library.md](./ui_motion_reference_library.md)。借鉴层级、留白、反馈和可达性，不复制品牌资产或未经授权实现。授权未知时标记 `idea_only`，不得把外部 Logo、角色或独特素材纳入运行时。
