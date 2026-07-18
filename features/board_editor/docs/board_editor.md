# 玩家棋盘编辑器

`board_editor` Feature 拥有玩家自定义棋盘的草稿编辑、模板目录和持久化契约。它依赖 gameplay 提供的 `BoardTopology` 与 `BoardTopologyTemplate`，但不拥有对局状态、移动规则或模式配置。

## 领域契约

- `BoardTopologyDraftModel` 保留模板画布坐标，允许编辑过程中出现空草稿、越过最小包围盒限制或多个断开区域。
- 提交和保存统一调用 `BoardTopology.create_custom()` 规范化坐标，再由当前 `BoardTopologyTemplate.accepts_topology()` 严格校验。
- 多个连通分量是明确的移动空间语义，不代表阵营，也不是错误；编辑器显示区域数量，实际移动仍由 gameplay 的连续 lane 决定。
- 一次鼠标拖动、预设替换、清空、模板载入或位置规范化都生成一条 `BoardDraftEditCommand`。
- 编辑器使用自己的局部 `GFCommandHistoryUtility`，不得污染正在进行的对局撤销栈。

## UI 与路由

- `navigation` 只在 `ui_route_registry.tres` 登记稳定路由 `board_editor`，不实现编辑算法。
- 模式选择页通过 `GFUIRouterUtility.push_route()` 打开编辑器，并在入栈前注入当前模板和拓扑。
- 编辑器提供画笔、橡皮擦、矩形与十字预设、清空、左上规范化、撤销、重做、模板保存、载入、删除和当前形状预览。
- 右键始终擦除；左键遵循当前画笔或橡皮模式。断开区域只提示，不阻止保存与使用。
- 返回的拓扑仍由模式选择页复核，不能通过 UI 回调绕过模式模板。

## 持久化

- `CustomBoardCatalogSaveData` 拥有 `custom_boards` SaveGraph section，当前 schema 为 `1`。
- `CustomBoardData` 使用 UUID v7 稳定身份，显示名限制 64 字符，保存创建和更新时间，并内嵌严格 `BoardTopology`。
- 玩家模板的 `topology_id` 必须为 `board.player.<uuid>`；统计键仍附加内容指纹，因此同一模板修改形状后不会错误复用旧成绩。
- `CustomBoardSystem` 只通过 `GameSaveGraphUtility.replace_section_data()` 写入统一 `player_data.save`，不创建旁路文件。
- Profile 已升为 `player_data@2`。本阶段不保留 `player_data@1` 双读分支；发布迁移应使用独立工具。

## 后续演进

当前模式模板最大为 8x8，画布已使用稀疏单元集合和按轴绘制网格，不依赖完整二维状态。下一阶段把棋盘表现拆为世界画布与 HUD，并增加相机缩放、平移、聚焦和可见区域裁剪；届时编辑画布复用同一视口交互能力，而不是另写一套超大棋盘控件。
