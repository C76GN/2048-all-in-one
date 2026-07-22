# 追加检索轮次 B：官方实机视频观察

观察日期：2026-07-22（Asia/Shanghai）

计数：4 条

口径：仅计开发者本人上传且包含连续实际玩法画面的公开视频。浏览器实际打开播放页并核对标题、上传方、时长与所列画面；时间点链接用于复核，不以视频标题或缩略图代替观察。

## V-B01：GUNCHO Release Trailer

- 上传方：[Arnold Rauers](https://www.youtube.com/@ArnoldRauers)（开发者）
- 视频：[GUNCHO Release Trailer](https://www.youtube.com/watch?v=YaU11dBtIsY)，约 1:15
- 可复核时间点：[00:20](https://www.youtube.com/watch?v=YaU11dBtIsY&t=20s)
- 画面事实：固定斜俯视镜头把小型六角竞技场完整留在一屏；角色、敌人与环境障碍占据离散格。底部左轮弹巢以大尺寸独立 UI 显示装弹方向，玩家移动/射击后弹巢朝向变化，因此资源状态和空间方向可以同时读到。
- 表现与音频：命中使用短促位移、闪光、尘屑和明显枪声，不靠长镜头或满屏粒子遮住下一步状态；西部配乐持续托底，但预告混音不能代表移动设备外放或游戏内并发策略。
- 限制：剪辑会跳过思考和失败恢复，不能据此测量输入延迟、动画可取消性、GPU 成本或完整教程质量。

## V-B02：Card Thief Release Trailer

- 上传方：[Arnold Rauers](https://www.youtube.com/@ArnoldRauers)（开发者）
- 视频：[Card Thief Release Trailer](https://www.youtube.com/watch?v=ylapoYTM7G8)，约 0:55
- 可复核时间点：[00:18](https://www.youtube.com/watch?v=ylapoYTM7G8&t=18s)
- 画面事实：主要操作集中在 3×3 牌阵；玩家路线跨过相邻牌，守卫、火把、阴影与数值都保留在牌面上。路径尚未结算时就能看到路线形状和涉及对象，空间风险不依赖长文本说明。
- 表现与音频：牌面位移、翻转、烟雾和局部亮暗变化持续很短，背景基本静止；硬币、火把与守卫反馈拥有不同短音色。画面高对比但部分状态仍依赖颜色/亮度，未从视频证实色觉替代编码。
- 限制：预告没有展示设置、屏幕阅读语义、长局牌面拥挤或低端设备帧时间；不能从录音判断实际响度规范。

## V-B03：Dungeons of Dreadrock Nintendo Switch Trailer Europe

- 上传方：[Christoph Minnameier](https://www.youtube.com/@doctorfunfrock)（开发者）
- 视频：[Dungeons of Dreadrock Nintendo Switch Trailer Europe](https://www.youtube.com/watch?v=kv3L44IQd1U)，约 2:04
- 可复核时间点：[00:35](https://www.youtube.com/watch?v=kv3L44IQd1U&t=35s)
- 画面事实：一个地牢房间基本完整出现在竖向画面中央，角色与敌人按格移动；门、压力板、火球路径和墙体轮廓均在行动前可见。玩家移动后敌人立即响应，随后很快回到可判断静态局面。
- 表现与音频：像素角色用极短步进/受击帧、局部火焰和小范围震动表达结果，过场与文字框才提高视觉权重；环境音和短促机关/命中声分工清楚，但剪辑不足以证明动态范围或声音并发上限。
- 限制：视频展示的是精选关卡，不能证明 100 关的教学曲线、提示触发条件、手柄误输入处理或真实性能指标。

## V-B04：Tinyfolks Gameplay Trailer

- 上传方：[Vandermaesen Games](https://www.youtube.com/@pyairvander)（开发者）
- 视频：[Tinyfolks Gameplay Trailer](https://www.youtube.com/watch?v=y-cOxhrZAIc)，约 1:02
- 可复核时间点：[00:25](https://www.youtube.com/watch?v=y-cOxhrZAIc&t=25s)
- 画面事实：战斗使用近单色 1-bit 画面，队伍与敌人分列两侧，生命/状态和动作选择固定在稳定区域；城镇页也沿用同一有限色板与像素字号，内容变化没有改变主要信息位置。
- 表现与音频：角色攻击以几帧位移、闪白和小型像素爆发完成，胜负/升级才使用更大的标题和转场；chiptune 和短 SFX 与视觉颗粒一致。视频未展示减少闪烁或独立音量选项。
- 限制：录制画面只能证明视觉组织和相对节奏，不能证明小字号在 390×844、客厅距离、色觉差异或屏幕阅读器下可用，也不能把 1-bit 风格等同于低 GPU/内存成本。

## 跨视频结论与当前项目映射

| 观察 | 对当前项目的增量 | GF / 所有者 |
| --- | --- | --- |
| GUNCHO、Card Thief 在结算前展示方向/路径 | 当前已有确定性规则、回放和无效移动通知，可增加只读影响预览 | 规则查询归 gameplay；overlay 归 themes/gameplay；Shader 参数继续走 `GFShaderParameterUtility` |
| Dreadrock 每步后快速回到静态可读局面 | 现有三种快速输入策略需增加“减少动态时仍可判读”的验收 | `GFActionQueueSystem` 承载时序；节奏/Profile 与可访问性策略归项目 |
| Tinyfolks 用稳定版式承载大量内容 | 当前真实响应式布局是优势，应进一步验证字体、状态图标与窄屏信息优先级 | `GFUIRouterUtility`、binding/focus 复用；视觉层级归 navigation/settings |
| 四条视频都以短语义音色区分动作 | 当前 6 类 SFX 已资源化，增量是危险/预览/连锁层级及减少刺激策略 | `GFAudioUtility`/bank 复用；事件命名、素材、ducking 和设置归 themes/gameplay |

本轮没有从视频推断 Shader 源码、Tween 参数、对象池、渲染管线或帧预算。相关实现只有在开发者技术日志或固定提交源码补证后才能升级为实现事实。
