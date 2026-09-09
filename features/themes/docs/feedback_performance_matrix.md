# 反馈性能与无障碍矩阵

本文定义棋盘反馈、庆祝效果、UI 动效和场景转场的统一预算。它是运行时硬约束和验收目标，不是已完成的设备实测报告。

## 所有权

- `GameBoardFeedbackProfile` 只保存领域事件到 `GameFeedbackRecipe` 的语义映射。
- `GameFeedbackPerformanceMatrix` 只把 `GameAccessibilityState` 投影成不可变的 `GameFeedbackBudget`。
- `GameplayAcceptanceMatrix` 声明输入方式、视口尺寸、棋盘规模、质量档位和 P95 门槛，并只用 `GFMetricSeries` 的真实采样生成通过/失败结论。
- `GameBoardFeedbackUtility`、`GameCelebrationVfxUtility`、`GameUiMotionUtility` 和 `SceneRouterSystem` 消费同一无障碍状态；它们不能自行发明第二套档位。
- `GFSettingsUtility` 负责设置持久化，`GFSignalUtility` 负责设置变更的连接所有权；Shader、Shake、Haptic、Action Queue 和对象池继续由对应 GF Utility 拥有。
- 表现只消费已经提交的 `TurnResult` 或领域事件，不能写回棋盘、推进 gameplay RNG 或改变回放 checkpoint。

## 运行时硬预算

| 档位 | 动作幅度 | 时长倍率 | 粒子倍率 | 冲击边缘数 | 碎片数 | 同时 burst | 彩带数 | 背景/庆祝 Shader |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `FULL` | 1.00 | 1.00 | 1.00 | 18 | 8 | 8 | 64 | 开启 |
| `REDUCED` | 0.70 | 0.85 | 0.55 | 10 | 5 | 5 | 32 | 开启 |
| `MINIMAL` | 0.25 | 0.65 | 0.20 | 3 | 2 | 2 | 0 | 关闭 |

预算是上限，不是必须生成的数量。池耗尽、素材缺失或同帧高密度事件时，按“装饰碎片 -> 冲击边缘 -> 背景扰动”的顺序降级；分数、结果文字、静态轮廓和必要声音不得因次要 VFX 饱和而丢失。

## 快速输入约束

- `REALTIME_RETARGET` 取消 GF 命名棋盘 Action Queue 中的旧位移动作，保留现存方块当前像素位置并校准已经提交的身份与数值。下一方向从当前位置连续接管；未参与下一次移动的方块仍继续到达原目标，无效方向不能把它们留在格间。
- GF 棋盘队列只等待位移与碰撞时刻的值提交；生成、合并脉冲与局部装饰由 Tile 持有，不阻塞后续动作。取消时失效的碰撞回调不得覆盖后续回合或池复用节点。方块数字直接显示碰撞后权威值，不播放不存在的中间数值。
- 当前主题保持整盘位置、旋转和缩放稳定，普通移动、合并与纪录都不启动根节点、背板或边缘冲击；反馈集中于运动路径、合并方块的短脉冲、颜色和语义音频。
- 快速重定向不得序列化或恢复棋盘快照，不得释放整盘方块后再从对象池逐个获取，也不得重新创建视觉语义没有变化的 Shader、材质或样式。
- HUD 分数反馈使用单一 GF 异步等待窗口；窗口内的多次变化合并为“首次旧值 -> 最新值”，不得为每次加分分别保留延迟协程。
- 每回合热路径不得仅为日志执行额外棋盘扫描；高频诊断必须使用 GF Metrics 的聚合采样，不能同步输出逐回合消息。
- `test_gameplay_input_mapping.gd` 以 120 次连续实时重定向和 120 次连续加分守护这些约束；正式设备性能仍按下方矩阵记录 P50、P95 和 P99。

## 无障碍覆盖

| 状态 | 强制行为 |
| --- | --- |
| 减少动态 | 动作幅度为 0、时长倍率不高于 0.55、冲击边缘为 0、碎片不高于 1、彩带为 0、背景与庆祝 Shader 关闭；UI 不创建 Tween，场景转场保留 cover/swap/reveal 语义但以零时长静态遮罩执行。 |
| 关闭 Shader | 背景和庆祝 Shader、彩带关闭；保留静态颜色、轮廓、文字和声音反馈。 |
| 关闭震动 | 不调用 Haptic；不改变 Shake、声音、文字或领域结果。 |
| 高对比反馈 | 使用 recipe 的 `high_contrast_color` 和非色彩轮廓；不改变规则、分数、随机流或资格。 |

无障碍设置优先于视觉档位。任何组合都必须保持同一 seed/命令序列的 canonical state 与回放 checkpoint 完全一致。

## 语义音频

- `GameAudioTheme` 把 `TurnResult` 归约为一个主事件：移动、受阻、合并、连续合并、转化或目标达成；一次回合不再叠加移动、合并和生成三组声音。
- `GameThemeUtility` 使用 `GFAudioEvent` 发布事件，并携带方向、合并数、生成数、转化数、分数增量和最大合并值。原生 Godot 音频与未来第三方后端消费同一事件契约。
- 细分事件使用 `GFAudioBank` 的 `/` 层级回退，例如 `tile/merge/chain` 在没有专属素材时回退到 `tile/merge`。新增语义不要求复制音频文件。
- 局部方块 VFX 可以独立降级或关闭，主音频不能依赖粒子、Shader 或反馈画布是否可用。

## 验收目标

以下门槛由 `GameplayAcceptanceMatrix` 执行。结果必须连同设备、构建、渲染后端、棋盘规模和档位记录；两条指标各少于 120 个样本时返回 `insufficient_samples`，不得标记为“已达标”。

| 目标环境 | 场景与档位 | 帧时目标 | 交互目标 |
| --- | --- | --- | --- |
| Steam 桌面，1920x1080 | 4x4 常规对局，`FULL` | P95 不高于 16.667 ms | 有效输入到首个主要反馈 P95 小于 50 ms |
| Steam 手柄，1280x720 | 32x32 边界、256 个有效格的不规则棋盘，`FULL` | P95 不高于 16.667 ms | 手柄输入到首个主要反馈 P95 小于 50 ms |
| Web，960x540 | 12x8 长方形棋盘，`REDUCED` | P95 不高于 20 ms | 键鼠输入到首个主要反馈 P95 小于 50 ms |
| 微信小游戏默认 16:9 目标机（根 Viewport 实测 1280x720） | 4x4 常规对局，正式默认 `MINIMAL` | P95 不高于 25 ms | 触控目标不小于 44px，首个绘制反馈 P95 小于 50 ms |
| 微信小游戏横屏压力场景，1280x720 | 12x8 边界、72 个有效格，`REDUCED` | P95 不高于 25 ms | 触控目标不小于 44px，首个绘制反馈 P95 小于 50 ms |
| 手机竖屏，390x844 | 6x10 边界、48 个有效格，`REDUCED` | P95 不高于 25 ms | 触控目标不小于 44px，首反馈 P95 小于 50 ms |
| 低端移动端，360x640 | 20x30 边界、180 个有效格的稀疏棋盘，`MINIMAL` | P95 不高于 33.3 ms | 保留文字、轮廓和声音的语义可读性 |

正式报告至少记录 P50、P95、P99 帧时、首反馈延迟、单帧峰值、对象池峰值/耗尽次数和活动 Action 数。帧时与首反馈延迟使用 `GFMetricSeries`，矩阵契约通过 `GameDiagnosticsUtility` 进入 GF Diagnostics 和 Support Report，尚无实测时明确输出 `measurement_status = not_measured`。只有 profiling 证明收益后，才允许引入 dirty-cell 或其他额外复杂度。

运行时证据默认关闭，并复用设置页的“本地性能轨迹”显式同意。开发 Console 通过 `acceptance.begin <case_id> <observed JSON object>` 开始窗口；JSON 必须完整声明平台、输入方式、根视口、紧凑布局偏好、棋盘边界、有效格数量、形态和 VFX 档位，触控用例还必须声明实际最小触控目标。矩阵逐字段匹配后只保留这份脱敏白名单，额外字段不会进入内存或支持报告，自动回放会直接拒绝验收窗口，不能冒充玩家输入。`wechat_touch_default` 只覆盖当前 16:9 目标机观测到的 1280x720 根 Viewport；项目使用 `canvas_items/expand`，其他设备宽高比必须按 `get_visible_rect()` 的实际逻辑尺寸新增并精确匹配用例，不能沿用本用例签署。`BoardWorldViewportController` 只在对局视图已经初始化时标记玩家可见帧边界，`GamePerformanceTraceUtility` 用共享 `GFClock` 的相邻单调 tick 计算真实墙钟帧间隔，避免把受 `Engine.time_scale` 影响的游戏 delta 当成帧时；输入延迟从触控进入项目且尚未调用 GF virtual pulse，或键盘/手柄触发 GF `action_started` 的时刻开始，经 `PlayerInputSystem` 和移动尝试贯穿同步回合计算。`BoardAnimationAction` 提交首批可见状态后只挂接一次 `RenderingServer.frame_post_draw`，下一次实际绘制完成才写入首反馈样本；音频可独立播放，但不能提前结束视觉指标。没有真实输入收据、动作无效、场景退出或迟到绘制时不会产出可签署样本。

两条 `GFMetricSeries` 各自最多保留 256 个样本，与既有 96 条 / 96 KiB 的 GF Session Trace 预算独立。执行 `acceptance.end` 后才允许矩阵签署结论：没有窗口为 `not_measured`；采样尚在进行、少于 120 个样本或视口等条件中途漂移为 `partial`，并输出规范原因；只有窗口终结、条件仍匹配且两条序列均达到样本门槛时为 `evaluated`。撤回同意、新对局和 Utility dispose 会清空 Observation 与两条序列，不允许跨会话拼接证据。
