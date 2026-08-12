# 玩家界面意图合同

本文档把项目的玩家身份、页面隐喻和视觉验收连接起来。它不替代
[`visual_style.md`](./visual_style.md) 的材质、色彩和动效规范，也不替代
GF 路由、输入、列表或生命周期机制；它回答的是这些机制要帮助玩家
“操作什么”。

## 产品身份

玩家是**无限合并实验室的规则编排者 / 数字印刷工坊操作者**。玩家
不是在操作一个换成纸媒皮肤的后台界面，而是在编排规则印版、运行
棋盘实验、保存校样并检查一次合并过程。

棋盘是跨页面的真实游戏物件；纸张、油墨、套印和机械节拍只负责说明
对象关系与因果，不得掩盖按钮文本、焦点、错误和危险操作。

页面映射：

| 玩家页面 | 交互隐喻 | 首要对象 | 传统结构的角色 |
|---|---|---|---|
| 主菜单 | 实验室总台 / Atlas 封面 | 可响应的微型棋盘 | 文本按钮保持明确导航 |
| 模式选择 | 规则索引与实验工单 | 六个模式及当前选择 | 紧凑数值样张只辅助确认规则 |
| 棋盘编辑器 | 版面工作台 | 可编辑棋盘版面 | 工具栏、历史和精确数值 |
| 玩法 | 正在运行的合并实验 | 权威棋盘 | HUD 只显示状态与动作 |
| 方块图鉴 | 样本 Atlas | 方块样本及发现关系 | 表格负责筛选与比较 |
| 方块试验台 | 活字与油墨工作台 | 当前方块配方 | 表单负责精确参数 |
| 回放 | 印刷过程时间带 | 当前步骤、标记与棋盘 | 列表负责大量记录 |
| 书签 | 冻结样张抽屉 | 棋盘缩略样张 | 常规按钮负责恢复与删除 |
| 设置 | 校准任务页 | 当前选项与局部预览 | 表单仍是主结构 |

设置、账号、错误、无障碍和危险确认不强制拟物化。只要隐喻会降低
可预测性、翻译适配或跨输入效率，就使用传统清晰结构，并共享项目
材质和状态语法。

## UI Surface Intent Brief

新玩家页面或中/大型结构改版在实现前必须提交一份短 Brief。局部
文字、间距、bug 修复不需要单独立项。Brief 至少回答：

```yaml
id: navigation/mode-selection
owner: navigation
player_goal: 选择并理解一套玩法规则
player_role_or_fantasy: 规则编排者
interaction_metaphor: 规则索引与实验工单
functional_mapping:
  - 选择模式 -> 更换规则印版与静态样张
  - 调整参数 -> 更新本次实验工单
primary_object: 六项规则索引与当前选择
primary_action: 开始本次实验
reading_order: [模式差异, 当前选择, 基础参数, 开始]
states: [rest, focus, selected, disabled, loading, error]
input_equivalence: [mouse, keyboard, controller, touch]
causal_feedback: 选择 -> 样张更新 -> 本地确认 -> 可开始
reduced_motion: 直接替换静态样张并保留选中标记
performance:
  first_feedback_ms: 50
  usable_before_ceremony: true
references: []
rejected_options:
  - 永久三栏样张台：样张、索引、配置等权会制造重复信息和视觉拥挤
  - 分页六项索引：少量模式不值得增加翻页与隐藏选项
acceptance_assertions:
  - 三秒内能指出当前规则和主动作
  - selected、focus、pressed 在静态图中可区分
  - 隐喻改变信息组织或因果反馈，而不只是装饰
capture_ids: []
```

Brief 不进入运行时资源，不作为 `GameModeConfig` 等确定性领域资源的
字段。需要数据化页面表现时，由对应 Feature 拥有 presentation
descriptor；领域配置仍只描述玩法真相。

## 首批页面合同

### 模式选择：规则索引与实验工单

Surface contract ID：`navigation/mode-selection`。

- 首读顺序是六个模式差异、当前选择、基础参数、开始。
- 六个模式由同一种 descriptor 数据驱动，不创建六套定制场景。
- 六项在同一页完整呈现；规则示例只作为右侧工单里的紧凑数值确认，
  不重复模式名、长说明、样张编号或结果段落。
- 默认工单只露出棋盘大小与开始；自定义棋盘、种子和比赛信息进入
  “高级设置”，不能与主动作等权。
- 窄屏把模式索引与一张完整工单依次堆叠，不复制桌面栏，也不产生
  独立样张表面。Reduced Motion 仍可直接替换静态数值关系。

### 回放：过程时间带

Surface contract ID：`replays/process-timeline`。

- 棋盘仍是主对象，时间带表示步骤、当前位置和关键 marker。
- 时间带可以跳转，但精确前后步、marker 文本与键盘/手柄路径必须保留。
- 大量回放记录继续使用 `GFVirtualListBinder`；时间带不改变目录容量或
  引入当前明确不支持的倍速。

### 书签：冻结样张抽屉

Surface contract ID：`bookmarks/frozen-proof-drawer`。

- 书签是一个可恢复状态，不是一个时间过程；棋盘缩略图是主要浏览对象。
- 目录最多 16 条，继续使用普通 `GFRepeaterBinder`，不为视觉差异复制
  列表生命周期机制。
- 删除、恢复失败和确认继续使用明确文本、焦点与常规按钮。

### 主菜单：实验室总台

Surface contract ID：`navigation/main-menu`。

- 菜单文本保持可预测；微型棋盘根据开始、档案、图鉴、试验台和校准
  等语义响应，不按任意按钮序号点亮。
- 紧凑/竖屏必须保留可辨认的微型棋盘母题，而不是退化为纯按钮页。
- 主菜单母题只呈现项目已经拥有的规则，不创建隐藏玩法或导航谜题。

### 设置：校准任务页

Surface contract ID：`settings/calibration-task-page`。

- 类别栏与表单保持传统，selected、focus、pressed 必须分离。
- Reduced Motion、高对比度、Shader 等难以凭名称预判的选项可以提供
  局部静态校准样张；预览不得创建第二份设置真源。
- 音量继续以真实音频状态为准，不为“世界观感”伪造百分比或播放结果。

## 实现边界

- 使用 GF 的路由、列表/表格、焦点、输入、资源会话和 typed operation；
  项目只拥有产品隐喻、页面数据与视觉语义。
- List、Grid、Card、Form 是可靠实现机制，不是页面概念。先确定首要对象
  和因果关系，再选择合适组件。
- 表现只消费权威业务结果。UI 不重算合并、存档、回放或主题真相。
- 常规控件反馈使用 `GameUiMotionUtility`，色彩与 StyleBox 使用
  `GameUiStyleUtility`；动效不散落自定义时长。
- 主要交互首反馈目标为 50ms 内；演出不得阻塞已可执行操作。

## 验收映射

每份 Brief 的 `acceptance_assertions` 和 `capture_ids` 必须映射到：

1. GUT 的结构、状态、输入与 Reduced Motion 回归；
2. `capture_visual_review.gd` 的真实玩家路径关键帧；
3. `capture_ui_vfx_matrix.gd` 的多视口、焦点、触控和静态终态；
4. 路由性能工具的 ready / first post-draw / motion-settled；若新增多阶段
   交互，再单独记录输入到首反馈，不能用页面打开时间代替；
5. 人工三秒首读：指出玩家当前对象、当前选择和主动作。

截图 manifest 必须记录本次适用的 surface contract ID，避免图片与设计
意图脱钩。自动结构通过不能替代人工语义签字。

## 外部参考与许可证

定向研究一个具体问题时选 2–4 个高相关案例即可。来源继续记录在
[`ui_motion_reference_library.md`](./ui_motion_reference_library.md)；
代码、素材、截图和品牌表现的授权分别判断。授权未知时只能
`idea_only`，不得把外部实现、Logo、角色或独特视觉资产纳入运行时。
