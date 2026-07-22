# Tinyfolks 深度产品分析

研究日期：2026-07-22（Asia/Shanghai）

类型：极简队伍管理 / 短局 RPG

证据：作者 itch.io、作者开发日志、Google Play 开发者页及作者上传实机视频；未下载或运行游戏。

## 产品与核心循环

Tinyfolks 在有限色板和固定版式中组织“建设城镇—招募/训练队伍—出征战斗—带回资源—继续建设”的循环。作者页面列出 20+ 职业、15+ 武器、20+ artifacts、7 座可升级建筑、13 个生物群系和 70+ 怪物；职业可以组合，建筑提供 craft、research 和一次性 bonus。内容量没有依靠不断扩张的主界面承载，而是把不同阶段放进稳定的城镇、队伍与战斗页面。

[作者实机 00:25](https://www.youtube.com/watch?v=y-cOxhrZAIc&t=25s) 可见：战斗双方固定分列两侧，生命/状态与动作选择保持在稳定区域；攻击只短暂移动角色和闪烁局部像素，随后立即恢复到可比较的阵型。这是“低素材预算不等于低信息密度”的有效样本。

## 表现：特效、Shader、动效

- itch.io 明确以 1-bit、minimalist、pixel art 标记视觉方向。近单色画面用轮廓、面积、位置和像素图标区分类别，而不是靠大量颜色层级。
- 攻击以几帧位移、闪白和小型像素爆发完成；胜负、升级或页面切换才使用更大的标题与转场，视觉预算与事件重要性匹配。
- 页面没有公开 Shader、调色、渲染分辨率、补间或批处理实现；“1-bit”是艺术约束，不是技术证明。若当前项目提供类似主题，仍需通过既有 Shader 参数与减少闪烁设置实现。

## 音效

作者页面将游戏标记为 chiptune，官方预告中持续芯片音乐与短促攻击/确认音保持同一颗粒感。没有一手资料说明作曲/音效负责人、动态音乐、事件 bank、并发限制或独立音量选项；视频也未展示静音、字幕化音效或听觉无障碍。因此可借鉴的是“声音密度与像素动效同样克制”，不是具体旋律或音色。

## UI/UX 与可访问性

- 城镇、队伍和战斗使用固定信息区，页面切换改变内容但不频繁重排主要控件；大量系统由图标、短标签和数字共同表达。
- 近单色带来强明暗对比，但小像素字号、闪白和仅靠图形语义也可能成为低视力或认知门槛。官方页面未声明高对比替代、字号、减少闪烁、键盘导航或屏幕阅读支持。
- itch 页面提供 HTML5、Windows、macOS 和 Linux 版本入口，并指向移动/Steam；广平台不等于输入与焦点体验等价，控制器、重绑和触控误操作恢复未证实。
- Google Play 的 Data safety 区域记录开发者声明“不与第三方共享数据、也不收集数据”。这是一手的产品隐私承诺，不是对所有历史版本/平台的独立审计；当前项目可借鉴公开边界与本地优先原则，而不是宣称已经验证对方实现。

## 玩法变体与功能设计

职业组合、武器、artifacts、建筑升级、生物群系和 Boss 在同一循环内形成多层 build。相比新增独立模式，这种设计让一次奖励选择同时影响队伍身份、短期战斗和城镇长期计划。当前项目已有 Recipe/Capability、内容目录、Profile 与多模式基础，却缺少真正的局内选择和短局 build。

可落地的最小实验应只有 3 个原创 modifier：在固定回合节点三选一，明确显示立即影响和持续时间，选择进入 snapshot、撤销与回放；先验证决策密度，再决定是否需要职业、装备或城镇等更重系统。

## 性能与低端线索

itch 页面提供可直接运行的 HTML5 版本，Windows 下载项约 117 MB，并覆盖 macOS、Linux 与移动入口。这些是一手的分发范围/包体线索，不是运行性能指标。有限色板、固定页面和少量同时角色可约束素材与画面并发，但 Unity 包体、浏览器运行、内存、帧时间和低端机型均无公开数据；不得把极简美术直接写成“性能优化”。

## 与当前项目比较及 GF 映射

| 发现 | 当前项目判断 | GF / 所有者 |
| --- | --- | --- |
| 20+ 职业与装备在固定循环组合 | 当前内容/存档基础更强，但缺局内少量选择 | Recipe/Capability 与 SaveGraph 可承载结果；职业、modifier、数值和平衡归项目 |
| 城镇、队伍、战斗保持稳定版式 | 当前响应式布局完善，可减少模式间重新学习 | focus/输入映射用 `GFInputMappingUtility`；页面 IA、控件语义与焦点顺序归项目 UI |
| 1-bit + 极短反馈维持高信息密度 | 可成为新增主题/低干扰表现参考，不复制素材 | Shader 参数走 `GFShaderParameterUtility`，队列走 `GFActionQueueSystem`，预热走 `GFRenderWarmupUtility` |
| chiptune 与短 SFX 统一颗粒 | 当前有 6 类 SFX、缺 BGM/自适应音频；先补层级和静音等设置 | 播放与 bank 用 `GFAudioUtility`；音乐、混音、字幕化声音和可访问性策略归项目 |
| 多平台但无公开性能指标 | 当前有明确 16.667 ms 预算，应保持证据标准 | 诊断工具可记录帧/内存；设备矩阵、阈值和发布门禁归项目 |
| Google Play 声明不收集/共享数据 | 当前有通用 diagnostics，但产品事件、留存与隐私摘要尚未成契约 | 默认本地、关闭/清除、事件 schema 与平台 Adapter 归项目；GF 不拥有产品隐私决策 |

## 可借鉴点、风险与证据限制

首选是“三选一 modifier + 稳定信息版式”的原创切片，并用保存、撤销、回放和相同 seed 验证确定性；第二优先才是低干扰主题和 BGM 层。产品诊断应另行发布人可读隐私摘要并默认本地。不要一次引入职业、装备、城镇、怪物和经济全套 RPG，也不要把 GF domain 组件误当成玩法所有者。预告与商店页无法证明长局信息负担、字号可读性、浏览器性能或触控恢复。

## 许可证与复用边界

Tinyfolks 是商业作品，作者 itch.io 与 Google Play 页面没有授予代码、Shader、像素图、字体、图标、音乐、音效、职业、怪物或数值表的再利用权。Data safety 是开发者声明的隐私信息，不改变许可边界。本报告只保留内容分层、固定版式、克制反馈和公开隐私边界等抽象设计证据。

## 一手来源

- [Pierre Vandermaesen：Tinyfolks itch.io](https://pierre-vandermaesen.itch.io/tinyfolks)
- [Tinyfolks 官方开发日志](https://pierre-vandermaesen.itch.io/tinyfolks/devlog)
- [Google Play：Tinyfolks（开发者页与 Data safety）](https://play.google.com/store/apps/details?hl=en&id=com.VandermaesenGames.Tinyfolks)
- [Vandermaesen Games：Tinyfolks Gameplay Trailer](https://www.youtube.com/watch?v=y-cOxhrZAIc)
