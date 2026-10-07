# 蜀（shu）

以《武林群侠传》的养成体验为启发，结合四川／蜀山元素的原创武侠修炼与生活养成游戏。先做 Web，并为后续 Steam 桌面版规划。

**Codex 做可玩 demo → 用户试玩拍板 → Codex 修订 → 更新决定与扩展计划。**

## 当前本机试玩：《两盏茶》完整支线

[在线正式版](https://jggagi.github.io/shu/)仍为 **0.1.4-tea-objects**（A/B 已验收发布）。阶段 C 已获用户验收；用户随后授权完整支线。本机候选 **0.1.9-tea-past-local** 已补齐医者诊察、写信和后事过去场景，完成本机专项与真实 Web 全流程验证；新画面与完整体验待你试玩拍板；用户已授权将当前源码归档至 GitHub 分支 `codex/tea-full-past-scenes`，在线试玩尚未发布本候选。

接受旧剑委托 → 剑坪双杯 → 旧院账册 → 诊录 → 柜中旧信 → 今天刚认识 → 几册旧记 → 最后一天 → 后事公文 → 归剑回到原剑坪。文书逐页读；医案、写信、日记与后事片段进入过去旧院，人物对白与时间变化在画面中呈现，收起回到当下调查。没有底部确认或右侧菜单。阶段完成、歇息与场景往返都留在支线内；最终重新调查同一双杯，先添一杯、停一会儿、再添另一杯，才显示《两盏茶》并允许返回养成。

查看与阅读不花精力或养成时间；原修炼、师傅与歇息数值保持。重新开始／刷新清空当前运行，无磁盘存档；《两盏茶》支线无声音或新奖励。听雨廊本地候选新增可开关的雨声与檐滴，见 [环境声音切片](docs/TINGYU_AUDIO_SLICE.md)。

[过去片段任务卡](docs/TEA_PAST_ALL_SLICE.md) · [过去片段验证](docs/TEA_PAST_ALL_VALIDATION.md) · [节奏收尾任务卡](docs/TEA_PACING_SLICE.md) · [本轮验证](docs/TEA_PACING_VALIDATION.md) · [日记演出任务卡](docs/TEA_MEMORY_SLICE.md) · [演出验证](docs/TEA_MEMORY_VALIDATION.md) · [完整支线任务卡](docs/TEA_FULL_SLICE.md) · [验证记录](docs/TEA_FULL_VALIDATION.md) · [已验收 C](docs/TEA_C_VALIDATION.md) · [旧院美术来源](assets/art/tea-c/source.json)。新支线归档入口已核实为 `jggagi/sub/tea/full-chain.json`，完整运行快照及来源哈希在 `assets/data/tea-full-source.json`、`tea-full-provenance.json`；历史原稿不迁移、不改写。

## 后山独立表现实验

[后山 Clouds v1 独立试玩](https://jggagi.github.io/shu/back-mountain/)：已认可的流动增强版，高空远云和山腰云气缓缓经过山体；4 动静、1 修炼、R 重置，L 保留旧光影对照。独立入口与版本／源码绑定见该入口 `build-info.json`；发布结果以实际部署为准。

「蜀山后山 · 独自修炼」沿用 DemoState，只提供修炼、动静／光影对比和重置；不接入正式主流程。运行：

```sh
godot --windowed --path . res://scenes/demos/back_mountain_training.tscn
```

键盘 1 修炼、4 动静、L 原画／增强光影、R 重置。Lighting v1 保留作实验对照；用户试玩认为变化不明显，后续停止打磨这套复杂光影，优先原画、简单调色与少量微动。详见 [切片与验证](docs/BACK_MOUNTAIN_SLICE.md)、决定 D028。

本机新增 **Back Mountain Environment v1.2**（太阳表现已获用户试玩认可）：同一独立场景中，真实六时辰驱动亮度／色调／晨雾，7 晴、8 多云、9 小雨，0 仅视觉夜景预览。按用户「三种天气没啥区别」反馈，已加强晴／阴亮度差、云量与雨雾，并让细雨在试玩窗口可见。时辰 1.2 秒、天气 8 秒平滑变化，4 静态保留当前环境并冻结运动；L 的旧光影实验保留，环境在关闭它时仍完整有效。晴天新增随真实时辰变化的淡金／暖橙太阳，多云、小雨与夜景会遮隐；见 [太阳修订](docs/BACK_MOUNTAIN_SLICE.md#environment-v12-晴天太阳2026-10-06)。在线链接仍是此前 Clouds 版本，本轮未发布。运行命令与截图见 [Environment v1 记录](docs/BACK_MOUNTAIN_SLICE.md#back-mountain-environment-v1客户端日期-2026-10-05)，最新检查见 [天气反馈修订](docs/BACK_MOUNTAIN_SLICE.md#environment-v11-天气反馈修订2026-10-05)。

此前 **Ambient Life v1 · 山间生趣**：远鸟偶尔掠过天空，松鼠短暂经过松枝，猫偶尔在岩石边安静趴着。复用已有时辰／天气／动静状态；不影响修炼与数值。A 开关生趣，B／S／C 强制查看鸟／松鼠／猫，U 恢复自动；强制查看仍遵守天气、夜景和静态限制。没有适合鱼的水域，不启用鱼。实现、参数和本机验证见 [本轮切片](docs/BACK_MOUNTAIN_SLICE.md#ambient-life-v12026-10-06)，待用户试玩验收，未发布。

此前 **Ambient Life v1.1 · 山间小动作**：猫在清晨／多云时偶尔抬头，晴天中午更多打盹，按现有风力参数轻摆尾；松鼠增加小幅迈腿、跑动起伏和停下时的尾巴调整。动作复用已有环境与事件时钟，关闭动态恢复静止；出现密度、位置与玩法保持。C 查看猫后约 6 秒可见清晨抬头、约 12 秒轻摆尾；S 查看松鼠，U 恢复自动。[修订记录](docs/BACK_MOUNTAIN_SLICE.md#ambient-life-v11猫与松鼠的小动作2026-10-06)。

此前本机 **大橘猫 v1 · 摸摸与自娱**：胖乎乎的橘色虎斑猫更容易在岩石边遇见，点击猫可摸摸，它会眯眼蹭手；闲着时会舔爪、拨落叶、翻身玩。晴天中午偏爱打盹，修炼时安静待着，小雨／夜景隐藏，关闭动态保留静卧并暂停互动。C 立即查看大橘，U 恢复自动；不消耗时间或资源。[本轮记录](docs/BACK_MOUNTAIN_SLICE.md#大橘猫-v1摸摸与自娱2026-10-06)。外形、节奏与互动仍待用户试玩，未发布。

当前本机窗口为 **大橘猫 v2 · 水彩画风**：按「画风有点违和」反馈，以现有后山与主角作风格参考，重新设计细线、水彩毛色、柔和阴影的胖橘。八个透明 PNG 姿态已接入，摸摸与自己玩的行为沿用 v1；旧 SVG 保留作历史。[素材与实际效果](docs/BACK_MOUNTAIN_SLICE.md#大橘猫-v2水彩画风2026-10-06)，新画风已获用户认可（2026-10-06「很好 我喜欢」），授权保存到 GitHub；在线试玩尚未更新。

Mac mini 独立启动：

```sh
/Users/guoq/.local/bin/godot --windowed --path /Users/guoq/Developer/shu res://scenes/demos/back_mountain_training.tscn
```

美术制作默认采用 Codex 建立 reference、Qwen 小样检查后批量生产；项目级 [game-art skill](.agents/skills/game-art/SKILL.md) 和来源记录随源码保存，候选图与凭据不入库。本机 Qwen 配置与发送授权边界见 [Qwen 美术制作配置](docs/QWEN_ART_SETUP.md)。

## 当前可玩：D01 听雨廊

江砚秋与叶知闲同处听雨廊。修炼推进时间与修为，请教口诀得到一次修炼加成，休息恢复精力。修为达到 60 完成第一课，可重新开始反复试玩。姓名与整体美术风格已由用户确认；构图、动态强度与数值继续供试玩拍板。当前使用分层生成的中国画背景、Q 版师徒、木桌与宣纸木框，原 SVG 占位稿仍保留供比较。

本机候选 **0.1.10-tingyu-environment-local**：作为 EnvironmentPresenter 的第二场景，听雨廊以自己的 profile 接入真实六时辰及晴／多云／小雨。保留原背景、竹叶、廊外雨雾和师徒；时辰跟随原行动，天气由右上「切换天气」选择。Static 保留完整画面并冻结环境运动；主动更换时辰／天气仍平滑过渡，Dynamic 从冻结位置恢复。环境切换不改变玩法状态。具体氛围与强度待用户试玩，见 [本轮切片与验证](docs/TINGYU_ENVIRONMENT_SLICE.md)。此前 30 秒循环保留为历史代码，不再驱动主场景。

本机已接入听雨廊完整 P0–P2 实施候选：统一纸木控制面板、茶气、摸猫、案上两器物、雨后湿色、山雾与风／行动声音，以及师徒呼吸和四个行动姿态。用户已明确授权向配置的北京 Qwen 工作空间发送两张原角色 PNG 参考图和四个精确提示；共完成四次 Qwen Image 3.0 生成，无重试。原始 RGB 输出只在本地以 `tools/compose_tingyu_actors.gd` 合入原始 RGBA 角色图，保留原 alpha 与多边形范围外的原像素。四姿态通过 Godot 原生预览；新 Web／Windows 包均导出成功，Web 鼠标行动流程与键盘天气／动静切换已复核，浏览器控制台无警告／错误。Windows 实机、设备听感与用户试玩仍待完成；原养成结算与 Tea 保持。见[当前实施与验证](docs/TINGYU_COMPLETE_SLICE.md)。

最新本机反馈修订：香炉恢复合适比例并升起细烟；猫更常来，默认多云约6秒可遇见，新增四个迈步、站姿与坐姿，在右侧空桌面短距离往返，点击仍可摸摸。Busy和静态暂停动作，恢复后接续。Mac原生画面已检查；具体节奏与步态待试玩，旧Web／Windows包尚未包含这两轮修订。见[猫走动记录](docs/TINGYU_CAT_DESK_SLICE.md)与[香炉记录](docs/TINGYU_INCENSE_SLICE.md)。

## 运行与导出

引擎与导出模板锁定 **Godot 4.7.2 stable**（见 `.engine-version`），语言为 GDScript，Compatibility 渲染；Web 使用单线程模板。

- 用 Godot 打开 `project.godot`，按 F5 运行主场景；Windows 上有 `godot` 命令时也可双击 `Play.cmd`。
- 在仓库根目录运行以下命令，导出 Windows／Web 两个试玩包：

```powershell
.\tools\build.ps1 -GodotBinary godot
```

- Windows：打开 `.local/build/windows/ShuDemo.exe`。同目录的 `ShuDemo.pck` 必须保留；运行导出包不需要安装 Godot。
- Web：使用 Python 3（仅标准库）运行 `python tools/serve_preview.py --open`，或双击 `Start-Web.cmd`。打开本机地址 `http://127.0.0.1:8765/`；需要先完成 Web 导出，不能直接双击 HTML。
- 若工具不在 PATH，可给构建脚本传引擎完整路径；启动脚本支持 `SHU_GODOT`／`SHU_PYTHON`。运行项目不依赖 Codex 会话目录。

## 试玩顺序

1. 点击「修炼吐纳」，观察精力、修为与时辰。
2. 点击「请教师傅」或画面中的师傅，选择「请教吐纳口诀」，读完后点击「继续」。
3. 再修炼一次：这次修为增加 18，之后恢复基础增量 12。
4. 休息恢复精力，继续修炼达到 60；点击「重新开始」回到首日初始状态。

键盘 1／2／3 对应修炼／请教／休息；4 切换静态／动态，5 切换下一天气，7／8／9 直接选晴／多云／小雨；对话选择时 Esc 可取消。当前没有存档，刷新、重开会开始新一轮。本地听雨廊可点击「开启声音」，旁边滑条调音量；`9` 小雨、`7` 晴可试听雨声与雨后余滴，在线版尚未更新。建议使用桌面窗口；手机竖屏布局留待后续。

## 维护入口

- [设计规格](docs/SPEC.md)：已确认方向、视觉要求、人物名单与待定项。
- [决定日志](docs/DECISIONS.md)：决定来源、确认状态和后续变更。
- [开发流程与路线图](docs/DEVELOPMENT.md)：验证记录、用户反馈与下一切片条件。
- [Codex 工作约定](AGENTS.md)：范围和验证规则。
- [概念图索引](docs/concepts/README.md)：三张原始概念图与 SHA256。
- [美术来源](assets/art/v2/source.json)与[天气美术来源](assets/art/weather3/source.json)：运行图层、生成提示与 SHA256。
- `assets/data/tingyu_environment.json` 调听雨廊时辰／天气表现与过渡，`assets/data/weather.json` 保留廊景雨线、竹叶位置与更新频率；`scripts/weather.gd` 为听雨廊 adapter，复用 `EnvironmentPresenter`，养成规则独立。`scripts/weather_cycle.gd` 仅为原循环历史。
- `assets/data/characters.json` 是当前姓名表；对白通过人物标识读取称呼。
- `assets/data/layout.json` 调人物位置／面板布局；`rules.json` 调养成数值（行动文案同步 `main.gd`）；`dialogue.json` 改对白。状态结算在 `scripts/demo_state.gd`，界面在 `scripts/main.gd`。
- `tools/make_art.py` 可重新生成原创 SVG 草图。当前界面使用带 OFL 许可的 Noto Serif SC 派生子集 Shu Demo Serif，旧 Sans 子集保留。字体来源、版本与 SHA256 随文件保存；新增汉字时用 `tools/rebuild_font.py` 扩展字库（fontTools，实际版本见字体来源记录；开发工具，运行无需安装）。

养成边界检查：

```powershell
godot --headless --path . --script res://tests/state_test.gd
```

天气切换与真实渲染检查：

```powershell
godot --headless --path . --script res://tests/weather_test.gd
godot --path . --audio-driver Dummy --script res://tests/weather_render.gd
```

当前渲染检查使用实际 Compatibility 画面，将时辰／天气／过渡／动静及 UI 截图写入 `.local/qa/tingyu-environment-v1`；同时记录实际窗口与图像尺寸。历史 weather3 性能记录保留，本轮不作跨设备帧率承诺。

每轮先收试玩反馈，再调整布局和节奏。D02 拟增加余观涛互动与第二项养成活动，待本轮验收后推进。


## 制作 skill 与下一轮 tea

养成模式制作入口：[game-cultivation-build](.agents/skills/game-cultivation-build/SKILL.md)，仓库级 0.1.1；支持养成行动、人物互动及 tea 等固定场景支线。拟议的 cultivation toolkit／编辑器插件仍为设计，尚未实现。

固定画景、时辰／天气与环境动态使用 [game-painted-scene-build](.agents/skills/game-painted-scene-build/SKILL.md)；低频环境动物与场景能力使用 [game-ambient-life-build](.agents/skills/game-ambient-life-build/SKILL.md)；raster 素材由 [game-art](.agents/skills/game-art/SKILL.md) 制作并在真实场景校准。现有 Environment/Ambient presenters 是 reusable shu modules，`shu_scene_runtime` addon 尚未实现。[制作方法 v1](docs/SCENE_REUSE_HANDOFF.md)记录听雨廊仅接时辰／天气时的历史状态及未来 addon 决策门；当前完整候选和复核状态见[实施记录](docs/TINGYU_COMPLETE_SLICE.md)。

[工具包设计](docs/CULTIVATION_MODE.md) · [检查记录](docs/CULTIVATION_MODE_CHECKS.md) · [新 chat 的 tea 交接](docs/TEA_HANDOFF.md)。A/B 与阶段 C 已验收；完整调查和过去场景已实现，D01 养成保持可用；新画面与完整体验继续由用户试玩拍板。
