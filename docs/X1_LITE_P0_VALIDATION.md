# X1 Lite P0 验证与试玩交付

日期：2026-10-24，America/Los_Angeles。初次交付状态：**X1 状态、原生窗口自动流程及跨进程存档通过，已提供试玩；浏览器交互、设备听感与用户认可待验收。** 当时 P0 的所有门槛尚未全部关闭，不自动进入 P1。

后续用户反馈：用户已明确「试玩没问题」，并授权开始[P1a 进城返山](P1A_TOWN_RETURN_SLICE.md)。当前 P0 体验已获认可；下文保留原交付时的技术验证边界，不由该反馈推定未明确的浏览器／设备专项也已实测。

## 源码与环境

- 按用户要求先提交推送规划：[`403a25459f2ef78a995c70d5f2e7427215758b76`](https://github.com/jggagi/shu/commit/403a25459f2ef78a995c70d5f2e7427215758b76)，分支 `codex/x1-shu-integration-plan`，推送后本地与远端引用一致；没有合并 `main`。
- 实际用户 `x1-lite`，Bash，Fedora 44 KDE 原生 Linux；工作副本 `/home/x1-lite/games/shu`。构建开始时该提交工作区干净，验收时只增加测试清理修正及本轮文档。初次试玩交付后，用户追加授权将 P0 记录、相关文档状态更新与测试修正一并提交推送到当前分支；构建来源仍以原提交加下述测试补丁为准。
- Godot `/opt/agent-creator/godot/bin/godot`，`4.7.2.stable.official.ed1daf0bf`，Standard / GDScript / Compatibility；复用已有匹配模板，没有安装或全局配置变动。
- 入口 `scenes/demos/cultivation_engine_v02_mentor.tscn`，`0.2.2-mentor-loop`；目录 `games/mentor_loop_catalog.json`，包含 `shu_mentor_loop` 与 `stream_study`。F5 旧 `DemoState`、完整 Tea 与 Chengping 来源副本未改。
- 最终独立 stage：`/home/x1-lite/games/shu/.local/build/x1-p0-20261024/stage-46b0a1ce5c59`。148 个消费文件逐项与源码和构建清单的 SHA256 一致；共享 runtime digest 为 `6803c2ed048e0ca203b8fd1d7886b6bda84216d1db738d4a7c8e85cdbc80b992`，运行库未变。

构建器使用显式师徒入口、标题、版本与 `--user-dir shu-cultivation-engine-mentor-loop`，未使用 macOS 的 `--reuse-stage`。完整源码绑定在 `.local/qa/x1-p0-20261024/source-stage-binding.json`；源码提交加下述已标注测试补丁，而非仅凭旧 SHA 声称最终候选干净。构建器固定写入的 `source_dirty: true` 不代替实际 Git 状态记录。

## 实测结果

| 层次 | 结果 | 范围与证据 |
| --- | --- | --- |
| Godot 导入 | 通过，退出 0，无错误／警告 | 最终 stage 独立缓存；`import-final.log` |
| 六组状态检查 | 781 项，0 失败，全部退出 0，无错误／警告 | 基础 184、五剑 179、物件 152、事件结束 31、语音 28、师徒 207；`state-final/state-results.json` |
| X1 原生窗口自动流程 | 960×600 与 1152×720 各 142 项，0 失败，合计 22 图；无错误／警告 | `native-final-results.json` 及对应两目录；真实渲染并播放松风动作，使用 Godot `push_input` 注入点击，不等同物理键鼠或用户试玩 |
| 退出后独立进程恢复 | 85 项，0 失败；两进程退出 0，无错误／警告 | writer 63、reader 22；实际 Loader／Session／SaveStore，完整类型快照一致、双包隔离及重复回执幂等；`process-restart/process-restart-results.json` |
| Web 单线程导出 | 通过，退出 0，无错误／警告 | 7 个构建文件合计 118,640,378 字节；`export-web-result.json`、`web-artifacts.json` |
| 本机 HTTP 产物绑定 | 7 个文件均 HTTP 200，完整长度及 SHA256 一致 | `http-binding.json`；这是传输验证，不是浏览器运行证明 |

所有证据根目录为 `/home/x1-lite/games/shu/.local/qa/x1-p0-20261024/`，属于忽略的本机日志和截图，不进入源码提交。检查包含日志中的 `SCRIPT ERROR`、`ERROR` 和警告，未仅以退出码判断。

原生窗口自动流程覆盖：听教调息付费分支、动作繁忙门禁、松风完整播放和唯一结算、练剑结果保存、回廊复命并保存结果、四次歇息至第二日、跨日后读取复命结果、数值／日期／场景／旗标／回执恢复及不重复播放对白。六组状态测试另覆盖五剑与溪亭规则；跨进程测试独立保存并恢复两包。

跨进程路线最终师徒状态为第二日卯时、听雨廊 result，精力 100、理解 1、修为 6、剑术 10、练剑 1 次、歇息 4 次、复命完成。溪亭独立状态为 riverbank、第一日暮时（`slot=2`）、余力 65、心得 8。该测试模拟动作完成回调，不能代替原生画面或浏览器；动作播放由原生窗口检查提供证据。临时测试存档按唯一归属标记清理，未覆盖人工存档。

## 发现与最小修正

首次语音测试虽然 28 项断言通过且退出 0，仍出现 Linux 退出时 `AudioStreamPlaybackWAV`／WAV 资源未回收。保留原日志和最小复现后，仅在 [语音测试](../tests/cultivation_engine_voice_player_test.gd) 的节点释放后等待音频服务 0.1 秒完成清理；两行变动，不修改语音播放器或游戏规则。补丁后该文件 SHA256 为 `7d3be41b35963336033756545f03ee7338a8ddc43cb8ed28b8be6430e2a38acd`，重新创建最终 stage 并完成上表检查。

首个跨进程 QA 候选用 JSON 作为严格比较的预期值，整数被解析成浮点数，导致 Dictionary 比较失败。最终 QA 改用保留类型的 Variant 预期文件，同时保留可读 JSON；这是测试比较器修正。原候选位于 `process-restart/candidate-001-json-comparison/`，不把其失败掩盖为产品通过。

## 试玩入口与步骤

交付时，X1 用户服务 `shu-p0-native-preview.service` 和 `shu-p0-web-preview.service` 均 active。原生进程使用固定 Godot 打开最终 stage；它是开发运行入口，不是已验收的 Linux 独立发行程序。原生启动日志有一条 X11 输入法 `wd.xic` 创建警告，游戏启动与 GPU 初始化正常；未将该警告算作无警告验收日志，也未修改全局输入法设置。

在 Mac mini 的 Windows App 中连接 X1 桌面，切到《蜀山·听教练剑》窗口即可试玩。也可在 **X1 桌面内的浏览器**打开 [http://127.0.0.1:18812/](http://127.0.0.1:18812/)；Mac 浏览器的同一地址不会访问 X1。服务为本机临时预览，重启机器后不保证继续存在。

1. 选择《慢半步》师徒包，开始新局。点师父听教，走到选择后选调息；核对消耗和理解变化。
2. 前往后山，任选五套剑法之一修习，等待动作收势；核对精力、剑术与听教带来的一次修为收益。
3. 回听雨廊向师父复命，再歇息四次进入第二日；观察日期与精力。
4. 在行动结果或待行动阶段保存，返回目录后继续，或正常关闭并重新启动后继续；核对日期、属性、位置与复命状态。交谈和动作中不能保存。每包是两个轮换检查点，不是两个手动槽。
5. 切换溪亭验证包，确认其独立进度，再返回师徒包继续。若选择 Web，还需保存后在同一浏览器／地址刷新，确认继续恢复。

关闭原生窗口后，可在 X1 桌面终端重新启动同一独立候选，用户目录和存档保持：

```bash
/opt/agent-creator/godot/bin/godot --windowed --path /home/x1-lite/games/shu/.local/build/x1-p0-20261024/stage-46b0a1ce5c59
```

Web 离线包：`/home/x1-lite/games/shu/.local/build/x1-p0-20261024/shu-x1-p0-web-20261024.zip`，88,164,992 字节，SHA256 `e7026eb46f175512fa3a5b9aab438d7b18ec2f83fc2a8e79375dfa96ad160520`。包含 Web 文件、来源元数据与 `PLAY.txt`；需 HTTP 服务，不能双击 HTML 代替。`creator-game-check` 已核对产物元数据，不能把该工具本身当作构建或试玩证明。

## 尚未验收与下一步

浏览器工具当前没有可用浏览器，`iab`／`chrome` 均不可用。因此未验证实际浏览器加载／按钮／刷新持久化／控制台；导出和 HTTP 读回不能替代。X1 物理键鼠与远程输入手感、设备配音听感、长期运行、Windows 实机、Steam Deck、实体手柄及用户认可也未验收。当前音频环境只发现 PipeWire `auto_null` 输出，不能宣称已听到配音。

先由用户试玩反馈可见流程、文字／布局、动作节奏与声音；补齐浏览器持久化等 P0 缺项后再关闭 P0 门槛。P1 城镇构图、往返代价和事件正文仍按[整合规划](CHENGPING_INTEGRATION_PLAN.md)单独确定，本轮没有实施城镇、移入承平源码、合并 main 或公开部署。
