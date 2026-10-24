# P1a：下山进城与返山

日期：2026-10-24，America/Los_Angeles。状态：最小往返已实现、X1 自动验证通过，原生窗口与 Web 包已提供，待用户试玩拍板。

## 本轮范围与规则

用户确认 P0「试玩没问题」，要求「开始 P1，先做进城与返山的最小闭环，完成后再让我试玩」。本片是[整合规划](CHENGPING_INTEGRATION_PLAN.md)的 P1a，采用同一个 `EngineSession` 从听雨廊下山到固定城镇地点，再返回听雨廊继续原养成。不扩大到 P1b 行走、调查案或战斗。

| 场景／行动 | 本片实现 |
| --- | --- |
| `tingyu_corridor` / `go_to_town` | 听雨廊「下山进城」，每程 1 时辰，不扣精力、不发奖；到达 `shanxia_town`，登记 `town_visited` |
| `shanxia_town` / `look_town` | 山下集镇「环顾街口」，可重复免费阅读；仅登记 `town_observed`，不推进时间或成长 |
| `shanxia_town` / `return_from_town` | 「返山回廊」，1 时辰，不扣精力；返回听雨廊，登记 `town_returned`；零精力也可离开 |
| 原师徒和后山 | 11 个原行动、对白／选择／本地音频、五剑和数值原样保留；往返不消耗一次调息提示，返山后可继续练剑复命 |

一局始终由同一个 Session 维护日期、属性、旗标、次数、结果与回执；没有第二套地图状态或费用结算。地点只允许听雨廊与集镇单一出入口，因此返回点明确，不添加来源栈。结果页先收起才可下一行动；原 `ready/result` 安全保存、对白／动作占用与幂等回执规则保持。一天六时辰，旅行可以自然跨日。

**每程 1 时辰、暂不扣精力、通用名「山下集镇」和路线示意图均为本片试玩参数／占位表现，尚未由用户逐项定稿。** 没有新 NPC 对白或新支线原稿，仅有原创短地点说明与行动回执。原主线／支线归档不变。

## 来源与隔离

- 开始基线：`58f56af9b8c39799f1c94d6492d552efe5848cdd`，`codex/x1-shu-integration-plan`，工作区干净；当时 fetch 后 `origin/main` 仍为 `3916899`，沿用已包含该基线和 P0 的当前功能分支。初次试玩交付后，用户追加授权将本片收尾提交推送，并新开任务接入承平。
- 新包 [shu_town_return](../games/shu_town_return/game.json)，内容版本 `0.3.0`；[新目录](../games/town_return_catalog.json)同样运行原 `stream_study`。原 `shu_mentor_loop`／溪亭的 JSON 未修改，P0 可继续试玩。
- 新入口 [cultivation_engine_v03_town.tscn](../scenes/demos/cultivation_engine_v03_town.tscn)；独立构建应用版本 `0.3.0-town-return`，custom user dir `shu-cultivation-engine-town-return`，存档子目录 `user://cultivation_engine_town_return`。不自动迁移 P0 存档。
- [包来源清单](../games/shu_town_return/source.json)固定八份继承 JSON 的原 SHA256。规则、人物、事件、动作资源表 `motions` 和配音表逐字节复用；仅在新包适配场景和新增三个行动。师徒原稿仍是 `trunk/mentor-slow-half-step.json` 与 `trunk/mentor-practice-report.json`。
- 城镇为本片原创 [SVG 路线草图](../assets/art/shanxia_town/route-sketch.svg)，本地 Inkscape 输出 PNG 供现有加载器使用；[来源和哈希](../assets/art/shanxia_town/source.json)同时保留原图与派生图。不是已完成的中国画城镇美术，不借用山门／旧院冒充城镇。
- 既有子集缺少「城」「镇」等文字。按固定官方 URL 取得相同 SHA256 的 Noto Serif SC 原字体，使用项目 `.local/` 独立 venv 的 fontTools `4.51.0` 重建既有命名字体，覆盖 793 码点并保留 OFL；没有全局安装或更换字体来源。
- 构建器仅为新入口补齐已有师徒原稿／音频来源文件；其实际范围仍收集全部 `games` JSON 资源，并非仅包含当前 catalog 的两个包。

## 验证与已知边界

固定 Godot `/opt/agent-creator/godot/bin/godot`，`4.7.2.stable.official.ed1daf0bf`，GDScript / Compatibility，X1 Lite / Fedora 原生 Linux。证据根目录 `/home/x1-lite/games/shu/.local/qa/x1-p1a-20261024/`；构建根目录 `/home/x1-lite/games/shu/.local/build/x1-p1a-20261024/`，均忽略。

最终候选 `stage-3ae601dd6b7d` 消费 164 个源码／资源文件，逐项与当前源码及构建清单的 SHA256 一致；共享 runtime digest `6803c2ed048e0ca203b8fd1d7886b6bda84216d1db738d4a7c8e85cdbc80b992` 与 P0 相同，运行库未变。收据 `source-stage-binding.json`。下列结果均消费该最终 stage；早先候选日志独立保留。

| 项目 | 当前结果 |
| --- | --- |
| 导入 | 退出 0，无错误／警告；`import-final.json`／`.log` |
| 七组状态 | 941 项／0 失败（新增往返 160＋原六组 781），全部退出 0，无错误／警告；`state-final-3ae601/state-results.json` |
| 原生窗口 | 960×600、1152×720 各 120 项／8 图／0 失败，合计 240 项／16 图；退出 0，无错误／警告；`native-final-<size>/` |
| 跨进程存档 | writer 38 项、reader 43 项，共 81 项／0 失败；不同 PID、退出 0，无错误／警告；`process-restart/process-restart-results.json` |
| Web 导出／本机 HTTP 产物读回 | 导出退出 0，无错误／警告；7 文件共 118,773,119 字节，全部 HTTP 200／长度／SHA256 一致；`export-web.json`、`web-artifacts.json`、`http-binding.json` |
| 浏览器实际交互／刷新恢复 | 工具 inventory 仍为空，未验证 |
| 用户试玩、设备听感、Windows、Steam Deck、手柄、长时 | 未验证；P0 用户认可不代替这些专项证据 |

状态检查覆盖非法地点／对白／动作占用拒绝的原子性、同操作回执重试、免费环顾、零精力与最后时辰恢复 fixture、跨日、完整城镇 ready/result 快照和旧两包存档隔离。原生窗口通过 Godot `root.push_input` 注入点击，实际渲染新场景、练剑完整动作、往返和复命，验证取消读档保留当前状态、城镇完整恢复、第二日往返及切溪亭后继续；这是原生窗口自动流程，非物理输入或浏览器。

跨进程 writer 在听教后保存城镇 result：精力 92、理解 1、第一日巳时、一次调息提示仍在；reader 严格恢复完整类型快照后返山（午时）并保存读回，再去后山松风练剑（申时）：精力 70、修为 6、剑术 10，提示仅消费一次；同时核对另一包存档字节和完整状态。动作完成回调在该集成检查中模拟，真实播放证据来自原生窗口。只清理归属标记匹配的唯一临时测试存档，未覆盖人工存档。

首次候选把 SVG 直接配置为背景，被既有只接受 PNG／JPG／WebP 的加载器拒绝；已改为本地 PNG 派生图，不修改运行库。第二候选实际走通主要路线，原生 QA 在切溪亭时遗漏既有替换运行确认；只补充测试的确认点击，保留失败日志。画面检查同时发现半身人物原画不适合直接放街面，最终城镇仅呈现路线示意，不将半身像伪作全身角色。

## 试玩与下一反馈

交付时 `shu-p1a-native-preview.service`、`shu-p1a-web-preview.service` 均 active，原生启动与 GPU 初始化无错误／警告。它是固定 Godot 驱动独立 stage 的开发试玩，不是已经验收的 Linux 独立发行程序。原 P0 的 18812 服务与存档保持。

在 Mac 的 Windows App 进入 X1 桌面，切到《蜀·下山一趟》窗口；或在 **X1 桌面内浏览器**打开 [18813 本机 Web 试玩](http://127.0.0.1:18813/)。本机临时服务不公开，机器重启后不保证继续存在；Mac 的同一 localhost 地址不指向 X1。

1. 选择《下山一趟·进城返山》开始新局，可先听教并选调息，也可直接下山。
2. 点「下山进城」，核对地点、时辰和精力；收起回报，在城内环顾街口并存档。
3. 返回篇章目录后继续或正常退出并重开，核对仍在城里；Web 另需在同一地址保存刷新确认持久化。
4. 点「返山回廊」，确认回到听雨廊且仅再花一时辰；继续后山练剑和向师父复命，检查原提示／成长仍连续。
5. 临近酉时再次下山，观察自然跨日；每次主动往返均有时间代价，读取已结算存档不再次收费。

关闭原生窗口后，可在 X1 桌面终端重开同一候选：

```bash
/opt/agent-creator/godot/bin/godot --windowed --path /home/x1-lite/games/shu/.local/build/x1-p1a-20261024/stage-3ae601dd6b7d
```

Web 离线包 `/home/x1-lite/games/shu/.local/build/x1-p1a-20261024/shu-x1-p1a-web-20261024.zip`，88,267,458 字节，SHA256 `8af5d91484d5dc6752f72c41757e77a06b92d9d64e91ed2b1c98a0a859a8b036`；含预览元数据与 `PLAY.txt`，解包后仍需 HTTP 服务。产物检查只证明当前字节，不代替浏览器操作。试玩重点：时间代价是否直观、集镇与听雨廊切换是否清楚、城内保存后恢复是否仍在城里，以及返回后原听教／练剑／复命是否连续。

本轮交付最小往返；用户随后明确要求 GitHub 收尾，并新开任务接入承平。下一任务按[P1b 交接](CHENGPING_P1B_HANDOFF.md)开始实际城镇行走／互动适配；城镇画景、行走角色与具体节奏继续通过小片试玩调整，不扩成调查或战斗。
