# R2-A 开发者与发行商实机视频观察

观察日期：2026-07-22（Asia/Shanghai）
范围：4 个由开发者或发行商上传、并能在连续片段中看到实际游戏状态的视频。没有下载视频、游戏或素材，也没有运行第三方程序。

## 观察方法

- 浏览器直接打开视频并定位到下列时间点，视觉事实只记录画面当时可见的棋盘、对象、HUD 和反馈。
- 时间点链接使用 YouTube `t=` 参数，点击即可复核。预告的剪辑、字幕和镜头可能为了展示而重排，不能代替对完整操作流程、性能或音频混音的实测。
- 本轮实际观察 **4 个官方视频、4 个可点击时间点**；每条至少有一个连续实机场景，不以封面、标题或搜索摘要计数。

## 01. Freshly Frosted — Early Preview

- 上传方：The Quantum Astrophysicists Guild（开发/发行团队）；[官方 press kit](https://www.qag.io/ffp/)嵌入同一视频。
- 视频：[YouTube](https://www.youtube.com/watch?v=YeUf4ILdQ_Y)；观察点：[00:22](https://www.youtube.com/watch?v=YeUf4ILdQ_Y&t=22s)。
- 画面事实：方形机器盘占据主体，格内箭头显示传送方向；原味、粉色和带糖霜甜甜圈同时沿路径移动，多个加工格喷出白色短暂烟团。棋盘外只保留紫色背景，没有大块计分或说明面板抢占空间。
- 对当前项目：方向、处理中和已完成状态应使用形状/对象状态与局部反馈共同编码；若做路径谜题，业务模拟与播放动画必须分离，回放只记录确定性操作。
- 限制：这是剪辑后的早期预览，不能确认关卡编辑操作、撤销入口、最终 UI 或发布版性能；本轮也没有独立评价旁白、音乐和 SFX。

## 02. Dorfromantik — Full Release Version 1.0 Trailer

- 上传方：Toukana Interactive（开发者）；上传频道与 [官方产品页](https://www.toukana.com/dorfromantik)一致。
- 视频：[YouTube](https://www.youtube.com/watch?v=gc8kT3WciJs)；观察点：[00:55](https://www.youtube.com/watch?v=gc8kT3WciJs&t=55s)。
- 画面事实：已生成的六角乡野地图被一圈白色可放置边界包围，下一块六角牌单独悬在右侧；地图上有小型任务标记，右上显示分数。镜头保持远景，村庄、林地、水道和田野仍可凭轮廓与色块区分。
- 对当前项目：把“下一对象、合法边界、局部任务、总目标”放进同一视野，能让空间规划无需频繁开菜单；月度挑战可复用现有 seed、回放和 SaveGraph。
- 限制：解释预告经过配音、字幕和剪辑，不能据此量化落牌 easing、长地图内存、相机性能或音频层级；也不能判定景深/阴影的具体 Shader 实现。

## 03. Stacklands — out now on Steam!

- 上传方：Sokpop Collective（开发者）；产品与版本资料见 [作者 itch.io](https://sokpop.itch.io/stacklands)。
- 视频：[YouTube](https://www.youtube.com/watch?v=7qpT2xXUaCs)；观察点：[00:15](https://www.youtube.com/watch?v=7qpT2xXUaCs&t=15s)。
- 画面事实：浅绿色桌面承载可重叠卡牌，右侧常驻蓝色 `House` Idea 卡并显示灯泡标记；字幕在实际盘面上解释“两块木头、一块石头”与村民堆叠后开始建造。配方说明与可操作对象没有切换到独立百科页面。
- 对当前项目：若试验空间配方，应在落位前直接显示需求、产物和失败原因，并让暂停、拖放和键盘/控制器走同一抽象动作；不应复制 Stacklands 的牌面、配方或经济。
- 限制：该时间点证明配方被嵌入实机说明，但不能证明所有堆叠命中规则、计时器顺序或拥挤局面的性能；音效也未单独核验。

## 04. Wilmot Works It Out — AVAILABLE NOW!

- 上传方：Finji（发行商）；[Finji 发布日志](https://finji.co/news/2024/10/23/wwio-out-now.html)嵌入同一视频并收录开发者设计说明。
- 视频：[YouTube](https://www.youtube.com/watch?v=syfKNCYnz_s)；观察点：[00:25](https://www.youtube.com/watch?v=syfKNCYnz_s&t=25s)。
- 画面事实：米色空场中央只有一组圆角方形拼块，局部图案已组成蓝白色人物/场景，Wilmot 自身也是同尺寸方块并位于拼图内部；画面不展示完成图、分数或复杂工具栏，玩家只能从边缘、颜色和局部图案推断关系。
- 对当前项目：可以借鉴“不给完整答案，但让局部关系足够可读”的分层提示；若用于有限步关卡，提示应逐层揭示约束而不是直接给出移动序列。
- 限制：发布预告是剪辑素材，不能从单帧判断拾取、推动、吸附手感、镜头缩放或完成判定；配乐与音乐同步结论只采用官方文字，不由该帧外推。

## 横向观察

四条视频共同呈现出一种比“堆更多全屏特效”更适合当前项目的反馈路线：把合法边界、方向、配方或局部关系直接画在对象附近；承诺操作后再用烟团、吸附或地块生长形成短仪式；HUD 只保留下一对象、目标和可逆操作。实现时可复用现有 `GFActionQueueSystem`、Shader 参数校验、音频事件、输入映射和确定性历史，规则与视觉配方继续由项目 Feature/主题拥有。
