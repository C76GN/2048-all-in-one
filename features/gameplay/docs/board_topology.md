# 棋盘拓扑契约

本文档定义 gameplay Feature 的棋盘空间模型。它是玩家自定义棋盘、超大棋盘、可缩放视口和跨平台布局的共同基础。

## 领域边界

- `BoardTopology` 只回答“哪些坐标存在”，不保存方块、阵营、规则或表现。
- `GridModel` 只在活跃坐标上保存 `TileState`，空洞不是空方块，也不占容量。
- `BoardTopologyTemplate` 由 `GameModeConfig` 持有，声明模式接受固定拓扑、可变矩形或自定义拓扑。
- 当前模式选择页的尺寸下拉框和 `board_editor` Feature 都只是拓扑输入界面，不是运行时棋盘契约。

GF 没有与“四向、带空洞、连续 lane”完全同义的通用类型。`GFFlowGraph` 表达流程连接，`GFHexGridMath` 表达六边形网格；复用它们会混淆领域语义。因此拓扑由 gameplay Feature 拥有，同时复用 GF 的 `GFValidationReport`、确定性随机、Command History、Level Session 与 SaveGraph。

## 坐标与规范化

1. 活跃坐标使用 `Vector2i`，不得为负数。
2. 包围盒左上角必须是 `(0, 0)`。
3. `active_cells` 必须去重，并按 `y`、`x` 行优先升序保存。
4. 玩家绘制输入由 `BoardTopology.create_custom()` 平移、去重和排序。
5. 持久化输入不做修复；非规范顺序、重复坐标、未知 schema 或空拓扑直接拒绝。
6. 当前安全上限为 262144 个活跃单元，后续超大棋盘需先完成分块渲染与性能预算再调整。
7. 运行时把拓扑视为不可变值；`active_cells` 读取只返回副本，改变形状必须整体替换属性或创建新资源，以便查询、包围盒与指纹缓存同步失效。

## 移动语义

`get_move_lanes(direction)` 只接受四个单位方向。每条 lane 从移动前沿向后排列，并满足：

- 每个活跃单元在同一方向恰好属于一条 lane。
- 相邻坐标缺失时立即结束当前 lane；同一行或列中的后续单元形成新 lane。
- `MovementRule` 只处理单条连续 lane，不能感知或跨越拓扑空洞。
- 合并、反向动画映射和对边生成都使用同一 lane 顺序。

## 身份与持久化

- `topology_id` 表达语义来源，例如矩形模板或玩家棋盘 ID。
- `get_content_fingerprint()` 只对规范化活跃坐标计算 SHA-256 截断指纹。
- `get_stable_key()` 组合语义 ID 与内容指纹，供统计、排行榜和 GF Level Session 使用。
- `GridModel` 快照严格保存 `schema_version`、`topology` 和 `tiles`；方块位置必须属于快照拓扑。
- 书签与回放不保留旧 `grid_size` 双读分支。发布后若需要迁移，使用独立的一次性迁移工具。

## 当前能力

- 任意矩形、十字形和自定义稀疏拓扑。
- 空洞安全的移动、生成、判负、棋盘预览、撤销、书签与回放。
- 棋盘表现使用稳定局部世界坐标，外层 `BoardWorldViewportController` 独占缩放、平移和完整聚焦；HUD 保持独立屏幕空间，诊断面板由 diagnostics feature 的独立 Window 承载。
- 鼠标中键拖动、滚轮缩放、原生触控板手势和双指触摸由 `GFPointerGestureUtility` 统一归一化，屏幕与棋盘局部坐标通过 `GFViewportUtility` 换算，运行时连接由 `GFSignalUtility` 管理。
- 单指短滑只负责棋盘移动，并通过 `GFVirtualInputSource` 写入玩法抽象动作；它不直接调用命令。双指序列一旦成立，本轮触摸只负责画布平移/缩放，不再回落成单指移动。
- `GameplayResponsiveLayoutController` 在桌面、紧凑横屏和竖屏间切换。竖屏 HUD 位于独立移动宿主并由 GF 安全区边距保护，继承布局的右栏在所有玩法断点都关闭。
- `BoardTopology.get_cells_in_rect()` 使用行区间缓存与二分边界查询可见活跃单元；`GameBoardController` 只通过 `GFObjectPoolUtility` 挂载当前窗口内的格子和方块节点。完整模型不受裁剪影响，缩放过小时进入仅显示棋盘底板的细节层级。
- 原 3x3 至 8x8 模式选择通过 `scalable_square_board_template.tres` 生成矩形拓扑。
- 调试扩建仅支持矩形正方形；它不是玩家棋盘编辑器。
- `board_editor` 已提供画笔、橡皮、矩形与十字预设、位置规范化、连通分量提示、局部 GF 撤销历史和玩家模板目录；撤销/重做通过 feature 自有 GF 输入上下文消费，控件与草稿信号由 `GFSignalUtility` 管理。
- 编辑画布使用稳定世界尺寸和共享 `CanvasViewportMath`，桌面与双指视口操作由 `GFPointerGestureUtility` 归一化，屏幕/画布局部坐标由 `GFViewportUtility` 换算；紧凑横屏和竖屏使用独立功能分区与物理安全区边距。
- 玩家模板使用 `custom_boards` SaveGraph section 和 `board.player.<uuid>` 稳定拓扑 ID。

## 表现与视口契约

1. `BoardTopology` 和 `GridModel` 坐标不得随窗口尺寸、缩放比例或 HUD 布局变化。
2. `GameBoardHost` 尺寸等于完整逻辑棋盘包围盒；`BoardWorld` 只改变统一缩放与位置，不修改单格尺寸或动画目标。
3. 可见格与可见方块节点是可丢弃的表现缓存，不是模型真源；平移、缩放或动画结束后必须从 `GridModel` 重新同步。
4. `GFActionQueueSystem` 处理动画期间允许更新背景格窗口，但方块节点集在 Action 完成或取消后再同步，避免回收正在 Tween 的节点。
5. 输入优先级固定为：UI `Control` 先消费事件；棋盘视口中的双指序列负责平移/缩放；未进入多指状态的单指短滑在抬起时转换为四向玩法动作；中键、滚轮与原生 pan/magnify 继续只控制视口。
6. 触控移动必须经 `GameplayInputActions` 和 `GFVirtualInputSource` 进入已启用的 gameplay `GFInputContext`，由 `PlayerInputSystem` 消费并创建 `MoveCommand`。任何 UI 或视口控制器都不得直接执行移动规则。
7. 方向含糊、距离不足或持续过久的单指轨迹必须拒绝；双指序列释放回单指后，必须等待所有触点结束才能开启下一次移动判定。
8. 玩法只通过 `GameplayBoardReadyData` 发布棋盘表现上下文；不得引用 diagnostics feature 的 Window、Panel 或 Utility。开发工具需要棋盘上下文时由 diagnostics 订阅该事件。

## 后续顺序

1. 已通过 `TileDiscoverySystem` 将稳定棋盘键接入严格图鉴发现模型。
2. 下一步以领域事件驱动成就，并通过平台 Adapter 接入排行榜。

任何后续形状都应先扩展拓扑或规则资源，不得重新引入固定二维数组或以 UI 尺寸推断逻辑空间。
