# 剧情工具对照试样

本页记录8809旧师傅口诀对照及其历史验证。当前源码已继续制作独立的[《慢半步》有声情节](MENTOR_VOICE_SCENE.md)，新入口为8811；不将旧版原生／浏览器证据当作新版测试。旧stage和8809服务保持。

客户端日期：2026-10-23。用户要求「先试样，让我看 demo 效果再推荐」。本轮为独立工具评估，不选定正式剧情工具，不迁移完整 Tea，不改变正式入口或既有存档。

## 可观察目标

在同一听雨廊、同一师徒和同一段已有「师傅的一句口诀」对白中，分别试用 Dialogue Manager 与 Dialogic 的真实解析／运行能力。玩家请教、选择领会或离开、阅读后返回，随后调息或休息，检查选择是否影响实际养成结果，并可在安全节点保存／读取。切换工具从相同新局开始，各工具存档隔离。

按用户最新视觉统一要求，江砚秋与叶知闲均使用 `assets/art/v2/` 的现有 2D 原画，与原廊景／桌案保持同场景画风；不生成新美术。室内养成／对白使用 2D，练武／战斗等动作场景才使用 3D 人物模型，见[场景视觉规范](SPEC.md#人物表现与场景视觉统一客户端日期-2026-10-23)。Dialogue Manager 使用本实验纸面界面，Dialogic 使用真实布局节点及时间线呈现。画面与制作方式的差异供试玩判断，不能由两者看起来相似就推导维护成本相同。

## 边界与来源

- 唯一养成权威仍是未改动的 `addons/cultivation_mode/session.gd`；工具只呈现对白和选择，白名单桥接现有 `Session.choose`。没有插件存档／自动存档，也不向剧情插件暴露任意养成写入函数。
- 试样内容来自 `games/shu_entry/events.json` 的 `mentor_tip`，正文／选项保持；成本8精力／1时辰、理解+1、下次修习额外6修为，修习22精力／2时辰／基础12修为、休息最多34精力／1时辰保持。仅将调息场所适配为廊下，作为工具夹具，不新增正式故事原稿。
- 新 `games/dialogue_tools_sample` 不登记入原 catalog。`scenes/demos/dialogue_tools_trial.tscn` 为独立入口。`tools/build_dialogue_tools_lab.py` 只在新 stage 中配置插件及自定义用户目录 `shu-dialogue-tools-lab`，源项目 `project.godot` 保持。
- 两个固定插件仅保存在 `third_party/dialogue_tools_lab`，父目录 `.gdignore` 阻止正式项目扫描其脚本类；构建时仅复制addon内容到stage标准路径并启用官方导出钩子，没有启用正式项目插件、全局安装或自动更新。
- Dialogue Manager 固定 `v4.1.0`，Dialogic 固定 `2.0-alpha-20`，均保留 MIT 许可、官方来源与下载 SHA256。Dialogic 仍为 Alpha；本轮兼容性必须以实际执行为准。
- 本轮不用云端生成、积分或付费服务；没有 Git 提交、推送或公开发布授权。

## 验证记录

本地试玩：[8809](http://127.0.0.1:8809/)。当前试样已实现，体验与正式工具选择等待用户试玩。

- 首版候选源码与stage共1024项输入逐SHA256保持，两个运行时纯文本副本与原对白源逐字节相同；原引擎、正式入口、旧两包与catalog共26项基线保持。该版曾混用江砚秋模型待机帧与 2D 师傅，现由用户视觉统一决定替代；下述完整原生／Web流程记录属于该候选。
- 原生GUI：A两窗口各56项／4张捕获、B两窗口各27项／4张捕获，交互断言均通过；实际检查了接受／拒绝、返回、一次加成、存读档和退出交谈。**原生退出并未通过稳定性验收**：A退出报告ObjectDB／resource残留；B在流程完成后退出发生signal11。清理等待未消除该问题，保留日志，不将断言0失败写成原生程序全通过，不据此推荐正式接入。
- Web：两边实际点击完成同一段对白，领会后92精力／辰时，修习后70精力／18修为／午时；B额外休息到100精力／18修为／申时。分别保存后立即刷新，A恢复70／18／午时、B恢复100／18／申时，确认两个存档隔离。最终页控制台检查单独保存。
- 浏览器实际DOM为762×428，canvas约761×427；原生标准窗口1152×720、960×600与浏览器证据分别记录。临时viewport测试设置不等于实际测量尺寸，交付前恢复默认。
- 最终Web导出无脚本／资源错误，但编辑器退出仍报告2个ObjectDB残留；记录为已知问题。Web约47MiB，不包含五套动作，只是同内容剧情工具试样。Windows、声音、长时及正式可扩展性未验收。

首次导出遗漏官方editor/export hooks并包含可选C#示例，已在独立stage按标准方式启用两个插件并排除未使用的C#伙伴场景。插件导入会在Web替换 `.dialogue`／`.dtl` 原始源，因此运行时编译评估使用构建时生成的逐字节相同 `.txt`；不更改对白或降低源文字白名单。首次错误／原生退出日志和最终浏览器证据均保留于 `.local/qa/dialogue-tools-lab/`。

构建前开发卷略低于20GiB门槛，未开始构建。仅将无占用旧候选与三份旧试玩归档中已确认完全相同的可重建资源／Web导出改为独立inode的APFS克隆；所有路径和SHA256内容保留，活跃服务stage未改。逐文件与前后容量凭据在 `.local/qa/dialogue-tools-lab/*clone*`，不把逻辑去重字节冒称物理回收量。

### 室内 2D 修订（2026-10-23）

当前 8809 已切换为独立新 stage：江砚秋、叶知闲使用同系列 2D 原画；练剑图集不进入本试样。1022 项源码输入与 stage 逐 SHA256 一致，原核心／旧包／正式入口的 26 项基线保持，两个对白文本副本保持逐字节一致。真实 Web 检查 A/B 切换、对白开启及 Escape 返回；两侧师徒原画、桌面遮挡与排版已查看，实际 DOM 为 685×428，截图在 `.local/qa/dialogue-tools-lab/browser-2d-*.png`。没有重跑原生完整流程或把首版结算／存档证据归为本轮新测试。

新 stage 首次导入遇到插件图标 UID 缺失，保留官方 `.import` 元数据后重导入发生退出 signal11；随后复用同版本、同资源的已验证导入缓存与 UID 索引，未复制编辑器状态或修改第三方源码。最终 Web 导出无脚本／资源错误，仍有 2 个 ObjectDB 退出残留；B 在浏览器加载时对三项插件资源 UID 发出警告并使用已有文本路径成功加载，不能记录为零警告。全新缓存首次导入、原生退出稳定性仍未通过，本轮只完成视觉反馈修订。收据与失败／最终日志分开保存在 `.local/qa/dialogue-tools-lab/visual-2d-*`。

## 复现

以下为当时构建流程；当前构建脚本已用于有声情节，复现旧版须使用本页QA收据指向的旧stage源码快照。

先按工作站规则核验容量和锁定Godot／模板；使用已有fontTools与本地原始OFL字体生成本实验字体，再构建独立stage。

```sh
python tools/rebuild_dialogue_lab_font.py --source <pinned-NotoSerifSC.ttf>
python tools/build_dialogue_tools_lab.py --output <existing-absolute-build-dir>
godot --headless --editor --path <returned-stage> --import
godot --headless --path <returned-stage> --export-release Web <returned-stage>/web/index.html
```

构建任务通过本机 `agent-dev run` 包装；实际命令／stage来源／检查收据保存在本轮QA目录。Windows、听感、长期性能与正式工具选型不由本轮构建自动验收。


## Godot 4.7.2 导入崩溃修复（2026-10-23）

21:28 的 `WorkerThread 3 / EXC_BAD_ACCESS` 来自独立 stage 的 `--editor --import`，日志停在 `Roboto-Regular.ttf`。安装二进制 UUID 与报告相同，但无匹配本地调试符号，不能声称已符号化定位引擎源码。表现与 Godot 上游 [并行字体导入崩溃 #111039](https://github.com/godotengine/godot/issues/111039) 一致。

`tools/build_dialogue_tools_lab.py` 现仅在生成的实验 `project.godot` 设置 `editor/import/use_multiple_threads=false`；原失败 stage 也已补入相同设置，以便继续原修复命令。保持 Godot 4.7.2、Compatibility、两个固定插件及正式项目设置。该设置是项目级规避措施，不是引擎补丁。

独立克隆中原失败导入 4.87 秒退出 0、无脚本／资源错误。新 stage 首次导入与随后重复导入均退出 0；首次 Dialogic 编辑器字体主题刷新报告 `fd` 为空，重复导入后消失。第二次导入和 Web pack 导出均无脚本／资源错误，仍有编辑器 ObjectDB 退出残留警告。新 stage 为 `stage-128495418715`；完整收据与首次错误保存在 `.local/qa/dialogue-tools-lab/crash-fix-20261023/`，不将首次退出 0 等同于无错误。

对全新 stage，先按上述命令完成一次导入，再重复 `godot --headless --editor --path <stage> --import`，确认资源及插件初始化错误已清空后导出。新 Web pack 复用与 4.7.2 锁定单线程 release 模板 SHA256 相同的 Web runtime；这是 pack 重建与真实浏览器检查，不冒称完整模板重新导出。独立检查入口为 [8810](http://127.0.0.1:8810/)，原 8809 服务保持。

26 项正式玩法／入口／存档代码基线 SHA256 全部保持。此前原生 Dialogic 退出 signal 11 与 ObjectDB 残留属于另一条路径，本次不据此宣称修复；Windows、长时稳定性未验证。

8810 修复候选实际浏览器复核：A 与 B 均完成请教→领会→返回→修习，领会后精力92，修习后70精力／18修为；两位人物均为原有2D原画。两张结果截图与最终源码绑定检查见同一修复QA目录。本轮不重验存读档。
