# 溪边茶亭 · 独立试玩 v1.3

客户端日期：2026-10-07。基线为隔离 worktree 的 detached HEAD `9cab32a`，起点 clean；本轮仅新增溪边茶亭切片及相关来源、构建与验证资料。用户提出石岸／茶亭／溪水／远山的新构图、六时辰三天气、水面流动与雨滴涟漪、石面橘猫与摸摸，并沿用独立试玩、Static／Resume／Reset和完整画面审核。本轮 v1 已获用户试玩验收（2026-10-07「验收通过」）；随后用户对远瀑方案回复「好」，本地新增 v1.1；其动感待新一轮试玩。

## 玩家看到的切片

- 左侧茶亭、前景石台、中央与右侧溪水、层叠远山构成新画景。原画为一张内置 imagegen 构图参考，审核后直接用于第一可玩候选；没有批量生产或新增 Qwen 外发。精确提示、参考、provider、尺寸与 SHA256 见 [素材来源](../assets/art/stream_teahouse/source.json) 和 [提示](../art/prompts/stream-teahouse/reference.txt)。
- 卯、辰、巳、午、申、酉与晴／多云／小雨由独立试玩宿主主动选择。沿用 EnvironmentPresenter，profile 单独配置；不自动推进养成时间。清晨偏冷、正午较亮、斜阳偏暖、暮色暗下，阴雨降低亮度并加强远山薄雾。
- 水面仅在按原画校准的 polygon 内出现两层细流纹；小雨出现稀疏扩散的扁椭圆水圈。露天空气区域有细雨与山间薄雾，茶亭屋顶／室内留在遮罩之外。所有效果使用宿主的 controlled presentation elapsed，不用独立 shader TIME。
- 同一只已认可水彩橘猫起始即在石面休息，约 6 秒后站起、约 8 秒开始走动，沿石台短路线停下、坐一会儿，再返回。复用原八姿态与六个桌面 companion 姿态以及既有 CatDeskMotion 路径数学，不复用听雨廊坐标。只做一个居民，未引入新随机出现调度或其他动物。
- 点击猫有眯眼蹭手与短句回应；热点随 pose 的 opaque bounds、pivot、scale和朝向更新。沿用已保存的掌心向下手形。摸摸暂停路线，回应结束接续；不增加成长、奖励或存档。
- 石岸是露天能力：小雨立即禁用行走／摸摸，猫在原位用 1.5 秒 dynamic delta 淡出，天晴／多云后逐渐恢复。不把石岸视为遮雨桌面。

## Static、恢复与 Reset

Static 保留完整原画和居民当前位置，行走猫转为原位站定，冻结水纹、雨线、涟漪、雾相位、猫移动／淡入淡出／摸摸时钟及短句计时，关闭猫热点。Resume 从同一相位／位置继续。玩家主动切换时辰或天气时，profile 的过渡仍完成，运动时钟继续冻结。Reset 恢复清晨、多云、Dynamic、原石岸起点并清空呈现与互动阶段。

宿主仅维护此独立环境预览的选择；不导入或修改 DemoState、主流程、养成结算和 Tea。UI 在世界调色之外。新 adapter、mask 与 profile 留在项目，不提取 addon。

## 运行和构建

原生独立入口：

```sh
godot --windowed --path . res://scenes/demos/stream_teahouse.tscn
```

1–6 选时辰，7／8／9 选晴／多云／小雨，空格切换 Static／Resume，R Reset；也可点画面下方按钮。点击岸边橘猫摸摸。

同工程、同锁定 Godot 4.7.2 stable 及对应模板，导出专用候选：

```sh
python tools/build_stream_teahouse.py --godot godot
python -m http.server 8771 --bind 127.0.0.1 --directory .local/build/stream-teahouse/web
```

打开 `http://127.0.0.1:8771/`。Windows 位于 `.local/build/stream-teahouse/windows/StreamTeahouse.exe`，同目录 PCK 必须保留。构建脚本只复制明确的依赖清单至忽略的 staging project，并在该副本设置独立主场景；原 project.godot 和主场景入口不变。构建 receipt 包含所用源码 SHA256。专用字体来源与重建方式见 [字体记录](../assets/fonts/source-stream-teahouse.json)。

## 验证与完整画面审核

最终候选的实际验证：

| 层级 | 证据 |
| --- | --- |
| 脚本／素材 | Godot 4.7.2 import 和 controller check-only 通过；独立字体 156 codepoints 覆盖通过。 |
| Cat adapter | Root 独立重跑 `tests/stream_teahouse_cat_test.gd`，56 项 / 0 失败：两个方向、接触 pivot、热点、Busy、Static、摸摸计时、雨中淡出及恢复、Reset。 |
| 主规则回归 | `tests/state_test.gd` 14 项通过；源码未修改。Headless macOS CA lookup 有宿主证书查询日志，不影响套件；原生渲染和 Web 未出现对应运行错误。 |
| 实际 Compatibility | `tests/stream_teahouse_render.gd`，Apple M4，75 项 / 30 张完整截图 / 0 失败。六时辰 × 三天气全部截图，审核石岸／水域mask、正反猫步态、摸摸、Static／Resume／Reset、1152×720 和 960×600。 |
| 真正水面动态 | 晴天水域同一区域前后帧实际像素不同；Static 全画面前后字节相同。首次新增像素检查发现 untextured Polygon2D 的 UV 不可用，改用 VERTEX varying 后全部重跑通过，并重导出候选；单纯时钟变化不作为动态完成证据。 |
| 本地导出 | 最终 Web 单线程和 Windows x86_64 专用包均导出成功，build log 无脚本／导出错误；源码哈希与 build-info 对照。 |
| 浏览器真实输入 | Codex in-app browser，实际鼠标 Reset、摸猫（出现蹭手短句）、Static／Resume，以及键盘时辰／天气切换；检查 Static 仍保留猫，恢复后雨中淡出。最终重导出后再次加载并操作复核，控制台无警告／错误。 |
| 用户认可 | 2026-10-07 用户明确回复「验收通过」，认可当前 v1；Windows 实机与后续瀑布增强保持独立边界。 |

完整截图与 render-report 位于 `.local/qa/stream-teahouse-v1/`，包括18种环境、动作、mask、动静及水面前后帧。图像审核：茶亭／远山仍可读，猫落脚在平整石台、两向尺度一致，水域mask避开露出石岸；选中按钮的文字过淡已修正，实际渲染复核。水纹与雨圈强度略增强后保持克制，最终动感仍由用户判断。

Windows 实机、手机竖屏、设备听感、低端设备和长时运行未验证；本切片没有新增声音。没有 Git commit／push／PR／merge 或公开发布。本机 Web 服务仅监听回环，供本轮试玩。

## 下一验收点

v1 的构图、天气、猫和交互已获用户认可。当前看 v1.3 的河流是否能感到顺流前进，远近尺度是否合适，水纹／倒影是否安静，暮色是否连贯，以及 Static／Resume／Reset 是否符合预期。保留远瀑，先收新动感反馈再决定参数修订。

## 验收追记与下一轮方案（2026-10-07）

用户验收 v1 通过，希望加强水的流动感，先从远处瀑布开始，并询问方案。当前推荐先选一段清楚的远瀑，以原画校准局部水路遮罩，做向下细流纹、内部微扰动与克制落点水雾；轮廓与山体固定，沿用环境时钟、时辰天气调色与 Static／Resume／Reset。此段记录当时的方案状态；随后用户回复「好」，已按下述 v1.1 实施。

## v1.1 远瀑本地候选

选中中部偏右的两级白色远瀑（逻辑位置约 x844–896、y187–281）。遮罩沿原画水路，原 PNG SHA256 不变；三组细长明暗片段向下流动，内部微扰动不超过一逻辑像素，山石、树木及瀑布外轮廓固定。落点范围 x829–891、y268–295 内有低不透明度薄雾，外形不平移。两份 shader 都只读取宿主 `elapsed`、亮度与色调，沿用 Static／Resume／Reset；暮色和阴雨不会出现一条自发光白带。

真实渲染审核发现首版流纹偏淡，Root 增强水路内部阴影片段后完整重跑：

- Godot 4.7.2 Apple M4 Compatibility：97 检查、50 张完整截图、0 失败，含原18环境、两种尺寸与原有猫／摸摸／雨／Reset回归。
- Static 前后完整图像字节相同；恢复继续同一时钟；Reset清零。单独改变远瀑 shader 的 elapsed，远瀑像素变化，相邻山体像素完全相同。实际变化 bounding box 在原生截图 `(736,194)`–`(768,260)`，处于远瀑遮罩内；其余动态在该对照中保持冻结。
- 完整画景、红色几何诊断遮罩与连续16帧已审核；参考原画上下两级水路，没有让山壁整体变形。阴雨与暮色远瀑保持同场景色调，猫与按钮仍可读。
- Web单线程和Windows专用包重建成功；24份依赖SHA256与最终receipt一致，构建／原生渲染无脚本或shader错误。实际浏览器点击正午／晴、Static／Resume、Reset，键盘切雨天暮色，控制台无警告／错误。

当前证据位于 `.local/qa/stream-teahouse-v1.1/`（包含 `render-report.json`、`qa_waterfall_mask.png`、动静原图及审阅用 `waterfall-motion.gif`）；本轮代码基线副本和日志位于 `.local/qa/stream-waterfall-v1/`，v1旧证据保留。GIF只是短连续帧审阅，不代表完整周期无缝循环或长时验证。

下一验收点：在完整画面中能否看出远瀑向下流动；流速、明暗强度和落点雾是否适合这张画。用户认可后再按实际水路逐段增强溪水急流。新远瀑动感待用户试玩；Windows实机、手机、低端与长时仍未验证。没有新增生图、声音、玩法或远端交付。

## v1.2 暮色区域连续性修订

用户反馈「暮色有区域不连贯」。真实暮色雨天画面中，茶亭右侧沿户外 polygon 斜边出现偏亮的切块；暮色背景已经调暗，原雨雾和水纹颜色未跟随世界调色，硬裁切让边界更明显。修正雨雾使用与背景相同的世界／天空色调和亮度，水纹同步世界色调；沿原户外 polygon 的内部边缘做40逻辑像素渐隐，画面最外侧边缘保持原样。保留茶亭遮雨范围、原画、profile、远瀑和呈现时钟。

本轮实际 Compatibility：104检查／54张完整截图／0失败。重新审核六时辰×三天气、1152×720与960×600，确认亮雾斜切消除，谷内雾仍有层次，水纹随暮色收暗。新增渲染回归对比开启／关闭雾：旧接缝位置原图红色增亮24/255，修正后0/255；谷内雾仍有像素贡献，暮色Static完整前后帧字节相同。既有远瀑变化与邻山稳定、Resume／Reset、猫和摸摸检查继续通过。

最终Web／Windows专用包导出成功，24份依赖SHA256与receipt一致。Web 实际加载 v1.2，键盘切换暮色／小雨和 Static／Resume，控制台警告／错误为空，留下暮色小雨动态供试玩。新证据位于 `.local/qa/stream-teahouse-v1.2/`，包含 `light_rain_you.png`、`dusk_mist.png`、`dusk_no_mist.png`、`dusk_static_a.png`／`b`、全18环境与对比图；本轮baseline和日志位于 `.local/qa/stream-dusk-fix/`，旧QA保留。修正后用户视觉验收、Windows实机与长时仍待验，未提交、推送或公开发布。

## v1.3 河流水面动态

用户要求增加河流水面动态。沿原水域polygon绑定5点主河道，向前推进两层断续亮纹与宽缓倒影明暗变化；透视坐标让远处更细缓，近处更宽更快。控制点、强度和12逻辑像素岸边渐隐见 `assets/data/stream_teahouse.json` 的 `river_flow`。原画在固定位置采样，只用来选出偏青水色并获得同位置颜色，暖色石面抑制新效果；没有源图位移、河床形变或整张背景抖动。雨圈保留，所有颜色跟随世界亮度和色调，Static／Resume／Reset继续使用同一呈现时钟。

首次实际渲染仍偏淡，Root提高碎亮纹和倒影明暗强度后完整重跑：134检查／81张完整截图／0失败。包含独立远近水域前后帧变化、石岸区域像素完全一致、完整Static帧相同、暮色接缝／雾保留回归、全部18时辰天气、两种窗口尺寸、猫／摸摸／Reset和远瀑回归。原生完整画面与连续24帧审核：动感集中在河面，原石岸、河床结构保持固定，未出现新的暮色亮块。相同晴天水域两秒前后帧RGB平均差由v1.2约 `(0.39,0.29,0.19)` 增至 `(1.48,1.16,0.91)`；这是像素动态证据，用户肉眼感受仍是独立验收点。

证据保存于 `.local/qa/stream-teahouse-v1.3/`，含 `river_original.png`、`river_a.png`／`b`、24张 `river_motion_*.png`、完整环境图、report与短预览 `river-motion.gif`。GIF由实际运行连续帧生成，只供审阅，短片末尾循环不是运行中的完整无缝周期。本轮baseline和日志在 `.local/qa/stream-river-v1/`，旧QA保留。

下一验收点：先选「午＋晴」，看中近景水纹是否沿水路前进，水流速度／强度与原画是否合适，再切暮色和Static比较。新视觉认可、Windows实机、低端与长时仍待验；未提交、推送或公开发布。

交付复核：Web单线程／Windows专用包重建成功，24份依赖SHA256与最终receipt一致，构建及原生渲染没有脚本／shader错误。Web实际加载v1.3，键盘切换正午晴天、Static／Resume和暮色小雨，控制台警告／错误为空。保留正午晴天动态供试玩；Windows包只完成导出，未在Windows实机运行。

## v1.3 用户认可与PR收尾（2026-10-07）

用户回复「不错 准备PR merge收尾」，认可当前v1.3本地视觉切片并授权commit／push／PR／merge。上文各轮“未提交”和“待试玩”为当时的历史状态；最新本地视觉认可与交付授权以本段为准。Windows实机、低端、手机和长时仍未验收，本次不新增公开试玩部署。

PR基于最新main `c83c8ffe39335fcc10b059283b3095d106d6235e`：保留已合入的山门庭院与方法资料，把本切片决定编号顺延为D056–D058，避免与庭院D054／D055重号。共用猫路径已由main提取至 `CatResidentMotion`，保留兼容wrapper并补齐专用包的依赖清单；此基线已复核实际渲染与导出。原2c48工作区、旧QA与本机包保持，安全快照在原工作区 `.local/safety/stream-teahouse-pr-20261007/`。

最终PR基线验证（2026-10-07）：猫adapter 56项／0失败，主规则14项通过；实际Compatibility 134项／81张完整截图／0失败，复核正午河流与暮色小雨画面。独立Web与Windows导出成功，补齐共用模块后的25份依赖SHA256全部匹配receipt。最终Web包实际加载，暮色／小雨、Static／Resume与Reset键盘操作通过，控制台警告／错误为空。新证据位于隔离PR工作树的 `.local/qa/` 和 `.local/build/stream-teahouse/`；Windows实机、移动端与长时运行未验证。
