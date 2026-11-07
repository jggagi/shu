# P3a · 江砚秋获批模型复用

本页保留18818原模型复用候选及其实际来源／检查。用户后续批准的[战斗反馈加强](P3_AMBUSH_FEEDBACK_SLICE.md)已形成独立18819候选；新效果的检查另行记录，不复用本页475项／50图为新结论。

客户端日期：2026-10-24，America/Los_Angeles。当前状态：**原源已取回，战场与近看已接入，最终构建通过**。本页承接[18817人物候选](P3_AMBUSH_CHARACTERS_SLICE.md)，记录用户纠正后的实际来源与待验收范围；不把旧候选的检查结果用于本次替换。

## 用户纠正与复用要求

用户指出「蜀山已经有江砚秋3D模型」，要求本次战斗沿用既有江砚秋形象。后续用户授权「fix SSH」，用于恢复访问保留在 Mac mini 的原制作资料。此前因 X1 暂未定位到获批源而另建主角造型的实施选择据此纠正：本次江砚秋复用原获批暖色模型，不重新设计脸、发型、服饰或身体比例。

历史 `assets/art/sword_jiang/study.glb` 与18817程序几何主角都不是这份获批暖色源。两者保留历史，不改名冒充获批模型；原18816／18817试玩、截图、来源和检查收据保留。

## 已取回的来源

获批依据沿用[暖色确认记录](image-motion/jiang-warm-sword-20261022.md)与[完整练剑循环的来源记录](image-motion/jiang-sword-cycle-20261023.md)。后者已记录同一 `phrase-warm-v4/jiang-sword-phrase.blend` 的完整 SHA256。

| 项目 | 本轮实际状态 |
| --- | --- |
| 原制作资料 | 用户自有 Mac mini，`/Volumes/AgentDev/Builds/shu/jiang-sword-phrase-20261022/phrase-warm-v4/jiang-sword-phrase.blend`。 |
| X1 只读原源 | 当前 worktree 的 `.local/sources/jiang-approved-warm-9aa7c926/jiang-sword-phrase.blend`。 |
| 文件大小 | 175,525,576 字节。 |
| SHA256 | `9aa7c926103f58b664427b2400601001562ff9a436b153c9b46d0c9241de6e65`，与既有获批来源记录吻合。 |
| 原源保护 | 本地权限444；派生导出另存，不覆盖这份取回源。 |
| 取回收据 | `.local/qa/ambush-characters/approved-model-retrieved.json`。 |

本轮只取回明确的制作产物，不同步仓库、`.git`、缓存或整个目录；后续编辑与适配仍在 X1 完成。Mac mini 继续保留历史资料，不恢复为《蜀》的主开发机。原源在忽略的 `.local/` 中，不能据此声称已经随源码提交到 GitHub。

## SSH 修复的实际范围

已有非默认专用 SSH key 未被普通连接选中，是本次无法登录的原因。根代理复用原 key 与既有 `known_hosts`，新增仅匹配四个 Mac 地址／别名的 `~/.ssh/config` 配置，权限600；别名连接与原 IP 连接均已登录成功。

本次没有修改 Mac 服务端配置或 `authorized_keys`，没有改变主机信任、开启密码认证或新建身份。私钥内容未读取或输出；文档不保存凭据。SSH 可用和源文件字节校验通过，不等于模型已经成功导入或战斗替换已经完成。

## 本轮适配边界

- 江砚秋从同一获批 `.blend` 派生战斗可用资产，保留身份、暖肤、深棕发、蓝衣与米白配色。坐标、尺度、骨架、材质和性能适配需有实际来源与外观核对；若需要简化，也须验证与原造型的对应。
- 已完成同源导出和玩家角色接入，战场与「人物近看」实际消费同一份获批来源的派生角色。
- 沈听岚及三名敌人本轮先保留原候选，不因江砚秋来源纠正而重新设计全体角色；沈听岚性别设定仍不由模型补定。
- 战斗规则、Session 唯一结算、安全存档和旧包保持。模型表现、转身、行走与出招不自行扣血、推进回合或游戏时间。
- 不新增云端调用、素材上传、费用或依赖安装。本轮没有 Git提交、推送或公开发布授权。

## 逐步验收卡

| 阶段 | 当前状态 | 完成时需记录 |
| --- | --- | --- |
| 恢复源访问 | 已完成 | 限定 SSH 配置、别名／原IP登录与原源取回收据；不附凭据。 |
| 校验获批源 | 已完成 | 文件大小、完整SHA与既有来源记录吻合，原源只读保留。 |
| 同源导出 | 已完成 | 既有Blender5.2.2 LTS，GLB75,202三角／17,700,976字节，原22骨／4网格／2动画；源文件导前后SHA不变。 |
| 战场与近看接入 | 已完成 | 两处实际消费同一派生角色，测试强制原模型active及22骨；原资源加载失败不会静默替换为程序几何主角。 |
| 动作与镜头 | 本机原生已验证 | 两尺寸正侧背面、脚点／统一尺度、真实骨骼攻击变化、提前取消立即复位、自然收势、走路与回待机；代理实际查看战场与近景。 |
| 规则与存档隔离 | 本轮已验证 | 16项规则／包／Session逐SHA未变；导出包完整移动／攻击／控制、胜败、重试、返回城镇、安全存读与同场师父对话／选择通过。 |
| 新候选构建与输入 | 本机已验证 | 225项输入与stage逐SHA一致，650码点字库全覆盖；导入／导出无脚本资源警告错误，7文件HTTP字节／SHA一致。 |
| 用户反馈 | 复用方向获认可 | 用户在原模型接入后反馈「不错，下面做什么」；随后材质收尾不追加用户认可，完整平衡和其他四人造型继续待反馈。 |

## 最终验证、入口与局限

沿用Godot4.7.2／Compatibility，X1原生X11实际渲染、Godot `root.push_input` 注入键鼠。最终三次均退出0，无脚本／资源警告错误，共475项、50图、0失败：

| 检查 | 结果 | 证据目录（当前worktree `.local/qa/ambush-characters/`） |
| --- | --- | --- |
| 原生近看1152×720 | 116项／20图 | `reuse-final1152/` |
| 导出PCK完整战斗与养成返回1152×720 | 243项／10图 | `reuse-final-pck-flow1152/` |
| 导出PCK近看960×600 | 116项／20图 | `reuse-final-pck-characters960/` |

最终stage为 `.local/build/ambush-approved-jiang-20261024/stage-b94c5502a570`，应用版本 `0.4.2-approved-jiang`，内容包JSON仍为0.4.0。GLB SHA256为 `e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27`。PCK94,573,380字节，SHA256 `818897d6f2934436ebf65c95225c4de8f069ceeadf5195eff2f5da50228c655c`；Web7文件134,404,991字节（约128.2MiB）。构建与HTTP绑定见 `reuse-final-build.json`／`reuse-final-http.json`，总收据为 `approved-model-final-validation.json`。

[X1本机18818试玩](http://127.0.0.1:18818/)仍用同一来源，材质收尾后刷新可见；没有自动刷新正在进行的战斗。新原生窗口使用同一PCK与独立 `shu-mountain-ambush-approved-jiang` 用户目录。服务分别为 `shu-ambush-approved-jiang-web-final-20261024.service`、`shu-ambush-approved-jiang-native-20261024.service`。18816／18817及原PCK保持；18818较早同源候选的stage和中间材质证据也保留。

原HSV调色烘入2K图，原 `JiangWarmGain` 保留为GLB线性COLOR_0，法线／ORM降到1K；原rig、服饰与手剑保持。Godot导入器未启用头／身主材质的顶点色消费，实查并补齐；Compatibility走sRGB路径，因此仅在实例的网格副本上将线性乘色重编码为sRGB，再按标准材质使用，不改原GLB或场景灯光。依据见[Godot材质实现](https://github.com/godotengine/godot/blob/4.7/scene/resources/material.cpp)及[Compatibility着色器](https://github.com/godotengine/godot/blob/4.7/drivers/gles3/shaders/scene.glsl)。测试实际检查活动材质与真实骨骼，并非用代理手臂节点冒充。

Blender5.2.2所带OCIO声明与已装库版本不匹配，导出器使用仅限该进程的兼容配置副本，未修改系统、安装或升级。保留首轮UV烘焙碎缝、gamma偏亮、未消费顶点色和直接线性乘色偏暗的中间候选，最后以源／衍生同光源图、Godot实际画面和色域检查确认当前处理。近看仍有少量减面／法线细碎纹，后续按反馈精修；没有逐像素等同承诺。

浏览器专项／刷新和IndexedDB、实体键鼠、输入法、设备听感、Windows／Steam Deck、长期性能与真实用户旧档迁移未由代理验证。用户反馈与代理检查分别记录。常驻原生窗口可能出现既有X11输入法 `wd.xic` 警告，实际启动日志单列；上述三次Dummy音频检查无此警告。主副本main保持干净并与origin/main一致；功能worktree仍dirty，未提交或推送。

## 反馈与后续批准

用户在原模型接入后反馈「不错，下面做什么」，认可本次复用方向；随后回复「好」，批准继续这场两人对三人的[反馈加强切片](P3_AMBUSH_FEEDBACK_SLICE.md)。新增范围为动作衔接、击退碰撞／打断、敌方攻击范围与药篓危机提示，不改规则数值或扩其他人物美术。反馈加强已完成本机检查，新[18819入口与实际结果](P3_AMBUSH_FEEDBACK_SLICE.md)另记，用户观感仍待试玩；本页记录继续归原模型复用候选。
