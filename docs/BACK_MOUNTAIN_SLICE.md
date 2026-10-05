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
