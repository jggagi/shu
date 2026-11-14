# 首街四屋精作样板：真实构件与新材质

客户端日期：2026-11-08，America/Los_Angeles。状态：0.7.5四屋与限定地面已实现；三次Ali在线图生图均成功下载、0重试，原PNG保持。最终383输入stage完成2538项状态、两尺寸完整原生600项／40张UI图及导出／HTTP，另留12张viewport A/B诊断图；独立CPU、源保护和限定地面GPU另列。18869已启动，实际Web UI未验证；用户最新反馈与此前小规模城镇场景仍有差距，当前美术完成度未获认可。

## 用户反馈与制作方法复核（同日）

用户指出「这个和我们之前打造的小规模城镇场景还有一定差距，为什么」。这是对当前画面质量的负向反馈，不能把上面的技术通过或此前concept认可当作0.7.5实际美术已验收。

Codex对照旧茶街画稿与实际制作记录后判断：旧场景按完整街景统一绘制建筑、树木、家具、岸线和光影，当前只生产三张基础材质、补充四屋构件，原有规则体块、重复街面与大部分周边仍保留，未充分迁移整幅场景的美术组织。连续跟随确实需要处理更多侧背和视点，但不意味着大城必须降低美术标准；现有证据也不能将差距归咎于百炼模型。下一实施提案应先以一段完整街区统一轮廓、环境层次、铺面与光色，在原连续镜头中做实际质量对照，达到旧茶街的整体完成度后再推广。该修正是诊断与提案，本轮仅记录反馈，未新增生图、改布局或启动重制。

## 已确认与本轮范围

用户已批准主街、侧巷、铺面三张concept方向，并授权通过百炼Ali制作本轮铺地、灰墙和屋瓦材质。已批准的是参考方向与该制作范围，不把concept或在线出图成功当作运行画面、可平铺或完整精作的认可。

本轮先在原街区四处建筑与限定主街／侧巷地面做0.7.5样板。四屋沿用原地块、类型和朝向，着重真实脚点、门窗凹进、屋檐厚度及侧背面的连续表现；四屋构件和材质已在实际Stage接入，新增53个mesh，不以一张正面贴图代替完整外观。本轮是四屋样板，不宣称整城精作完成。

| 四屋 | 原地块ID | 原范围 `[x,y,w,h]` |
| --- | --- | --- |
| 茶铺 | `ward_city_22_19` | `[8250,7220,170,160]` |
| 布铺 | `ward_city_23_15` | `[7250,7470,170,160]` |
| 民居 | `ward_city_23_19` | `[8250,7470,170,160]` |
| 两层民居 | `ward_city_22_16` | `[7500,7220,170,160]` |

选定范围记录在本轮 `.local/qa/chengdu-crafted-street/production-plan.json`。主街 `[7800,7560] → [7800,7290]` 与横巷 `[7450,7420]` 用于观察四屋、侧面与脚点；本轮真实应用和完整原生沿街行走结果见下表，用户对新画面的认可另待试玩。

## 空间、状态与旧版本保护

15360×11520连续城市、592栋原住宅、622处原障碍、原通路和导航保持，全城镜头继续跟随人物；不缩放城市、人物或镜头。继续复用 [`shu_chengdu_scale / 0.7.0`](../games/shu_chengdu_scale/game.json)、原 [`catalog`](../games/chengdu_scale_catalog.json)、[`walks.json`](../games/shu_chengdu_scale/walks.json)及 [`chengdu-scale-layout.json`](../assets/data/chengdu-scale-layout.json)，由唯一EngineSession管理位置、时钟、数值、旗标、回执和保存。

保留原师徒对话与选择、五剑、伞／归还重访、茶馆双门、保存／Load、返山与确认重置。四屋仍是外景，不新增可进入铺面、可上楼空间、买卖、剧情、持久字段或任务；新材质与视觉构件不改变通行。原南门绘景、全城既有六格材质以及本片之外的建筑保持原范围，具体保护在最终字节／几何核验记录。

旧0.7.4文件、18868预览、素材及存档保留，技术与用户反馈见[10栋建筑变化切片](CHENGDU_VARIED_STREET_SLICE.md)。新应用 `0.7.5-crafted-street` 使用独立用户目录 `shu-chengdu-crafted-street-20261108` 与SaveStore `user://chengdu_crafted_street`，入口与文件如下。

| 用途 | 实际文件 |
| --- | --- |
| 场景入口 | [`cultivation_engine_chengdu_crafted_street.tscn`](../scenes/demos/cultivation_engine_chengdu_crafted_street.tscn) |
| 表现适配 | [`chengdu_crafted_street_mode_view.gd`](../addons/cultivation_mode/chengdu_crafted_street_mode_view.gd)、[`chengdu_crafted_street_walker.gd`](../addons/cultivation_mode/chengdu_crafted_street_walker.gd) |
| 四屋与材质 | [`chengdu_crafted_street_stage.gd`](../addons/cultivation_mode/chengdu_crafted_street_stage.gd)、[`chengdu_crafted_street_surfaces.gd`](../addons/cultivation_mode/chengdu_crafted_street_surfaces.gd) |
| 纯表现配置 | [`chengdu-crafted-street-layout.json`](../assets/data/chengdu-crafted-street-layout.json)，四屋、采样与限定地面三块范围，无新玩法／碰撞 |
| 新预览 | [18869四屋试玩](http://127.0.0.1:18869/)，最终五文件HTTP字节核验通过，实际Web UI未验证 |

## 三张新材质：实际来源与限制

[`source.json`](../assets/art/chengdu_crafted_street/source.json)记录提供方Qwen、模型 `qwen-image-3.0`，三次串行图生图、0自动重试，实际使用付费API。每次输入两张已批准参考、输出一张1024×1024 RGB图；`prompt_extend=false`、`enable_thinking=false`、`watermark=false`、`n=1`。三张均已在线成功并下载，当前状态为 `SELECTED_FOR_SCENE_REVIEW_USER_PLAYTEST_PENDING`。

| 材质 | 运行PNG／SHA256 | 精确提示词 | 两张参考 |
| --- | --- | --- | --- |
| 铺地 | [`paving.png`](../assets/art/chengdu_crafted_street/paving.png)；`fc95222ff41d31514d91fb93d70022adcdeb0c30a4fa4e267b54ad6e96cda0fb` | [`01-paving.txt`](../art/prompts/chengdu-crafted-street-20261108/01-paving.txt) | [主街concept](concepts/chengdu-street-references-20261108/01-main-street.png)＋[原茶街风格图](concepts/chengdu-painted-gate-20261108/town-style-reference.png) |
| 灰墙 | [`plaster.png`](../assets/art/chengdu_crafted_street/plaster.png)；`099016d92b36561c84c49b217e3329ce9b97447f32b7843b277f374b61008635` | [`02-plaster.txt`](../art/prompts/chengdu-crafted-street-20261108/02-plaster.txt) | [铺面concept](concepts/chengdu-street-references-20261108/03-shopfront.png)＋同一原茶街风格图 |
| 屋瓦 | [`roof.png`](../assets/art/chengdu_crafted_street/roof.png)；`d4400e08f30fce43b33a45e3bcd6a4bac656f2f1275511ab6b0ae3a5820f3b19` | [`03-roof.txt`](../art/prompts/chengdu-crafted-street-20261108/03-roof.txt) | [侧巷concept](concepts/chengdu-street-references-20261108/02-side-lane.png)＋同一原茶街风格图 |

三张运行PNG与提供方原下载字节相同，没有离线改图。来源文件保留每张prompt及参考的准确路径、尺寸、SHA和请求参数；生成项目素材适用提供方条款，不另声称第三方许可。原图审阅记录为正视基本色纹理，无人物、文字或透视场景，不包含门窗立面插画；不从素材成功推定门窗几何已实现。

图像本身不保证无缝。已实现的内存派生按 `source.json.runtime_derivation` 处理：铺地取 `[4,4,1016,1016]`，灰墙取 `[96,96,832,832]`，屋瓦取 `[8,8,1008,1008]`；只在两轴24px对边条带内向成对均值混合，使最外沿相配，再生成mipmap，无镜像或离线新图片输出。gain分别为0.95、0.84、0.90。限定地面以不透明材质替换原4个plane，只在三块羽化范围接续主街／横巷／布铺巷，铺地周期3.2m，不新建地面网格或改变高度；实际像素与mask范围证据见下表。在线成功与本机配置状态分别见[百炼配置追记](QWEN_ART_SETUP.md)，本文不记录凭据或实际接口／工作空间地址。

## 本轮可观察验收点

1. 人物从主街到横巷时，脚点落在实际地面，门前与墙边接触自然；铺地纹理随世界表面稳定，不随屏幕漂移，地面接缝与重复边缘不抢眼。
2. 茶铺、布铺、民居和两层民居的门窗有可读的凹进、框体与厚度；在斜看和侧移时仍是构件深度，不能只在正面像一张贴纸。
3. 屋檐有真实出挑和厚度，屋顶退隐、角色遮挡和深度正确；构件留在原地块内，不堵主街或横巷。
4. 穿行前后能看到合理的侧面和背面，正侧转角、屋檐、墙脚及材质连续，不把正面图直接拉到侧背。
5. 原地图／点击行走、师徒选择、伞、茶馆双门、保存恢复、返山与确认重置保持；四屋以外的大城和旧0.7.4预览保留。

上述目标的技术检查范围与用户观感分别记录；场景图、CPU范围／绑定、连续镜头、完整原生、导出／HTTP和真实浏览器不互相代替。

## 最终验证记录与下一试玩点

最终应用stage为 `.local/build/chengdu-crafted-street-20261108/stage-991bd615f215`，383项输入，runtime digest `324569d90f52ea273cf92321ad4aad0bec601a944bd24e930544ba5b022b9c75`。本轮QA在 `.local/qa/chengdu-crafted-street/`，工作树为 `codex/chengdu-connected-streets` / `7c992c578b1fe4a1624c769812425b38080771d3` 加已有未提交修改。

| 层次 | 最终真实范围 |
| --- | --- |
| 用户授权 | 三张concept方向与Ali三材质制作已批准；运行画面的新观感待用户试玩 |
| 在线素材生产 | 三次串行图生图均成功并下载，每次两参考／一张1024RGB，0重试；原PNG与来源记录保持 |
| 四屋实现与CPU | `architecture/final/cpu.json`通过19494次结构断言，非19494项游戏流程；四屋几何／材质变化、53个新增mesh，其余588屋保持，622障碍、镜头、导航与唯一Session边界保持，原plane只换限定材质。CPU／headless结构不当作画面或帧率证明 |
| 独立源审／保全 | `architecture/source-review.json`31项、`architecture/preservation-audit.json`37项均PASS，错误／pending空；绑定本轮stage、CPU、地面GPU和原生报告。原372输入仅构建登记工具有授权变化，新383输入与source匹配，旧stage及原PNG保持 |
| 限定地面GPU | 原4个plane的独立fixture13项通过；mask外497450像素均不超过1级8位RGB差，证明该fixture下范围外保持，不等于全城每像素图审或用户观感通过 |
| 短真实应用／素材贡献 | 实际应用149项／10张UI图，单独记录、不累入完整原生；1152短图只切换新材质，240532／921600像素变化，证明真实贡献，是像素A/B而非性能数据 |
| 最终完整原生 | 1152×720、960×600两实际窗口各300项／20张UI图／0失败／正常退出，合计 **600项／40张UI图**，日志无问题；沿主街／横巷与原城市完成原行为、双门／伞、保存Load、返山与重置。另每窗6张viewport A/B诊断，合计 **12张诊断图**，不混入UI图或累计短流程 |
| 状态／导入／导出 | Godot4.7.2／Compatibility／匹配Web单线程；导入约10.69秒，基础184＋Scale2303＋导航51共2538项／0失败，导出约2.97秒，均正常退出 |
| 最终HTTP／旧预览 | 18869已启动，五文件均HTTP200且完整字节SHA与磁盘一致。PCK **133566056B**，SHA `f184200278910a44f54dfae03de5c6977a5ba370e4d872af58616cae5e2cb69f`；HTML SHA `c073411803a3451f6a68869341cfea4eca7d076085e7b605174314b7aa3d4998`。旧18864—18868页面保持原冻结字节；HTTP不代替Web UI |
| 最终汇总 | `final-delivery.json`实际为PASS，383输入的source manifest不一致表为空；2538状态、600完整原生／40张UI图、12张viewport诊断与独立核验分别绑定本轮stage，未借用旧版本计数 |
| 实际Web UI／保存刷新 | **未验证**。CUA现能发现并选择Chrome，但多种已记录的tab创建方式均触发内部 `timeoutMs` 错误，未获得可控页面；未观察游戏导航或保存刷新，工具故障与游戏运行结果分开记录 |
| 设备／声音／性能／观感 | Windows、声音、实体输入、长期、性能及用户运行观感未验；结构断言与像素变化不作稳定帧率承诺 |

保持Godot4.7.2 stable、GDScript、Compatibility及匹配Web单线程模板。日志、截图和临时产物继续进入忽略的 `.local/`。现请用户沿主街—横巷试玩四屋，判断脚点、门窗深度、屋檐和侧背面是否自然，再决定下一修订。本轮不提交、push、合并或公开发布，不自动将样板扩成全城新构件或更多生图。
