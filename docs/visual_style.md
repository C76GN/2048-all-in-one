# 视觉风格指南

本文档记录 `2048-all-in-one` 已实现的两套视觉主题及共同表现契约。页面任务与验收映射见 [ui_surface_intent.md](./ui_surface_intent.md)，运行与截图方法见 [validation.md](./validation.md)。

## 当前两套主题

默认 **Print Edition / 印刷工坊** 使用稳定 ID `halftone_atlas`，保留已有设置的资源身份。它是一张可操作的数字游戏海报：骨白纸面、大号衬线数字、朱红主操作、墨色版线和少量群青色。按钮落下和释放如短促压印，模式以可读的真实合并公式区分。画面、字体、控件材质与 UI 动效必须一同成立，不能仅替换背景颜色。

可选 **Quiet Paper / 素纸** 使用 `quiet_paper`，保留上一套暖白、深绿、细圆角和轻反馈。其资源快照位于 `features/themes/resources/themes/game/quiet_paper/`。设置页通过现有主题描述符列出这两项，切换成功后立即更新当前控件、预览与后续场景。当前没有其他已发布风格。

两套主题都让棋盘、数值和玩家的下一步动作优先。印刷版的识别来自排版尺度、色面和不同控件角色，不以厚重黑框包住所有内容，也不以装饰噪点掩盖布局问题。

## 印刷版色彩与材质

| 语义 | 当前资源值 | 用途 |
|---|---|---|
| 骨白纸面 | `#F2E9CF` | 页面、海报与任务表面 |
| 墨色 | `#25231F` | 大数字、正文、版线与主要外框 |
| 朱红 | `#CC3B2F` | 开始按钮、选中与主要事件 |
| 群青 | `#253C96` | 键盘焦点和有限的高值色阶 |
| 主按钮浅色字 | `#FFF8E8` | 在朱红常态下保持至少 4.5:1 对比度 |
| 次文字 | `#706954` | 状态说明与次级信息 |
| 输入纸面 | `#F8F1DD` | 可编辑字段 |
| 棋盘底板 | `#E1D4B2` | 组织留空位置与方块 |

- 主操作是朱红印签：直角、2px 墨色轮廓、浅色字，无投影。按下和焦点保持各自可读状态。
- 次级动作使用底部细线；弱操作保持文字入口；输入框保留完整轻边界和稍重底线。不能把它们统一画成同样的圆角卡片。
- 标签页选中时使用墨底纸色字，规则卡的持久选中使用朱红边界和暖色纸底。hover、focus、selected 不互相替代。
- `SurfaceRole.SHELL` 在印刷版以顶端版线组织区域，不形成四边重复框。共享容器消费数值配置，不能反向依赖主题 Feature。
- 直角与轻微切角保持纸张轮廓。允许标题或母题页边出现稀疏、静态套准标记；仅 `print_marks_enabled` 控制这些标记，素纸关闭。不得铺成全屏网格、错位字影或无语义纹样。
- 经典方块从纸色、暖色进入朱红、群青和墨色。低值数字用墨色、高值用纸色；每一色阶检查大字号对比度，不仅检查端点。

素纸的资源保留 `#F5F3EB` 背景、`#FFFEFA` 表面、`#24352F` 主字、`#326759` 强调色，约 6–10px 控件圆角。轻投影、原数字字体和原 UI 节拍随主题一起恢复，不继承印刷版的直角或压印开关。

## 字体

印刷版的英文标题和数字使用 `shared/assets/fonts/ui_print_display.tres`，基础字体为 DM Serif Display Regular。中文回退到原有 `ui_sans_display.tres`，Noto Sans SC 字重 740；正文仍使用随包 Noto Sans SC，避免让中文长句承担展示字体的密度。

字体来自 Google Fonts 固定提交 `7efaaeb60f72588557a6605b48311611937304ba`，文件为 76,580 字节，SHA256 为 `8CC3643535EDF039AA5D95440A8542735E9197E4F4B8D9303E980FEFBF5AB616`。授权为 OFL，证据位于 `shared/assets/fonts/dm_serif_display_ofl.txt`，来源完整记录在 `build/print_edition/font_source.json`。发布主题不依赖 SystemFont 或本机字体。

- `GameUiPalette.body_font/display_font/numeric_font` 是字体真值。首页母题、HUD、实际 Tile 和历史预览消费同一数值字体。
- `Tile.setup()` 接受当前数字字体；对象池复用时重新应用，空字体清除旧 override。`GameplayVisualWarmup` 预热当前字体，不能只预热一个外观不同的默认数字。
- `GFTextFitter.MeasurementMode.SINGLE_LINE` 负责方块数字适配。大数、长中文、英文、不同视口都检查 ShapedText 范围与裁切；数字不加描边、发光或错色阴影。
- 微信字体映射和字形覆盖由发布流程维护。新文案必须更新覆盖证据，不能沿用旧子集测试结论。

## 资源与表现所有权

- `GameTheme` 组合调色板、棋盘、方块、UI motion、背景、反馈、庆祝与转场；`GameAudioTheme` 独立承载音效。两者均通过 `features/themes/resources/gf_content_package.json` 登记稳定资源键。
- manifest metadata 声明 `theme_id`、显示/说明翻译键与唯一默认项。`GameThemeCatalogUtility` 提供轻量描述符，设置页不维护第二份硬编码主题列表。
- 激活通过 `GFActivationTransaction` 与 `GFValidationReport`；成功后由 `GameThemeUtility.visual_theme_changed` 通知页面。页面先应用当前完整视觉树，再恢复自身语义角色和主题预览。失败时保留原主题，不显示假成功。
- `GameUiPalette` 集中提供颜色、字体、焦点 Profile，以及按钮/字段/面板/标签圆角、边宽、主按钮投影、次操作底线、SHELL 顶线和静态印刷标记开关。
- `GameUiStyleUtility` 消费材质配置。页面选择 PRIMARY、SECONDARY、QUIET、ICON、SHELL、SELECTED 等角色，不复制主题颜色或跨主题复用旧 StyleBox。
- 一次控件样式操作由 `begin_bulk_theme_override()` / `end_bulk_theme_override()` 批量提交，不让每项 override 独立引发通知和布局计算；同一控件不嵌套批次。
- `BoardTheme` 提供棋盘和空格颜色、`board_corner_radius/board_border_width`、`empty_cell_corner_radius/empty_cell_border_width`。主棋盘、母题和历史预览投影这些值，不改命中几何。
- `TileColorScheme` 提供数值色阶，默认资源位于 `features/themes/resources/themes/mode_visuals/defaults/`。`TileVisualFamilyStyle` 提供身份轮廓、稀疏标记、描边和 `shadow_opacity`，通过 `GameTheme.tile_visual_theme` 按稳定家族 ID 解析。
- `GameUiMotionUtility` 与 Presenter 拥有动效生命周期；`GameUiStyleUtility` 只提交静态材质。页面不建立另一套私有 Tween 系统。

## 背景、转场与启动

共同背景 Shader 为 `features/asset_library/resources/shaders/background/halftone_paper_background.gdshader`。印刷版 `grain_strength = 0`，素纸保留 `0.006` 静态细纹；两者的 `grid_strength`、`cloud_strength`、`stipple_strength`、`scanline_strength` 和 `pulse_speed` 都为零。

关闭网格与云层时使用静态短路径；颗粒也关闭时不计算 hash。两套当前主题均不运行常驻背景时间更新，不以每帧纹理、背景平移或整盘震动制造质感。`GameShaderAnimationDriver` 与减少动态、失焦、隐藏、Shader 关闭策略仍保留完整生命周期契约。

印刷转场使用 `print_sheet_transition.gdshader`：纸面滑过边界，带两条有限墨线。`halftone_cover_transition.tres` 为 70ms，`halftone_reveal_transition.tres` 为 100ms。素纸保留原 `halftone_wipe_transition.gdshader`。转场资源拥有颜色、材质和时间，`GFScreenTransitionUtility` 与 `SceneRouterSystem` 拥有切换、输入阻断、取消和终态；短动画不是页面加载时间指标。

`app/scripts/boot.gd` 仍为轻量启动壳，原生 `printworks_boot_splash.png` 与壳保持同一品牌构图。正式 runtime 在线程加载，真实进度出现后不重新布局。Boot 不 preload GF、游戏主题或玩法 Shader，不为了动态换肤把重型依赖拉入原生首屏。进度来自真实初始化和预热；字体、资源加载成功不等于首绘没有编译停顿，仍需测量。

## 棋盘与方块

棋盘稳定地占据主要操作区域。印刷版板框为 2px 墨色直角，空格以色差区别，不再给每格叠加底框；方块轮廓约 1px，无投影，避免缩放时形成发虚的双重边缘。素纸恢复 12px 棋盘圆角、1px 轻边界和 6px 空格圆角。

- `TileShapeSurface.build_outline()` 是真实轮廓构造来源，预览不另造不一致的近似图标。数字水平居中，不跟随整盘旋转。
- `TileDefinition.visual_family_id` 决定家族，数值变化只调整色阶与字号。非经典形状保留规则身份，不为装饰随机旋转。
- `TilePatternOverlay` 仅承载低密度家族或 Recipe 标记。印刷版图案纹理透明度为零，稀疏母题约 0.12；素纸保留约 0.025 纹理和 0.10 母题。数字中央保持可读。
- 已登记 Kenney Pattern Pack 2 素材保留 CC0 证据；资源存在不表示当前主题必须绘制它。
- 缩放、平移、Fit 和不同拓扑都以稳定可操作区域为先。横屏、紧凑横屏和竖屏分别验证，不等比缩窄桌面布局。

## 页面组织与交互

首页以大号 2048、主题棋盘和开始/继续建立海报层级。模式页直接展示真实规则示例，当前规则与开始动作在紧凑和竖屏布局中保持可达。辅助功能使用明确任务名称，不向玩家展示设计契约词或引擎实现词。

局内以棋盘为中心，分数、步数和最大值采用紧凑记分版线。详情按需展开，在每个视口都可见；暂停、撤销、提示和缩放控件不覆盖棋格。空书签/回放有明确空状态，选中稳定业务 ID 后展示实际预览。设置、图鉴和历史按任务组织，不强制嵌套三栏卡片。

- 44px 触控根、键盘/手柄静态描边和持久选中不因主题变化而消失。印刷焦点采用群青，朱红主按钮用浅色前景焦点，减少动态也保持完整状态。
- 焦点、hover、按下、禁用和选中可分别辨认，不依赖颜色闪烁或动画结束才能操作。
- Container 拥有布局；Presenter 只在稳定根节点内移动可见表面。装饰层使用 `MOUSE_FILTER_IGNORE`，根按钮位置、比例、文字与命中区域不随压印摇摆。
- 弹层遮罩和任务卡由同一 modal generation 拥有；关闭立即冻结提交，每代只提交一次业务动作。迟到回调不得改变新页面。
- 列表稳定 ID 原位更新，保留焦点与选择；只揭示新建且可见条目，不因刷新重播整页。

## 动效节拍与性能

印刷版 `GameUiMotionProfile.print_motion = true`。UI 的短动作如纸签落版：先有可见响应，再收束；素纸的独立 profile 保留原短揭示与轻反馈。

| 动作 | 印刷版当前资源 |
|---|---|
| 按下压印 | 约 35ms，内部表面压深 2.5px |
| 释放 | 约 105ms，一次有界 0.8px 回弹 |
| hover/focus | 印刷分支直接约 80ms 收束，表面极轻抬起，无根节点缩放或倾斜 |
| 首次纸签落下 | 约 130ms，位移 6px、16ms 有界错峰 |
| 普通面板进入 | 约 120ms；含交互后代时只做自身透明度的墨色显现，不移动后代 |
| 内容更新 | 约 120ms；含交互后代时保持位置与大小，仅更新自身透明度 |
| 方块移动 | 120ms，QUAD OUT |
| 方块生成 | 100ms，印刷版从 0.94 倍回到 1 倍；素纸从 0.88 倍回到 1 倍，均无旋转 |
| 合并局部压印 | 两段各约 55ms；印刷峰值为 `Vector2(1.035, 0.93)`，素纸为均匀 1.06 倍，均无旋转 |

- `panel_enter_offset = 8px` 和 `content_switch_offset = 3px` 仅作用于无交互后代的普通表面；含按钮、输入等后代的容器只改变 `self_modulate`，不让整个控件群漂移。印刷 hover 不经过 40ms overshoot 分段，不能把未消费字段累加为可见时长。
- 不移动、旋转或挤压整个棋盘。根节点冲击、背景、棋格后层和边缘碎片关闭时真正跳过 Tween；合并反馈局限于相关方块。
- 合并数字在碰撞时提交，不显示领域中不存在的中间值。新输入接管保留屏幕位置，连续前往新目标；无效方向不使已有移动瞬移或中止。
- 减少动态立即提交可读终态，保留焦点、选择、遮罩、错误和真实进度，不等待不可见动画。
- `GFUIRouterUtility`、`GFUIRoute`、`GFUIUtility` 拥有路由、Modal 栈、返回、焦点恢复、owner/`GFAsyncScope` 取消、预载和去重。
- `GFNotificationUtility` 唯一拥有通知优先级、去重和生命周期；FeedbackRail 使用稳定槽位与通知 ID。
- 列表使用 `GFTableDataView`、keyed cache 和现有 GF binder。错峰数量有界，超预算内容直接提交静态终态。
- 庆祝使用有界 `GPUParticles2D` 和主题事件 preset，不在 fragment 中模拟整场粒子。反馈性能矩阵仍见 `features/themes/docs/feedback_performance_matrix.md`。

## 验证与证据

主题切换验证实际可见控件、字体、边框、背景和预览均恢复，而非只检查选择器 ID。`test_print_material_switching.gd` 检查材质角色、往返切换、棋格几何和复用 Tile 字体；其他主题、动效、对比度、焦点与结构测试继续有效。

自动检查后仍需查看默认印刷版与素纸的真实截图，覆盖主页、模式、局内、详情、弹层、历史和设置。首反馈、ready、first post-draw 与 motion-settled 分开测量，平均 FPS 不足以说明手感。截图工具若中途失败，已生成图片只是部分证据，不得声称整个矩阵通过。外部动效参考见 [ui_motion_reference_library.md](./ui_motion_reference_library.md)。
