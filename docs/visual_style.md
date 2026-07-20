# 视觉风格指南

本文档记录 `2048-all-in-one` 的当前视觉方向。后续修改背景、方块、菜单、HUD、弹层、动效或主题资源时，先对齐本文档，再改具体资源和脚本。

## 视觉 Thesis

目标气质：CMYK 半调纸媒游戏。

关键词：

- risograph arcade puzzle
- CMYK halftone print
- zine-like paper interface
- side repeat print bands
- restrained paper-card depth

这不是深色玻璃 UI，也不是上一版单纯暖色像素棋盘。画面应像一张可玩的独立游戏宣传页：灰白纸面、低对比印刷条纹、克制的暖色块、疏朗半调网点、硬边框和清楚可读的数字。背景和纹理要有纸媒气质，但不能喧宾夺主。

当前第一套主题是 `halftone_atlas`：灰白印刷纸面、局部低对比版纹、中性灰墨棋盘、奶油/芥黄/陶土/灰青方块，以及按身份家族固定的稀疏母题。主题是长期产品卖点，不是一次性换皮；视觉资源、UI 色板和音效主题都必须能通过设置一键切换。

## 总体原则

1. 先让棋盘像一个印刷游戏物件。
   - 主菜单、游戏局内、模式选择、回放和设置都围绕同一套纸媒印刷 UI 语言展开。
   - 棋盘、方块、按钮和面板统一使用深墨色边框，圆角保持很小。

2. 纸底安静，印刷色有角色。
   - 背景默认是暖白纸底，不使用深色氛围云雾。
   - 青、黄、粉、品红只用于条纹、选中态、方块层级和短反馈。
   - 大面积内容区应偏干净，避免所有控件同时高饱和。

3. 半调纹理要克制。
   - `TilePatternOverlay` 只绘制星点、弧线、轨道、分栏等低密度家族母题。
   - 纹理只用于类型识别、纸媒质感和错版感，不承担文字可读性。
   - 文字可读性优先于花纹表现，数字对比度不能被纹理牺牲。
   - 不使用 blur、glow、大阴影或大面积粒子当作默认风格。

4. 资源是视觉真相来源。
   - 每个视觉主题和音效主题都是 `features/themes/resources/gf_content_package.json` 中的独立稳定资源键，不存在中央直引用注册表。
   - manifest metadata 必须声明 `theme_id`、显示/说明翻译键和唯一的 `is_default`；`GameThemeCatalogUtility` 据此生成轻量 `GameThemeDescriptor`。
   - 当前主题包来自 `features/themes/resources/themes/game/*.tres`。
   - `GameTheme` 只承载视觉主题，`GameAudioTheme` 独立管理声音主题；视觉与音效可自由组合。
   - 新主题进入运行时前必须通过 `GameThemeCatalogUtility` 的描述符校验和资源级 `GFValidationReport`，覆盖默认 ID、重复 ID、视觉依赖、庆祝 VFX、语义音效事件和 `GFAudioBank` 完整性。
   - 设置菜单只枚举描述符；完整主题在激活时按稳定键加载，并通过 `GFActivationTransaction` 切换。
   - 背景 uniform 参数来自 `features/themes/resources/themes/game/backgrounds/*_profile.tres` 的 `GFShaderParameterProfile`，由 `GFShaderParameterUtility` 校验并应用。
   - 方块轮廓与母题来自 `GameTheme.tile_visual_theme`；`TileVisualTheme` 按稳定家族 ID 返回 `TileVisualFamilyStyle`，主棋盘、图鉴与历史预览共享同一来源。
   - 按钮焦点参数来自 `GameUiPalette.button_focus_shader_profile`；庆祝特效来自 `GameTheme.celebration_vfx_theme`，包含素材键、基础 Profile 和事件 preset。
   - 方块颜色来自 `features/themes/resources/themes/tile_schemes/*.tres`。
   - 棋盘色来自 `features/themes/resources/themes/board/*.tres`。
   - UI 色板来自 `GameUiPalette`，由 `GameThemeUtility` 应用到 `GameUiStyleUtility`。
   - 表现层不应硬编码覆盖主题资源，除非是明确的临时调试或测试态。

## 调色板

当前主色是灰白印刷纸面 + 局部青黄版纹 + 暖色方块 + 深墨棋盘：

- 纸面灰白：`#e9e6dc`
- 印刷青：`#9ed2ce`
- 深墨棋盘：`#203f4c`、`#2a1b2c`、`#000000`
- 纸色/奶油：`#f1e2be`、`#e6d1a1`、`#f0d696`
- 暖棕/红棕：`#caac77`、`#c0977a`、`#944431`
- 草绿/灰绿：`#ad9d62`、`#a9a994`、`#87867a`
- 高值深色：`#594a45`、`#445162`

使用规则：

- 低值方块可以更接近纸色，确保数字像印在纸上。
- 中值方块使用青、黄、粉、绿、红时，优先用深墨色文字。
- 高值或特殊类型可以进入深青、深紫、黑色，并使用纸色文字。
- 默认按钮和信息面板以纸色为主，hover/focus/selected 才使用黄、红棕或青。
- 不要把背景、按钮、方块和粒子都推到满饱和 CMYK；参考图的好看来自纸底留白和局部印刷色。

## 背景

背景使用 `features/asset_library/resources/shaders/background/halftone_paper_background.gdshader`。方向是灰白纸底、侧边重复印刷条纹、低对比半调网点、轻纸纹、淡棋盘纸块、细虚线网格和极慢的像素墨流。具体颜色、速度和强度由 `GameTheme.background_shader_profile` 引用的 `GFShaderParameterProfile` 声明，`GFShaderParameterUtility` 负责批量写入和 uniform 存在性校验；shader 文件只提供安全默认值。

推荐约束：

- `base_color` 在 `halftone_atlas` 中使用灰白纸面色。
- `accent_color` 通常是印刷青，只作为局部版纹和轻微色偏。
- `secondary_color` 通常是印刷黄。
- `warm_color` 通常是印刷粉或品红。
- `cell_color_1` / `cell_color_2` 控制低对比 checker 纸块，只能作为纸面色差，不应看起来像 UI 棋盘。
- `grid_size` / `sub_grid_size` 控制主副网格尺寸。主网格默认不画线，副网格使用短虚线给纸面一点结构。
- `grid_color` / `sub_grid_color` 应使用深墨色的低 alpha 版本，不使用高饱和青黄粉。
- `grid_strength` 控制侧边条纹、checker 纸块和细网格整体强度，应保持低到中等。
- shader 默认 `grain_strength` 建议保持在 `0.008` 到 `0.020`；单个主题可略高，但需要截图验证。
- shader 默认 `stipple_strength` 建议保持在 `0.000` 到 `0.006`；单个主题可略高，但不能影响文字。
- `sub_line_thickness` 建议保持在 `0.40` 到 `1.20`；再粗会显得像网页背景网格。
- `sub_dash_length` 建议保持在 `4.0` 到 `12.0`；不要做连续强线。
- `cloud_pixelation` 控制像素墨流的低分辨率采样，当前主题使用宽屏比例，不依赖外部 noise texture。
- `cloud_scroll_speed_1` / `cloud_scroll_speed_2` 控制两层程序化噪声的缓慢漂移；速度必须低，避免背景像动态天空或水波。
- `cloud_center_pos` / `cloud_position_impact` 控制墨流围绕画面上方轻微弯曲。它只负责纸面活性，不负责主视觉叙事。
- `cloud_strength` 建议保持在 `0.010` 到 `0.050`；再高会回到深色云雾背景的问题。
- `interaction_offset`、`interaction_direction`、`interaction_energy` 只由 `GameBoardFeedbackUtility` 在有效操作后短时驱动；主题 Profile 的静态值必须为零。
- `scanline_strength` 建议保持在 `0.000` 到 `0.008`。
- `glow_strength` 建议保持在 `0.000` 到 `0.100`。
- `pulse_speed` 建议保持在 `0.000` 到 `0.080`。

禁止方向：

- 深色雾面、玻璃态、霓虹发光或网页式渐变背景。
- 粗噪点、脏污纹理、影响文字和棋盘识别的高对比花纹。
- 背景图案强到抢走棋盘注意力。
- 像素墨流移动过快、对比过强，导致玩家感觉整张 UI 在漂。
- 把整张画面做成同一种米黄色，丢掉 CMYK 印刷层次。

## 场景转场

默认主题使用 `features/asset_library/resources/shaders/transition/halftone_wipe_transition.gdshader`。覆盖与揭示分别配置为 `features/themes/resources/themes/game/transitions/halftone_cover_transition.tres` 和 `halftone_reveal_transition.tres`，由 `GFScreenTransitionUtility` 统一管理根视口覆盖层。`SceneRouterSystem` 只从当前 `GameTheme` 解析 `GFScreenTransitionEffect`，不创建节点或 Tween。

该 shader 来自外部 2D 遮罩转场思路，但项目版不依赖外部 gradient 或 shape texture，改为程序化斜向纸张擦除、稀疏形状扰边、半调网点、轻纸纹和青/品红错版移动边。已覆盖区域必须不透底，避免新旧场景在中间帧重影；印刷图案只允许出现在移动边缘。`reverse_progress` 允许同一 shader 由主题资源声明覆盖和揭示方向。

约束：

- 转场只承担场景切换的方向感，不作为常驻背景特效。
- 新主题必须同时提供 cover/reveal 两个 `GFScreenTransitionEffect`，并通过 `GameTheme` 引用；禁止在路由系统内增加主题分支。
- 转场层级、时长、输入阻断、ShaderMaterial 和进度参数属于主题资源配置；节点生命周期、取消和完成回调属于 GF Utility。
- 默认 `width` 应保持在 `0.10` 到 `0.18`，形成短促清楚的纸张移动边，不能变成长雾化淡入。
- 默认 `shape_tiling` 应保持在 `12` 到 `28`，形状块应像纸媒印刷遮罩，而不是大块马赛克或细碎噪点。
- 默认 `shape_influence` 应保持在 `0.08` 到 `0.20`，只轻微扰动擦除边缘，不能生成铺满全屏的形状拼贴。
- 默认 `grain_strength` 应保持在 `0.008` 到 `0.020`，和背景纸纹同一量级。
- 默认 `band_strength` 应保持在 `0.04` 到 `0.16`，只给擦除边缘一点青色印刷纹理。
- 默认 `fill_opacity` 应接近或等于全不透明，保证覆盖阶段不出现两个场景叠影。
- 默认 `edge_opacity` 和 `edge_strength` 应高于铺墨层，保证玩家能看见明确移动边。
- `registration_offset` 只用于青/品红错版边缘，不能变成霓虹描边。
- 动画时长应控制在约 `0.24s` 到 `0.30s`，覆盖阶段需要足够可见，但整体不能拖沓。
- 禁止用闪白、霓虹、强 glow 或全屏粒子替代纸媒遮罩。
- 禁止把转场做成一张居中或全屏静态插图；必须能看出擦除方向和移动边。

## 启动画面

启动画面分为极轻 `app/scripts/boot.gd` 与正式 `app/scripts/boot_runtime.gd` 两级：前者立即承接原生首帧并在线程中加载后者，后者负责 GF 初始化、素材注册和主菜单预热状态。它应当像一张小型印刷机状态卡，而不是系统默认 loading 或空白黑屏。

约束：

- 背景复用当前纸媒背景 shader，保持浅灰白纸面、轻噪点和低对比图案。
- 中央内容可以有品牌标题、微型棋盘和状态文字，但不能变成营销页。
- Godot 原生启动阶段使用 `printworks_boot_splash.png` 提前显示完整静态首帧；项目加载页继续使用同尺寸、同位置的微型棋盘和进度槽，禁止先显示孤立 Logo 再重排整个构图。
- 轻量 Boot 禁止 preload GF、主题、玩法脚本或 shader；这些依赖必须由 BootRuntime 在线程资源加载完成后再进入场景树。
- 进度条使用 `features/asset_library/resources/shaders/ui/startup_progress_bar.gdshader`，保留粗墨边、颗粒空槽和星纹填充。
- 启动背景和进度条静态参数由 `features/themes/resources/themes/boot/*.tres` 的 GF Profile 声明；Boot 初始化 GF 架构前只使用无状态 `GFShaderParameterUtility` 写入参数。
- 进度必须由真实启动流程驱动，至少覆盖 GF 初始化和主菜单预热，不使用纯假进度。
- 预加载条件、超时和最短停留延迟统一使用 `GFAsyncWaitUtility`，不自行维护 deadline 或 `SceneTreeTimer`。
- `GFScenePreloadMap` 只预热最高频相邻路径：启动期准备主菜单与模式选择，模式选择期再准备玩法场景；不得在原生首屏阶段并发预载所有低频菜单。
- 首次玩法需要的方块轮廓、稀疏母题和常驻反馈画布必须在不透明加载页后完成首绘提交，避免第一次操作临时编译 2D pipeline。
- 启动画面停留时间要短，默认只用于避免启动期空白和突然跳转。
- 动态加载页首帧必须直接承接原生静态构图，只在结束时使用约 `0.16s` 淡出收束；主场景仍由 GF 场景转场接管，二者不能产生黑帧或重复长动画。

## 方块与棋盘

方块是第一视觉信号。它们应该像印刷小卡片，不像网页色块。

规则：

- 方块使用实心底色、深墨粗描边、统一短投影、同色亮边、可识别轮廓和低密度母题。
- 默认描边使用深墨色或黑色，边框宽度通常为 3px 到 6px。
- `TilePatternOverlay` 负责绘制低对比度身份纹理和 Recipe 边缘标记；中央数字区域必须保持安静。
- 数字必须始终清晰。必要时使用深墨色或纸色文字，不为了色板统一牺牲对比度。
- 棋盘底板使用中性灰墨色，空格子使用低对比暖灰，让棋盘像一件稳定的实体游戏物件。
- `TileDefinition.visual_family_id` 先解析 `TileVisualFamilyStyle`，同一身份的不同数值必须保持同一家族；数值只改变色阶和字号。
- 身份家族同时决定剪角、缺口、比例、描边色与一个稀疏母题：经典为安静的柔和方框，斐波那契为不对称剪角和角落弧线，复合家族为对角剪角，卢卡斯为八边形和成对角括号，比值基础与因子分别为侧缺口、上下票口。轮廓变化应控制在单元格内，数字本身不得旋转或偏离中心。
- GF Recipe 的 `visual_layer_id` 只投影为边缘小标记。复合方块不得叠加多张全幅纹理，也不得让标记遮挡数字。
- 方块颜色不得在 `GameBoardController`、`Tile` 或动画 Action 中随意覆盖主题资源。

主题资源建议：

- `classic_tile_theme.tres` 是视觉基准，负责最稳、最容易读的 CMYK 色阶。
- `fibonacci_tile_theme.tres` 和 `lucas_tile_theme.tres` 可以调整青、黄、粉的顺序，但要保持文字对比度。
- `red_tile_theme.tres` 和 `blue_tile_theme.tres` 用于特殊类型或模式时，可以更偏品红/深青，但不能变成警示色海报。

## UI 面板与控件

UI 应像纸媒工具页里的可交互模块，不像半透明网页控制台。

信息架构：

- 首屏必须在三秒内明确主对象与主动作。主菜单以品牌、棋盘样本和“开始游戏”为第一阅读层，不再使用等权按钮堆叠的中央大卡片。
- 游戏局内让棋盘占据视觉中心；分数、步数和最大方块只保留为紧凑状态条。操作教程、测试工具和次要说明不得常驻抢占桌面空间。
- 设置、图鉴和历史记录是任务页，不复用调试式三栏模板。内容按任务分类，侧栏或移动端标签只负责切换类别。
- 桌面端可以并置主对象和辅助信息；移动端必须重新编排优先级，不能把桌面三栏等比缩窄。窄屏第一视口仍应保留主标题、当前任务和主要动作。
- 空间分组优先于套卡片。页面区段不使用层层嵌套的面板，只有独立条目、详情面板和弹层可以形成明确表面。

布局：

- 主菜单、模式选择、设置、暂停、回放、书签和游戏结束使用一致的纸色面板、深墨边框、短间距和小圆角。
- 1280x720 是基础验证尺寸；1920x1080 和窄屏需要重新检查，不允许文字重叠、裁切或溢出。
- 面板用纸色或暖白底，边框用深墨色；不要使用玻璃态半透明大卡片。
- 设置和回放这类信息界面可以更安静，但仍要保留印刷边框和 CMYK 交互强调。

字体：

- 正文、标题和数字字体都由 `GameUiPalette` 提供语义资源；页面只能声明文本角色，不得自行查询系统字体。
- 默认主题随包携带 `shared/assets/fonts/noto_sans_sc_variable.ttf`，许可证保存在同目录。Steam、Web、微信和移动端必须使用同一份字形资源。
- 禁止把 `SystemFont` 作为发布主题的正文、标题或数字字体；系统字体只允许用于编辑器工具或明确的本机诊断界面。
- 标题通过字号、字重语义和留白形成层级，不再依赖手写字体制造个性。方块数字与状态数字使用统一数字角色，确保快速扫读。
- 新主题可以替换三种语义字体，但必须在资源校验和 Web/窄屏截图中验证中文、数字、标点、换行和最长按钮文案。

控件：

- `GameUiStyleUtility` 负责统一按钮、输入框、滑条、文本语义和基础控件的静态样式；界面脚本只能声明 `PRIMARY/SECONDARY/MUTED`、`PANEL/SELECTED`、`DEFAULT/FOCUS` 等语义，不得复制色值或缓存跨主题 `StyleBox`。
- HUD、菜单等界面的瞬时强调反馈必须调用 `GameUiMotionUtility`，节点脚本不得自行维护 Tween 元数据。
- 动态文本应通过统一适配边界计算字号。`GFTextFitter` 的 Godot 4.7 退出期 RID 问题由 `gf-framework#6` 跟踪，修复位于 `gf-framework#7`；上游修复发布前，方块数字使用一次最大字号测量后按比例收缩，禁止逐字号循环测量。
- `GameThemeUtility` 负责把当前主题的 `GameUiPalette` 注入 `GameUiStyleUtility`；`GameUiMotionUtility` 只依赖 Style Utility 准备控件，并负责 hover、focus、pressed、intro、reveal 和 pulse 动画。设置页切换主题后要能依据已保存的语义角色立即重建当前场景样式。
- 按钮默认是纸色块加深墨描边，hover 用印刷青，pressed 用印刷黄，focus 可使用品红边框。
- 按钮的 hover/focus/pressed 可通过 `features/asset_library/resources/shaders/ui/button_focus_dash.gdshader` 显示移动虚线圆角描边，半径、线宽、虚线密度和速度由 UI 色板引用的 GF Profile 控制；默认态必须隐藏，避免整屏控件同时动。
- focus 要比 hover 更清楚，方便键盘和手柄导航。
- pressed 反馈要短、明确，不要像 selected 状态。
- 禁用态降低透明度和对比，不改变布局尺寸。

## 动效

动效要像轻量印刷游戏界面：短、清楚、机械感强。

目标达成和新纪录使用主题化庆祝 VFX。`GameCelebrationVfxTheme` 决定 shader 素材键与基础印刷色板，`GameCelebrationVfxPreset` 决定单个事件的时长、透明度和动态参数；新增主题不得在 `GameCelebrationVfxUtility` 中增加新的硬编码颜色或速度常量。

时间范围：

- 新方块出现：约 `0.10s` 到 `0.14s`，从较小 scale 弹出。
- 合并：约 `0.12s` 到 `0.16s`，短暂放大后回到原位。
- 移动：约 `0.08s` 到 `0.12s`，清楚但不拖沓。
- hover / focus：约 `0.06s` 到 `0.12s`。
- 列表或子项 reveal：约 `0.10s` 到 `0.18s`。
- 面板 intro：约 `0.16s` 到 `0.24s`。

行为规则：

- 不使用 blur、glow、长淡入和大位移作为默认动效。
- 同一元素不要同时叠加大位移、大缩放和强粒子。
- Container 管理的子控件不能被动效改写最终位置。
- 隐藏子控件不播放 reveal。
- 动画不能成为状态可读性的唯一来源。
- 每次有效移动只编排一次整批反馈：外层方向冲量、`GFShakeReceiver2D` 的 board channel 细震、棋盘受力边缘碎片和背景 shader 响应必须共享同一等级。
- 普通移动只使用最低等级；单次合并、高价值/多次合并和纪录反馈逐级增强。不得按方块数量重复播放整屏震动。
- 合并冲击先更新目标定义，再用约 `0.13s` 的数值与色阶成长反馈连接旧值和新值；HUD 分数反馈稍晚于棋盘冲击，形成明确因果顺序。

## 测试与验证

已存在的视觉相关测试：

- `test_visual_polish.gd` 验证背景 shader、启动 GF 等待流程、半调场景转场、主题化 Tile 轮廓与稀疏母题、文字对比度、按钮焦点 Profile、庆祝事件 preset，以及 GF 震动与背景联动反馈。
- `test_game_theme_utility.gd` 验证内容包描述符、默认主题约束、按键加载、GF 激活事务、GF settings、背景/UI/VFX Profile、`GFSignalUtility` owner 连接、场景转场、语义音效事件和音频银行挂载令牌。

后续视觉改动至少检查：

- `docs/visual_style.md` 是否仍描述当前方向。
- `features/asset_library/resources/shaders/background/halftone_paper_background.gdshader` 的颗粒、点纹、细网格、像素墨流、扫描线和 glow 参数是否保持克制。
- `features/themes/resources/themes/game/backgrounds/*_profile.tres` 是否完整覆盖背景 shader 需要由主题控制的 uniform，且不在 `GameTheme` 脚本中重新声明同名字段。
- `GameUiPalette.button_focus_shader_profile` 与 `GameTheme.celebration_vfx_theme` 是否完整，且项目脚本中没有重新出现直接 `set_shader_parameter()`。
- `features/asset_library/resources/shaders/transition/halftone_wipe_transition.gdshader` 的印刷擦除、半调网点和纸纹强度是否仍短促、低对比。
- `features/themes/resources/gf_content_package.json` 是否为每个主题登记独立资源键、完整描述符 metadata 和唯一默认项，且没有重新引入中央主题注册表。
- 视觉 `GameTheme` 是否完整引用棋盘、方块色阶、UI 色板、庆祝 VFX 和 cover/reveal GF 转场；独立 `GameAudioTheme` 是否完整解析全部语义事件。
- `features/themes/resources/themes/tile_schemes/*.tres` 是否仍由资源定义方块色。
- `TileVisualTheme` 的家族签名是否唯一，`TilePatternOverlay` 的母题是否稀疏、中央留白且不会影响数字识别。
- `GameUiStyleUtility` 的默认、选中、字段与文本语义是否能在色板切换后正确重建。
- `GameUiMotionUtility` 的 hover、focus、pressed 动画反馈是否仍有明确区别。
- 安全 GUT 是否通过。

## 当前待改进

1. 场景资源仍有少量布局级 `theme_override_font_sizes`；后续新增运行时控件样式必须优先声明到主题资源或 `GameUiStyleUtility`，不得重新在节点脚本中硬编码色板。
2. 默认 Noto Sans SC 已解决跨平台字形一致性；后续主题若要强化纸媒个性，应优先增加经过中文覆盖验证的 display font，而不是退回系统 fallback 或整页手写字。
3. `printworks` 已切换到 Nathan Gibson 的 Universal UI Soundpack（CC BY 4.0）中筛选出的 OGG 短音效，并通过 `features/asset_library/resources/gf_content_package.json`、`GameAssetLibraryUtility` 和 `GFAudioBank` 与当前主题事件 ID 播放；后续需要继续做响度和混音打磨。
4. 回放、书签和模式选择还需要按任务页原则继续消除等权卡片与过量说明。
5. 回放/书签列表已接入 `GFRepeaterBinder`，后续只有在历史记录数量明显增大时再引入 `GFVirtualListModel`。
