# P3 · 两招控制层动作增强

客户端日期：2026-10-25，America/Los_Angeles。状态：**本机与实际PCK检查完成，18830已交付；增强动作与对照体验待用户试玩**。承接[六招工坊](P3_MARTIAL_WORKSHOP_SLICE.md)，用户对先提升一招剑、一招掌的控制器、重心和脚锁并与原动作比较回复「好」。本片不扩大六招的战斗规则或门派范围。

## 2026-10-26 用户反馈与后续修订

用户对18830反馈「好像没有看出太大区别」，因此本页检查只保留为控制层、来源、脚锁及本地渲染／输入技术证据，增强动作没有获得视觉认可。复查发现首屏默认穿云刺原版、人物偏小且战术杂物干扰，以及剑尖未过顶、掌伸展更小和髋转方向错误；前轮数值与本地帧审阅不能代替用户判断。

两招大轮廓重做、默认近看与直接呈现增强版的后续工作见[可见轮廓修订切片](P3_MARTIAL_READABILITY_SLICE.md)。后续新版已交付18831，旧18830、原制作源及本页历史结果保留，不能把后续动作或检查视为本页版本已获认可。

## 玩家可观察的结果与验收点

在 **X1桌面内**打开[18830动作增强工坊](http://127.0.0.1:18830/)，或切到同PCK原生窗口；从战斗工具栏打开「武学工坊」，选择落雁斩／劲风掌后切换版本。

| 招式 | 增强制作目标 | 比较条件 |
| --- | --- | --- |
| 落雁斩 | 后坐沉髋蓄势，髋部先转，胸肩随后，剑锋斜落、随势回中；双脚锁定 | 原版与增强版同一释放／命中／总时长、剑气、声音和镜头 |
| 劲风掌 | 沉髋屈肘蓄掌，髋、胸、肩、腕依次送出，掌劲离手后保留余势，再松肘收掌；双脚锁定 | 原版与增强版同一释放／命中／总时长、掌风、声音和镜头 |

工坊仍列出六招。选中落雁斩或劲风掌后，可从「动作版本」选原版／增强版，或按「同刻对照」在两版之间切换；其他四招仅原版，对照控件禁用。切换同一招的版本须保留当前时间、暂停状态、1倍／0.5倍速及战术／正面／侧面镜头，重新采样不补播已经越过的音效。可暂停拖动回看，也可常速完整播放；「对照上一招」继续交换不同招式，不与同招版本对照混用。

原版与增强版分别接受本机「通过」「退回修改」及意见；退回仍须非空原因。原版键为招式ID，增强版键为 `ID@enhanced`。选中版本的说明、状态栏和审阅记录应一致，重开仍保留；批次或资产变化后重新待审。本机标记不代替用户认可。停止应回到起势并显示已停止，自然结束显示试演已结束。

验收重点是常速的发力顺序、半速的关节连续性、脚部接地、剑掌方向及完整收势。数值脚锁或骨架通过不代表动作已经自然，仍须真实场景查看和用户试玩。

## 制作工具与资源边界

使用既有本地Blender 5.2.2 LTS，通过12个自定义控制对象和12个约束（含4条两段IK）编辑两招，再烘焙回原22骨架；**没有安装或使用Rigify**。`CTRL_COG`控制重心，躯干／视线对象控制身体相位，腕目标与肘pole控制出手，脚目标与膝pole控制脚锁和弯曲平面。控制曲线可在Blender Graph Editor编辑；运行时只读烘焙片段，不带制作期约束系统。

制作输入为[落雁斩](../assets/data/martial_workshop/control_rig/sword_cleave.json)与[劲风掌](../assets/data/martial_workshop/control_rig/palm_gale.json)，离线[批处理器](../tools/build_martial_control_variants.py)调用[控制动作编译器](../tools/hero_lookdev/build_martial_control_motions.py)。原六招 `catalog.json`、原recipes、模型与动作只读；增强变体由独立[control_variants.json](../assets/data/martial_workshop/control_variants.json)关联到原招式，保持六个招式ID。两个变体均为纯试演。

输出采用指纹目录 `assets/art/martial_workshop/control_rig/<move_id>/<fingerprint>/`，包含carrier-only动作GLB、100fps导入配置、manifest和source-motion。可编辑完整模型与控制对象位于 `.local/sources/martial-control-rig/<move_id>/<fingerprint>/controls.blend`；最终准确路径、SHA和生产输入以各任务manifest及source-motion为准，制作源不加入运行包。原角色没有独立指骨，开放掌沿用既有固定手型；本片不实现指骨、布料或头发模拟。

```bash
python3 tools/build_martial_control_variants.py --check-only
python3 tools/build_martial_control_variants.py \
  --report .local/qa/martial-control-rig/motion/batch.json
```

同输入重跑须核对缓存产物SHA，不能只凭文件存在宣称命中。手工改动作时先另存原Blend的本地副本，再用显式回流生成独立候选，保留默认两招变体和原制作源：

```bash
python3 tools/build_martial_control_variants.py \
  --edited-blend palm_gale=/absolute/path/to/controls-edited.blend \
  --variants-output .local/qa/my-motion/control_variants.json \
  --report .local/qa/my-motion/batch.json
```

回流文件须保持原22骨、rest、源身份、控制器名称和中性端点；仍须复验脚锁、腕目标、剑轴、连续性、真实ActorBinding和场景衔接。制作器的字段与坐标详见[控制层制作说明](../assets/data/martial_workshop/control_rig/README.md)。本轮没有新云端调用、采购、全局安装或Git提交／推送。

## 运行与存储合同

Godot 4.7.2 stable、GDScript、Compatibility与Web单线程保持。Catalog加载六招原目录及可选增强变体，共用单时钟播放器与实际掌心／剑刃锚点；不新增招式ID分支或第二套Session。独立工坊Stage只收宿主对局快照，关闭时释放视口并恢复战场。Rules、EngineSession、SaveStore、内容包0.5.0、原两剑实战及既有养成流程保持。

本地审阅仍在 `user://martial_workshop/reviews.json`，整批哈希包含原目录与变体资源。原生和Web各自保存，站点来源不同不自动同步。app为 `0.6.1-control-rig-candidate`，独立userdir `shu-martial-controls`；18830与同PCK原生已启动，18829及旧服务保持，不迁旧档。两版在同一演武视口切换，本片没有同时显示两个视口。

## 实际验证与交付

<!-- CONTROL_RIG_FINAL_VALIDATION -->

最终stage为 `.local/build/martial-control-rig-20261025/stage-dd3454add740`，376项消费输入与工作源逐SHA一致。Godot 4.7.2固定引擎14条最终导入、状态、真实渲染／输入及导出命令均退出0，最终QA日志无警告／错误。状态1163项包含原规则52、木栅127、Session86、两剑322、目录86及控制层490；六套实际渲染／输入2063项／59图通过，合计3226项检查。

| 最终真实渲染／输入检查 | 尺寸 | 检查／捕获 |
| --- | --- | --- |
| 新控制层与原版对照，原生源stage | 1152×720 | 392项／8图 |
| 原六招工坊，原生源stage | 1152×720 | 336项／10图 |
| 新控制层与原版对照，实际PCK | 960×600 | 392项／8图 |
| 原两剑实战与试演，实际PCK | 960×600 | 367项／14图 |
| 劲风掌试演，实际PCK | 960×600 | 309项／9图 |
| 护药胜败、重试、返城与师徒流程，实际PCK | 1152×720 | 267项／10图 |

输入通过真实Godot `root.push_input`鼠标／键盘事件及实际下拉菜单选择注入，没有直接发控件信号代替操作；检查同刻切换的实际骨骼、特效几何、暂停／0.5速、时间线端点回拖、音效消费时点、独立审阅及重开保存，也核对关闭后原宿主／战斗／镜头和渲染调度恢复。音频使用Dummy调度与播放器状态验证；这不等于浏览器、实体键鼠或设备听感检查。

另有120张正面／侧面相位图与136张常速／半速连续播放帧复查，最终未再观察到早期左肘翻转与末帧突跳；这些不并入上述59张UI捕获。独立制作审查26项通过，真实Blender控制曲线垂向4mm编辑后回流导出，确认新GLB与原版不同，脚锁、腕目标与骨架约束保持，独立编辑候选缓存通过；默认两招与原制作Blend未被覆盖。最终消费来源整合后再次生产仍2缓存命中、0生成。CPU-only UI夹具13项为早期接口自检，亦不并入3226项总数。

最终两个动作目录及可编辑源对应如下；完整资源和来源SHA由各任务manifest、source-motion与总收据记录。原制作Blend均为只读0444，编辑时另存副本。

| 增强动作 | 最终动作GLB | 可编辑源（本地） |
| --- | --- | --- |
| 劲风掌 | [356b78415a075f0a/motion.glb](../assets/art/martial_workshop/control_rig/palm_gale/356b78415a075f0a/motion.glb) | `.local/sources/martial-control-rig/palm_gale/356b78415a075f0a/controls.blend` |
| 落雁斩 | [1216c8073a5b5ae0/motion.glb](../assets/art/martial_workshop/control_rig/sword_cleave/1216c8073a5b5ae0/motion.glb) | `.local/sources/martial-control-rig/sword_cleave/1216c8073a5b5ae0/controls.blend` |

原角色GLB、22骨rest／蒙皮、六招原catalog与recipes、旧制作器、Rules／Session／SaveStore、内容包、环境／特效／音频的受保护字节保持；当前变体加载、播放器／绑定器、Stage／UI、字库、构建闭包和消费来源记录有本轮明确变更。不能把“原六招目录保持”解读为运行层完全未改。

早期固定及随躯干旋转的肘部引导目标候选的翻肘／末帧跳变已在数值审查中发现并于冻结前修复，草稿保留于本地rejected-assets。固定引擎一次headless导入在字体处signal11，使用相同stage源重试后干净通过，失败日志保留于failed-import。三类测试观察问题分别涉及短时窗测量的帧阶段、音效在点击前已自然结束，以及在准确释放时刻之后观察移动掌心；修正同步和独立释放姿态夹具，未放宽原阈值，最终完整重跑。失败历史未计入最终PASS，也未据此宣称所有工具与运行环境没有历史警告。

Web7文件共155,905,126字节，逐文件HTTP状态／完整SHA／MIME验证通过，WASM为 `application/wasm`。PCK为116,073,520字节，SHA256为 `5971b4f03a257d781cc6ecb825f324c02dcbc045cc7434de9a85e412fd3b170b`。`shu-martial-controls-{web,native}-final-20261025.service`两服务均active，[18830试玩](http://127.0.0.1:18830/)及同PCK原生已启动，旧14个服务active。常驻原生仍有既有X11输入法提示，和14条干净QA日志分别记录。

权威收据为 `.local/qa/martial-control-rig/final-validation.json`；该目录下最终命令日志、六套 `final-*/report.json`、visual-review、independent-production-review及motion/final-proof和cache-after-integration记录精确命令、源与产物哈希。主副本main与origin/main均为 `7c992c578b1fe4a1624c769812425b38080771d3` 且干净，候选worktree仍dirty；没有Git提交／推送或公开发布。

浏览器打开请求已queued，当时CUA无可用surface，实际浏览器玩法／性能仍未验证。Windows／Steam Deck、实体输入与原生中文输入法、设备听感、长时性能和真实旧档迁移未验；用户对动作自然度与工坊对照体验的认可待试玩。没有以数值通过或本机帧审阅代替用户艺术判断。

## 下一验收点

1. 在落雁斩与劲风掌常速完整播放中，看清沉髋、髋胸肩腕发力及收势；脚部不漂，肘腕无突跳。
2. 暂停到相同秒数，在两版之间切换，身体改变而镜头、时间、劲气和播放状态保持；越过的音效不补播。
3. 0.5倍速、时间线前后拖动、换版本、停止及关闭均保持单一时钟并清理临时资源，返回原战斗可继续出招和完成护药／返城／师徒互动。
4. 两版意见独立保存、重开可见，资源改动回待审；另外四招、上一招对照及原版六招保持。
5. 只有用户认可两招的自然度与工具价值后，再决定批量模板化和可视化配方编辑器；不自动铺开所有武学与门派。
