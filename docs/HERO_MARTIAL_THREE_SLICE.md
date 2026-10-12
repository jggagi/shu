# 江砚秋 · 剑、棍、拳三招图像动作

启动客户端日期：2026-10-11；当前更新：2026-10-12。用户调用 `game-image-motion-build`，并选择「剑法＋双手棍法＋拳掌，各做一招」。剑法与拳掌v2已完成50／53帧透明包、独立后山场景、原生检查及Web导出；剑法Web控件已实际查看，拳掌Web最后检查因超时后浏览器安全策略阻止恢复而未完成。棍法两次获授权提交均FAILED，没有源片。Windows及玩家验收待执行。工作标签不确定正式武功设定，静态参考图不等于成片。

本机制作预览：`http://127.0.0.1:8794/`，文件在 `.local/qa/hero-martial-three-v1/index.html`。可正常／半速看灰模，页面循环仅供观察，素材仍按单次动作制作。

## 三招输入

| 任务卡 | 动作来源与差异 | 输出 | 目标画景 |
| --- | --- | --- | --- |
| [横抹回剑](image-motion/jiang-sword-horizontal-return-v1.md) | CMU02_08的横向剑路，区别于原v4背转斜劈；剑是右手刚性道具，没有剑身捕捉标记。 | 20个120Hz源动作的逐8帧样本＋末帧静止10格；30帧／15fps／2秒 | 后山独立研究 |
| [双手扎棍](image-motion/jiang-staff-forward-thrust-v1.md) | 原创staff约束研究，两握点沿同一棍轴相距0.34m；进步送棍、回棍退步。不是人体捕捉或横扫。 | 30fps源逐2帧采样；60帧／15fps／4秒 | 溪边茶亭独立研究 |
| [站桩冲拳](image-motion/jiang-fist-straight-punch-v1.md) | CMU02_05单次右拳前送、躯干旋转与回收；空手，无新增道具。 | 源帧65–313逐8帧采样；32帧／15fps／2.133333秒 | 后山独立研究 |

三张参考为1254×1254的内置imagegen候选，分别持一柄剑、一根双手棍、空手握拳。沿用棕发高马尾、浅蓝发带、白袖蓝袍和布靴。静态身份／武器已查看，最终美术认可待用户；拳法参考的头发留白小于提示目标，成片必须复核发梢、发带与衣袖出框。三段灰模为512×512、H.264／yuv420p，无声音。

原身份图SHA256为 `ac78cfceaf99dfff64f9dc48a54cee5561e4b1715e06152073a2ecf53833dcb3`。精确提示在 `art/prompts/hero-martial-*-reference-v1.txt`，三次内置生成按实际SHA记录到 `art/manifest.jsonl`；隐藏模型与seed不推测。候选PNG和输入包在忽略制作区，尚未选入运行assets。

CMU[官方目录](https://mocap.cs.cmu.edu/search.php?subjectnumber=2)将02_08记为swordplay、02_05记为punch/strike。02_08、02.asf与许可复用仓库资源；02_05从[官方文件](https://mocap.cs.cmu.edu/subjects/02/02_05.amc)下载至 `.local/qa/hero-martial-three-v1/source/02_05.amc`。它们是身体参考，不考证为中国武术拳种，也不保证手指与器械轨迹。

## 完成与证据

Root决定动作区间、画景目标和上传边界，使用已有Blender4.5.9 LTS生成灰模。`tools/hero_martial/render_guides.py`以全动作身体、头部与器械范围建立固定正交相机，保留源平移／转向；棍法只读原动作JSON。无逐帧变焦、重新居中或把跨步最低点锁地。

Real `luna_worker`仅实施单招输入打包器和保护检查。`prepare_input.py`复制原图字节、编码连续PNG、核验时序并完整解码，记录每帧／参考／视频SHA；重核源文件后原子发布，拒绝已有输出与缺帧。它不生成主角动作，也不替代alpha打包器。

输入阶段：Root独立检查11项单元检查通过，实际三段编码／完整解码通过，参考图复制字节一致。各段 `metadata.json`、`guide-source.json` 在 `.local/qa/hero-martial-three-v1/inputs/`，总表为 `input-summary.json`。已看灰模全段抽样与所选段关键帧；浏览器三段 `readyState=4`，剑法正常／半速、棍法半速、拳法正常播放核验通过。当时未生成Godot成片；后续证据见下方独立画景记录。

| 输入 | 参考PNG SHA256 | 灰模MP4 SHA256 |
| --- | --- | --- |
| 横抹回剑 | `a20d1df05bef591aec209d75140227166ae10397d859746429fff2eca55f9509` | `4e6046e8d599364280f666e449ed0f6993855221b7570961bc1a346085b19e3e` |
| 双手扎棍 | `6cf1dd766fa623b5e87a71df7797c50f638449dfc86aef18a911d5542759fca9` | `2c846636c36416ee81eeb4fd5ead7027635bbc94aa73ef604bd1d4909918e687` |
| 站桩冲拳 | `84f56b2908eb295add9051cca6fc492a33ccdad2fc7319c0902649e5bf06a829` | `7187388732b2129c2c9e28df44a61dd296654cde30a83d126c545146d689ca72` |

## 下一步与许可

拟沿用[万相官方ModelScope体验页](https://www.modelscope.cn/studios/Wan-AI/Wan2.2-Animate)。当前页面可加载，旧任务为SUCCEEDED，不据此推断新额度或质量。当前模型标题Wan-Animate-2，Move驱动参考角色，wan-pro说明为25fps／720p；实际输出仍以媒体核验为准。

此前许可明确只覆盖旧单式两份输入。用户随后回复「新的素材上传」，批准上述新三张PNG＋三段MP4至该官方体验页、Move／wan-pro各生成一次、仅零付费。六份输入均已完成上传。棍法首轮FAILED、拳掌首轮裁切后，用户分别回复「允许额外重试一次」及「允许上传 v2 并生成一次」；两次额外任务均已执行，总共五次提交，不再扩大尝试。授权与输入SHA见本地upload-authorization.json及retry-authorization.json。未调用付费API，单独账单费用未提供。

上传前排查（历史）：文件选择器事件接口超时，扩展文件访问／重启／原资料恢复后仍未解决。最终退出本次调试连接，原生选择器恢复Open；锁屏后由用户再次解锁，随后棍／拳及拳掌v2参考均上传成功。当前阻塞是棍法服务端FAILED且未暴露原因。授权原话、输入SHA与事件在`.local/qa/hero-martial-three-v1/upload-authorization.json`。

生成后检查身份、完整身体、两手握点与细武器，再做各段alpha／固定帧包并进入目标画景。源动作或裁切错误退回输入／生成。旧单式alpha／局部清理工具仍绑定原样本；本轮限定三个shot_id的新包装器已实际处理剑法50帧与拳掌53帧，棍法无源片可处理。诊断中的`figure_bbox`沿用的是底部30%连通块边界，不是全人物边界；新两招另用固定首帧脚点及统一尺度在后山校准，保留源片位移。两包已有Canvas检查页及各自Godot研究入口。

原后山v4、正式M2和Tea保持原资源与入口。本轮无正式结算／新奖励。用户随后授权创建PR并合并源码，在线试玩部署未授权。玩家对当前剑／拳预览反馈「不错」，完整拳剑细节、所有环境和平台仍按各自证据记录；棍法必须先获得可用原片，再核验双手接触。

## 剑法首段结果（2026-10-11）

原生选择器在退出本次浏览器调试连接后恢复Open，剑法PNG＋MP4上传成功；官方页面一次生成返回SUCCEEDED，任务`2d28d6b8-3748-4088-bdd2-7b613f027546`。事件接口虽超时，实际下载的两份MP4字节相同；Root复制原片、完整解码，并核验960×960／25fps／50帧／2秒与全部帧时间戳。原片SHA为`e6a5e438f4e3c61ceac1a357d2d06b6514c129047f1863c904fa9fa4890a8f68`，完整任务记录在`.local/qa/hero-martial-three-v1/jobs/sword.json`；实际模型修订／seed未公开。

新增`tools/hero_martial/package_clip.py`仅支持本轮三个固定shot_id，按实际媒体测量帧数／帧率／几何，拒绝已有输出和原资源命名空间。复用既有CPU ISNet-Anime helper与已安装模型，统一缩小至480×480，不裁切、不插帧、不改RGB；新素材在`assets/art/hero_martial_v1/jiang-sword-horizontal-return-v1/`。50帧、5张1952×1464图集与原片共约11.8MB；raw／RGBA与诊断在AgentDev可重建制作区。失败产生的独立新中间目录会保留，后续运行拒绝覆盖，尚非原子发布工具。

Root复核8项新保护测试通过；实际模型处理成功，50帧RGB全部逐像素等于原片统一缩放，全部图集单元等于对应RGBA，manifest列出的文件SHA全部通过，所有角点透明，所有帧边界接触为false。人工看0／12／25／37／49的浅色与深色背景、以及第0帧靴子近看，未见明显白边／残影／细剑漏抠。其余45帧尚未完整人工逐帧验收，目标画景与玩家认可仍未完成。

8794预览页新增实际剑法原片，加载为960×960、2秒、readyState4；通过AX按钮实际半速播放（rate0.5、paused false、时间推进）。这只证明本地原片查看路径，不证明Godot／Web／Windows场景接入。

首段输出时，棍／拳尚因锁屏未上传；该限制后续已解决。独立打开官方full-mode页仍含iframe，未据此宣称选择器修复。剑法成功任务未重复提交。

## 后两招生成与修订（2026-10-12）

棍法同一组输入的首次任务`ed96c8b6-272c-43b5-a0c4-d8f4f4ef7680`与用户授权的额外一次`40802fc0-575c-4e70-8aca-77b0dafd6055`都返回FAILED。页面只给任务与排查编号，未说明原因，两次都没有视频。原输入和失败回执保留；没有第三次任务、alpha或棍法场景产物。

拳掌input-v1任务`ce9c7f32-2cb2-4cb8-98cd-8ec2b787d482`成功，但开场马尾被上边框裁掉，原片保留并拒绝用于alpha。Root制作留白参考v2，SHA`003c64a478558da8f4a0bf38e22d90eb816b2dc5e83dc84d50ec046cb06ea9e9`，用户明确允许新PNG与同一灰模MP4额外生成一次。input-v2任务`cc4926bd-7caa-4474-84a8-65e9029e7800`成功，实际960×960／25fps／53帧／2.12秒，源SHA`28ca3d8d407f7a90453378b68c69fc4b7e5631e54a302c957d032aff203c1c7f`。12个源样本的马尾／完整身形留边复核通过；没有用遮罩修补旧片裁切。

拳掌v2独立包在`assets/art/hero_martial_v1/jiang-fist-straight-punch-v1/`：53个480方格、5张1952×1464图集，含原片总计7,793,279 bytes。复用同一既有ONNX模型，未安装依赖或联网抠像。Root独立核验全部53帧RGB等于原片统一缩放、全部atlas单元等于对应RGBA、所有文件SHA及冻结任务回执SHA相符、角点透明且全段无边界接触。5帧按480方格浅深底近看；另以240方格查看覆盖全部53帧的四张浅深底序列表，未見明显裁切／底色残留／细发漏抠。此检查不是最终玩家认可。

`matte-review.html?shot=sword|fist`只载入对应包，双Canvas同一帧显示浅／深底，不插帧、不调色或重新取锚点。浏览器实际验证两个包加载50／53帧、正常速、半速、暂停／恢复、末帧保持与滑杆到末帧；原片单独播放。它不是Godot、真实画景或Windows证据。合计五次生成返回三次SUCCEEDED与两次FAILED，其中拳掌v1因裁切拒收；最终只有两段可用透明草稿。当前没有新增模型／输入／第三次尝试或其他服务的授权。

## 两招独立后山预览（2026-10-12）

用户在交付试玩入口后反馈「不错，我们的skill需要更新吗」。记录为对当前剑／拳预览的正向反馈；未将其扩大为Windows、全部时辰／完整器械接触或棍法验收。Codex的拳掌Web实际UI检查仍未完成，保留其原始证据边界。

入口为[剑法场景](../scenes/demos/hero_martial_sword.tscn)与[拳掌场景](../scenes/demos/hero_martial_fist.tscn)。Real luna_worker实施已确定的最小参数化，Root审核、补齐字体、测试与渲染。播放器可选择manifest、研究标题、位置／统一尺度及固定源锚点；旧v4的默认manifest、平滑与原始／清理alpha切换保留。新两招只使用自己的包，隐藏未提供的清理alpha切换，不套用旧清理区域。正式project.godot、DemoState、M2和Tea未改。

舞台1440×900，人物固定位置(1010,565)；剑法统一缩放0.78，固定源锚点(424,904)，拳掌0.90／(522,810)。锚点先乘cell_scale=0.5，再按演员尺度绘制；所有帧用同一锚点，保留原片真实身体／脚部位移。复用现有后山色彩、轻纸感、接触阴影与环境调制；材质A/B及环境切换不改时间、姿态、几何或游戏权威状态。未声称精确人体／器械跟踪或所有脚步无滑动。

旧字体缺少新招式标题字形，新建OFL字体子集`ShuHeroMartialSerif.ttf`，覆盖168个码位，两场景独立选用；来源与SHA在`assets/fonts/source-hero-martial.json`，原字体文件保持。独立[构建器](../tools/hero_martial/build_review.py)只支持这两个研究入口，白名单staging只带选定包，排除source.mp4；不改正式入口，不是批量生产或发布工具。

字体记录区分历史实际命令和可移植命令模板；运行已选字体无需源字体或本机AgentDev缓存。离线重制时，从记录的Source取得并核对SourceSHA256，将模板中的`<verified-source.ttf>`替换为调用者的文件路径，在仓库根运行。现有fontTools环境仍是前提；工具拒绝已有输出，需在独立制作checkout保留并移出原字体／记录副本后重建，不能覆盖当前选定资产。

| 验证层 | 剑法 | 拳掌 | 边界 |
| --- | --- | --- | --- |
| Godot4.7.2导入／Web导出 | 成功 | 成功 | GL Compatibility，Web单线程 |
| 实际场景自动行为检查 | 280项，0失败 | 295项，0失败 | 帧表、正常／半速、暂停／重播／末帧、Static／Resume、深层DemoState保持 |
| 原生真实渲染 | 36项，14张图 | 36项，14张图 | 1152×720、960×600，起／中／末帧、Static像素保持、晴天与酉时小雨、材质A/B；Root查看场景尺寸下代表画面 |
| Web实际UI | 已载入并操作 | 未完成 | 剑法正常／半速、暂停／重播、Static／Resume、天气与时辰已操作；Web实际浏览器视口较小，不冒充上述原生尺寸证据 |
| Windows／用户认可 | 未验收 | 未验收 | 低端性能、Windows实体运行与最终观感未验 |

拳掌Web仅观察到加载进度，后续截图检查超时导致工具会话重置；恢复本地浏览器连接被浏览器URL安全策略拒绝。已停止浏览器恢复，没有换浏览器、改URL或间接控制来规避策略。因此不能把拳掌Web导出／原生测试记为Web实际UI通过。

本机试玩：[横抹回剑](http://127.0.0.1:8814/)／[站桩冲拳](http://127.0.0.1:8815/)；[素材总览](http://127.0.0.1:8794/)保留输入、原片与透明页。三处只绑定127.0.0.1，服务需保持运行；换机器须重新构建和启动。先正常／半速观察动作与脚底，再看小雨／酉时与Static／Resume，用户反馈决定后续修订。

最终构建与检查日志在`/Volumes/AgentDev/Builds/shu-hero-martial-three-v1/review-sword-final-v1/`和`review-fist-final-v1/`，冻结收据分别为`sword-7d65a9a0db-receipt.json`与`fist-b23727b1c7-receipt.json`，均保留源文件、staging和Web哈希。渲染证据在各自`render/`目录。`.local/qa/hero-martial-three-v1/current-validation.json`汇总当前保护检查和未通过的验收门。

源码归档另从提交`5d949cd74e2822a3147115bc531d1651a07e3499`创建不含历史缓存的Git文件树，598份文件SHA一致。19项输入／片段保护、剑280／拳295项场景检查和原v4的411项回归通过，两个新staging的Web导出成功；新字体元数据模板也进入本次依赖哈希。证据在`.local/qa/hero-martial-pr-v1/clean-archive-validation.json`与AgentDev的`shu-hero-martial-pr-v1/5d949cd74e28/`。它验证归档依赖闭包，不替代上方原生、Web实际UI或Windows证据。

重建独立场景（现有Godot4.7.2及同版本模板环境；输出为新的可写目录，Mac外部构建按AGENTS使用agent-dev包装）：

```sh
python3 tools/hero_martial/build_review.py --shot sword --godot /path/to/godot --output /new/path/sword-review
python3 tools/hero_martial/build_review.py --shot fist --godot /path/to/godot --output /new/path/fist-review
# 使用构建输出所打印的Web目录；仅本机开放。
python3 -m http.server 8814 --bind 127.0.0.1 --directory /path/to/sword-review/Web/sword-run-id
python3 -m http.server 8815 --bind 127.0.0.1 --directory /path/to/fist-review/Web/fist-run-id
```

## 重建输入

已有匹配Blender／FFmpeg环境中从仓库根运行；Mac仍按AGENTS用 `agent-dev run --` 包装，不安装或更换工具链。输出路径必须全新，原图用已有文件重用，新的图像结果不能确定性复现。

```sh
blender --background --factory-startup --python tools/hero_martial/render_guides.py -- --repo . --kind sword --amc assets/data/sword_mocap/source/02_08.amc --start 0 --count 20 --hold-end 10 --output /new/path/sword-frames
blender --background --factory-startup --python tools/hero_martial/render_guides.py -- --repo . --kind staff --output /new/path/staff-frames
blender --background --factory-startup --python tools/hero_martial/render_guides.py -- --repo . --kind fist --amc /path/to/02_05.amc --start 8 --count 32 --output /new/path/fist-frames
python3 tools/hero_martial/prepare_input.py --shot-id jiang-sword-horizontal-return-v1 --reference /path/to/sword-reference-v1.png --frames-dir /new/path/sword-frames --fps 15 --output /new/path/sword-input
python3 -m unittest discover -s tests -p test_hero_martial_inputs.py -v
```
