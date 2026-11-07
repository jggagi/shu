# P3 · 掌风与落尘工具小样

客户端日期：2026-10-25，America/Los_Angeles。状态：**用户同意的纯试演已实现，完成本机与实际导出PCK检查，观感等待试玩**。承接[穿云刺与回风扫](P3_MARTIAL_SKILLS_SLICE.md)后关于多类别／门派扩展和开源工具的讨论，本片验证 Effekseer 掌风冲击与 Material Maker 风纹／烟尘的制作、导出和场景融合，不批准整套掌法、门派系统或新战斗规则。

用户随后反馈首版已有基础但效果仍不够；专用掌法动作与冲击修订已在独立18828交付，见[劲风掌修订卡](P3_PALM_IMPACT_REVISION.md)。18827首稿继续保留，以下验证只属于当轮，不覆盖新版。

## 玩家可见范围

战斗工具栏新增「掌风小样」：沈听岚沿用现有左手出手动作，在空地试演飞行掌风、淡青扩散气环和贴地落尘，再恢复站姿、镜头与原战斗操作。它不造成伤害、不消耗行动／时辰、不改敌人计划或药篓状态；现有动作只是节奏与位置参考，不称为新制作的掌法动作。繁忙门禁、重复试演、离场、重置及临时效果清理已检查。

在 **X1桌面内**打开[18827掌风小样](http://127.0.0.1:18827/)，点战斗工具栏「掌风小样」；也可切到同PCK原生窗口。app `0.5.1-palm-vfx-candidate`、userdir `shu-mountain-ambush-palm-vfx`，gamepack 保持 `0.5.0`。旧[18826两招试玩](http://127.0.0.1:18826/)和原存档保留，新目录不迁档。Godot 4.7.2／GDScript／Compatibility 与 Web 单线程保持。

## 工具与可编辑源

| 制作部分 | 实际路线 | 当前证据边界 |
| --- | --- | --- |
| Effekseer 掌风冲击 | 官方 Linux 1.80.7 便携包；原创五层 Ring／Crescent，CUI 编译，官方 `libViewer.so` Recorder 输出透明图集。 | 两次官方渲染图集逐字节一致，24帧／60fps、2048×768；工具检查不代替游戏实拍。 |
| Material Maker 风纹与烟尘 | 固定 1.8 源与原创 `.ptex` 噪声图，调用工具真实 GPU 导出器；隔离 CLI 补丁只处理离线启动、渲染器就绪与退出。 | 两张512×512原始PNG已真实导出并绑定SHA，补丁不改噪声／shader／导出计算；工具退出仍有资源释放提示。 |
| Godot 场景呈现 | 图集普通透明 quad、风纹与贴地尘面，由原 Stage 唯一时钟推进。 | 原生与实际PCK已检查。Effekseer 图集使用预乘 alpha，正常深度测试，不安装战斗运行插件。 |

源、许可证、准确工具版本／命令与 SHA 分别保存在[Effekseer 来源](../assets/art/mountain_ambush/palm_lab/effekseer/source-effekseer.json)、[可编辑工程说明](../assets/art/mountain_ambush/palm_lab/effekseer/README.txt)与[Material Maker 说明](../assets/art/mountain_ambush/palm_lab/material_maker/README.md)。工具下载／源码试用隔离在 `.local/tools/martial-vfx-authoring/`，没有全局安装、购买、云端生成或上传。原始 atlas 没有 Python 二次绘制；游戏不携带这两个工具的二进制。

Effekseer 两次录制均成功退出，但保留 `gtk_disable_setlocale() must be called before gtk_init()` 启动提示。Material Maker 最终源运行器退出0，保留6个ObjectDB实例和1个资源退出时仍在用的提示；此前原二进制超时、首版源运行器的Steam／UI元数据／渲染就绪错误已归档，不能写成工具日志全净。它们和 Godot 游戏 QA 的警告／错误分别记录，见[Material Maker 来源](../assets/art/mountain_ambush/palm_lab/material_maker/source.json)。

## 验证与下一验收点

最终stage `.local/build/palm-vfx-20261025/stage-4aaacbf222bc`，299项输入与worktree逐SHA一致。状态587项、七套原生／实际PCK画面输入2317项／74张捕获通过；13条最终导入、检查与Web导出命令均成功，QA日志无警告／错误。掌风两尺寸各275项检查确认三次试演、状态／人物／镜头精确恢复、临时节点清空和无新声音调度；旧招、护药胜败／重试、返城安全存读及返山师父选择继续通过。输入为Godot注入，不是浏览器或实体输入。

独立来源114项通过，覆盖规则／包／模型保护与两个工具的来源、补丁和原始输出绑定；另实看最终1152原生与960实际PCK的飞行／冲击／恢复共6张，未见黑底、图集边或UI重叠，静态审图不代替动态手感。Web7文件153,848,080字节、PCK114,016,484字节，HTTP完整SHA读回与WASM MIME通过；`shu-ambush-palm-vfx-{web,native}-final-20261025.service`均active，旧18826／18825／18824／18823八个服务保持。常驻原生启动另有X11输入法`wd.xic`警告，与13条干净QA日志分开。主main干净且与origin/main同为`7c992c5`，候选dirty；无提交推送或公开发布。

权威总收据为`.local/qa/palm-vfx/final-validation.json`，同目录`final-commands.json`、`independent-source-audit.json`、`independent-material-source-review.json`、`independent-runtime-static-review.json`、`independent-visual-review.json`与`independent-qa-review.json`保留绑定、命令、报告和实际图像。两个工具证据分别归`.local/qa/palm-vfx-effekseer/`与`.local/qa/palm-vfx-material-maker/`；creator-game-check只核对产物尺寸与SHA，不冒充运行验收。

首轮旧招回归发现真实攻击繁忙时「掌风小样」按钮外观仍可用，回调本身已有busy拒绝，没有触发试演。补齐同一繁忙列表的禁用后重做freshstage；原3项失败与首轮产物保存在`final-attempt1/`，不计入最终通过结果。

下一验收点是用户试玩掌风发出、落点与消散是否清楚，动作参考、特效亮度和尘量是否合适。本轮是克制气环工具小样，尚未形成专用掌法动作或门派辨识。浏览器打开请求仅queued，实际操作／性能、Windows／Steam Deck、实体输入、设备听感、长时及真实玩家旧档迁移未验证。本片没有新增声音，旧声音设置不据此重新验收。
