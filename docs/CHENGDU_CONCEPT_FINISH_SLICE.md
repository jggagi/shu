# 成都首街：概念图差距修订

客户端日期：2026-11-09，America/Los_Angeles。用户要求「比较一下实现和参考概念图的差距，想办法fix」。这是对表现差距的修订授权，不是对0.7.6.1美术的认可。保留15360×11520、592栋住宅／622障碍、连续跟随、原导航及唯一EngineSession。本轮仍是首街样板，不自动表示全城已达到概念图完成度。

## 实际对照与实施选择

对照[主街concept](concepts/chengdu-street-references-20261108/01-main-street.png)、[横巷concept](concepts/chengdu-street-references-20261108/02-side-lane.png)、[铺面concept](concepts/chengdu-street-references-20261108/03-shopfront.png)，与0.7.6.1同机位[实际中段](../.local/qa/chengdu-ground-flicker/after/baseline/0364_middle.png)、[横巷](../.local/qa/chengdu-ground-flicker/after/baseline/0518_lane.png)。参考与实景的街宽、人物比例基本能对应，差距不能归结为城市太大。

| 影响观感的差距 | 本轮修正 |
| --- | --- |
| 墙几乎纯白，橘色木框与深窗缺少材质层次 | 新斑驳灰泥／深茶褐木材，按真实米制世界坐标取样，18栋原街屋统一绑定，保留实际门窗开口；墙脚有受潮旧色 |
| 瓦顶读成暗色曲板，瓦口和檐下体积不明显 | 新冷青灰瓦纹与暖灰磨损边，四栋关键屋补真实筒瓦端、短梁头及石脚分块 |
| 两株树像贴皮圆球，缺少枝隙与不规则轮廓 | 原两株庭树的球冠隐藏，保留树干锚点；使用黄绿细叶、透空原画与世界空间叶簇卡片 |
| 铺面像普通木墙，柜台与器物过小 | 四栋关键屋补侧窗横档、柜面、竹帘及有限壶／托盘／布巾／缸篮层次；没有新增NPC、交易或室内玩法 |
| 路面过净、长条缝均匀，接地关系弱 | 粗旧宽短石板、缺角裂缝及轻苔；在原地面与原绘景pass中取样，没有新加共面地面贴片 |

四个关键地块为 `ward_city_22_16`、`ward_city_22_19`、`ward_city_23_16`、`ward_city_23_15`；树仍是 `ward_city_22_15`、`ward_city_23_19`。新构件分批次独立挂在原建筑上，原批次mesh签名不改；不把旧ID／深度校准强行套到新细节。所有新构件排除旧绘景匹配，原0.7.6.1地面唯一归属与0.01米深度修正保持。新增材质和投影取色在本实例内适配，离开恢复；绘景pass为10个sampler，原画、校准及数据PNG保持原字节。

## 本轮素材

用户继续使用既有北京百炼配置。初始系统钱包锁定，0次线上调用；用户回复「已解锁」后完成两次串行标准 `qwen-image-3.0` 生产，0自动重试，无Pro调用。选入原PNG与完整来源见[素材记录](../assets/art/chengdu_concept_finish/source.json)，精确prompt见[材质](../art/prompts/chengdu-concept-fix-20261109/01-surfaces.txt)及[叶簇](../art/prompts/chengdu-concept-fix-20261109/02-foliage.txt)。

`surfaces.png` 为1024²四格RGB：灰泥、屋瓦、石板、木材。运行按512²分格、16px对边处理后独立生成mipmap，不声称原图天然无缝。`foliage.png` 是RGB近洋红背景，没有真实alpha；运行按色差剔除背景并处理边缘，原PNG不修改。两项都先检查素材，再做实际场景图审，不把素材生产成功等同于用户视觉认可。

## 验证与下一验收点

最终为 `stage-a41a91f40c45`，app `0.7.7-concept-finish`，412输入、runtime digest `1f12015f67a6ca4879d1cbe0546e1b589a49a1ba5717d515220a044bf000c191`。HEAD仍为 `7c992c578b1fe4a1624c769812425b38080771d3`、dirty；Godot4.7.2 stable／Compatibility／匹配单线程Web模板不变。材质helper SHA `256de41d622fb7672e4af2fe410b06f9fa3595ac115c6d16ce5fe4f2a6d7e52f`，细节helper SHA `ad05ee01e69002baba3e78506cf6ef96142791b4999e6d986a5a21cb1e3e1d44`。

| 实际验证范围 | 最终结果 |
| --- | --- |
| 素材 | 2次标准3.0成功调用、0自动重试；原PNG SHA保持，4格运行分离／接缝处理与叶RGBA派生可复现 |
| 原来源保护 | 412 source／stage SHA一致；原407中405逐字保留，只改Stage接线和builder登记、5项新增；原绘景、校准、核心d322地面修复及导航／状态保持 |
| 独立CPU | 38项审计、70,521项实际两helper合同0失败、日志无ERROR／WARNING；原7895几何顶点／UV／法线／索引／变换不变，4关键屋22个细节材质、24批次及两树均在原lot内；真实Stage退出与原row／表面对象恢复通过 |
| 叶派生 | 原RGB在过滤前按色差转RGBA，补透明边缘再生成11层mip；两树共享，实际headless派生约146ms，非FPS结论。全部mip的可见强洋红像素为0；仅6个低层mip有小色差，不夸大为每个像素绝对无色差 |
| 构建与状态 | 导入exit0，184＋2303＋51＝2538项状态／导航0失败，Web导出exit0；日志无错误警告 |
| 原生完整输入 | 1152×720、960×600各264项／20张UI图／0失败／正常exit0、日志问题0，合528项／40图，另4张绘景A/B；师傅互动、行动结果、首街／横巷／远城、伞／重访、双门、保存Load、返山和确认重置通过 |
| 实际移动与图审 | 同761帧路线、2组各65张PNG，相机轨迹差0；独立审阅10张最终实景，瓦口／窗格／墙面／石路可读，没有先前三角撕裂、地面矩形或粉红碎边 |
| 地面时序回归 | 沿用修闪光时冻结420点／5294对相邻帧，p95跳变1.4532→1.2393级，≥12级短亮峰仍为0；严格365点子集1.0609级／0峰，两已知闪点未复发。数字不是全城全部渲染帧保证 |
| 预览 | 原[18871](http://127.0.0.1:18871/)同源更新，5文件HTTP200且完整字节与最终包相同；PCK143501552字节，SHA `cb3ab4db5c942cde054369a89549728435664f84fdd09f59d85e3a75625278d8`。原用户目录 `shu-chengdu-art-street-20261108`、保存 `user://chengdu_art_street` 保持 |

实景对比：[主街概念／改前／改后](../.local/qa/chengdu-concept-fix-20261109/comparison-middle.png)、[横巷对比](../.local/qa/chengdu-concept-fix-20261109/comparison-lane.png)。这些是全帧等比缩放的QA组合，未裁切／修图；准确来源SHA另有 `comparison-source.json`。实际UI：[最终主街](../.local/qa/chengdu-concept-fix-20261109/native-wayland-1152/1152x720_01c_art_street_middle.png)。

证据位于 `.local/qa/chengdu-concept-fix-20261109/`：`stage.json`、`check-exits.json`、`after/summary.json`、两原生exit／报告、`after-temporal.json`、`known-spikes-before-after.json`、`independent-final-review.json`、`http-artifacts.json`及`final-review.json`；独立结构证据在 `.local/qa/chengdu-concept-finish/architecture/`，最终 `preservation-audit.json` 绑定同一来源。与[地面修复](CHENGDU_ART_STREET_SLICE.md)原记录分开。

第一轮 `stage-79b8714b8b7e` 的构建、2538项状态、Web导出与两尺寸完整原生流程虽通过，实际图审发现叶簇过小且过暗，不能作为最终观感交付。随后只调整叶簇朝向／冠幅与材质配色，没有追加生图；最终来源和验证另记。

第二轮 `b5e36ab6c5e7` 的叶卡扩大后出现粉红碎点，是RGB缩小采样把背景与细叶混合造成，不能以CPU结构通过替代图审。最终改为缩小过滤前派生RGBA，透明RGB边缘修复后再生成mip，原图不修改；该候选同样归档，不累计为最终原生结果。

仍有可见差距：叶卡存在扇形／平行枝纹的片状感，重复屋型与街面净空依然较规整，铺面陈设和人物活动不及近景concept；旧绘景烘焙日光与新材质实时光之间仍有局部边界。这里交付本轮可观察的改进候选，不声明复制了concept或全城达到最终美术完成度。CUA本轮库存为空，真实Web UI、浏览器保存刷新、Windows、设备听感、实体输入及性能未验证。

下一试玩点：正常窗口下走主街中段、进入横巷并看茶铺，直接辨认墙皮／石脚、瓦口、透空树冠和铺面层次；同时观察地面不再闪光、人物脚点和通路正常。具体美术完成度仍由用户试玩判断，Windows、声音、实体输入、浏览器保存刷新及性能未测则不补签。没有本轮提交、push、合并或公开发布。
