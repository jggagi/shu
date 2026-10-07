# 听雨廊：从固定画景到有呼吸的场景

**案例日期：2026-10-07。** 听雨廊把一张固定山廊画扩成可停留的场景：时辰与天气映照在远山和窗外，风、雨、灯、茶烟和小生命都有各自节奏；师徒、桌案和 UI 仍清楚。下面记录的是一套可复用的制作思路，所有参数、坐标、出现节奏和验收状态都属于听雨廊。

## 可复用模块与场景适配

| 作用 | 蜀的共享模块 | 听雨廊适配 |
| --- | --- | --- |
| 时辰／天气映射与平滑组合 | [EnvironmentPresenter](../../../../scripts/environment_presenter.gd)，由后山环境和听雨廊共用 | [weather.gd](../../../../scripts/weather.gd) 读 DemoState.time_index，绑定听雨廊 profile、图层、灯光、风雨与 reset；配置见 [tingyu_environment.json](../../../../assets/data/tingyu_environment.json) |
| 生趣机会调度 | [AmbientLifePresenter](../../../../scripts/ambient_life_presenter.gd)，由后山生趣和听雨廊共用 | [tingyu_ambient_life.gd](../../../../scripts/tingyu_ambient_life.gd) 读取听雨廊的实际路径／落点能力，负责该场景的鸟、猫素材、动画、热点和调度；见 [tingyu_ambient_life.json](../../../../assets/data/tingyu_ambient_life.json) |
| 游戏状态与前景忙碌 | [DemoState](../../../../scripts/demo_state.gd) 是游戏状态来源；[main.gd](../../../../scripts/main.gd) 连接场景回调 | Adapter 观察宿主时辰、天气、行动和对白忙碌状态；表现逻辑不结算修为、精力、时间或剧情 |
| 声音播放 | 无跨场景声音模块 | [tingyu_ambient_audio.gd](../../../../scripts/tingyu_ambient_audio.gd) 读取真实天气／动作事件，并按 Static、Reset 与离场处理播放和待播声音 |

复用的是两个 presenter 的边界与职责；profile、坐标、marker、图层、mask、音频素材、猫路径和局部 shader 都仍是场景绑定。后山对应适配器是 [back_mountain_environment.gd](../../../../scripts/back_mountain_environment.gd) 与 [back_mountain_ambient_life.gd](../../../../scripts/back_mountain_ambient_life.gd)。这不是 addon，也不需要把场景脚本复制到 skill。

## Resident motion and interaction

师徒呼吸、眨眼和行动姿态只呈现宿主已经开始的行动；行动结算仍在 [DemoState](../../../../scripts/demo_state.gd)。猫可在有遮蔽的桌面出现、沿场景路径短程走动、停下坐卧并响应点击；热点按当前姿态边界更新。v2 自定义指针是掌心向下、手指并拢微弯的手形，光标素材来源记录中的热区为 (8,24)。当前听雨廊有猫的实际可交互实现；新场景必须重新确认生境与交互边界。

相关适配与美术：[tingyu_ambient_life.gd](../../../../scripts/tingyu_ambient_life.gd)、[tingyu_cat_desk_motion.gd](../../../../scripts/tingyu_cat_desk_motion.gd)、[tingyu_actor_life.gd](../../../../scripts/tingyu_actor_life.gd)、[猫姿态布局](../../../../assets/art/ambient_life/orange-cat-layout-v2.json)、[桌面猫布局](../../../../assets/art/ambient_life/tingyu-cat-desk-layout-v1.json)、[指针 v2](../../../../assets/art/ui/cat-pet-cursor-v2.svg)、[指针热区来源](../../../../assets/art/ui/cat-pet-cursor-v2-source.json)。

## 效果与实现索引

| 玩家看到／听到 | 配置 | 运行与素材 |
| --- | --- | --- |
| 六个时辰与晴／云／小雨的综合色调、远山雾、窗光、雨后湿色 | [tingyu_environment.json](../../../../assets/data/tingyu_environment.json)：time_profiles、weather_profiles、mist_layers、window_light、wetness | [weather.gd](../../../../scripts/weather.gd)、[ambient.gdshader](../../../../assets/shaders/ambient.gdshader)、[mist.gdshader](../../../../assets/shaders/mist.gdshader)、[rain.gdshader](../../../../assets/shaders/rain.gdshader)、[weather.json](../../../../assets/data/weather.json)；背景为 [tingyu-veranda-v2.png](../../../../assets/art/v2/tingyu-veranda-v2.png) |
| 一阵连贯的风先带竹叶、再带帘穗；叶响跟随实际风力 | tingyu_environment.json 的 wind_moments、ambient_audio | weather.gd、[bamboo_wind.gdshader](../../../../assets/shaders/bamboo_wind.gdshader)、[bamboo-wind-v3.png](../../../../assets/art/weather3/bamboo-wind-v3.png)、[leaf-rustle.wav](../../../../assets/audio/tingyu/leaf-rustle.wav) |
| 窗洞檐口积水、短滴落下，停雨后留少量余滴 | tingyu_environment.json 的 eave_drips | weather.gd、[eave_drips.gdshader](../../../../assets/shaders/eave_drips.gdshader)、[eave-drop-1.wav](../../../../assets/audio/tingyu/eave-drop-1.wav) 与 [eave-drop-2.wav](../../../../assets/audio/tingyu/eave-drop-2.wav) |
| 黄昏灯罩和邻近木面转暖，窗外仍偏冷 | tingyu_environment.json 的 lantern_light 与时辰 profile | weather.gd、ambient.gdshader；灯位贴合听雨廊原画 [tingyu-veranda-v2.png](../../../../assets/art/v2/tingyu-veranda-v2.png) |
| 茶盏热气和香炉细烟随风微偏 | tingyu_environment.json 的 tea_steam、incense_smoke；香炉几何在 [layout.json](../../../../assets/data/layout.json) | weather.gd、[tea_steam.gdshader](../../../../assets/shaders/tea_steam.gdshader)、[incense_smoke.gdshader](../../../../assets/shaders/incense_smoke.gdshader)、[desk-v2.png](../../../../assets/art/v2/desk-v2.png) |
| 师徒呼吸、眨眼和行动姿态只反映已发生的宿主行动 | 动作时长／呼吸幅度在 tingyu_actor_life.gd；tingyu_life.json 仅保存器物与休息叙述，不能当作角色动画配置 | [tingyu_actor_life.gd](../../../../scripts/tingyu_actor_life.gd)、[角色来源记录](../../../../assets/art/tingyu_actors/source.json)、[main.gd](../../../../scripts/main.gd)；不改 DemoState 结算 |
| 猫在遮蔽桌面短程走动，停下、坐卧、可摸；热点随姿态边界更新 | [tingyu_ambient_life.json](../../../../assets/data/tingyu_ambient_life.json)、[猫桌面布局](../../../../assets/art/ambient_life/tingyu-cat-desk-layout-v1.json)、[猫姿态布局](../../../../assets/art/ambient_life/orange-cat-layout-v2.json) | tingyu_ambient_life.gd、[tingyu_cat_desk_motion.gd](../../../../scripts/tingyu_cat_desk_motion.gd)、[猫桌面图层](../../../../assets/art/ambient_life/tingyu-cat-desk-v1.png)、[猫姿态图集](../../../../assets/art/ambient_life/orange-cat-painterly-v2.png) |
| 声音与真实事件对应：雨循环、风起叶响、檐滴触地、行动衣料、摸猫呼噜、鸟声 | tingyu_environment.json 的 ambient_audio | [tingyu_ambient_audio.gd](../../../../scripts/tingyu_ambient_audio.gd)、[音频来源记录](../../../../assets/audio/tingyu/source.json)、[main.gd](../../../../scripts/main.gd) 的行动和摸猫回调 |

### 新固定画景的交接清单

- 先看实际画面与 scene tree：主体、窗洞／桌面边界、前后层、透明边缘、UI 和可供小生命落脚的真实区域。
- 标出宿主实际提供的时间、天气、行动和 Busy 信号。EnvironmentPresenter 当前接受 mao、chen、si、wu、shen、you 六时辰及 clear、cloudy、light_rain 三天气；先核对新宿主是否适用这些语义，再写 profile／adapter 映射。增加任意新 ID 需要先检查模块的模型边界，并非只换 JSON 即可；玩法时间仍由宿主提供。
- 明确 Static：保留已出现的画面和静止居民，冻结所选动态与其呈现 elapsed；恢复后从冻结姿态接续。此例中，用户主动要求的 profile 转换单独推进，即使风雨运动冻结也可完成。Reset 和离场要清空／收束的内容也要逐项明确。
- 先在实际窗口确认原画构图，再加少量效果。逐一检查 mask、锚点、遮挡、人物脸和 UI；坐标、alpha、频率、音量、天气密度、首次出现时间都重新按新画面调。
- 生趣按真实 scene capability 决定：听雨廊有遮蔽桌面及猫路径，所以猫可雨中留在桌面并可交互；后山没有可复用的雨棚猫位。不要从 Tingyu 推出通用的猫频率、位置或雨天行为。
- 复用已选用的原画／姿态时保留来源；新增raster姿态沿用[game-art流程](../../game-art/SKILL.md)，记录alpha、atlas区域、接触pivot、显示尺度和来源，先在实际场景校准。方法复用不自动授权新云端外发或切换生成provider。
- 让动作相位使用获准的呈现 elapsed delta；表现 adapter 只读状态，不建立第二套 gameplay authority。实际 Reset、Static／Resume、Busy、离场都要看声音、热点、淡入淡出和排队事件能否一致收尾。

## 已观察的问题与制作检查

- **帘穗曾被任务牌挡住。** 早期风切片要检查全图和局部，辨认主要／次级响应与UI遮挡；完整候选随后调整任务牌给帘穗留空间。新场景要对当前布局复核，不能把历史截图当作现状。
- **首轮檐滴太细。** 在 1152×720 的真实渲染里看不清；放大滴头并提亮后，再确认它仍落在窗洞开口且不覆盖人物／UI。
- **灯暖检查。** 听雨廊按原画灯罩和相邻木面制作有界暖色，保留深色灯框与人物可读性。新场景用实际时辰前后画面检查局部温差是否可辨认，并据试玩调强度。
- **香炉被桌面压扁。** 从桌案源图局部取香炉，用局部轮廓遮罩保留器物笔触，并用邻近裸桌木纹修补旧区域；烟从炉盖出发。这里的 crop、mask 和坐标绑定原图，不能直接搬到另一张桌子。
- **步态检查。** 使用逐姿态步行帧，并分别核对脚点、朝向、透明边、接触 pivot 和姿态比例；以真实桌面路径校准。姿势热点按当前 frame bounds 更新，不能用猫节点中心代替可见轮廓。
- **手形指针方向不合适。** 第一版抬手掌被用户拒绝。v2 改为掌心向下、手指并拢微弯，SVG 来源 JSON 精确记录接触点 (8,24)。新版已经加载并查看，但实际悬停／移出和用户认可仍待验；不把“形状注册成功”写成鼠标验收。
- **注意力协调检查。** 区分宿主前景 Busy 和场景内部显著事件状态；启动／调度时检查是否可以开始，推进已有事件时不要又把它自己的 salience 当作停止条件，否则它可能无法结束或释放门。可对照 [main.gd](../../../../scripts/main.gd) 中的 foreground_attention_busy、scene_life_attention_busy，以及 scene adapter 对两者的选择。

## 当前证据边界

[完整实施记录](../../../../docs/TINGYU_COMPLETE_SLICE.md)覆盖的是 2026-10-07 候选，不能把其中旧构建记录自动延伸到后续改动。风、檐滴、灯、香炉与猫的逐片记录分别见 [wind](../../../../docs/TINGYU_WIND_SLICE.md)、[eave drips](../../../../docs/TINGYU_EAVE_DRIPS_SLICE.md)、[lantern](../../../../docs/TINGYU_LANTERN_SLICE.md)、[incense](../../../../docs/TINGYU_INCENSE_SLICE.md)、[cat desk and cursor](../../../../docs/TINGYU_CAT_DESK_SLICE.md)。

- 实际 Godot 窗口／渲染帧、脚本回调、Web 导出和用户操作是不同证据。加速 delta 预览可定位效果状态，不证明自然等待间隔或长期运行。
- 最新 actor PNG 候选有原生姿态预览和 Web 输入复核；其 Web／Windows 导出发生在后续香炉与猫走动修订之前。Windows 实机运行、设备扬声器／耳机听感未验证。
- 香炉烟已获本轮「很好」反馈。猫移动与 v2 指针的本机渲染／资源加载记录，不等于用户完成实际指针悬停验收；完整候选的动作密度、声音与整体试玩仍需用户确认。
- 只把具体观察写成对应层级的证据；一个切片的正面反馈不自动覆盖后来修改或整个候选。

更多制作流程见 [game-painted-scene-build](../SKILL.md) 与 [game-ambient-life-build](../../game-ambient-life-build/SKILL.md)。

## 最新认可追记（2026-10-07）

用户在山门庭院任务中明确确认最新版听雨廊Web试玩收尾通过，更新此前Web／猫／光标与整体待试玩的阶段状态。Windows实机、设备听感及长时证据仍分别保留；此轮未重测听雨廊。下一实际复用案例见 [山门庭院](mountain-gate-courtyard.md)。
