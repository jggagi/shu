# 蜀山后山 · 独自修炼

切片 `back-mountain-demo-1`。用户已授权制作；独立表现实验，效果与参数待用户试玩，不升级为正式产品规格。实现基线 `35acdc0`，现有 dirty 内容保留；源码归档授权见文末。

## 要验证什么

固定中国画能否通过克制的风、空间、行动回应和时辰变化，成为愿意停留修炼的地方。没有新剧情、NPC、地图、战斗、休息、存档或声音。

## 实现合同

- 江砚秋 `player_yanqiu` 独坐石台；远山、中景、松树石台、人物／剑四层。视差使用 1440×900 设计坐标，幅度可调。
- 两处物件点击共用一个修炼入口；`DemoState.new()`、`train()` 与 `reset()` 是唯一数值权威，规则来自 `rules.json`。接受点击即结算一次，短演出后显示实际结果；busy 时重复点击与重置拒绝。
- 单独的阵风、薄雾、远处瀑布、少量落叶；人物呼吸、短眨眼、修炼闭眼与发梢微动。演出不承担数值结算。
- 养成时辰驱动场景光雾；环境时钟独立。UI 不参加场景染色。
- 静态模式保留当前时辰的色温／明暗／雾量，停止场景动态和视差；即时 hover 提示、修炼结算、结果和重置仍正常。切换不重启修炼、不改变数值。
- `back_mountain_training.json` 只放表现与布局参数，不复制养成规则。

## 复用边界

复用状态规则、人物 ID、现有画风参考、OFL 字体来源与渲染检查方式。后山控制器、雾／风／瀑布效果及新角色姿态为 scene-specific；旧雾 shader 绑定听雨廊窗户，不直接套用。没有修改 `main.gd`、`demo_state.gd`、现有天气、tea 流程或正式主场景。

美术选用与 SHA256 见 [source.json](../assets/art/back_mountain_training/source.json)，精确提示在 `art/prompts/back-mountain-*.txt`。`approved` 仅表示本实验制作选用，不表示用户美术验收。四张生成 PNG 原样保存，角色用 AtlasTexture 两格，剑为原创 SVG 占位素材。

使用独立 `ShuBackMountainSerif.ttf`，保持旧场景字库不动。原始 Noto Serif SC SHA256 与 OFL、实际 fontTools 版本见 [字体记录](../assets/fonts/source-back-mountain.json)；复现入口 `tools/rebuild_back_mountain_font.py`，不依赖本机绝对路径。

## 本轮文件

- 场景 `scenes/demos/back_mountain_training.tscn`、控制器 `scripts/back_mountain_training.gd`、参数 `assets/data/back_mountain_training.json`。
- `assets/art/back_mountain_training/`：`far.png`、`mid.png`、`near.png`、`actor-sheet.png`、`sword.svg`、`source.json`。
- 四个场景 shader：`back_mountain_mist.gdshader`、`back_mountain_hair_wind.gdshader`、`back_mountain_near_wind.gdshader`、`waterfall_flow.gdshader`。
- 两份 `tests/back_mountain_training_*.gd`，新增脚本／shader 对应 Godot `.uid`。
- 独立字体及来源 JSON、`tools/rebuild_back_mountain_font.py`，四份 `art/prompts/back-mountain-*.txt`；向原有 `art/manifest.jsonl` 追加本次记录。
- 本文、`DECISIONS.md` D026、`DEVELOPMENT.md` 当前切片。原有 `.gitignore` 和 game-art 接入文件保留。

## 运行

在 Mac mini 仓库根目录：

```sh
/Users/guoq/.local/bin/godot --path /Users/guoq/Developer/shu res://scenes/demos/back_mountain_training.tscn
```

正式 `run/main_scene` 保持 `scenes/main.tscn`。键盘 1 修炼、4 动静对比、L 光影增强／原画、R 重置。

## 玩家验收

1. 不操作时安静但有生命；移动鼠标时有极轻的空间层次。
2. hover 人物／剑能知道可修炼；点击后人物与环境共同回应，结果实际可见。
3. 修炼后的时辰从光与雾可感知，状态 UI 仍清晰。
4. 动静切换可以公平比较；静态仍能完成行动，精力不足不改变状态，重新开始恢复初始场景。

当前纯修炼可达时辰为卯 → 巳 → 申 → 次日卯 → 巳，精力不足后仅重新开始；不显示旧场景的 60 修为功课目标。午／酉由明确标记的 QA fixture 检查，不作为可玩额外行动。

## 验证记录

2026-10-05，Godot `4.7.2.stable.official.ed1daf0bf`：

- 后山 headless：54 项 PASS；包括唯一结算、busy 拒绝、失败原子性、完整重置、静态修炼／切换及十个表现周期后的阵风／眨眼。
- 既有 `state_test.gd` 14 项、`weather_test.gd` 8 项、`tea_object_state_test.gd` 90 项均 PASS。
- 真实 macOS Compatibility／Apple M4 渲染：61 项 PASS，0 失败，1152×720 与 960×600 控件可见并在窗口内。验证 viewport 鼠标命中与快速双点击；原生 OS 输入另记。
- 动静同时间的数值区域像素不变，静态跨表现时钟像素不变；冻结时钟下视差和风 shader 有实际像素变化。晨／午／酉光色检查通过，午／酉明确为不可达 QA fixture。
- 真实原生鼠标走完人物／剑修炼、演出中切静态、静态两次修炼、精力不足拒绝及重置／恢复动态。结果为 100/0 → 78/12 → 56/24 → 34/36 → 12/48；第五次状态不变。最终版本已重新打开初始动态场景。
- 四张 PNG 与记录 SHA256 一致；字体 231 个码点覆盖通过；正式入口、main、DemoState、rules、weather 与 weather_cycle 对比 HEAD 保持原样，`git diff --check` 通过。

早期沙箱运行有用户日志路径／macOS 证书权限警告；最终状态回归与窗口渲染在正常 macOS 环境重跑，日志无 ERROR／FAIL。未安装新工具或改全局设置。

证据目录 `.local/qa/back-mountain/`（Git 忽略）：`state.log`、三个回归日志、`render.log`、`qa-report.json`、`native-observations.md`、`preserved-core-check.txt`、`git-status.txt`。

实际截图：`01_idle_dynamic.png`、`02_idle_static.png`、`03_before_training.png`、`04_training_feedback.png`、`05_after_training_new_time.png`；`06_dynamic_later_a.png`／`07_dynamic_later_b.png`；`08_static_later_a.png`／`09_static_later_b.png`；`10_narrow_960x600.png`；`11_gust_without_wind.png`／`12_gust_wind_response.png`；`pointer_world_a.png`／`pointer_world_b.png`；`fixture_unreachable_午时.png`／`fixture_unreachable_酉时.png`。

复跑后山自动检查：

```sh
/Users/guoq/.local/bin/godot --headless --path /Users/guoq/Developer/shu --script res://tests/back_mountain_training_test.gd
/Users/guoq/.local/bin/godot --path /Users/guoq/Developer/shu --script res://tests/back_mountain_training_render.gd
```

## 尚未验证

用户对氛围与动作的主观认可；Web／Windows 导出和真实浏览器操作、低配性能、手机、Steam Deck、声音、长时间运行均另行记录。外置卷身份 metadata 本轮不可读，未做依赖安装／大型导出。


## Back Mountain Lighting v1（2026-10-05）

状态：实现与自动渲染检查完成；用户试玩认为变化不大，已决定后续不采用这套复杂光影组合（D028）。仅保留为后山实验记录，不升级为全游戏视觉标准；SPEC 未改。Godot 4.7.2 stable / GL Compatibility 保持。

### 主光方向与实现

原画右上天空最亮，石台顶面／右侧、人物朝右的面已有亮部，因此主光假定来自屏幕右上，射向左下。DirectionalLight2D 的本地 +Y 为光线方向，旋转保持 31°～49°，服从已有 painted lighting，不跨屏幕翻转。

采用 painted world lighting + 一个有限作用的 DirectionalLight2D + 接触／有限柔投影 + 慢云影。WorldCanvas 单独在 layer 1，状态／面板／按钮留在原画布；方向光不支持物件受光掩码，所以远山、中景与落叶使用 unshaded 材质，近景 shader 只让石台地面带响应原生光。框线也不受光。

- 原生受光：江砚秋、旧剑、近景石台／地面带；只有人物大轮廓与剑身两个简化 occluder，PCF5 柔化、低强度。轮廓保持基准位置，不追随呼吸和 hover 抖动。
- 接触影：坐姿／石台、剑／地面、台阶岩石三个小范围软影；偏环境灰褐、不用黑色椭圆。人物与剑另有两个有限长度柔投影，随时辰改变长度、角度与浓度，同源物件保持同一视差层。
- 仍为 painted：远山、中远山、寺观、远瀑、天空与森林、松树；由统一 tint／brightness、既有雾与世界云影表达时辰。没有远景实时投影，没有重绘素材、法线图或 3D。
- 云影：单张 128² 低频 noise，一次创建；16 秒柔缓周期，乘色亮度范围 0.88～1.0，只覆盖世界画面。没有每帧创建纹理／材质、动态 RenderTexture、多 pass blur 或 bloom。
- 唯一时间 authority 仍是 DemoState.time_index。六份参数见 [back_mountain_lighting.json](../assets/data/back_mountain_lighting.json)，不写入 rules；卯／辰／巳／午／申／酉全部覆盖。晨偏冷有雾、午清亮影短、晚暖暗影长；太阳方向只有小幅调整，日影长度是美术模拟。
- 修炼中仍只结算一次；旧光照保留至演出结束，然后用 1.05 秒平滑过渡到新时辰，雾浓度同时过渡。动态开启时高潮有约 0.216 秒、峰值 +2.5% 的小幅亮度回应。

### 两个 A/B 开关

`dynamic_enabled` 与 `lighting_enabled` 独立。4 切动静，L／顶部「光影：增强／原画」切光影。原画模式关闭方向光、occluder、接触影、柔投影与云影，恢复 v0 tint／雾。开关不改变养成状态、时辰或表现时钟，不重新结算／重启正在进行的修炼。静态冻结云影与微动；行动后的时辰光照过渡仍正常。重置恢复初始卯时光照，保留用户选择的两个开关。

### 本轮改动

新增 `scripts/back_mountain_lighting.gd`、`assets/data/back_mountain_lighting.json`、`back_mountain_contact_shadow.gdshader`、`back_mountain_cloud_shadow.gdshader` 及 Godot UID。小改后山控制器、既有 hair／near shader、两份后山 QA；独立字库重新子集化到 238 码点覆盖新开关文字，并更新来源 SHA256。场景仍通过原有独立 tscn 启动，既有布局／玩法参数文件无需改动。更新本文、D027 和 DEVELOPMENT。

### 实际验证

本轮最终状态检查 128 项 PASS；macOS Cocoa / Apple M4 Compatibility 实际渲染 138 项 PASS、0 失败，40 张截图，1152×720 与 960×600 排版／热点在窗口内。包括：

- 两开关四种组合、busy 中切换、唯一结算、时辰 profile 映射、训练结束平滑过渡、静态云影冻结和 reset。
- 云 shader 参数独立变化、原生 sun OFF／ON、occluder OFF／ON 均产生真实世界像素变化。视差从实际收到的 viewport MouseMotion 读取坐标，避免另一个窗口的桌面鼠标位置干扰当前画布。远山测试区域及数值 UI 不受原生光影响；云影及 profile 过渡不改变 UI 像素。
- 固定帧光影 round-trip 世界像素一致；另用修改前保存的 v0 控制器，在相同静态时钟下与 Lighting OFF 对照，完整世界区域逐像素一致（`original-restore.log`）。初始动态跨运行截图的视差会随鼠标位置不同，不拿它冒充固定帧对照。
- 实际观察六个时辰、接触局部与云影截图：冷暖／亮度变化可辨，坐姿底缘与剑下有轻柔暗部，没有长黑影、矩形边缘或可辨认的 noise 纹理。仍保留原画明暗；主观空间感待用户判断。
- 18 项正式入口／core／rules／原始美术及来源散列对比本轮开始快照均一致；没有修改 main、DemoState、天气或 tea。

证据目录 `.local/qa/back-mountain-lighting-v1/`：`state.log`、`render.log`、`qa-report.json`、`original-restore.log`、`preserved-core-check.txt`、`git-status.txt`、`native-observations.md`。最终新场景启动日志 `play-final.log` / `play-final-engine.log` 无错误；`live_play_initial.png` 已观察，初始 100／0、动态与光影均开启。本轮 CUA 选择到仍在运行的 v0 窗口，未在该窗口重置用户的 56／24 进度；v1 的原生 OS 鼠标／键盘操作未验证，不把 render test 的 viewport 输入算作原生试玩。早期沙箱 editor import 成功，但保存全局 editor settings 被权限拒绝；最终运行与渲染在正常 macOS 环境完成。

必需截图：`01_original_lighting.png`、`02_lighting_v1_mao.png`、`03_lighting_v1_si.png`、`04_lighting_v1_noon.png`、`05_lighting_v1_shen.png`、`06_lighting_v1_you.png`、`07_contact_shadow_detail.png`、`08_cloud_shadow.png`。另有 `02b_lighting_v1_chen.png`、`09_cloud_clear.png`、`10_native_sun_off.png`／`11_native_sun_on.png`、`12_native_occluders_off.png`／`13_native_occluders_on.png`、`16_training_profile_start.png`／`17_training_profile_mid.png`／`18_training_profile_end.png`。辰／午／酉为直接设置时间的 QA fixture，不增加玩家行动。

### 边界与下一验收点

这是绘画光影与少量 2D 原生遮挡的美术模拟，不能产生精确地形高度、真实太阳轨迹或重塑原画面部体积。没有新游戏规则／素材。Web／Windows 构建与真实输入、低配性能、长时运行尚未验证；未提交、推送或发布。

用户试玩反馈：「我觉得变化不大，我们之后还是不用这么复杂」。停止 Lighting v1 继续打磨，保留实现与验证记录。后续以原画质量、简单调色和少量微动为优先方向；不再以增加光影技术层数作为默认改进方式。

下一验收点在下一个已授权切片中确定，重点看玩家可感知的美术或交互改善；不重复要求用户验收本次复杂光影。本次仅记录反馈，没有删除代码或改动当前运行默认开关。


## 源码归档授权（2026-10-05）

用户在确认停止复杂光影投入后要求「推到 github」。本次将后山可玩切片、Lighting v1 实验及 D028 试玩结论、项目级 game-art 分工、选定素材／精确提示／来源和必要 QA 一并归档到既有 `jggagi/shu`。`.local/`、`.godot/`、`art/work/` 和 Python 缓存留在本机；不保存凭据。Git 提交与远端散列是源码交付证据，历史“未提交／推送”描述属于此前实现阶段。此次只更新源码，既有 gh-pages 未执行新的 Web 导出／部署。

## Back Mountain Clouds v1（2026-10-05）

用户已授权制作，尚待试玩拍板。复杂 Lighting v1 的视觉收益有限；本轮优先玩家肉眼可感知的环境表现，不为了物理正确性增加系统，不默认扩展复杂实时光影。只验证山间云气能否让后山有空气、距离和呼吸感。

- 高空远云：一张宽幅柔淡云气层，在原画天空上、独立中景山峰后。远景 PNG 已包含天空，不能直接将云放在该不透明 PNG 后方；保留原图，通过中景透明山峰建立实际前后关系。
- 山腰云海：两层，第一层在远景上／中景峰前轮廓后，第二层遮中景山腰、位于松树石台与人物后。没有前景云、脸前雾或 UI 遮挡。
- 单个 `back_mountain_cloud.gdshader`，复用既有 `mist_seed=471205` 的 128² seamless NoiseTexture2D；两次纹理采样，极慢横向 UV drift、0.004 UV 正弦低频形变、24 秒平滑聚散。没有新增 PNG、每帧资源创建、模糊链或云管理器；旧轻雾及 Lighting 实验保持。
- 实际设计画布参数：高空 7 px/s、alpha 上限 0.12；山腰前层 4 px/s、上限 0.44，后层 3.2 px/s、上限 0.352。不同固定 phase（0.3／2.2／1.1），风向同向。alpha 是局部上限，还乘软边／碎云覆盖与 0.24～1.0 的聚散因子；首版 0.18 和原画静态雾混在一起，故仅调强可见遮挡，不增技术层。
- 没有新增 brightness response／云影接口。Clouds 在 L 关闭复杂 Lighting 后仍完整工作；Lighting 原代码、配置和默认开关保留。
- 4／顶部动静开关：Static 留住当前云形，冻结移动、形变、聚散；Dynamic 从冻结的表现时钟继续。R 重置恢复初始云形，并保留两个开关选择。DemoState 的 day／time_index／energy／cultivation 与 train() 结算不受云影响。

本轮文件为控制器、原表现 JSON、一个云 shader／UID、两份原有 QA 与本文；决定 D030 和 DEVELOPMENT 仅追加记录。场景 tscn、main、DemoState、rules、tea、Lighting 源码／配置和原始美术均不修改。复用噪声与原创 shader 来源见 [clouds-source.json](../assets/art/back_mountain_training/clouds-source.json)。

### Clouds v1 验证与试玩

证据目录 `.local/qa/back-mountain-clouds-v1/`。固定时钟真实引擎截图：`01_static.png`、`02_dynamic_t0.png`、`03_dynamic_t10.png`、`04_dynamic_t20.png`、`05_valley_cloud.png`。后者为实际 t20 帧的山腰局部；辅助的同帧去云图用于检查云的贡献，Static 后续 seek 图用于冻结检查。使用 seek，不等待 20 秒。

Godot 4.7.2 stable：指定 checkout 的 headless 状态检查 153 条 PASS、0 FAIL；macOS Cocoa／Apple M4 Compatibility 真正渲染 157 条 PASS、0 FAIL（1152×720 和 960×600）。包含原有修炼唯一结算、拒绝／重置／viewport 热点、光影回归，以及云参数、层级、静态冻结／恢复、无养成变化检查。最终两份日志无 ERROR／FAIL；未做 Web／Windows 导出。

Codex 已逐张查看 01～05：没有硬边或明显整张 PNG 平移感；中央山腰和右侧山谷局部有淡云遮挡，近景石台／人物保持清楚。10／20 秒对照的云带变化可辨，但整体仍偏克制，尚未达到整座山消失的强遮挡；不将像素变化或测试通过视为用户认为“明显更好”。辅助去云对照确认山体像素确由云改变，静态跨 seek 为 0 差异。

新版 standalone 已正常启动（play.log／play-engine.log）。CUA 仍绑定旧 Lighting v1 实例，未操作旧窗口；本轮原生 OS 鼠标试玩未验证，viewport 输入检查不冒充原生试玩。Web／Windows、低配性能、长时运行和用户视觉认可尚未验证；不提交、不推送、不发布。

下一唯一验收点：「现在这些云，是不是明显让后山活起来了，而且没有抢走江砚秋的注意力？」


### Clouds v1 试玩修订：流动增强（2026-10-05）

用户反馈「云的飘动我看不太出来」。初版自动渲染和截图变化通过不代表玩家能感知；保留初版证据于 `.local/qa/back-mountain-clouds-v1/before-flow-revision/`，本节参数替代上述初版参数。

当前高空 14 px/s、alpha 上限 0.18；山腰前层 12 px/s、上限 0.44，后层 9.6 px/s、上限 0.352。shader 横向采样频率由 1.7 调至 2.8，让碎云有更容易追踪的柔轮廓；云带更薄、纵向曲线更不规则，色彩略向淡米白调整。聚散幅度降为 0.8～1.0，避免横移被整层淡出吞没。形变仍为 0.004，周期仍为 24 秒；层数、共享噪声、两次采样和 Lighting／玩法边界不变。

指定副本状态 153 条 PASS、真实 Apple M4 Compatibility 渲染 158 条 PASS，零失败；静态跨 seek 仍为 0 差异。新增 `02b_dynamic_t5.png`，Codex 重新查看静态、0／5／10／20 秒和山腰局部，能辨认山腰碎云位置更快改变，人物和石台保持清楚。用户本 chat 回复「很好 我喜欢」，认可当前流动增强版；本轮视觉验收完成，认可范围为后山 demo 的当前云效果与参数。新版标题「蜀山后山 · Clouds v1 · 流动增强版」，启动日志为 `play-flow.log`／`play-flow-engine.log`；原生 OS 输入与 Web／Windows／低配／长时验证边界保持。无提交或推送。


### 用户试玩认可（2026-10-05）

用户「很好 我喜欢」。保留当前流动增强参数，不继续增加复杂效果。本轮后山云的视觉验收已完成；不将该认可扩为所有平台、正式产品美术标准或远端交付授权。下一切片尚未安排；当前代码未提交／推送。


### Clouds v1 一键三连授权（2026-10-05）

用户在认可流动增强版后要求「一键三连」，授权本切片源码提交／推送／PR 合并，以及既有 GitHub Pages 的独立后山试玩入口 `https://jggagi.github.io/shu/back-mountain/`。既有根路径 A/B 试玩与本机 tea C 并行修改保留。本次仅交付本 chat 的 Clouds v1 文件与必要说明，不将 tea C 纳入提交。

发布 Web 从 canonical main 的合并提交 `git archive` 快照导出，临时仅覆盖快照的 `run/main_scene` 为 `res://scenes/demos/back_mountain_training.tscn`、`config/name` 为后山云实验、`config/version` 为 `0.1.0-back-mountain-clouds-v1`；正式工程入口及版本保持。声明的覆盖、引擎、提交和产物 SHA256 写入独立入口的 `build-info.json`。用匹配版本单线程 Web 模板，无新依赖。

实际 commit／PR／merge／Pages 部署与浏览器输入验证以 Git、发布 `build-info.json` 及 `.local/qa/back-mountain-clouds-v1/release/` 收据为准；本节记录授权与方法，不提前声称部署成功。Windows 导出／启动不属于本次 Web 发布验证。

## Back Mountain Environment v1（客户端日期 2026-10-05）

**状态：已授权实现、本机自动与真实渲染验证完成；尚待用户试玩验收。** 当前源码基线 `e7fa420`，`main` 上已有 tea C／完整支线并行修改均保留；没有提交、推送或部署，在线入口仍为已发布的 Clouds v1。

### 目标与结构

用户已确认 Clouds／cloud shadow 带来明显正向视觉价值，复杂 Lighting v1 的成本与玩家收益不相称；本轮优先简单调色、分层原画和可见的环境流动。

`DemoState.time_index + rules.times → EnvironmentPresenter → BackMountainEnvironment → 既有云／雾、细雨、世界调色和艺术云影`。

- 通用 presenter 是一个约 200 行的 RefCounted：读取 profile、验证 ID、确定性合成、独立时辰／天气插值和暴露当前／目标参数。没有场景节点、第二套游戏时间、养成结算、随机天气或气候模拟。
- 后山适配器知道实际图层与 shader。保留已认可云的三层、速度、碎云轮廓和种子噪声；只调 alpha／tint，小雨将现有山腰云略压低。复用轻量云影 shader 和已有噪声，独立于旧 Lighting 开关；不叠两份云影。
- 远景原画用低对比山色罩染与顶部渐变天空罩染，人物／近景统一 world tint × brightness。UI 留在原画布。现有听雨廊 rain shader 包含窗户 mask，因此没有照搬；新增后山专用细雨 wash，不含粒子、落地 splash 或屏幕白线阵列。
- 保留 Lighting v1 源码、配置、原生光／接触影实验及原默认开关。L 可关闭旧实验；Environment 的时辰、云、云影、雾、雨仍生效。旧 Lighting 的调色不再覆盖 Environment 的最终参数。

### 时辰与天气

| 时辰 | 当前主要差异 |
| --- | --- |
| 卯 | 冷而湿润，亮度较低，雾较多，远山较柔。 |
| 辰 | 开始变暖、变亮，雾稍散，远山渐清楚。 |
| 巳 | 清亮白昼，云与山层次较清楚。 |
| 午 | 六档中最亮，雾最少，保留原画克制用色。 |
| 申 | 偏暖、柔和，远山对比开始下降。 |
| 酉 | 暖暮色、明显变暗，远山逐渐沉入暮色；小雨组合仍可读。 |

| 稳定天气 ID | 当前修正方向 |
| --- | --- |
| `clear` | 少量云气，弱云影、较少雾、稍亮、较弱风，无雨。 |
| `cloudy` | 保留认可的云量与流速，云影恢复，天空略暗、雾稍多、风稍明显。 |
| `light_rain` | 更多低云、明显雨雾、天空更灰、远山对比下降、略暗，加入细而低不透明度的雨线。 |

六个时辰与三个天气各自定义，没有 18 份重复组合。配置在 `assets/data/back_mountain_environment.json`，最终亮度设下限。时辰 1.2 秒、天气 8 秒各自从当前画面插值；切换中断不跳帧，修炼不会让天气提早完成。小雨转晴时，雨线先用 4 秒淡出，其余云／雾／明暗继续完成 8 秒过渡。

修炼接受时仍仅调用一次 `DemoState.train()`，HUD 与环境目标立即读取结算后的真实时辰，1.8 秒演出继续；只有表现参数插值，没有“半个午时”的游戏状态。Night Preview 只覆盖视觉 profile：较低亮度、冷色、单独更深的天空和较柔远山，云继续按原表现时钟移动。没有新夜景 PNG、月亮／灯火或正式夜间时辰。

4 静态冻结云、雾、雨和云影的运动，保留当前时辰／天气／夜景；profile 过渡与修炼仍可进行。R 在 idle 重置真实状态、退出夜景并归初始卯时，保留选定天气与两个 A/B 开关；busy 中重置仍拒绝。

### 本轮文件

- 新增 `scripts/environment_presenter.gd`、`scripts/back_mountain_environment.gd`、`assets/data/back_mountain_environment.json`。
- 新增 `assets/shaders/back_mountain_environment_art.gdshader`、`assets/shaders/back_mountain_rain.gdshader`，以及新资源 UID。
- 修改 `scripts/back_mountain_training.gd` 接入目标／QA 控件，修正精力条与按钮重叠；场景 tscn 和原云参数／shader 不变。
- 新增 `tests/back_mountain_environment_test.gd`；更新 `tests/back_mountain_training_test.gd` 的两处旧调色／材质断言、`tests/back_mountain_training_render.gd` 的当前环境序列。旧渲染序列保留为 `_run_legacy_lighting_clouds()`，它记录旧视觉实验；当前默认命令运行 Environment v1，不将旧像素结论复用为当前验收。
- 后山独立字库 `ShuBackMountainSerif.ttf` 与 `source-back-mountain.json`：复用已存在 fontTools 4.60.1 和已归档源字体，扩至 291 码点；未安装依赖、未改 tea 字库。
- README、本任务卡、DECISIONS D032、DEVELOPMENT 仅补本轮入口／状态；SPEC 没有写入调色数值或把本轮实现升级为验收。

### 运行与实际验证

```sh
/Users/guoq/.local/bin/godot --windowed --path /Users/guoq/Developer/shu res://scenes/demos/back_mountain_training.tscn
```

1 或点江砚秋／旧剑修炼；4 动静；7 晴、8 多云、9 小雨；0 夜景预览；L 旧光影；R 重置。天气按钮位于顶部小区域，不盖山体。正常修炼只可达卯→巳→申，辰／午／酉作为真实 `state.time_index` QA fixture 完整验证，没有新养成行动。

真正执行：Godot `4.7.2.stable.official.ed1daf0bf`，macOS／Apple M4／GL Compatibility。

- `back_mountain_environment_test.gd`：93 条 PASS，零失败；全 18 组合确定性、分段推进一致、无效 ID、独立／中断过渡、雨先退、完整 DemoState／tea 字段保持、修炼目标、重置与 Lighting OFF 的实际 uniform 写入。
- `back_mountain_training_test.gd`：153 条 PASS；修炼唯一结算、busy／低精力拒绝、动静切换、原 Lighting 与云接口回归。
- 原 `state_test.gd`：14 条 PASS；原 `weather_test.gd`：8 条 PASS。
- `back_mountain_training_render.gd`：98 次实际断言调用（report 中 84 个唯一名称），零失败；19 张真实 960×600 PNG。通过 viewport 真实 hit testing 点击三个天气／夜景／动静／reset／人物热点，修炼 100/0 → 78/12、卯→巳；静态连续帧一致，动态雨／云时钟和世界画面变化。全部 Environment 截图在 Lighting OFF 下生成。
- 后山字体原始 SHA256、生成子集覆盖及 Godot 实际导入后的 `Font.has_char()` 覆盖全部控制器文案通过；`font-coverage.log` 为 PASS。最终 standalone 已打开，标题「蜀山后山 · Environment v1 · 时辰与天气」，`play.log` 无错误；不据此声称原生输入通过。
- 25 份原始美术／来源、core、rules、天气、tea 数据、主入口及旧 Lighting 文件与本轮开始 SHA256 完全一致；`git diff --check` 通过。最终正常权限测试／渲染日志无 ERROR／FAIL。早期沙箱 macOS 证书、窗口服务及 editor settings 保存限制不作为测试通过记录。

证据在 `.local/qa/back-mountain-environment-v1/`（忽略）：`state.log`、`training-state.log`、`core-state.log`、`corridor-weather.log`、`render.log`、`report.json`、`preserved-before.json`、`preserved-core-check.json`。

可复跑：

```sh
/Users/guoq/.local/bin/godot --headless --path /Users/guoq/Developer/shu --script res://tests/back_mountain_environment_test.gd
/Users/guoq/.local/bin/godot --headless --path /Users/guoq/Developer/shu --script res://tests/back_mountain_training_test.gd
/Users/guoq/.local/bin/godot --path /Users/guoq/Developer/shu --audio-driver Dummy --script res://tests/back_mountain_training_render.gd
```

必需截图均已生成且实际查看：`01_mao_clear.png`、`02_mao_cloudy.png`、`03_mao_rain.png`；`04_wu_clear.png`、`05_wu_cloudy.png`、`06_wu_rain.png`；`07_you_clear.png`、`08_you_cloudy.png`、`09_you_rain.png`；`10_night_preview.png`；`11_cloudy_to_clear_mid.png`、`12_rain_to_clear_mid.png`。另有修炼 `13_training_start.png`、`14_training_mid.png`、`15_training_end.png`，雨运动 `rain_motion_t5.png`／`rain_motion_t10.png`，静态 `static_hold_a.png`／`static_hold_b.png`。

### 视觉自评与边界

Codex 逐张看了必需 12 图及修炼起／中／终帧：卯冷、午亮、酉暖暗可直接辨认；同午时晴更清楚、多云云带与暗化更明显、小雨的低云／雨雾使远山更朦胧。细雨很克制，960×600 单张图主要感受到雨气，雨线没有成为主体；夜景有深天空与远山层次，人物衣袖／五官仍可读，但当前没有独立月光亮部。暮雨偏暗但不吞掉人物，顶部／底部 UI 保持原色与可读。全部这些效果在 Lighting OFF 仍成立。以上是 Codex 的制作自评，用户是否“一眼感到时间与天气”仍待试玩。

本轮未验证原生 OS 鼠标／键盘、Web／Windows 导出、低配、手机／Steam Deck或长期性能；viewport 合成输入不冒充原生输入。没有存档、声音、随机天气、天气玩法收益、季节或真正夜间玩法。外置卷 metadata 查询不可用，未绕过卷检查进行外置构建或安装；只复用现有本地工具执行本机检查。

下一验收只回答：**不看时辰文字，能否感到一天正在过去？晴、多云、小雨，是否像三个不同的蜀山时刻？** Environment v1 用户认可后才考虑听雨廊作为第二 adopter。

### Environment v1.1 天气反馈修订（2026-10-05）

用户试玩反馈：「晴天 多云 小雨 没啥区别」。首版细雨在 960×600 下是低透明的亚像素线，多云的云量／遮光差也不足。本轮局部修订，不将此前 Codex 的视觉自评当成人的验收。

- 晴：天气亮度倍率 1.12、云量倍率 0.12、雾倍率 0.35，露出清楚山峰。
- 多云：亮度 0.90，高云／山腰云倍率 1.5／1.7、雾 1.6，增加云带与遮光。
- 小雨：亮度 0.78、高云／山腰云 2.2、雾 4.0，远山更柔；雨线加宽至约一个显示像素、长度 16–28 原画像素，速度 250 原画像素／秒。雨在中景之后、前景与人物之前，透明边缘自然透出背景雨，脸部实心区不受影响。
- 远／中景共同使用现有环境罩染 shader，中景雾化较轻；原云 shader／速度和复杂 Lighting 源码保持，8 秒天气／4 秒雨退、六时辰与修炼结算不变。没有新素材、粒子系统、随机天气或玩法修改。

本轮代码仅改 `back_mountain_environment.json`、后山适配器、细雨 shader、后山窗口标题和相关两份检查脚本。通用 presenter 没有改接口或插值；窗口标题含 **Environment v1.1**。

本机实际检查：环境状态 93、修炼回归 153、真实 Apple M4 Compatibility 渲染 119 次断言（105 个唯一名称），均 PASS；23 张 960×600 截图。新增固定同一时刻三天气的画面亮度排序，以及只改变 rain_amount、只改变 rain_time 的独立渲染检查，避免用云移动冒充雨可见。

| 真实时辰 | 晴平均亮度 | 多云 | 小雨 |
| --- | --- | --- | --- |
| 卯 | 0.5143 | 0.4072 | 0.3492 |
| 午 | 0.6467 | 0.5176 | 0.4392 |
| 酉 | 0.3603 | 0.2867 | 0.2494 |

这些是画面艺术区 RGB 加权均值，不是显示器测光或人类辨识度证明。固定雨时钟、只关雨，6336 个区域像素变化；只改雨时钟，9288 个区域像素变化；完整顶部／底部 UI 与脸部实心区域均零差异。渲染检查发现雨节点相对 z 顺序问题，已修正为中景内 z=0，复跑通过。

日志与报告：`.local/qa/back-mountain-weather-feedback/`；原图对照在其 `before/`，当前截图在 `.local/qa/back-mountain-environment-v1/`，新增 `rain_uniform_on/off.png`、`rain_only_motion_t5/t10.png`。Codex 已观察卯／午的三天气、酉雨、夜景与过渡；暮雨／夜雨仍偏暗，人物轮廓与脸部保持可读，等待用户意见。

未提交／推送／发布，Web／Windows 与原生输入未验证。下一唯一验收：不看天气文字，是否能直接认出晴、多云和小雨。试玩时每次切换保留约 8 秒完成平滑过渡。

### Environment v1.2 晴天太阳（2026-10-06）

用户要求「晴 可以加入太阳吗」。本轮加入小型淡金／暖橙日轮，晴天显示，多云和小雨按原 8 秒过渡淡出；夜景隐藏。位置、半径、暖色和强度写在现有六个 TimeProfile，晴可见性写在三个 WeatherProfile。薄 presenter 继续只合成／插值参数，后山适配器创建一个小型绘制日轮，云与山峰自然遮挡；没有新增真实光源、光芒、镜头效果、生成 PNG 或养成效果。

清晨位于右侧较低天空，正午升高，傍晚在左侧偏暖、部分被峰顶与松枝遮挡；这是一条构图用轨迹，不代表天文模拟。修炼依据真实 DemoState 时辰平滑改变日轮位置，静态对比不伪造游戏时间，切天气也不推进资源或时辰。窗口标题 Environment v1.2。

生产文件：`assets/data/back_mountain_environment.json`、`scripts/environment_presenter.gd`、`scripts/back_mountain_environment.gd`、`assets/shaders/back_mountain_sun.gdshader` 及其 UID；后山控制器仅更新窗口版本文字。当前验收重点为太阳的构图／大小与水墨画面的协调；其他场景和原始素材保持。

证据目录 `.local/qa/back-mountain-sun/`；当前真实截图仍在 `.local/qa/back-mountain-environment-v1/`。未提交／推送／发布；Web／Windows、实体输入和长期性能未验证。此次请求不视为此前三天气表现已经获得认可。

太阳本轮本机验证：状态检查 93 条 PASS；Apple M4／Compatibility 实际渲染 156 次断言、142 个唯一名称、25 张截图，零失败。固定时钟只关日轮，6160 个艺术区像素变化，完整顶部／底部 UI 与脸部实心区域零变化；六时辰位置、晴／云／雨可见性、晴转多云与云／雨转晴的中途淡化、夜景隐藏／恢复均通过。当前 core／rules／tea／原始后山素材等 26 份输入与本轮开始哈希一致（准确数量见 `preserved-check.json`）；太阳大小／位置／色调仍待用户试玩。清晨、正午、傍晚日轮截图已实际观察。

试玩用 `.local/qa/back-mountain-sun/play_clear.gd` 打开同一真实 demo 场景，仅在开局选择晴天，方便直接看太阳；常规入口仍保持原默认天气，按 7 选择晴。此启动脚本不修改养成状态。

太阳试玩验收（2026-10-06）：用户反馈「不错 我喜欢」。Environment v1.2 本轮晴天太阳表现验收通过，保留当前构图、半径、暖色与时辰位置参数。该认可不新增提交／推送／发布授权，也不代表 Web／Windows 或下一场景已验收。太阳切片收尾，下一切片尚未安排。

## Ambient Life v1（2026-10-06）

状态：D035 已授权实现，尚未用户试玩验收。本轮目标是让后山偶尔出现自然生命，仍保持安静、松弛。动物只属于环境表现，不产生行动、奖励、点击互动或养成效果。

本轮文件：新增 `scripts/ambient_life_presenter.gd`、`scripts/back_mountain_ambient_life.gd`（及 Godot UID）、`assets/data/back_mountain_ambient_life.json`、`assets/art/ambient_life/{birds,squirrel,cat}.svg` 与 source.json、`tests/ambient_life_presenter_test.gd`、`tests/back_mountain_ambient_life_test.gd`；修改 `scenes/demos/back_mountain_training.tscn`、`scripts/back_mountain_training.gd`、`tests/back_mountain_training_render.gd`、后山专用字体 ShuBackMountainSerif.ttf 与 source-back-mountain.json，以及 README、BACK_MOUNTAIN_SLICE、DECISIONS、DEVELOPMENT 四份文档。专用字体仅补齐 QA 按钮汉字，并保留 OFL 来源；没有修改茶场景字体。

`Environment state + Scene capabilities → AmbientLifePresenter → BackMountainAmbientLife`。公共 presenter 不认识场景节点、坐标或素材，只观察真实 Environment 时辰、天气、夜景 QA 与现有 dynamic 开关；场景适配器读取显式 markers，沿路径播放小型原创 SVG。Environment／Clouds／Lighting 代码与参数保持原样，其他场景不接入。

### 当前 capabilities 与素材

| 类型 | 启用 | 场景依据与表现 |
| --- | --- | --- |
| Birds | true | 开阔天空提供 `SkyBirdLane`，从左侧远天空掠向右侧，位于山峰与前景之后；1～3 只，三帧简化振翅，轻微上下起伏。 |
| Squirrel | true | 现有松树斜枝提供 `SquirrelPath`；一次跑过一段、短停、继续跑、淡出，不驻留。 |
| Cat | true | `CatSpot_Rock` 位于左侧现有岩石边；`spot_type=rock`、`sunny=true`、`sheltered=false`。低对比静卧，微弱呼吸，不设动物点击区。 |
| Fish | false | 后山只有远景瀑布，没有适合呈现鱼影的近处河流、池塘或溪面；不新增水域或鱼节点。 |

素材目录 `assets/art/ambient_life/`：birds.svg 72×14（三帧）、squirrel.svg 68×44、cat.svg 96×52，均为本轮原创简化矢量轮廓。来源、作者与 SHA256 在 source.json；没有复制参考作品或生成大尺寸动物图。最终大小由本轮配置控制。

### 自动出现与环境关系

当前参数为制作初值，位于 `assets/data/back_mountain_ambient_life.json`，不写成永久 SPEC：

| 类型 | 下一机会间隔 | 一次持续 | 晴／多云／小雨机会概率 |
| --- | --- | --- | --- |
| Birds | 28～58 秒 | 10～13 秒 | 0.80／0.45／0 |
| Squirrel | 60～110 秒 | 4.4～5.4 秒 | 0.65／0.50／0 |
| Cat | 80～150 秒 | 26～48 秒 | 0.55／0.45／0.30，仅有遮雨落点时允许小雨 |

机会不保证出现。成功事件结束后再采样间隔；机会未通过天气、概率、占用或修炼状态检查时，重新等待一个间隔。RandomNumberGenerator 使用明确 seed `20261006`，按定时机会抽样，逐帧只推进时钟。测试可覆盖 seed；强制 QA 不消费随机流、不修改配置或永久概率。

卯／辰／巳／午正常，申／酉机会概率乘 0.65；后山夜景默认关闭全部动物。晴天猫优先 sunny 落点，多云可用普通落点，小雨只能用 sheltered 落点；当前后山没有遮雨落点，因此小雨无猫。测试中的临时屋檐 marker 只验证选择规则，不加入生产场景。没有猫寻路。

同一时刻最多一个明显动态事件（鸟、松鼠或未来鱼），安静猫可共存。真实修炼 `busy` 抑制新事件。关闭生趣清空全部动物并暂停调度；Dynamic OFF 隐藏鸟和松鼠、暂停调度时钟，已有猫恢复完整静止姿态，避免停在半帧。再打开 Dynamic 恢复剩余等待；天气／夜景改变时清除不再允许的事件。

### 运行与 QA 控件

```sh
/Users/guoq/.local/bin/godot --windowed --path /Users/guoq/Developer/shu res://scenes/demos/back_mountain_training.tscn
```

底部小型 QA 控件：A 生趣开关，B 远鸟、S 松鼠、C 猫，U 恢复自动。强制只绕过出现概率，仍要求 scene capability、dynamic、天气与夜景允许；强制预览暂停自动调度，U 清除强制事件并恢复自动剩余等待。原有 1 修炼、4 动静、7／8／9 天气、0 夜景、L 旧光影、R 重置继续可用。R 沿原 DemoState 重置逻辑，同时重启生趣固定 seed；Ambient adapter 自身 reset 不修改玩法。

自动检查与实际 Compatibility 渲染入口：

```sh
/Users/guoq/.local/bin/godot --headless --path /Users/guoq/Developer/shu --script res://tests/ambient_life_presenter_test.gd
/Users/guoq/.local/bin/godot --headless --path /Users/guoq/Developer/shu --script res://tests/back_mountain_ambient_life_test.gd
/Users/guoq/.local/bin/godot --path /Users/guoq/Developer/shu --audio-driver Dummy --script res://tests/back_mountain_training_render.gd -- --ambient-life
```

尚未验证 Web／Windows、实体鼠标键盘、声音与长期运行；本机 viewport 注入点击与键盘检查单独记录，不视为实体输入验收。原游戏仍无动物声音。当前可见性／节奏由用户试玩决定，不提前迁移第二场景。

### 本轮实际检查与视觉自评

Mac mini／Godot 4.7.2／Apple M4／GL Compatibility 实际执行：

| 检查 | 结果 |
| --- | --- |
| AmbientLifePresenter 固定 seed、分帧一致性、占用、强制／自动隔离、静态、天气与夜景 | 56 条 PASS |
| 后山 Ambient 集成：完整 DemoState／tea 字段与 Environment 快照、真实 marker 移除、遮雨猫测试 fixture、重置 | 60 条 PASS |
| 原后山修炼、动静、Lighting／Clouds 回归 | 153 条 PASS |
| 原 Environment 状态回归 | 93 条 PASS |
| 原核心养成 state_test | 14 条 PASS |
| 原 Environment／太阳实际渲染回归 | 156 次断言 PASS、25 张截图 |
| Ambient 实际 Compatibility 渲染 | 73 次断言 PASS、14 张截图；最终零失败、零引擎错误 |

渲染证据目录 `.local/qa/back-mountain-ambient-life-v1/`，报告 report.json 与 ambient-render.log。实际截图：`01_base_no_life.png`、`02_birds.png`、`03_squirrel.png`、`04_cat.png`、`05_clear_life.png`、`06_cloudy_life.png`、`07_light_rain_life.png`、`08_dynamic_off.png`，另有 `02_birds_motion_start.png`、`03_squirrel_early.png`、`03_squirrel_middle.png`、`07_light_rain_no_animals_baseline.png`、`08_dynamic_off_hold.png`、`09_training_after_reset.png`。

02／03／04 是明确标记的强制 QA；05／06 通过现有配置与 seed 自然调度，只有生趣时钟受控推进，其他运动冻结。晴天截图记录自然鸟事件在 58.5 秒时的约 4.10 秒龄，多云记录自然松鼠事件在 108.45 秒时的约 1.33 秒龄；这是确定性截图证据，不是实际墙钟长时间试玩。07 为真实生产 marker 的雨景，没有遮雨落点，动物全部隐藏。08 的静卧猫在两个受控时刻保持整个艺术区像素一致。

实际运动对照：鸟在两个可见时刻沿路径移动超过 100 个艺术坐标像素，改变 88 个渲染像素；UI 顶／底栏和人物脸部零变化。松鼠前→中、中→后分别改变 400／403 个艺术区像素，三个截图落点均沿现有松枝。首次远鸟检查错误要求至少 100 个变化像素，导致单项失败；在实际看图确认远鸟应保持微小后，改为两次可见运动位置与正像素变化联合检查，重跑通过。首次报告与日志保留为 attempt1-report.json、attempt1-ambient-render.log。

Codex 实际查看八张要求截图及鸟／松鼠运动图：鸟小、远、克制，不穿到人物前；松鼠脚点贴松枝，未横穿空背景；猫像岩石边本来就趴着的小动物，低对比、没有卖萌标记。人物仍是首要视觉主体，当前没有明显抢镜元素。建议保留三种生命的当前大小与低密度，本轮无需删猫或进一步降频；自然节奏与“山间生趣”感仍待用户试玩确认。

素材三份 SHA256 与来源一致。任务起点对照的 29 份输入中 24 份一致，含 core rules／DemoState、Environment、Clouds、Lighting 与原后山美术；另外五份 main.gd、project.godot、export_presets.cfg、tea.json、tea_memory_scene.gd 在本轮外的并行写入范围发生更新，按现状保留。准确对照见 preserved-check.json，不声称并行文件未变化。`git diff --check` 通过；本轮无提交、推送或发布。

下一唯一试玩问题：这些偶尔出现的小生命，是否让蜀山更有自然生命和人间烟火，同时保留安静、松弛的山间气质？

## Ambient Life v1.1：猫与松鼠的小动作（2026-10-06）

用户要求「猫和松鼠可以随着环境有一些动态吗」。本轮局部表现修订已授权，未获动作强度验收。只修改后山 Ambient adapter、动物 SVG 与来源、少量 motion 配置、窗口版本文字、针对性测试及记录；公共调度器、原有间隔／概率、路径／落点、Environment／Clouds／Lighting 与养成规则保持。

- 猫：四个 96×52 原创姿态（静卧、小幅抬头、轻微侧看、轻摆尾），帧 0 保留原静卧轮廓。一次出现仍为 26～48 秒，大多数时间静卧；约每 18 秒中的第 6～9 秒，清晨卯／辰或多云可抬头，晴天巳／午更多睡觉。第 12～14 秒依已有 Environment 风力参数轻摆尾。小雨有遮雨落点的测试场景仍静卧，生产后山雨天仍无猫。修炼或明显动态事件（鸟／松鼠）发生时，不播放抬头／摆尾。已有微弱呼吸保留。
- 松鼠：四个 68×44 原创姿态（停下、三帧迈腿／尾巴），继续原跑→停→跑路径与时长。跑动起伏不超过 2.2 个艺术坐标像素，风力参数仅轻微影响步频；暂停阶段脚点稳定，仅短暂调整尾巴。
- 动作只取现有事件年龄、环境风力、天气和真实时辰，无逐帧随机和第二套环境时钟。关闭 Dynamic 隐藏松鼠并复位其姿态；已有猫恢复原静卧帧与完整静态比例，重新打开再按原事件年龄继续。

素材现为四帧紧凑图集：cat.svg 384×52、squirrel.svg 272×44，运行 AtlasTexture 按原单帧大小取样；scale、颜色、位置不扩大。source.json 更新原作者与 SHA256，原有 birds.svg 不变。QA 键位与启动命令沿用上一节；窗口标题含 Ambient Life v1.1。

新增实际动作截图入口：

```sh
/Users/guoq/.local/bin/godot --path /Users/guoq/Developer/shu --audio-driver Dummy --script res://tests/back_mountain_training_render.gd -- --ambient-motion
```

当前验收点：猫和松鼠的动作是否自然可见，且保持后山安静、松弛的气质？未提交、推送或发布；Web／Windows 与实体输入仍未验证。

本轮实际验证：Ambient 调度器回归 56 条 PASS，后山生趣集成（含新增姿态、时辰／风力、注意力抑制、静态复位、路径边界与状态隔离）99 条 PASS；Apple M4／Compatibility 实际渲染 54 次断言 PASS、12 张 960×600 截图，零失败。证据目录 `.local/qa/back-mountain-ambient-life-v1-1/`，报告 report.json，日志 presenter.log、integration.log、motion-render.log。猫静卧→抬头改变 129 个艺术区像素，抬头→轻摆尾改变 254 个；松鼠两个跑停对照分别改变 409／415 个。

实际截图：cat_age1.png、cat_age7.png、cat_age12_2.png、cat_age12_8.png、cat_wu_age7.png、cat_quick_suppressed.png、cat_busy_suppressed.png、cat_dynamic_off.png、squirrel_early.png、squirrel_run.png、squirrel_pause.png、squirrel_dynamic_off.png。全部是明确的受控 QA 姿态，不声称为自动出现或长时间试玩。Codex 已实际查看猫的静卧／抬头／摆尾、午时／静态，以及松鼠早期／跑动／暂停图：动作可见但克制，猫身体稳定留在岩石上，松鼠沿松枝，人物仍为视觉中心。建议保留本轮动作强度，待用户试玩确认。

task-start 哈希对照：DemoState、rules、公共 AmbientLifePresenter、Environment presenter／adapter／data、原云 shader 与 scene marker 均未变化；后山控制器只有窗口标题更新。三份动物来源 SHA256 匹配，鸟素材未变化。`git diff --check` 通过；并行 tea 文件保留，未提交、推送或发布。

## 大橘猫 v1：摸摸与自娱（2026-10-06）

用户要求「我希望猫是大橘猫，可爱一点，能够和玩家互动，也能自己玩」（D036）。本轮把后山猫从安静的偶发远景元素改为更容易亲近的橘色虎斑，保留原岩石落点。方向已明确授权，外形、动作与节奏等待试玩。

- 外形：圆脸、胖肚、奶油色下巴／爪子、橘色虎斑；八帧 96×72 可编辑原创 SVG，显示比例 1.15。没有新增外部参考图或图片生成调用。来源、作者及 SHA256 在 `assets/art/ambient_life/source.json`，标准库生成脚本 `tools/make_orange_cat.py` 可重建同一图集。
- 摸摸：直接点击实际猫位置，眯眼轻蹭约 3.2 秒，底栏回应「大橘眯着眼，蹭了蹭你的手。」；过程中重复点击不重启动作。透明热点跟随实际层变换，不与主角、剑或 UI 重叠，不消耗精力／时辰，不改变修为、剧情或 Environment 状态。
- 自娱：约每 30 秒中的第 15～17 秒舔爪，第 19～23.5 秒拨小落叶、短暂翻身，再休息。已有清晨／多云抬头与风力轻摆尾保留；晴天巳／午偏爱打盹。修炼或鸟／松鼠经过时自娱暂停，摸摸回应与自娱期间抑制新的明显生趣事件。
- 出现：晴／多云的机会间隔 3～6 秒、白天基础概率 1，停留 180～240 秒；原调度器的傍晚概率修正保留。雨天没有遮雨落点，猫及热点隐藏；夜景不出现。关闭 Dynamic 保留静卧但禁用互动；关闭生趣隐藏猫；R 正常重置也清除摸摸状态和姿态。鸟／松鼠配置、路径、Environment 与 core rules 保持。

启动仍用上方独立场景命令；窗口标题「蜀山后山 · 大橘猫 v1 · 摸摸与自娱」。C 立即查看大橘、U 恢复自动，晴／多云自动出现不需要强制 QA。底栏提示点击大橘摸摸。当前猫在清晨／多云自己玩约需等到出现后 19 秒；这项时长是可调参数。

针对性验证入口：

```sh
/Users/guoq/.local/bin/godot --headless --path /Users/guoq/Developer/shu --script res://tests/back_mountain_orange_cat_test.gd
/Users/guoq/.local/bin/godot --path /Users/guoq/Developer/shu --audio-driver Dummy --script res://tests/back_mountain_orange_cat_render.gd
```

证据目录 `.local/qa/back-mountain-orange-cat-v1/`。Web／Windows、实体输入、声音与长期运行仍未验证；本轮没有动物声音。本机实际渲染、自动检查和用户试玩认可分别记录。未提交、推送或发布。下一唯一验收点：大橘是否足够可爱，摸摸回应和自己玩是否自然可见。

本机实际验证：新增猫互动集成 74 条 PASS；原生趣集成 99、公共调度器 56、原修炼 153 条 PASS。真实 Apple M4／GL Compatibility 窗口渲染 55 条断言 PASS、六张 960×600 截图，实际 viewport 鼠标点击触发摸摸，猫图像区域变化 1516 个像素，所有 DemoState 字段与该 fixture 的 Environment 状态保持。最终检查零失败、零引擎错误。首次集成发现重置后隐藏猫仍留在摸摸帧，已在 adapter reset 明确恢复帧 0 后复核通过。

截图与 report.json 清楚区分：01_clear_auto_cat.png 和 03_auto_self_play_age20_4.png 为固定 seed 的自然调度（仅生趣时钟受控推进），02_mouse_pet_reaction.png 为真实 viewport 注入鼠标；04_cloudy_forced_cat.png、06_static_cat_frame0.png 为受控 QA，05_light_rain_no_cat.png 为生产无遮雨落点。并非长时间墙钟试玩或实体鼠标验收。Codex 实际查看这些画面和额外舔爪／翻身草图截图：橘色圆脸、虎斑与胖肚清晰，动作留在原岩石上，提示文字可读，主角仍为视觉中心。当前外形与节奏供用户试玩决定。

渲染首次报告因误把主动切天气后的 Environment 与切换前比较而失败；第二次猫像素区域未包含 viewport 缩放，正确输入与姿态检查通过但像素检查失败。改为每个 fixture 自己的状态快照，以及实际图像坐标、稳定窗口尺寸后重跑全部通过；保留 attempt1／attempt2 日志及报告，不降低像素验收。最终日志 orange-cat-integration.log、orange-cat-render.log；原回归日志 ambient-regression.log、presenter-regression.log、training-regression.log。font 子集 306 字符覆盖 PASS，来源哈希匹配。与 v1.1 起点哈希对照确认 core rules／DemoState、公共调度器、Environment 数据和适配器、Clouds shader、scene marker 未变（preserved-check.json）；鸟／松鼠素材哈希也保持。`git diff --check` 通过，保留并行 tea 内容；未提交、推送或发布。

## 大橘猫 v2：水彩画风（2026-10-06）

用户认为 v1 猫「画风有点违和」，要求设计与环境／游戏统一的可爱橘猫素材（D038）。重新对照实际主角与后山背景，修正平整色块、均匀描边的问题：细而略不规则的棕灰线，水彩／淡彩毛色与柔和阴影，细毛发笔触、赭橙虎斑、米白下巴与肉爪，保持圆脸胖肚与温和表情。画风方向来自用户明确要求；具体候选仍待用户认可。

本轮内置 imagegen 生成一张角色设定与八姿态图集，1774×887 RGBA，实际有 1,024,671 个全透明像素；各姿态均有透明外缘和可见猫像素。PNG 原样保存于 [orange-cat-painterly-v2.png](../assets/art/ambient_life/orange-cat-painterly-v2.png)，八姿态为静卧、抬头、侧看、摆尾、舔爪、翻身、拨叶子、摸摸回应。精确 [提示词](../art/prompts/orange-cat-painterly-v2.txt)、实际主角及 [后山风格参考](concepts/orange-cat-scene-style-v2.png) 随 provenance 保留；provider=codex-imagegen，隐藏模型不填写。此次为一只角色的画风设定与本机候选检查，没有 Qwen 量产或付费 API 调用；后续批量制作仍遵守 game-art 分工。

后山已使用这份候选：Godot AtlasTexture 读取 4×2 图集，记录各帧区域与落脚锚点，保留约 96 艺术坐标宽 × 原 1.15 scale 的逻辑尺寸。PNG 没有裁切、抠图或像素修改；两处相邻姿态边界微调只发生在 atlas 坐标。跨行的空白差用锚点抵消，舔爪／翻身不在岩石上下漂移。Sprite offset 随姿态，frame metadata 表示动作编号，不再从 SVG 横向坐标推断。旧 cat.svg 与生成脚本留作 v1 历史；鸟／松鼠素材、原概率和本轮前全部猫行为不改。

窗口标题「蜀山后山 · 大橘猫 v2 · 水彩画风」，运行命令与 C／U、点击摸摸沿用 v1。已实际执行：生趣集成 99 条 PASS；橘猫集成 102 条 PASS，含八姿态 alpha、图集边界、显示尺寸、热点／重复点击、全状态快照和重置；Compatibility 实际渲染 65 条 PASS、八张 960×600 截图，零失败、零引擎错误。真实 viewport 鼠标点击后的猫图像区域改变 2242 个像素，原养成与该 fixture 的 Environment 快照不变。

证据在 `.local/qa/back-mountain-orange-cat-v2/`：asset-audit.json、integration.log、ambient-regression.log、render.log、report.json。截图 01_clear_auto_cat.png、02_mouse_pet_reaction.png、03_auto_groom_age15_2.png、04_auto_self_play_age20_4.png、05_auto_roll_age21.png、06_cloudy_forced_cat.png、07_light_rain_no_cat.png、08_static_cat_frame0.png。01／03／04／05 是固定 seed 自然调度、受控推进生趣年龄；06／08 为受控 QA，02 为注入鼠标，07 是生产雨景无猫。Codex 已查看八张：毛色与环境协调，圆脸可读，细线／毛发与主角比前版更接近；翻肚皮、舔爪、拨叶子和摸摸抬脸均有区别，原岩石落脚稳定，主角仍占画面视觉中心。该自评不代替用户美术认可。

与前轮哈希对照，DemoState／rules、公共调度器、Environment 数据／presenter／adapter、原云 shader 和 scene marker 相同（preserved-from-v1-check.json）。SVG 历史与 raster/layout 的来源 SHA256 匹配；`git diff --check` 通过，未提交、推送或发布。Web／Windows、实体输入、声音与长期运行仍未验证。下一唯一验收点：这版橘猫是否既可爱，又像本来属于当前蜀山画面。


### 水彩橘猫试玩认可与 GitHub 归档授权（2026-10-06）

用户反馈「很好 我喜欢 保存到 github」，当前水彩橘猫美术验收通过，授权保存本轮可复现切片到 GitHub。上述待认可／未授权说明是历史阶段状态；本次归档包括猫所依赖的后山天气、太阳、生趣调度和原互动，保留并行《两盏茶》工作。使用独立功能分支，在线部署／合并未授权；本机截图和忽略目录继续留本机，不当作版本化产物。


归档前独立验证：以远端 main 的 e7fa420 为基础，仅带入上述后山文件与相关文档，核心 DemoState／主流程／tea 数据保留该基础版本。状态 14、后山修炼 153、调度 56、环境 93、生趣 99、橘猫 102，共 517 条检查通过；真实 Compatibility 渲染 65 条、八张截图通过并实际查看。两份后山测试将并行剧情新增字段改为“存在时填充并比较”，因此保留本机完整快照覆盖，也可在 GitHub 既有状态模型上独立运行。本机证据在 `.local/qa/back-mountain-orange-cat-v2/github-stage/`，图片与缓存不入库。


### 归档追记与当前 PR 状态（2026-10-06）

归档时已提交并推送 `ecf40067ee9a7b8a408befcb71e8bd1ea4c6cea7` 到 `codex/back-mountain-orange-cat-v2`，远端哈希核实相同；当时创建草稿 PR #3，48 个范围内文件。独立工作树未带入 DemoState、主流程、Tea 素材／数据／文档或入口配置改动，原 checkout 并行工作保留。本机交付收据 `.local/qa/back-mountain-orange-cat-v2/github-stage/delivery-receipt.json` 及 scoped-render 证据继续留本机，不提交或删除。

当前重新核对：[PR #3](https://github.com/jggagi/shu/pull/3) 已 MERGED，Tea PR #4 也已 MERGED，GitHub main 为 `89e4369`；不再描述为 OPEN/draft。上述记录保留归档历史，不据此推断在线试玩已更新。本轮只保存 scene-making skills 与文档，不新增部署或游戏验证。
