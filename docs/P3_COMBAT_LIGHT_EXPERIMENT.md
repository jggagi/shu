# P3a · 回澜剑战斗灯光实验

后继：[战斗整体打磨](P3_AMBUSH_POLISH_SLICE.md)已按「全部改进」授权更新人物镜头／UI、动作轻重和美术统一；18825现为0.4.11候选，请刷新。本页保留0.4.9／0.4.10的历史检查与六稿，不作为新版证据。

客户端日期：2026-10-25，America/Los_Angeles。当前：**已按动作偏快反馈完成0.65速修订及本机／实际PCK检查，新节奏待试玩**。用户反馈「好一些了，动作有点快」表示灯光方向改善，不等于全部视觉或新节奏已验收。承接[可破坏木栅切片](P3_SONGFENG_BARRICADE_SLICE.md)，保留原灯光实验与六稿证据；当前效果与商业参考品质仍有距离。

## 本轮节奏修订与当前18825

仅把战场出招、受击、击退及相连特效改为局部0.65速，不改规则或GLB／适配器。源动作命中0.13秒对应实际0.20秒，原0.32秒剑式约0.492秒，击退0.18秒约0.277秒，收势等待0.22秒约0.338秒；步行、待机、景物、UI／相机和试演0.70秒峰值停留保持。试演手动取样仍为源动作0.13秒，三档共用同一新节奏。

当前stage `.local/build/action-tempo-20261025/stage-3a7d1264fed0`，262项源／stage逐SHA一致，runtime digest `aa689fd4e165b1797b92c15e139c68edeed467a64efcefc47f423350a47333f7`；app `0.4.10-action-tempo-candidate`，gamepack仍0.4.1。同18825和userdir `shu-mountain-ambush-combat-light`已更新，**已打开的页面请刷新**；未执行自动刷新或验证浏览器重新载入。只替换旧18825灯光Web／原生服务，旧stage `f727ec60b10c`与产物留存，18824／18823保持。

比上轮262项输入仅9项变化：Actor wrapper、Stage、helper三份runtime，五份来源元数据和灯光UI测试。16项规则／Session／内容保护、除wrapper外其余6份角色代码／GLB、17项环境、两份光影JSON与原Blend SHA／444权限保持；696字形与字体二进制不变。独立来源29项、QA复核与最终6图审阅另记，不并入下列渲染数；节奏观感仍待用户判断。

状态52＋127＋86＝265项；四套真实Godot输入检查共 **1048项／41图／0失败**：原生灯光1152×720与实际PCK灯光960×600各334项／10图，PCK反馈960×600为130项／11图，PCK全流程1152×720为250项／10图。9条最终命令exit0、Dummy QA日志无警告错误。覆盖新节奏、试演状态保持／busy门禁／资源恢复、反馈与胜败重试、返回城镇、安全存读及返山师父选择。没有把上轮1496项／62图或性能probe计为本轮新检查。

命中反馈点实测：原生回澜／截脉指分别199／199ms，实际PCK197／198ms，Stage／Actor／helper速率均0.65；该点Actor elapsed约0.14083秒，是演员源动作时钟，不能当成原GLB完整clip的绝对偏移。命中时序按实际反馈信号记录，存在帧采样量化。未重跑性能，不提供本轮FPS结论，上轮60cap短观察仅归前轮。

Web7文件153,473,184字节，PCK113,641,572字节，SHA256 `5180b79da1e8f2a7410195af863db3b6873796aabebf6d20a03cad37bb39beca`。HTTP7文件完整SHA／WASM MIME与creator-game-check通过；`shu-ambush-action-tempo-web-final-20261025.service`及`shu-ambush-action-tempo-native-final-20261025.service`均active，旧18825 combat-light两服务已停止。新原生常驻仍只有既有X11输入法警告，无游戏脚本／资源错误；主main干净并与origin/main `7c992c5` 一致，候选worktree保持dirty，未提交推送。

本轮权威证据为 `.local/qa/ambush-action-tempo/final-validation.json`，命令与日志见同目录 `run_final.py`、`final-commands.json`及四个 `final-*` 报告，独立复核见`independent-source-audit.json`、`independent-qa-review.json`、`independent-visual-review.json`，交付见`http-final.json`、`native-final.json`、`replaced-preview-services.json`和`creator-game-check-final.json`。浏览器刷新／输入／性能、Windows／Steam Deck、实体输入、声音、持续性能及真实旧档迁移未验收。

下一验收聚焦放慢后是否清楚或拖沓，以及撞栅长链中剑式已收势、光弧仍随撞击链驻留是否合适。短时浮字叠头牌、窄窗计划列滚动的既有限制保留；用户新节奏认可仍待试玩，不自动批准新招式或其他扩展。

## 实际演出与试玩

同一战局中点击演出按钮循环三档，默认第三档；以江砚秋回澜剑作同姿态对照，真实两名友方的push／strike／interrupt攻击复用同一小型灯光helper，截脉指为青绿色，敌方不增加招式灯：

| 档位 | 实验内容 |
| --- | --- |
| 原演出 | 保留原灯光，不增加招式灯；三档共用本轮动作节奏。 |
| 招式光 | 随招式时点加入短时点光与原创剑弧，不增加该灯的投影。 |
| 光与投影 | 使用相同光色、几何与时序，增加Cube实时点光投影。两档感知亮度并未证明完全匹配。 |

在 **X1桌面内**打开[18825试玩](http://127.0.0.1:18825/)，或切到同PCK原生窗口。先点「近看回澜」，再切另一档重复比较，最后正常出招撞栅或拆侧路。试演临时把正交size乘0.78，在原获批动作0.13秒姿态停留0.70秒后恢复相机、角色朝向／根变换与处理状态，回到待机；不扣行动或游戏时间，不改变HP、回合、药篓、木栅与持久状态。真实攻击不增加该停留或zoom，仍由原事件序列驱动命中、受击与结算。

试演与真实动作期间锁住环境光影／演出／试演控件，恢复基线后解锁；景物动静仍独立。每次最多一盏短时点光，恢复／离场即释放灯与剑弧。最终使用普通深度测试的白芯暖边剑弧，Glow关闭、曝光乘数1，保留天空配色。不引入LightmapGI、SSAO、体积雾或内置景深。

Godot4.7.2／GDScript／Compatibility与Web单线程路线保持。只做本地原创视觉实现，不复制参考游戏的源码或资产，不换引擎／渲染模式，不做采购、安装、云图生成、Git提交推送或公开发布。

## 首轮灯光基线与历史候选

基线为前轮stage `58998e8275cb`，完整build-info、258项SHA与HEAD／dirty保存在 `.local/qa/ambush-combat-light/baseline.json`。最终stage为 `.local/build/combat-light-final-20261025/stage-f727ec60b10c`，262项源与stage逐SHA一致；比基线旧输入9项改动、新增4项、无移除。app `0.4.9-combat-light-candidate`、gamepack `0.4.1`、独立userdir `shu-mountain-ambush-combat-light`，不迁移旧档；696码点实际字形覆盖完整。

16项Rules／Session／SaveStore／encounter／内容JSON、7份角色脚本／GLB、17项环境／光影输入及江原Blend SHA和444权限保持。运行来源见[本轮manifest](../assets/art/mountain_ambush/environment/source-combat-light.json)。主副本main干净并与origin/main `7c992c5` 一致，候选worktree保持dirty；旧18824／18823原生与Web保留，历史检查不并成本轮新检查。

## 首轮灯光检查与历史包

旧规则52＋木栅127＋会话86＝**265项状态检查**；最终六套真实Godot输入／渲染检查共 **1496项、62图、0失败**（60UI＋2world）：

| 最终检查 | 窗口 | 项数／图片 |
| --- | --- | --- |
| 原生灯光专项 | 1152×720 | 324／10 |
| 实际PCK灯光专项 | 960×600 | 324／10 |
| 实际PCK木栅 | 960×600 | 289／10 |
| 实际PCK环境光影 | 960×600 | 179／9UI＋2world |
| 实际PCK反馈 | 960×600 | 130／11 |
| 实际PCK完整流程 | 1152×720 | 250／10 |

覆盖三档／同姿态试演、权威状态保持、相机与演员根状态恢复、繁忙门禁、真实友方与敌方攻击差别、资源释放，以及木栅战术、胜败重试、返回城镇、安全存读、步行返山和师父选择。全部12条最终命令exit0，Dummy音频QA日志无脚本／资源警告错误；实际输入是Godot `push_input`，不是浏览器或物理键鼠。

独立来源32项通过、最终两尺寸10图复核及原生性能probe另记，不加进1496项／62图。权威收据为 `.local/qa/ambush-combat-light/final-validation.json`，命令／日志见同目录 `run_final.py`、`final-commands.json`及各 `final-*` 报告；另有 `independent-source-audit.json`、`independent-visual-review.json`、`independent-qa-review.json`。

首轮Web共7文件153,471,680字节，PCK113,640,068字节，SHA256 `ab65f24b4396fa0b61ba663ca60b893b29fdc77a3839a3e5cf2416feca19d394`。当时7文件HTTP完整字节／SHA与WASM MIME核对通过，见首轮QA的`http-final.json`、`creator-game-check-final.json`。原`shu-ambush-combat-light-web-final-20261025.service`与`shu-ambush-combat-light-native-final-20261025.service`交付时active，现已由上方节奏版替换停止，旧产物保持；常驻原生既有X11 `wd.xic` 输入法警告与Dummy QA干净日志分别记录。

原生独立probe52项通过，1152×720、模式顺序0／1／2／2／1／0，共6样本约13.43秒，每样本预热30帧、采样90帧；帧间隔中位16.55–16.66ms、P95 17.56–17.84ms。它固定源姿态并保持helper峰值，受60cap／VSync和未停止后台服务限制，不是持续战斗，不证明投影无开销、Web性能或长期表现。原始数据见 `final-pck-native-comparison/native-comparison.json`。

## 首轮六稿取舍与原验收

| 制作稿 | 实际观察与取舍 |
| --- | --- |
| draft1 | DualParaboloid地面网纹与天空洗白，拒用；天空变化的单独成因未隔离。 |
| draft2 | 改Cube投影、关闭Glow／曝光乘数1，地面与天空恢复，但剑弧被遮住。 |
| draft3 | 仅换shader仍未解决投影几何遮挡，未作为最终弧。 |
| draft4 | 按视线铺带并后退0.18，弧可见但过细、低对比。 |
| draft5 | 仅stage中的青色／禁深度诊断定位几何，不交付。 |
| draft6 | 加宽提亮白芯、保留暖边和普通深度测试，作为最终候选并做两尺寸复核。 |

这些制作稿只作过程证据，不冒充最终通过版本。当前仍有短时浮字与头牌叠、弓手详情需滚动等既有可读性限制；两光照档同参数不等于感知亮度已匹配。独立审图认为可供比较，并非商业品质验收。

首轮原定由用户比较灯光／投影是否值得保留、剑弧是否清楚；本轮已按动作偏快反馈收窄为上方节奏验收，没有自动批准氛围深度、构图或新招式。首轮浏览器surface为空且iab不可用，open_in_codex仅queued，不算浏览器跑通；其他平台和设备未验收边界保留。

## 技术参考与原创边界

- 《歧路旅人》参考Acquire的[UNREAL FEST EAST 2018原始演讲](https://www.docswell.com/s/EpicGamesJapan/KXPWY5-UE4_UFE2018_ACQUIRE_OCTOPATHTRAVELER)，重点p71–73的战斗镜头、专用点光与后处理；[Epic开发者访谈](https://www.unrealengine.com/spotlights/octopath-traveler-s-hd-2d-art-style-and-story-make-for-a-jrpg-dream-come-true?lang=en-US)确认特效同步点光与角色对环境投影。资料没有据此确认角色法线贴图或具体shadow-caster算法。
- 《逸剑风云决》参考2024 CiGADC吴迪演讲的[游戏葡萄文字整理](https://www.taptap.cn/moment/608885334469510383)及[官方认可／Paper2D说明](https://www.sina.cn/news/detail/5104220292253416.html)。未观看原始演讲视频，不把整理稿称作原始视频；也不把UE5／Lumen／Niagara／DLSS写成该作已确认技术栈。

本轮借鉴战斗灯光与可读性思路，在《蜀》已有真实3D模型和Godot舞台上原创实现；上述链接是研究来源，不是导入的运行依赖或素材许可。
