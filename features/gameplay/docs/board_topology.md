# 棋盘拓扑契约

本文档定义 gameplay Feature 的棋盘空间模型。它是玩家自定义棋盘、超大棋盘、可缩放视口和跨平台布局的共同基础。

## 领域边界

- `BoardTopology` 只回答“哪些坐标存在”，不保存方块、阵营、规则或表现。
- `GridModel` 只在活跃坐标上保存 `TileState`，空洞不是空方块，也不占容量。
- `BoardTopologyTemplate` 由 `GameModeConfig` 持有，声明模式接受固定拓扑、可变矩形或自定义拓扑。
- 当前模式选择页的尺寸下拉框和 `board_editor` Feature 都只是拓扑输入界面，不是运行时棋盘契约。

GF 没有与“四向、带空洞、连续 lane”完全同义的通用类型。`GFFlowGraph` 表达流程连接，`GFHexGridMath` 表达六边形网格；复用它们会混淆领域语义。因此拓扑由 gameplay Feature 拥有，同时复用 GF 的 `GFValidationReport`、确定性随机、Command History、Level Session 与 GFSaveProfile。

## 坐标与规范化

1. 活跃坐标使用 `Vector2i`，不得为负数。
2. 包围盒左上角必须是 `(0, 0)`。
3. `active_cells` 必须去重，并按 `y`、`x` 行优先升序保存。
4. 玩家绘制输入由 `BoardTopology.create_custom()` 平移、去重和排序。
5. 持久化输入不做修复；非规范顺序、重复坐标、未知 schema 或空拓扑直接拒绝。
6. `BoardTopology` 的领域/序列化防御上限为 262144 个活跃单元，单轴规范化坐标不得超过 262143；这不是玩家产品容量。领域工具仍可表示预算内的大型稀疏拓扑。
7. `BoardTopology.get_playable_validation_report()` 是 `GridModel`、对局启动、书签/回放接管和无障碍逐格投影共享的唯一可玩预算：活跃格最多 256，包围盒宽高分别最多 256，包围盒面积最多 256。因而两格超宽或 256 格对角线即使是合法领域拓扑，也不能进入当前可玩会话。
8. 超出可玩报告的实验拓扑必须先采用分块领域算法、自绘或 MultiMesh 表现，并建立独立的移动、输入和辅助技术预算；不得直接物化为逐格 `Control` 或同步无障碍矩阵。
9. 运行时把拓扑视为不可变值；`active_cells` 读取只返回副本，改变形状必须整体替换属性或创建新资源，以便查询、包围盒与指纹缓存同步失效。

## 移动语义

`get_move_lanes(direction)` 只接受四个单位方向。每条 lane 从移动前沿向后排列，并满足：

- 每个活跃单元在同一方向恰好属于一条 lane。
- 相邻坐标缺失时立即结束当前 lane；同一行或列中的后续单元形成新 lane。
- `MovementRule` 只处理单条连续 lane，不能感知或跨越拓扑空洞。
- 合并、反向动画映射和对边生成都使用同一 lane 顺序。

## 身份与持久化

- `topology_id` 表达语义来源，例如矩形模板或玩家棋盘 ID。
- `get_content_fingerprint()` 只对规范化活跃坐标计算 SHA-256 截断指纹。
- `get_stable_key()` 组合语义 ID 与内容指纹，供统计、本地排行榜分组和 GF Level Session 使用。
- `GridModel` 快照严格保存 `schema_version`、`topology` 和 `tiles`；方块位置必须属于快照拓扑。
- 书签与回放不保留旧 `grid_size` 双读分支。发布后若需要迁移，使用独立的一次性迁移工具。

## 当前能力

- 任意矩形、十字形和自定义稀疏拓扑。
- 空洞安全的移动、生成、判负、棋盘预览、撤销、书签与回放。
- 棋盘表现使用稳定局部世界坐标，`GFSpatialCanvas2D` 独占内容根、视图状态、缩放、平移和坐标转换；由 game_session 拥有的 `BoardWorldViewportController` 只追加 HUD fit inset、边缘余量和完整聚焦构图策略。HUD 保持独立屏幕空间，诊断面板由 diagnostics Feature 的独立 Window 承载。
- 鼠标中键拖动、滚轮缩放、原生触控板手势和双指触摸由 `GFSpatialCanvas2D` 自己的输入策略和内部 `GFPointerGestureUtility` 统一归一化；控制器不再创建第二套通用手势状态机。世界/画布/屏幕坐标由同一个 `GFSpatialCanvas2D` 换算，运行时连接由 `GFSignalUtility` 管理。
- 单指短滑只负责棋盘移动，并通过由 game_session 拥有的 `GFVirtualInputSource` 写入玩法抽象动作；它不直接调用命令。双指序列一旦成立，本轮触摸只负责画布平移/缩放，不再回落成单指移动。
- 由 game_session 拥有的 `GameplayResponsiveLayoutController` 在桌面、紧凑横屏和竖屏间调整棋盘留白；HUD 始终是由 GF 安全区保护的全屏覆盖层，摘要、通知和回合字幕共用屏幕边缘反馈轨。横屏按棋盘实际世界包围盒宽高比动态求解右侧 fit inset，并在几何变化时重算；竖屏则把反馈轨放在棋盘与触控区之间。瞬时文本和操作栏不得进入棋盘矩形外扩 50px 的动态包络。继承布局的左右栏在所有玩法断点都关闭。
- `BoardTopology.get_cells_in_rect()` 使用行区间缓存与二分边界查询可见活跃单元；由 game_session 拥有的 `GameBoardController` 在揭示前按单帧预算把最多 256 个当前窗口格子与方块完整预热到 `GFObjectPoolUtility`，重复 setup 只保留最新请求且不并发启动第二个预热 worker。完整模型不受裁剪影响；由 themes 拥有的 tile 表现不再保留整块底板，因此缩放过小或实验拓扑超过 256 个可见格时暂时隐藏逐格 Control，未来若需要轮廓必须使用独立低成本 silhouette，而不能恢复密集底板。
- 原 3x3 至 8x8 模式选择通过 `scalable_square_board_template.tres` 生成矩形拓扑。
- 调试扩建仅支持矩形正方形；它不是玩家棋盘编辑器。
- `board_editor` 已提供画笔、橡皮、矩形与十字预设、位置规范化、连通分量提示、局部 GF 撤销历史和玩家模板目录；撤销/重做通过 feature 自有 GF 输入上下文消费，控件与草稿信号由 `GFSignalUtility` 管理。
- 编辑画布使用稳定世界尺寸，桌面与双指视口操作由 `GFSpatialCanvas2D` 输入策略归一化；编辑控制器只仲裁笔刷/橡皮和笔画生命周期。内容根、视图状态和坐标换算仍由同一个画布持有；紧凑横屏和竖屏使用独立功能分区与 GF 物理安全区边距。
- 玩家模板使用 `custom_boards` GFSaveProfile section 和 `board.player.<uuid>` 稳定拓扑 ID。

## 表现与视口契约

1. `BoardTopology` 和 `GridModel` 坐标不得随窗口尺寸、缩放比例或 HUD 布局变化。
2. `GameBoardHost` 尺寸等于完整逻辑棋盘包围盒；`BoardWorld` 在 GF 内容根内始终保持零位移和单位缩放，统一缩放与位置只由 `GFSpatialCanvas2D` 写入，不修改单格尺寸或动画目标。
3. 可见格与可见方块节点是可丢弃的表现缓存，不是模型真源；平移、缩放或动画结束后必须从 `GridModel` 重新同步。
4. 由 game_session 拥有的 `GameBoardAnimationUtility` 使用绑定棋盘节点的 GF 命名队列处理动画。动画期间允许更新背景格窗口，但方块节点集在 Action 完成或取消后再同步，避免回收正在 Tween 的节点。
5. 输入优先级固定为：UI `Control` 先消费事件；棋盘视口中的双指序列负责平移/缩放；未进入多指状态的单指短滑在抬起时转换为四向玩法动作；中键、滚轮与原生 pan/magnify 继续只控制视口。
6. 触控滑动与 HUD 方向键必须经由 game_session 拥有的 `GameplayInputActions` 和 `GFVirtualInputSource`，进入 `features/game_session/resources/input/gameplay_input_context.tres` 声明的 `GFInputContext`，再由同属 game_session 的 `PlayerInputSystem` 消费并创建由 gameplay 拥有的 `MoveCommand`。键盘、鼠标按钮、手柄和触摸只提供不同物理来源，任何 UI 或视口控制器都不得直接执行移动规则。
7. 视口的键盘/手柄缩放、平移、完整聚焦与鼠标滚轮/中键、触控双指操作映射到同一组 `view_*` 抽象动作；任何设备都不得成为唯一可达路径。
8. 输入动画策略固定为缓冲、动画期间阻断和实时重定向三种。实时重定向取消当前 GF Action 后必须按当前 `GridModel` 快照恢复视觉节点，禁止继续播放已经失效的目标轨迹。
9. 方向含糊、距离不足或持续过久的单指轨迹必须拒绝；双指序列释放回单指后，必须等待所有触点结束才能开启下一次移动判定。
10. game_session 的 `GamePlayController` 同时发布两种所有权明确的载荷：由 gameplay 拥有的 `BoardTopologyReadyData` 只携带复制隔离的 `BoardTopology`，供图鉴发现等领域观察者消费；由 game_session 拥有的 `GameplayBoardReadyData` 才暴露棋盘表现宿主，仅供 diagnostics 建立开发上下文。gameplay 不得引用 diagnostics 的 Window、Panel、Utility 或 game_session 控制器。

## 当前接入与后续边界

1. `TileDiscoverySystem` 只消费 `BoardTopologyReadyData` 的拓扑副本，将稳定棋盘键接入严格图鉴发现模型；tile_catalog 不依赖 `GameplayBoardReadyData` 或任何 game_session 表现类型。
2. 成就已消费规范统计与发现事件；`ProgressStatsSystem` 已用稳定棋盘键、模式和规则集身份隔离本地排行榜，只接收比赛合格的严格结果。
3. Steam、微信或服务端排行榜仍是后续平台能力，必须经显式 bridge contract 重新校验与裁决；本地榜和拓扑键本身不构成线上权威证明。

任何后续形状都应先扩展拓扑或规则资源，不得重新引入固定二维数组或以 UI 尺寸推断逻辑空间。
