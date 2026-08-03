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
   - `TilePatternOverlay` 只绘制弧线、折角、分栏等低密度家族母题，并可在边缘叠加已审计的低透明度几何纹样。
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
   - 按钮焦点参数来自 `GameUiPalette.button_focus_shader_profile`；棋盘冲击与手柄震动来自 `GameTheme.board_feedback_profile` 中成对的 `GFShakePreset` / `GFHapticPreset`；庆祝特效来自 `GameTheme.celebration_vfx_theme`，包含素材键、基础 Profile 和事件 preset。
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
- `animation_time` 不是主题 Profile 的静态参数，只由 `GameShaderAnimationDriver` 在目标可见、应用聚焦且动效启用时推进；失焦、隐藏、减少动态或关闭 Shader 时必须停止推进，静态策略可卸载材质以避免持续片元开销。
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

该 shader 来自外部 2D 遮罩转场思路，但项目版不依赖外部 gradient 或 shape texture，改为程序化斜向印刷擦除、稀疏形状扰边、半调网点、轻纸纹和青/品红错版移动边。已覆盖区域必须不透底，避免新旧场景在中间帧重影；印刷图案只允许出现在移动边缘。`reverse_progress` 允许同一 shader 由主题资源声明覆盖和揭示方向。

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

- Godot 原生启动阶段使用只含几何品牌和微型棋盘的 `printworks_boot_splash.png`；项目轻量壳以同一品牌构图补上阶段文案、百分比和真实进度槽。槽体、裁切区与动态填充必须位于同一个响应式 `Control` 层级，不得再把空槽烘焙进按比例裁切的图片后另行叠加固定坐标填充。
- 中央构图可以包含品牌标题、微型棋盘和进度槽，但不能变成营销页，也不能在动态加载开始后重新排版。
- 轻量 `Boot` 禁止 preload GF、主题、玩法脚本或 shader；它只通过 `ResourceLoader` 在线程中加载 `BootRuntime`，后者进入场景树后才创建 GF 架构。
- `features/asset_library/resources/shaders/ui/startup_progress_bar.gdshader` 是素材目录中的可选 Shader；当前启动代码未消费它，也不能把它描述为轻量壳依赖。未来若启用，只能在 GF 初始化完成后的正式启动编排或主题场景中应用，并应补真实截图验证。
- 进度必须由真实启动流程驱动，至少覆盖 GF 初始化和主菜单预热，不使用纯假进度。
- 预加载条件、超时和最短停留延迟统一使用 `GFAsyncWaitUtility`，不自行维护 deadline 或 `SceneTreeTimer`。
- `GFScenePreloadMap` 只预热最高频相邻路径：启动期准备主菜单与模式选择，模式选择期再准备玩法场景；不得在原生首屏阶段并发预载所有低频菜单。主场景跳转由 `SceneRouterSystem` 在 cover 前显式 `prime_scene()` 一次，正式切换将 `preload_before_change=false`，让 GF 直接复用缓存或 in-flight 请求，不能为了“保险”重复提交预载。
- 首轮背景、转场、焦点与庆祝 Shader 由 `GFRenderWarmupUtility` 按 `startup_render_warmup_manifest.tres` 统一触碰；方块轮廓、稀疏母题和常驻反馈画布仍必须在不透明加载页后完成真实首绘，避免第一次操作临时编译自绘 2D pipeline。
- 启动画面停留时间要短，默认只用于避免启动期空白和突然跳转。
- 动态加载页首帧必须直接承接原生静态构图，只在结束时使用约 `0.16s` 淡出收束；主场景仍由 GF 场景转场接管，二者不能产生黑帧或重复长动画。

## 方块与棋盘

方块是第一视觉信号。它们应该像印刷小卡片，不像网页色块。

规则：

- 方块使用实心底色、深墨粗描边、统一短投影、同色亮边、可识别轮廓和低密度母题。
- 默认描边使用深墨色或黑色，边框宽度通常为 3px 到 6px。
- `TilePatternOverlay` 负责绘制低对比度身份纹理和 Recipe 边缘标记；中央数字区域必须保持安静。
- 非经典家族可从主题取得一个经稳定素材键登记的几何纹样；默认主题仅采用
  Kenney Pattern Pack 2 的 CC0 精选子集，以不高于 `0.055` 的透明度绘制，并用
  52px 中央静区隔离数字。经典数字家族不使用纹样底图。
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
- 同一视口只保留一个全局第一动作。局部编辑器可以在彼此独立的任务区各自拥有一个主动作，但返回、删除、筛选和翻页不能与它争夺视觉重量。
- 游戏局内让棋盘占据视觉中心；分数、步数和最大方块只保留为紧凑状态条。操作教程、测试工具和次要说明不得常驻抢占桌面空间。
- 设置、图鉴和历史记录是任务页，不复用调试式三栏模板。内容按任务分类，侧栏或移动端标签只负责切换类别。
- 桌面端可以并置主对象和辅助信息；移动端必须重新编排优先级，不能把桌面三栏等比缩窄。窄屏第一视口仍应保留主标题、当前任务和主要动作。
- 空间分组优先于套卡片。页面区段不使用层层嵌套的面板，只有独立条目、详情面板和弹层可以形成明确表面。

布局：

- 主菜单、模式选择、设置、暂停、回放、书签和游戏结束使用一致的纸色面板、深墨边框、短间距和小圆角。
- 1280x720 是基础验证尺寸；1920x1080 和窄屏需要重新检查，不允许文字重叠、裁切或溢出。
- 面板用纸色或暖白底，边框用深墨色；不要使用玻璃态半透明大卡片。
- 页面或弹层的最外层任务表面使用 `SHELL`：不透明纸面、约 2px 深墨边框、无模糊的 7px 硬偏移底板。居中弹层的 `SurfaceVboxContainer` 还在顶部保留短青/黄套印标记；全页 `PanelContainer` 不强加装饰条。硬底板只用于顶层任务表面，不能给每一层嵌套卡片重复加厚。
- 暂停、达成和游戏结束等阻断式状态先压暗局内内容，再把唯一任务卡置于中央；卡内信息、摘要和操作必须同时可读，不能以裸文字覆盖棋盘。
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
- 动态文本应通过统一适配边界计算字号。方块数字使用当前 GF `GFTextFitter.MeasurementMode.SINGLE_LINE`，并由完整 GUT 的 `ShapedText` / `Font` RID 退出基线阻止测量回归。
- `GameThemeUtility` 负责把当前主题的 `GameUiPalette` 注入 `GameUiStyleUtility`；`GameUiMotionUtility` 只依赖 Style Utility 准备控件，并负责 hover、focus、pressed、intro、reveal 和 pulse 动画。设置页切换主题后要能依据已保存的语义角色立即重建当前场景样式。
- 按钮默认是纸色块加深墨描边，hover 用印刷青，pressed 用印刷黄，focus 可使用品红边框。
- `PRIMARY` 按钮使用最明确的无模糊深墨硬偏移底板；普通按钮保留更轻的同类实体投影，弱化操作可以保持平面。hover 的纸片展开并保留约 `5px` 到 `6px` 投影，pressed 回缩且底板收短到约 `1px` 到 `2px`，形成纸卡被按下的触觉。
- 选中态使用低饱和印刷青纸面；品红主要保留给键盘/手柄焦点边框，避免“已选择”和“当前焦点”混用同一信号。
- 键盘/手柄 focus 通过 `features/asset_library/resources/shaders/ui/button_focus_dash.gdshader` 显示移动虚线圆角描边，半径、线宽、虚线密度和速度由 UI 色板引用的 GF Profile 控制；焦点环必须内嵌在按钮稳定包络中，hover 不冒充 focus，默认态必须隐藏。
- focus 要比 hover 更清楚，方便键盘和手柄导航。
- pressed 反馈要短、明确，不要像 selected 状态。
- 禁用态降低透明度和对比，不改变布局尺寸。

## 动效

动效要像轻量印刷游戏界面：短、清楚、机械感强。

目标达成和新纪录使用主题化庆祝 VFX。运行时由 `GameCelebrationConfettiEmitter` 以有界 `GPUParticles2D` 发射彩带：`GameCelebrationVfxTheme` 选择单片绘制 shader 与参数 Profile，Profile 只定义 `col0..col7`、`edge_strength` 和 `grain_strength`；`GameCelebrationVfxPreset` 定义事件时长、透明度以及粒子速度、摆动、旋转、尺寸和宽高比。单片 canvas shader 必须保持常数级绘制，不得使用内建 `TIME` 或在 fragment 中模拟整场粒子运动；运动由粒子系统负责。`FULL`、`REDUCED`、`MINIMAL` 的彩带上限分别为 64、32、0，减少动态或关闭 Shader 时也为 0，权威规则见 `features/themes/docs/feedback_performance_matrix.md`。新增主题不得在 `GameCelebrationVfxUtility` 中增加新的硬编码颜色、速度或数量常量。

时间范围：

- 新方块出现：约 `0.09s` 到 `0.12s`，以全不透明、略放大和轻微旋转的纸片姿态落定；不再从透明小点淡入。
- 合并：约 `0.16s` 到 `0.20s`，短暂放大和旋转后回到原位，数值成长可与落定并行。
- 移动：基准 `0.14s`，使用 `QUAD OUT` 保持路径可读；质量档位只能通过统一反馈预算缩短。
- hover / focus：约 `0.06s` 到 `0.12s`。
- 列表或子项 reveal：约 `0.10s` 到 `0.18s`。
- 面板 intro：约 `0.16s` 到 `0.24s`。
- 菜单首屏和任务弹层可以按“标题/主对象 → 信息 → 主动作 → 次要动作”的顺序做小间隔错峰入场，但总等待应短，不能让玩家等控件出现后才可操作。

统一 UI 动效语法：

- **按钮**：`BaseButton` 根节点只负责布局、命中、文字与焦点，scale、position 和 modulate 始终保持基础值。`GameButtonMotionPresenter` 在其内部稳定包络中绘制纸片：静止态预留约 `8px` 到 `32px` 水平 motion gutter；hover/focus 首帧换为印刷青和米白粗描边，约 `58ms` 展开并按指针接触侧轻微倾斜，再用约 `92ms` 回正；pressed 在约 `52ms` 内回缩到接近静止几何、下沉并收短硬投影，释放后依据当前 hover/focus/selected 状态恢复。状态优先级为 `disabled > pressed > selected > hover/focus > rest`，按住后移出或失焦不得提前取消 pressed；运行时改变 `disabled` 必须在下一帧清除陈旧的按压、hover 和焦点表现。
- **切换控件**：开关、分段按钮和可选卡片只沿其状态轴移动一次，轨道/纸面颜色与滑块或选中标记同步落定；selected 表示持久状态，品红 focus 边框表示当前输入位置，两者不能互相替代。
- **列表与分页**：只对本次新创建且可见的条目按阅读顺序错峰出现，单项约 `0.10s` 到 `0.18s`，相邻间隔保持很小；刷新已有数据不得让整页反复重播。拥有稳定业务 ID 的图鉴、配方、成就、档案与排行榜采用 keyed cache 原位更新，保留节点、选择和焦点；只在真正删除业务项时释放节点。超长回放列表继续使用 `GFVirtualListModel` / `GFVirtualListFocusModel` 维护有界窗口，`GFRepeaterBinder` 只负责无身份要求的模板物化，不把它误当 keyed reconciliation。结构变化后由 `GFControlFocusUtility` 重建焦点顺序。跨帧分页必须保存不可变请求快照，只允许最新 generation 原子替换条目、页码和焦点；旧任务只能清理自己的临时结果。
- **滚动条**：静止时保持低对比，指针进入、键盘滚动或拖拽时短促增亮或加宽，停止交互后平稳恢复；滑块位置必须直接跟随真实滚动值，不使用滞后、回弹或装饰性假进度。可交互根节点的尺寸、scale、focus 与命中几何始终稳定且满足 44px 触控契约；缩放或透明度动画只作用于 `MOUSE_FILTER_IGNORE` 的内部视觉层。GF 不提供滚动条表现动画，该行为由 `GameUiMotionUtility` 绑定项目控件。
- **弹层**：遮罩和任务卡分层进入；遮罩先建立阻断关系，任务卡再以一个主方向的小位移、轻微缩放和错峰内容落定。两者必须由同一个 modal-level 句柄和 generation 原子拥有；完成、取消、反向、owner 退出与减少动态都要同时 settle，迟到回调不得改写新一代状态。关闭开始立即冻结任务卡输入，每一代只允许一次业务提交；退出动画完成并确认原 panel 已离场后才发布终态，不能用全屏场景擦除代替普通弹层。任务卡宽度必须钳制在视口安全边距内；横排动作不足以保留每项 `112×44px` 时改为纵排，不允许固定桌面宽度撑破 320/360/390px 手机视口。
- **异步状态**：低于主题 `ui.loading.delay` 的瞬时工作不显示 Loading，超时后才显示稳定文字或局部指示；成功原位替换内容，失败把错误留在触发区域并提供静态颜色/文案，迟到 generation 不得覆盖新状态。进度只反映真实 determinate 值；没有可计算进度时使用明确的“不确定/等待”文案，不伪造百分比。
- **首页开场**：正式启动完成后，先建立纸面背景，再由 `2 / 0 / 4 / 8` 方块和微型棋盘完成一次短组装；十个菜单按钮按阅读顺序约每项 `32ms` 错峰，从左右空间锚点以纸片“发牌”方式撞入并短回摆，外层命中框不移动。发牌继承按钮当下的 focus/selected/disabled 语义，不得强制回到 rest；任何 hover、focus 或 press 输入都必须同时接管纸片和文字，不能留下延迟隐藏文字。开场未落定时，未揭示控件不得获得命中或焦点；首个规范化动作 token 只精确完成演出并被消费，下一 token 才能执行业务。减少动态初始即为 settled，不得隐藏地多吞一次输入。主动作最后落定并取得焦点。开场不轮播图鉴、试验台、档案或模式页面；首次进入可播放完整编排，再次返回使用短版本。
- **减少动态**：不延迟状态提交，也不等待不可见 Tween；按钮、列表、滚动条、弹层和首页开场直接落到稳定终态，保留焦点、选中、禁用和遮罩等非运动信号。常规动效不得成为理解状态、完成操作或恢复焦点的前置条件。

GF 与项目边界：

- `GFUIRouterUtility`、`GFUIRoute` 和 `GFUIUtility` 拥有稳定 route ID、逻辑层、Modal 栈、遮挡、返回、焦点恢复，以及面板提交前的 owner/`GFAsyncScope` 取消、预加载、并发去重和 typed operation 终态；项目 `GameUiRouterUtility` 只补默认预算与“提交后 owner 同帧退出”的精确实例回滚。路由 metadata 可以声明项目 motion profile，但 GF 路由不实现具体视觉时间线。需要退场动画的页面先由项目动效完成，再调用 `back()`，调用方必须等待 route result，不能 fire-and-forget。
- `GFScreenTransitionUtility` 和主题提供的 `GFScreenTransitionEffect` 只用于启动完成后的主场景 cover/load/reveal。它是单一全屏覆盖层，不能用于按钮、滚动条、列表、页内切换或并行弹层。
- `GameUiMotionProfile` 是视觉主题拥有的语义参数资源；Button、Panel、Modal、List、Content、Number、Scroll，以及 Toast、Loading、Progress、Local Error、Reward Result 的默认节拍都从该资源查询。`GameUiMotionUtility` 统一拥有这些局部可取消 Tween、retarget、`complete_now()` 和减少动态静态终态；页面只能选择语义，不自行散落时长、缓动与 Tween 元数据。
- `GFNotificationUtility` 仍唯一拥有 priority、dedupe、队列上限与通知生命周期；当前 vendored GF 的 dedupe 契约不产生 aggregate 字段或更新信号。`FeedbackRail` 只呈现当前 record，轨道的 `VBoxContainer` 子槽保持布局稳定；进入首帧保持实色可读，只对槽内表面做短位移与退出淡出，迟到 finished 以通知 ID 拦截。
- 首页开场若需要可跳过的多阶段串并行时间线，可以使用绑定首页节点生命周期的独立 `GFActionQueueSystem` 命名队列；标题、棋盘、菜单锚点、节拍、最终态和跳过策略仍归项目，且不得复用玩法棋盘队列。`GFReactiveStateStore` 不用于 hover、滚动条透明度或 Tween progress 等瞬时表现状态。
- `easings.net` 与 Motion 等外部前端仓库只作为缓动曲线、可中断状态、列表 stagger、布局连续性和 reduced-motion 的设计参考；项目不得复制 GPL 实现或引入 Web 动画运行时，所有采纳行为都要重新表达为 Godot Tween、GF 队列与项目语义参数。

行为规则：

- 不使用 blur、glow、长淡入和大位移作为默认动效。
- 同一元素不要同时叠加大位移、大缩放和强粒子。
- Container 管理的子控件不能被动效改写最终位置；按钮可见变换只能发生在内部 Presenter，并且纸片、倾斜包围盒、粗描边、硬投影和内嵌焦点环都必须留在根按钮及最近裁剪祖先的安全包络内。
- 隐藏子控件不播放 reveal。
- 动画不能成为状态可读性的唯一来源。
- 暂停菜单、目标达成和游戏结束等 `SceneTree.paused` 期间可见的 UI Tween 必须使用暂停时仍处理的模式；否则截图、键盘导航和真实玩家都会看到只出现一半的弹层。减少动态时应直接落到最终可读状态。
- 每次有效移动只编排一次整批反馈：普通 `MOVE` 只使用约 `4.5px / 0.25° / 150ms` 的根节点确认和轻触觉，不启动背景 Shader、边缘冲击、Backdrop 或 GF Shake；`MERGE` 及以上才使用完整强调通道。棋盘从基准位连续到达峰值再回到基准位，禁止输入当帧先跳到峰值。
- `BoardMotionBackdrop` 位于棋盘后层，常态只绘制低对比局部棋格。普通移动不生成纸片、不旋转棋格；合并及以上反馈才按动态预算旋转棋格并在后层绘制无描边纸片：近方形棋盘可累计最多 `±90°`，宽矩形棋盘只做不超过 `6°` 的短促受力并回正，避免交换长宽轴；高价值反馈只增加纸片数量与行程，棋盘倾角封顶约 `5.5°`。
- 层级固定为：全屏纸纹、局部棋格与后层纸片、棋盘硬阴影、棋盘与格槽、方块硬阴影与方块、屏幕空间 HUD。普通生成与合并不在方块前景绘制会遮住数字的碎片；分数增量只在顶部 HUD 呈现，不在方块上叠加浮动文字。
- 合并冲击先更新目标定义，再用约 `0.13s` 的数值与色阶成长反馈连接旧值和新值；HUD 分数反馈稍晚于棋盘冲击，形成明确因果顺序。
- GF 通知和回合字幕共用屏幕边缘 `FeedbackRail`：横屏位于棋盘右侧，并由棋盘实际世界包围盒宽高比动态求解 fit inset；竖屏位于棋盘与触控区之间。翻译文本不得携带语义颜色 BBCode，提示表面负责对比度和优先级边框；普通回合字幕不重复缩放脉冲。反馈轨与操作栏必须避开棋盘矩形外扩 `50px` 的冲量/旋转安全包络，棋盘几何变化后必须立即重算。

## 测试与验证

视觉验证的命令、跨视口截图矩阵、人工签字要求和安全运行策略统一以 [`docs/validation.md`](./validation.md) 为准，活跃改进项统一进入 [`docs/roadmap.md`](./roadmap.md)。本规范只维护视觉与动效契约，不复制测试库存、某次截图结果或待办清单。

视觉改动必须同时验证主题资源合同、Shader 参数所有权、方块数字可读性、稳定 44px 命中根、键盘/手柄焦点、Reduced Motion 静态终态以及多视口裁切。自动测试通过不能替代真实截图与人工检查。
