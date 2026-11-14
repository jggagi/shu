# 成都连续街区：大场景候选

客户端日期：2026-11-07，America/Los_Angeles。状态：本轮构建、原生 UI 和浏览器技术检查已通过；世界排布、尺度与观感仍待用户试玩认可。

## 授权与本轮目标

用户在「城市结构过于线性」反馈之后，进一步询问大场景，并对「约 3 × 3 屏面积、五个户外区域合并、跟随镜头、茶馆保留独立室内」的提案回复「做」。本轮据此把西门、市街、百工巷、榕树坪和临河巷放进同一片可步行的户外世界，让路程、建筑遮挡、岔路与绕行在连续空间里呈现。

当前世界逻辑尺寸为 `3840 × 2160`，相对原 `1280 × 720` 逻辑画面，横纵各为三倍、面积九倍，因此称「约 3 × 3 屏」。这只是逻辑尺寸比较；实际可见范围随相机透视、跟随参数和窗口而变，不能据此推算完整成都的规模。具体布局、镜头范围、步行速度和实际观感仍待用户试玩。

## 入口与存档隔离

| 项目 | 当前候选 |
| --- | --- |
| 内容包 | [`shu_chengdu_large`](../games/shu_chengdu_large/game.json)，版本 `0.5.0` |
| 内容目录 | [`chengdu_large_catalog.json`](../games/chengdu_large_catalog.json)，保留原 `stream_study` 验证包 |
| 场景入口 | [`cultivation_engine_chengdu_large.tscn`](../scenes/demos/cultivation_engine_chengdu_large.tscn) |
| 户外地图 | `chengdu_city`；五个区域共享同一地点状态 |
| 室内地图 | `chengdu_teahouse`；保留前后两门 |
| SaveStore 基础目录 | `user://chengdu_continuous_city` |
| 独立构建用户目录 | `shu-chengdu-continuous-20261107` |
| 本机试玩 | [18862 成都连续街区](http://127.0.0.1:18862/)，在 X1 桌面内浏览器打开 |

旧四图 `18860`、六图 `18861` 与 `shu_chengdu / 0.4.1` 候选保持，已有构建及证据仍见[成都首片](CHENGDU_FIRST_STREETS_SLICE.md)。新包 ID、内容版本、应用目录和保存位置独立，不自动迁移或覆盖旧档。主开发路径与本次临时工作树职责保持，未授权 Git 提交、push、合并或公开发布。

## 连续世界与玩家行为

户外西门、市街、百工巷、榕树坪、临河巷是显示区域，跨区始终保持 `chengdu_city`；走过边界不会执行旅行行动、切换地图或扣除时辰。山中与茶馆仍由现有 Session 通过行动进入、返回，不创建第二套城市状态。

当前地面为 `[80,120,3680,1960]`，角色半径 `12`、寻路格距 `20`。院落、街铺、茶馆外墙、榕树池和河水边界形成实际障碍，南侧市街与北侧巷道提供不同绕行路线。户外热点和合法落点由 [`walks.json`](../games/shu_chengdu_large/walks.json) 定义；区域名、建筑范围、道路带与参考路径在 [`chengdu-large-layout.json`](../assets/data/chengdu-large-layout.json)，表现布局不结算资源或剧情。

- 点击可走地面，角色规划合法路径，镜头随脚点移动；建筑和水域阻挡与导航一致。
- 画面右上提供可收起的小城图，显示街路、建筑、当前脚点和区域；在图中点击也请求合法步行，不跳跃位置或推进剧情。
- 顶部区域名随脚点进入的区域变化；地图只是显示与寻路入口，不增加任务、解锁或持久状态。
- 茶馆前门临市街，后门接百工巷；室内仍是独立场景，两门回到户外的不同门前落点，可穿店通行，也可从外街绕过。
- 原城中方向木牌、街边货架、货埠告示和河面查看保留；方向文字按同一片城市调整。茶馆掌柜、茶客仍为匿名职业，竹伞可拒绝、带走、归还并保留重访记忆。
- 普通走动、看物件、进出茶馆免费；下山与返山仍各一时辰、不扣精力。原师徒五剑、调息、休息、跨日与声音保持。

户外有八个热点、十处障碍，茶馆逻辑几何与人物／失物架保持。这些是当前候选的实现规模，不确立后续全城人口、店铺数量、交易系统或完整日程。没有新增长篇剧情、人物 `say`、TTS、任务门禁或强制路线。

## 关键落点与恢复

| 旅行 | 行动与目标入口 | 当前逻辑脚点 |
| --- | --- | --- |
| 下山入城 | `go_to_town` → `chengdu_city.from_mountain` | `[440,1760]` |
| 茶馆前门入店 | `enter_teahouse` → `chengdu_teahouse.from_market` | `[640,570]` |
| 茶馆后门入店 | `enter_teahouse_back` → `chengdu_teahouse.from_lanes` | `[640,240]` |
| 前门回户外 | `leave_teahouse` → `chengdu_city.from_teahouse_front` | `[1600,1540]` |
| 后门回户外 | `leave_teahouse_back` → `chengdu_city.from_teahouse_back` | `[1600,900]` |

五个户外区域共用同一地图的合法脚点，茶馆保留独立室内位置；当前路径、镜头、小城图展开状态和区域标签属于表现状态，不新增数值权威。恢复检查应确认角色与镜头在原脚点重新对齐，不重做旅行、伞结算或人物记忆。普通事件仍须结束后进入可保存阶段；重新开始回到本包初始状态。

## 验证与交付记录

本轮固定 Godot `4.7.2.stable.official.ed1daf0bf` / GDScript / Compatibility，Web 使用匹配单线程模板。冻结 stage 为 `.local/build/chengdu-continuous-20261107/stage-dc7b3c0bc18e`，292 项输入逐 SHA256 与源码及导入后 stage 相同。源码为 `7c992c578b1fe4a1624c769812425b38080771d3` 加本轮 dirty 修改，分支 `codex/chengdu-connected-streets`；主副本保持同 HEAD 的 clean main。旧四图／六图通过记录不代替以下新检查。

| 验证层次 | 本轮实际结果 |
| --- | --- |
| 内容／旧包字节 | 新内容278项静态检查通过。上一冻结版270项输入中268项逐字节保持，只有原ChengduWalker补默认舞台工厂、构建工具登记新入口／独立字库。旧包、模型、材质、音频和旧字体保持；新包rules／characters／motions／voices字节继承。原六图包全部JSON保持。 |
| 冻结状态检查 | 大图203、原回环445、成都合同95、旧行走124、基础184，共 **1,051项／0失败**，五组正常退出0，日志无错误警告。覆盖真实远距分段移动、五区同scene且不结算行动、两门落点、空间门禁、伞与精确存读档，15字段Session不变。 |
| 原生大图UI | 1152×720、960×600各 **171项／11图／0失败**，均正常退出0。真实Godot鼠标／键盘事件操作：师父选择、入城时辰消耗与回执、菜单／确认遮挡、城图收起／展开与远路规划、五区连续步行、主画面地面点击、取伞、北绕茶馆后门归还／重访、正门回街、走远后精确读档、返山与确认重开。没有直接注入角色位置、相机、Session或游戏click_at调用。 |
| 旧六图UI回归 | 同一最终stage的原六图回环 **154项／8图／0失败**，正常退出0，日志无错误警告。验证默认舞台工厂仍保持原路线、两门与读档。三次原生图形进程串行、各自独立XDG_DATA_HOME。 |
| 镜头／几何专项 | 五区、后门和四角共10点实际1280×720渲染，导航／可见实体validate均为空；3084个合法40px间距样本、3736步真实follow函数模拟均无人物出框。集成真实步行时镜头移动约2966逻辑像素、边界全部有效；屏外热点排除、投影／反投影对应。每个舞台实例构建一次，连续步行不重建；菜单和事件仍沿用原界面重建方式。 |
| 规划与帧间隔 | 同源码导航建格中位约27.4ms，44次route中位约5.6ms，最远互动规划约141.3ms（独立CPU微测，不是FPS）。原生两尺寸行走采样3137／3134帧，均值16.668／16.666ms，P95为17.796／17.770ms、最大18.954／18.923ms，测试上限60FPS；实际地图输入分派包含等待帧，1152最大约66.5ms。限于本机与此段采样。 |
| 字体 | 新独立ShuChengduLargeSerif使用原固定OFL源、fontTools4.51，911所需码点、0缺字，输入哈希与最终代码／内容／layout相等。旧Chengdu字体未重写。 |
| Web构建／HTTP | 导入与Web单线程导出均退出0，日志无脚本／资源错误警告。HTML收尾只固定画布和图标。七文件约156.48MiB，完整HTTP读回SHA256全部等于磁盘；PCK `d955fa974b41dda27079f2df5bbdff08804af1e10c940e6e32dee60313e6868b`。creator-game-check另外记录PCK／WASM非空大小与哈希，其元数据检查不代替玩法验收。 |
| 浏览器流程／刷新 | 独立Chrome profile实际鼠标／键盘回放 **89条** 输入／截图轨迹，五区、两门、伞、读档、返山和重开走通，无控制台错误／警告、pageerror、失败请求或HTTP错误。携伞时在 `chengdu_city [3330,1290]` 真实保存并刷新，完整payload逐字节相同，SHA256 `5209a2780b42ba27e16ea02fddcb224e0d34be5a61343ac92c88e97c22cbc77f`；恢复精力92、人物记忆、两图位置、旗标与回执。IndexedDB只读检查，没有游戏状态注入或伪造存档。 |
| 浏览器帧回调观察 | 刷新后3480次被动requestAnimationFrame回调，均值17.42ms、P95约16.8ms、最大816.7ms。此段包含室内外切换、读档等操作，存在一次较长回调间隔；不能据此声称全流程无停顿、GPU完成帧率或低配设备已验收。 |
| 用户认可／其他平台 | 具体布局、密度、距离、镜头与观感待用户试玩；Windows、Steam Deck、实体输入、设备听感、低配／长时性能未验证。五剑数据与资源字节保持，本轮没有重新播放完整五剑动作。 |

主代理已查看两尺寸的巷道／河岸、城图、茶馆前后门、归还与浏览器刷新／读回／重开画面。初版镜头边界在南角存在人物出框风险，专项检查后调整为 `[440,450,3400,1770]` 并重跑十点实渲染、采样和跟随模拟，最终集成使用调整后的同一stage。独立只读复审未发现新的P1/P2；未将其代替实际输入检查。

收据位于 `.local/qa/chengdu-large/`：`state/receipt.json`、`state/navigation-timing.json`、`native-1152`、`native-960`、`old-loops`、`stage-probe.json`、`browser/receipt.json`、`http-artifacts.json`、`protected-inputs.json`、`artifact-check.json` 与 `final-delivery.json`。本轮未提交、push、合并或公开发布；18860／18861旧服务与页面仍保留。

复现构建使用：

```bash
python3 tools/build_cultivation_engine.py \
  --output /absolute/existing/build-directory \
  --entry scenes/demos/cultivation_engine_chengdu_large.tscn \
  --title '蜀 · 成都连续街区' --app-version 0.5.0-continuous-city \
  --user-dir shu-chengdu-continuous-20261107
```

用固定引擎对返回stage导入，运行 `tests/cultivation_engine_chengdu_large_test.gd`。真实窗口为 `tests/cultivation_engine_chengdu_large_render.gd -- --qa-size=1152x720` 或 `960x600`，每个图形进程设置独立 `XDG_DATA_HOME`。同stage导出Web后运行 `python3 tools/finalize_chengdu_web.py /absolute/stage/web`，再启动本机服务；HTML收尾保留PCK／WASM字节。

下一试玩点：从西门沿不同道路走到河岸时是否有连成一城的感觉，镜头和小城图是否容易辨向，巷中绕行与茶馆双门是否自然，以及步行距离、遮挡和街面密度是否舒适。后续扩建依据这轮实际体验决定。
