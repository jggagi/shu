# P3a · 松风古道细节修订

用户后续回复「统一」，后继[松风古道光影统一](P3_SONGFENG_LIGHTING_SLICE.md)已完成本机与实际PCK检查，当前入口18823、观感待用户试玩。本页18822、802项／41图及原生短测保留为细节候选证据，不覆盖后继光影修订。

客户端日期：2026-10-24，America/Los_Angeles。状态：**细节已接入，最终本机与实际PCK检查通过，当前视觉候选待用户认可**。用户认为上一版环境不够精细，授权针对扁块叶冠、大平面山崖和较裸地面直接修订；本轮继续同一场山道遇袭。旧[18821环境及941项／63图](P3_SONGFENG_ENVIRONMENT_SLICE.md)保留为前轮证据。

## 实际变化与来源

- 盘松已换为原创多级根干／枝条、真实针叶几何与已有CC0针叶贴图组成的GLB：32,320三角面、3个mesh、1,869,488字节。只有WindCrown微动，最大0.007弧度，根干与主枝固定；来源、可编辑Blend及SHA见[盘松来源](../assets/art/mountain_ambush/environment/source-detail-pine.json)。已有贴图仅缩图嵌入，没有新生成raster。
- 近处崖壁增加分块、裂隙和岩层；岩石与暗砾显式处理线性色域。古道改为中性灰石片、低苔色地面，增加22块石片、260个浅埋暗砾与22处草；原52项ProtonScatter布局保持。具体资源与着色见[细节来源](../assets/art/mountain_ambush/environment/source-detail-environment.json)。
- 当前实际runtime为5份GLB：两种岩石、grass-a、grass-b和新盘松。grass-b是本轮新消费的既有资产；stone-step与pine-source仍保留源码原字节，但不进入本轮运行闭包。

同一9×7平地规则、角色、Session和存档保持；16项保护文件、7份角色代码／GLB、Stage／View、原字体及江原Blend的SHA与444权限均核对保持。场景动静继续由stage统一驱动，「景物：静止」不暂停战斗。只复用已有免费CC0素材与原创几何，无采购、云端生成、依赖安装、Git提交／推送或公开发布。

## 最终检查与产物

最终stage为 `.local/build/songfeng-detail-20261024/stage-6f746738a1db`，252项源与stage逐SHA一致；版本 `0.4.6-songfeng-detail-candidate`，custom userdir `shu-mountain-ambush-songfeng-detail`。673码点字体字节保持。权威汇总为 `.local/qa/songfeng-detail/final-validation.json`，逐条命令／日志、导出检查见同目录 `final-commands.json` 与 `creator-game-check.json`。

Godot4.7.2／Compatibility、Web单线程；导入、导出及规则52／会话84项全部退出0，无脚本／资源警告错误。实际Godot输入注入与渲染合计 **802项、41图、0失败**：

| 最终检查 | 结果 | `.local/qa/songfeng-detail/` 证据目录 |
| --- | --- | --- |
| 原生环境1152×720 | 219项／10图 | `final-native-environment1152/` |
| 实际PCK环境960×600 | 219项／10图 | `final-pck-environment960/` |
| 实际PCK反馈960×600 | 120项／11图 | `final-pck-feedback960/` |
| 实际PCK完整流程1152×720 | 244项／10图 | `final-pck-flow1152/` |

覆盖格子投影与遮挡、景物动静／复位／释放、击退／碰撞／截脉指、胜败／重试／返城、安全存读与返山师父选择。本轮不重复人物suite；角色相关原资源保持的来源检查与前轮人物结果分别记录。独立来源审查49项、两尺寸4图视觉复核均PASS，见 `independent-source-audit.json`／`independent-visual-review.json`，不追加到802项或当作用户审美认可。静态图不能证明远处针叶无闪烁。

Web共7文件、153,427,090字节；PCK为113,595,488字节，SHA256 `cb2fe4bbf42708d3ff052b9ee27e179dbaa79ceb1e8861197a1233bb213d69a9`。HTTP完整读回7／7与SHA一致，WASM MIME正确，见 `http-receipt.json`。主main干净并与origin/main `7c992c5` 一致，本轮源码仍为独立worktree的未提交修改。

## 原生负担观察与平台边界

环境本体为126个mesh、162,750三角面、303个节点；对象数变化不能单独证明Web性能改善。另对最终实际PCK做原生短测：60帧预热、180帧采样约4.115秒，60fps上限下实测 **43.75fps**，平均帧间隔22.86ms、p95为27.33ms、最大32.10ms，静态内存峰值157.35MB。每帧约1,978次draw call／494,448个primitive计入整个场景、UI、SubViewport与阴影；后台旧预览未停，负载未受控。该结果不代表满60帧、Web或长期性能，不计入802项。精确命令与数据见 `native-performance-receipt.json`／`native-performance.json`。

常驻新原生启动只有既有X11 `wd.xic` 输入法警告，无脚本／资源错误，见 `native-startup.json`／`.log`；上述Dummy音频QA日志干净，两者分别记录。CUA的apps／browsers为空，打开请求queued不能作为浏览器实操证据。浏览器输入／刷新／性能、用户视觉认可、实体输入、听感、Windows／Steam Deck、长期性能和真实旧档迁移仍未验收。

## 当前试玩与下一验收

在 **X1桌面内**打开[18822细节修订试玩](http://127.0.0.1:18822/)，或切到同PCK原生窗口。`shu-ambush-songfeng-detail-web-20261024.service` 与 `shu-ambush-songfeng-detail-native-20261024.service` 均active；旧18821及更早服务保持，未迁移玩家旧档。

先看盘松针叶／多级枝干、崖壁裂隙与古道路面，再切景物动静并正常移动、击退和使出截脉指。下一验收点是用户判断这轮精细度与战术可读性，并反馈实际浏览器流畅度；当前画面仍为审美候选。
