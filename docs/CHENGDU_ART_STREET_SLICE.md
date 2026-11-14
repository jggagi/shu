# 首街与横巷整段美术重做

2026-11-09补记：原18871预览现已同源升级至[概念图差距修订0.7.7](CHENGDU_CONCEPT_FINISH_SLICE.md)，本页0.7.6／0.7.6.1来源和QA保留为历史，不冒充新材质／细节版本的验证。

客户端日期：2026-11-08，America/Los_Angeles。状态：用户反馈地面异常闪光后，0.7.6.1修订已通过同路线逐帧对照、构建及两尺寸完整原生流程，[18871](http://127.0.0.1:18871/)已更新至 `stage-c837f6078954` 并核对HTTP字节。真实Web UI和用户视觉认可仍未验证。以下保留0.7.6原制作与验收历史，修复结果单独记录。

## 地面闪光修复（2026-11-08）

用户后续反馈「地面有些地方有异常闪光」，没有据此认可整街视觉。冻结0.7.6在同路线、同相机的实际Wayland GPU采集中复现：部分地面从绘景短暂退回更亮的底材。关闭镜面高光仍有闪动，新街及旧南门地面投影均涉及；不能只通过降低高光来关闭此反馈。首街还有相同高度重合的铺地，各mesh私有可用画稿不同，形成重复覆盖。

0.7.6.1修正仅在新世界投影helper内：地面先以共同的4／4／5个允许ground源ID及世界锚点选择一个参考，再按捕获源ID确定覆盖者；重复ground签名不重复注册。地面透明pass按世界法线偏移0.01米，所有校准坐标在偏移前记录，保留深度测试。地面使用独立shader；屋顶／树冠的vertex与此前最终版本逐字相同，不写VERTEX。当前实例的8个旧南门地面material使用私有派生shader接受同样偏移，仍由原helper同步，退出恢复原shader。原南门源码、所有画稿／ID／深度法线／校准、实心mesh、布局、相机、碰撞与玩法逐字保留；仍9个sampler，没有额外生图。

修订构建 `stage-c837f6078954`，helper SHA `d3224694c166f0a5896f34b8b2491c1f7443a7720aa05f1429446daf3503c4ce`，407输入，runtime digest `1b677320898d45854bc98a99f4f83e45780bb6d71664cb54ffa70920c0b1a02d`。同一HEAD `7c992c578b1fe4a1624c769812425b38080771d3`、dirty状态，Godot4.7.2 Compatibility；本轮未提交或push。app版本 `0.7.6.1-ground-fix`，用户目录与 `user://chengdu_art_street` 保持0.7.6原值，继续使用同一个18871预览来源。

最终验证结果如下。QA统一在 `.local/qa/chengdu-ground-flicker/`，与0.7.6原验收分开；旧基线及被拒绝候选不累计到本次检查。

| 验证范围 | 本次实际结果 |
| --- | --- |
| 来源与保全 | 相对0.7.6的407输入仅helper变化、406项逐字保留；最终源码／stage／导入后407 SHA全同。22项独立保全、404项实际场景CPU、8781项helper合同均PASS，日志无ERROR／WARNING |
| 构建与状态 | 固定4.7.2导入exit0；184＋2303＋51＝2538项状态／导航检查0失败，Web单线程导出exit0，所有日志无ERROR／WARNING |
| 移动GPU对照 | 原生1280×720相同761帧路线，前版4组、最终2组，每组65张PNG；最终130张，同组与前后相机轨迹差0。三视角取色仍可见，没有用关闭绘景代替修复 |
| 固定世界地面样点时序 | 沿用修前冻结的420点／5294对相邻1—2帧，亮度跳变p95从9.2802降为1.4532级，≥12级短亮峰从59变为0。数字为“样点×时序三帧”计数，不是独立事件或全部渲染帧 |
| 排除阴影的严格子集 | 同一冻结365点／4911对，p95从7.6955降为1.3986级，≥12级短亮峰39→0；采样条件、world点、帧号与相机均未按修后重选 |
| 实际逐帧图审 | 检查北段752／753／754、南段276／277／278、中段364及巷口518等9图，地面保留绘景且无先前底材矩形，屋顶与树叶没有被拒绝版的三角裂块；不声称逐张检查全部761帧或全城 |
| 完整原生输入 | 1152×720及960×600各264项／20张UI图／0失败，均正常exit0、日志问题0，合528项／40图，另4张绘景A/B。完成行动结果、师傅对话选择、城镇路线、伞／重访、双门、保存Load全字段、返山及确认重置 |
| Web产物与预览 | 原18871同源更新，5文件HTTP200且与最终磁盘逐字相同；PCK141165588字节，SHA `b681cbcb83af31ec24f6519b78513f8e8c54517b70443c9775755c74a90a20ee`；用户目录及保存位置保持 |
| 尚未验证 | 本轮CUA库存为空，真实Web UI／浏览器保存刷新未验；Windows、声音、实体输入、性能和用户视觉认可仍未验。原生结果不替代这些判断 |

最终收据：`architecture-final.json`、`check-exits.json`、`after/summary.json`、`after-temporal.json`、`known-spikes-before-after.json`、`independent-final-review.json`、两份`native-wayland-*-exit.json`及对应报告／图像、`http-artifacts.json`、`browser-attempt.json`和`final-review.json`。下一次试玩仍需由用户确认，当前证据只关闭本次复现路线上的技术缺陷。

失败候选已归档：`77c60ea18651`只统一winner后出现矩形底材；`1e05f73cfebd`加公共允许源仍有接缝、固定样点亮度跳变p95反增；`39cf62bbc55f`的地面数字改善，但共享vertex写入引入屋顶／树冠三角撕裂，被图审拒绝。该候选两尺寸原生在约118秒由本任务SIGTERM中止，exit -15不能记为通过。最终改为独立ground shader后重新验证，不复用其完整流程结论。

下一验收点：刷新原试玩页，连续行走南门—首街—横巷，确认局部地面不再亮闪，同时屋顶、树冠、人物脚边与道路边界保持正常。用户反馈关闭仍以实际试玩为准。

## 用户反馈与本轮批准

用户指出0.7.5「这个和我们之前打造的小规模城镇场景还有一定差距，为什么」，随后授权整段重做。0.7.5的素材生产、结构断言、原生流程及导出通过，继续只证明其技术范围；当前美术完成度没有获用户认可。历史反馈与证据见[四屋精作切片](CHENGDU_CRAFTED_STREET_SLICE.md)，不改写为视觉通过。

本轮目标是一段完整首街与横巷的统一构图、建筑轮廓、环境层次和光色，在大城连续跟随镜头里达到此前茶街的整体完成度。主街、巷口、铺面、树冠、墙脚、街面与阴影需一起组织，不能以又一轮基本材质替换或构件数量作为完成标准。完成后由用户在实际运行中评价，尚不自动推广为全城美术认可。

| 层次 | 当前范围 |
| --- | --- |
| 已批准 | 整段首街＋横巷的美术重做，沿旧茶街整体制作方法推进 |
| 保持 | 15360×11520、592栋原住宅／622障碍、大城连续跟随镜头、原导航与唯一EngineSession |
| 已实现 | 18栋街屋与2株庭树的几何／底材、三实际底稿和校准数据；三选定画稿只对地面／屋顶／树叶做世界投影 |
| 已验证范围 | 最终来源构建与2538项状态／导航、17767项CPU合同、84项保全；实际GPU图审、两尺寸528项原生检查及40张UI图 |
| 尚未验证 | 真实Web UI保存刷新、Windows／声音／实体输入／性能与用户观感 |
| 不自动扩大 | 全城重绘、可进入新室内、新剧情／状态／玩法或后续额外生图 |

## 艺术制作brief

整段画面先形成明确主次：街道是可走的视线通道，铺面与巷口有节奏，远近屋檐和树冠有可读叠层，侧背面延续同一空间。细节为建筑用途、尺度与环境服务；不靠密集摆件填满空地，也不以全局变暗或加滤镜掩盖重复体块。

原茶街及已批准concept提供笔触、色彩、层次和光色关系的参考，不把其布局、建筑位置、树木或岸线搬到当前大城。参考文件沿用[原茶街画稿](concepts/chengdu-painted-gate-20261108/town-style-reference.png)、[主街concept](concepts/chengdu-street-references-20261108/01-main-street.png)、[横巷concept](concepts/chengdu-street-references-20261108/02-side-lane.png)和[铺面concept](concepts/chengdu-street-references-20261108/03-shopfront.png)。

本轮采用Qwen标准 `qwen-image-3.0`，4次串行调用均成功下载、0次自动重试，选定3张、拒绝1张。首张南段使用3张参考，出现新增人物、桌子与布局偏移，被拒绝；`south-v2`、中段与横巷均只使用各自实际底稿及负面词，选定图均为1536×864 RGB，原下载PNG字节不改。准确参考、参数、prompt与SHA见[来源记录](../assets/art/chengdu_art_street/source.json)；prompt保留[首版南段](../art/prompts/chengdu-art-street-20261108/south.txt)、[选定南段](../art/prompts/chengdu-art-street-20261108/south-v2.txt)、[中段](../art/prompts/chengdu-art-street-20261108/middle.txt)和[横巷](../art/prompts/chengdu-art-street-20261108/lane.txt)。拒绝图属于实际成功调用，不从调用数中扣除；本轮没有后续生图计划。

三视角已从实际新Stage采集：1280×720，原13.5米／52°／FOV39连续跟随相机；脚点分别为南段 `[7800,7560]`、中段 `[7800,7290]`、横巷 `[7450,7420]`。底稿是无人物、接触影、Label3D和UI的环境，树冠几何保留、屋顶退隐置零；新街段绘景在采集前还原为旧overlay，保留原南门绘景。每张均有同源ID、深度／世界法线和完整参考相机矩阵。需要改变屋檐、开洞或树冠轮廓时，先由Stage体现，再重新采集底稿，不让画稿替未存在的几何制造入口。

| 视角用途 | 整体艺术重点 | 必须保持的空间事实 |
| --- | --- | --- |
| [南段实际底稿](concepts/chengdu-art-street-20261108/south-camera.png) | 主街纵深、铺面节奏、屋檐与树冠叠层、统一光色 | 实际相机、街宽、建筑／巷口位置与可走中线，不新增挡路物 |
| [中段实际底稿](concepts/chengdu-art-street-20261108/middle-camera.png) | 首街中段的铺面、现有门窗深度与檐口厚度 | 原门窗／门洞位置、裁切与透视，不放大镜头或给实心mesh添加画中入口 |
| [横巷实际底稿](concepts/chengdu-art-street-20261108/lane-camera.png) | 分岔关系、转角、墙脚和侧背面连贯 | 主街连接、真实侧墙／背墙、树干与树冠位置，不把正立面翻贴到侧墙 |

共同约束是保留几何、通路、相机与真实树冠锚点；不重画人物，不含UI，不凭画稿新增门洞。完整构图的改善应在此前提下，由实际Stage和校准绘景共同提供。

## 运行与产品边界

继续复用 [`shu_chengdu_scale / 0.7.0`](../games/shu_chengdu_scale/game.json)、原 [`catalog`](../games/chengdu_scale_catalog.json)、[`walks.json`](../games/shu_chengdu_scale/walks.json)及 [`chengdu-scale-layout.json`](../assets/data/chengdu-scale-layout.json)。原位置、时间、数值、旗标、回执和保存仍由唯一EngineSession负责；师徒选择／五剑、伞／归还重访、双门茶馆、Load、返山与重置保持。

玩家相机继续跟随整座大城中的人物，不把三张原画改为固定屏幕背景或三个固定房间。[新Stage](../addons/cultivation_mode/chengdu_art_street_stage.gd)及[纯表现配置](../assets/data/chengdu-art-street-layout.json)提供18栋街屋与2株庭树的几何和环境。[世界投影适配](../addons/cultivation_mode/chengdu_art_street_art.gd)只覆盖地面、屋顶与树叶；灰泥墙、木构、深色构件和门窗保持统一底材及真实几何，人物、UI和旧南门绘景独立保留。每屋固定参考优先级、每片元只取一张有效画稿的RGB；地面依固定世界锚点排序，不让当前跟随相机决定画稿或混合多张RGB。屋顶ID内侧退让3像素，树叶／地面不退让，中段排除6个会投出额外假树的源签名；配置见[calibration.json](../assets/art/chengdu_art_street/calibration.json)。运行仍为9个sampler，采集颜色补偿仅在离线脚本中使用。

本片只改18栋的表现，574栋保持，原592栋／622障碍、相机与导航不变，原0.7.5的382个输入逐字保留。新[入口](../scenes/demos/cultivation_engine_chengdu_art_street.tscn)为 `cultivation_engine_chengdu_art_street.tscn`，app `0.7.6-art-street`，用户目录 `shu-chengdu-art-street-20261108`，保存位置 `user://chengdu_art_street`。旧18864—18869页面仍与冻结包字节相同。新户外仍不等于新室内、店铺交易、剧情或持久状态；不更改剧情归档规则。

当前是可试玩整体街区候选。最终中段／横巷图审中，原先窗边条纹、假树矩形和树冠绿硬环已消除；小瓦纹与绘景边界仍可能偏移，参考不可见面保留底材，原画烘焙的日光不等于任意实时重打光。其余大城沿用此前风格，不宣称已达到旧茶街最终完成度或获得全城美术认可。

实际应用UI截图：[1152×720首街中段](../.local/qa/chengdu-art-street/native-wayland-1152/1152x720_01c_art_street_middle.png)、[960×600横巷](../.local/qa/chengdu-art-street/native-wayland-960/960x600_01d_art_street_lane.png)。这两张是本地QA记录，不作为版本化美术素材。

## 制作记录与QA框架

最终候选证据分层如下；采集、GPU图审、完整输入及用户认可分别记录。

| 记录层次 | 本轮需要的证据 | 当前状态 |
| --- | --- | --- |
| 几何与三机位底稿 | 实际新Stage／配置、无UI／人物底稿、参考相机与表面身份，引用同一冻结来源 | capture stage `78301c421df8`采集exit0，最终日志无ERROR／WARNING；三底稿在数据pass修正前后逐字相同 |
| 几何数据独立核验 | ID与源签名识别地面，完整VP逆矩阵射线求交，与packed深度／法线独立比较 | 3视角共15可靠点PASS；原深度阈值0.03米，实际最大误差0.000923米；法线UP角最大0.225573°，阈值2° |
| 校准绘景生产 | 准确prompt／参考、每次结果、原PNG、SHA和来源 | 4次成功下载，3选定／1拒绝，0自动重试；三张选定原PNG逐字安装 |
| 最终GPU图审 | 同实际观察点检查画稿可见、源边界与原几何 | `reliable-surfaces-review`中段／横巷已分别独立图审；固定单画取色及仅可靠表面覆盖后，重影、假树矩形和绿硬环已消除；不等于用户视觉通过 |
| CPU范围与旧来源保护 | 独立结构／生命周期合同、源范围与冻结字节 | 17767项CPU检查、84项保全PASS；407输入的源码／stage／导入字节一致，旧382输入保持；18屋改／574屋同，592屋／622障碍不变 |
| 最终构建与状态 | 同一来源固定引擎导入、状态／导航检查、Web导出 | `stage-318a71eed049`，407输入，runtime `1585e03dc669ba88658d4dc87483ff0ff540053f4d61e2865f933d75a7bb37b4`；导入exit0，184＋2303＋51＝2538项0失败，单线程Web导出exit0 |
| 完整原生输入 | 两尺寸实际Wayland窗口与鼠标／键盘分发，日志与正常退出 | 1152×720及960×600各264项／20张UI图／0失败，均exit0、日志问题0；合计528项／40张UI图。实际完成师傅互动与行动结果、南门→首街5观察点→横巷→远城、取伞保存／归还／重访、双门四向、Load全字段、返山与确认重置；不累计被拒绝候选 |
| 最终应用像素A/B | 同一真实应用暂停后只切换新绘景，人物／状态／相机不变 | 两尺寸各2张on／off诊断、合计4张viewport图，另于40张UI图。1152变化328232／921600像素（35.62%），960变化315429／921600（34.23%）；仅证明绘景实际贡献，不是性能或用户审美结论 |
| Web导出与HTTP | 新预览及产物与导出磁盘逐字一致 | [18871](http://127.0.0.1:18871/)已启动；5文件HTTP200并逐字一致。PCK141161556字节，SHA256 `6b269f3ba3b0a77a82d29d7e0bbe6193b8878c790058ddada75488a84df91294`；旧18864—18869保持 |
| 真实Web UI／其他平台 | 实际浏览器输入与保存刷新，平台／声音／性能另记 | 未验证。Chrome新tab返回handle，但goto／DOM快照／关闭均报内部timeoutMs错误；open_in_codex仅queued，未观察页面。Windows、声音、实体输入及性能未验 |
| 用户视觉验收 | 实际运行的完整街区是否缩小与旧茶街的差距，连续镜头下是否成立，下一修订点 | 待试玩，只有用户反馈可关闭 |

保持Godot4.7.2 stable、GDScript、Compatibility和匹配的Web单线程模板。冻结helper SHA前缀 `115ff564`、Stage `398f3ad1`、layout `19dfe109`。日志、截图、生产回执与缓存进入忽略的 `.local/`；本轮不提交、push、合并或公开发布。

失败证据保留在 `.local/qa/chengdu-art-street/`：首次capture有nonindexed mesh运行错误，已作废归档；一次字体导入发生SIGSEGV，保留首轮日志，同一stage重新导入及最终采集均正常退出。另两轮数据pass分别暴露逆sRGB处理错误和Compatibility cubic ALBEDO转换造成的深度高字节偏差，旧FAIL收据均保留。修正只在采集脚本：固定4.7.2 Compatibility下，以16轮二分逆cubic转换，正值使用对应power目标、零值保持零；同GPU256灰阶逐字相等后，再通过上述原阈值地面求交核验。这两项采集数据修正没有改变运行shader的数据解码或降低核验阈值；后续选画与覆盖范围修订另见上文，其他renderer的采集转移未验证。

早期 `first-paint-review` 只证明1张south画稿在3观察点实际显示；其像素比例不作最终三画稿证据。随后 `035619` 候选虽有526项／40图原生记录及导出，但多画RGB融合造成双窗和树干重影，已拒绝，不能累计到最终结果。最终改为固定单画及可靠表面覆盖，没有追加生成。

证据统一在 `.local/qa/chengdu-art-street/`：`stage.json`、`check-exits.json`、`capture/capture-summary.json`、`geometry-validation.json`、`transfer-compensation-gpu.json`、`reliable-surfaces-review/`、`architecture/preservation-audit.json`、两份 `native-wayland-*/chengdu-scale-render-report.json`及各自像素A/B、`http-artifacts.json`和`browser-attempt.json`；早期候选与失败日志保留。下一验收点是用户在大城连续镜头下试玩首街和横巷，评价整体构图、轮廓、生活层次与边界；技术通过不自动关闭视觉反馈。
