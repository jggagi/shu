# Tingyu Corridor — Ambient Life Second Adopter

> 本文保留首轮生趣及位置修订的历史记录。当前摸猫、频率、桌面走动与遮蔽落点已继续修订，最新实现和验证见[猫常来与桌面走动](TINGYU_CAT_DESK_SLICE.md)及[完整实施](TINGYU_COMPLETE_SLICE.md)；下文历史参数与检查不代表最新版本。

客户端日期 2026-10-06。本地切片从最新 `origin/main` 的 `0589f5eedd64b3a1d528500bba320d1e504caaa2` 开始，位于隔离 worktree `/Users/guoq/.codex/worktrees/tingyu-ambient-life-v1/shu`、分支 `codex/tingyu-ambient-life-v1`。原 checkout `/Users/guoq/Developer/shu` 仍在 `main` / `7f34a5347e60c87fb982df1fb3d488a41d4d4f40`，tracked 与未跟踪状态未改；本轮不 commit、push、建 PR、merge 或部署。

本轮验证同一个 `AmbientLifePresenter` 是否能通过薄 adapter 和场景能力接入第二个真实场景。PR #6 的 EnvironmentPresenter 接入保持原样；本轮没有修改 `scripts/ambient_life_presenter.gd`，没有创建 addon，也没有接入 Squirrel、Fish、鸡、蝴蝶或其他动物。

## 场景能力与适配器

`AmbientCapabilities` 由 `scenes/main.tscn` 声明，并在主 UI 建立时挂到 `cultivation_scene`。Tingyu adapter `scripts/tingyu_ambient_life.gd` 只读取该根节点下的 `BirdLane` 与 `CatSpot_*`：

| 节点 | 能力 | 场景语义 |
| --- | --- | --- |
| `BirdLane` | `birds: true` | 窗洞上方的远景天空，路径留在廊外山景一层。 |
| `CatSpot_SunnyThreshold` | `cat: true` | 右侧案几空台面的外侧、见晴处；`sunny=true`、`sheltered=false`。 |
| `CatSpot_Eave` | `cat_sheltered` | 右侧案几空台面、靠师傅一侧的檐下位置；`sunny=false`、`sheltered=true`。 |

未声明的 squirrel、fish 能力为 false。场景节点只表达落点和环境特性；天气筛选、foot-anchor、缩放、层级和姿态由 adapter 负责，没有新建 annotation 或导航框架。

Clear 天优先选见晴落点；Cloudy 可用一般落点；Light rain 的新猫事件只选 sheltered 落点，没有可避雨位置时由 presenter 的现有场景门槛拒绝。已有露天猫遇雨时在原落点短淡出，退场后等待下一次事件选点，不瞬间消失、移动或在天气转晴后重新闪现。鸟在 Clear 可偶发出现、Cloudy 机会更低、Light rain 关闭；只使用 1–2 只的当前场景调参。数值属于 `assets/data/tingyu_ambient_life.json` 的可调制作参数，不是新产品规格。

## 姿态、注意力与职责

猫复用已认可的水彩大橘图集和 foot pivot。新文件 `scripts/ambient_cat_motion.gd` 提取原有低频姿态时间表；后山与听雨廊 adapter 共用这段不含场景坐标的 idle pose 选择，spot、绘制位置和层级仍各自处理。后山摸摸回应保留在原 adapter；听雨廊本轮没有加入摸猫或宠物关系。

Tingyu 的 `foreground_attention_busy()` 读取主循环 `busy`、`state.dialogue_open`、`awaiting_continue` 与 `state.tea_active`。忙碌期间 scheduler 不开始新事件；已在飞行中的远鸟继续完成短航程；画面已有的猫固定回休息姿态。Static 隐去鸟、保留猫的 frame-zero 姿态并冻结 Ambient Life 时钟和当前透明度，包括淡入、淡出与遇雨退场；Dynamic 从同一呈现状态恢复。Ambient adapter 只读 `weather.presenter` 的真实时辰、天气、Dynamic 状态和宿主忙碌门，不改变 Environment 或 DemoState。

## 审核后修订（2026-10-06）

用户批准本次审核建议后，修正露天猫遇雨的瞬隐和 Static/Dynamic 切换的透明度跳变，全部留在 Tingyu adapter。首次体验仅调整固定 seed，保留原间隔和天气概率；当前配置无 Busy、持续卯时的调度模拟中，晴、多云、小雨的首次自然猫事件均约 51 秒。晴天首批鸟约 4 分 54 秒，多云约 16 分 18 秒，小雨关闭；30 分钟模拟中分别为 6、2、0 次鸟事件。它们是当前 seed 的可复查模拟结果，不是实际等待测量或永久频率承诺；玩家操作和 Busy 会影响事件顺序。

## 玩家反馈修订：猫的比例与落点（2026-10-06）

用户反馈“猫的大小和位置不太对”。当前按猫过小、檐下旧落点悬在盆景旁的画面问题调整：缩放从 0.52 到 1.3，晴天脚点从 `(1230,438)` 移到案几外侧 `(1290,472)`，雨天从 `(1320,410)` 移到案几内侧 `(1228,472)`。两处都使用现有绘画中可见的空台面；没有新增承托素材、玩法或调度行为。已在 Compatibility 实际窗口人工查看晴／雨的躺卧与抬头四张预览，位于 `.local/qa/tingyu-cat-placement-v2/`。这轮是位置与缩放的画面修订，未重跑下文自动回归；先前 148 项回归与 73 项渲染结果对应修订前的比例和落点。新画面仍待玩家认可。

## 验证与画面审阅

Godot `4.7.2.stable.official.ed1daf0bf`。本轮执行：

- `tests/ambient_life_presenter_test.gd`：通过；现有 presenter 行为、固定 seed、天气/capability gate、busy、Static/Dynamic 均覆盖。
- `tests/tingyu_ambient_life_test.gd`：148 项、0 失败；场景 marker/capability、晴雨选点、事件种子与忙碌门、完整 DemoState 前后快照、静态冻结、动态恢复和重置均覆盖。新增遇雨原地淡出、淡入／自然淡出／遇雨退场的 Static/Dynamic 透明度连续性、鸟在真实师傅 Busy 中继续航程、真实修炼 tween 自然完成、Tea 医案往事阅读 Busy，以及默认多云 75 秒内的非强制猫事件与重置重放检查。重置比较保留 DemoState 中单调递增的 `tea_session` 与 `tea_story_token` 失效计数器；Ambient 期间完整快照仍要求逐字段不变。
- `tests/back_mountain_ambient_life_test.gd`：通过；后山 pose 共用提取没有回归。
- `tests/weather_test.gd`：178 项、0 失败；既有时辰/天气、Static/Dynamic、修炼、师傅选择、Tea 物件与重置路径通过。
- `tests/tingyu_ambient_life_render.gd`：Apple M4 / macOS / Compatibility 实际窗口，73 项、17 张捕获、0 失败。包括真实师傅选择、Tea 首杯查看、晴猫、雨棚猫、远鸟、忙碌对白、Static、Dynamic 姿态和重置；新增遇雨淡出三阶段、部分透明度冻结／恢复、真实修炼 Busy、模拟自然猫事件与酉时小雨檐下猫。报告逐项记录检查结果；模拟自然事件通过加速 delta 驱动，不代表实际等待测量。

Render QA 原始图与 `render-report.json` 在忽略目录 `.local/qa/tingyu-ambient-life-v1/`：

- [01_clear_cat.png](../.local/qa/tingyu-ambient-life-v1/01_clear_cat.png)
- [02_rain_cat.png](../.local/qa/tingyu-ambient-life-v1/02_rain_cat.png)
- [03_birds.png](../.local/qa/tingyu-ambient-life-v1/03_birds.png)
- [04_dialogue_busy.png](../.local/qa/tingyu-ambient-life-v1/04_dialogue_busy.png)
- [05_tea_busy.png](../.local/qa/tingyu-ambient-life-v1/05_tea_busy.png)
- [06_static.png](../.local/qa/tingyu-ambient-life-v1/06_static.png)
- [07_dynamic_resume.png](../.local/qa/tingyu-ambient-life-v1/07_dynamic_resume.png)
- [10_rain_fade_mid.png](../.local/qa/tingyu-ambient-life-v1/10_rain_fade_mid.png)
- [12_static_partial_alpha.png](../.local/qa/tingyu-ambient-life-v1/12_static_partial_alpha.png)
- [13_dynamic_partial_alpha_resume.png](../.local/qa/tingyu-ambient-life-v1/13_dynamic_partial_alpha_resume.png)
- [14_real_train_busy.png](../.local/qa/tingyu-ambient-life-v1/14_real_train_busy.png)
- [15_simulated_cloudy_auto_cat.png](../.local/qa/tingyu-ambient-life-v1/15_simulated_cloudy_auto_cat.png)
- [16_you_rain_sheltered_cat.png](../.local/qa/tingyu-ambient-life-v1/16_you_rain_sheltered_cat.png)

位置修订前的画面审阅记录：已人工查看完整画面及猫、鸟局部：晴猫在右侧窗沿边，比例和脚点落在窗台结构上；雨猫缩在同侧较高的檐沿，和晴天点位有可见差别；远鸟小而淡，留在窗外山景上方，没有穿过人物或 HUD；师傅选项期间猫保持原位安静；Tea 物件界面隐藏 cultivation scene，动物没有显示在支线画面；Static/Dynamic 姿态差别可见。修订后人工复核遇雨原地淡出、部分透明度冻结／恢复、修炼 Busy 和模拟自然猫画面；酉时小雨下，檐下猫在右侧暖灯附近仍可辨认，保留当前调色供玩家判断。酉时截图使用呈现层时辰覆盖，不表示玩法时间已推进到酉时。自评结果支持继续交给玩家判断，不代表用户试玩认可。

## 未验收项与下一点

用户试玩认可仍待完成。当前不含听雨廊摸猫，不验证 Windows 实机、长时自然出现频率或低配性能；强制事件用于画面检查，另有加速 delta 的自然调度回归；尚未进行长时间真实等待试玩。具体落点、间隔、缩放、时长都是首轮制作参数，可以依据试玩修改。下一点仅请用户判断猫与远鸟是否自然融入听雨廊；认可前不抽取 `addons/shu_scene_runtime/`。
