# 蜀（shu）

以《武林群侠传》的养成体验为启发，结合四川／蜀山元素的原创武侠修炼与生活养成游戏。先做 Web，并为后续 Steam 桌面版规划。

**Codex 做可玩 demo → 用户试玩拍板 → Codex 修订 → 更新决定与扩展计划。**

## 当前支线试玩：归剑问天 · A/B

[在线试玩（GitHub Pages）](https://jggagi.github.io/shu/) · 建议桌面横向窗口；首次加载约 55 MB。

**0.1.4-tea-objects**（内容 tea-ab-object-2；在线部署版本以 build-info.json 为准）：养成画面点击「归剑问天 · 旧剑委托」（或按 6），接受后进入剑坪。悬停旧杯有淡墨亮边和小标签，直接点击即查看并更新「旧杯 0/2 → 1/2 → 2/2」；杯旁浮层提供修补／询问，不再经底部确认或右侧统一菜单。点击另一杯切换浮层，点击空白／Esc 只收起浮层；进入支线后，整条支线完成前不返回养成主界面。

剑坪底部仅显示薄札记；右下「廊下歇息」沿用恢复至多 34 精力、推进一时辰，留在剑坪并保留进度。查看与两杯完成不耗精力／时间；首杯修补 -22、每杯询问 -8，每个物件行动在当前运行内只结算一次，重访不会重复收费。精力不足时对应动作不可用。两杯直接查看后自动达成 A/B 本段条件，原有初期推想显示在札记；这不是整条支线完成，仍留在剑坪；不发装备或修为奖励。刷新／关闭／重新开始会重置，没有新增存档。

只修订现有 A/B 的物品交互与支线返回规则；阶段 C 和后续行程尚未实现，2/2 后显示“本段线索已收齐；支线后续尚未开放”，不假装支线结局、不自动返回。顶部 HUD、听雨廊养成流程和美术原图保持；首杯描述／修补反馈采用用户明确给定的 UI 适配文字，第二杯、传闻、推想及原稿揭示顺序保留，历史原稿不迁移。

[任务卡](docs/TEA_SLICE.md) · [验证记录](docs/TEA_VALIDATION.md) · [美术来源](assets/art/tea/source.json)。玩法状态、内容和布局分别在 demo_state.gd、assets/data/tea.json、tea-layout.json。历史原稿保持原位，本轮运行文字直接引用原稿；没有新写或迁移支线稿。

## 后山独立表现实验

「蜀山后山 · 独自修炼」沿用 DemoState，只提供修炼、动静／光影对比和重置；不接入正式主流程。运行：

```sh
godot --windowed --path . res://scenes/demos/back_mountain_training.tscn
```

键盘 1 修炼、4 动静、L 原画／增强光影、R 重置。Lighting v1 保留作实验对照；用户试玩认为变化不明显，后续停止打磨这套复杂光影，优先原画、简单调色与少量微动。详见 [切片与验证](docs/BACK_MOUNTAIN_SLICE.md)、决定 D028。

美术制作默认采用 Codex 建立 reference、Qwen 小样检查后批量生产；项目级 [game-art skill](.agents/skills/game-art/SKILL.md) 和来源记录随源码保存，候选图与凭据不入库。

## 当前可玩：D01 听雨廊

江砚秋与叶知闲同处听雨廊。修炼推进时间与修为，请教口诀得到一次修炼加成，休息恢复精力。修为达到 60 完成第一课，可重新开始反复试玩。姓名与整体美术风格已由用户确认；构图、动态强度与数值继续供试玩拍板。当前使用分层生成的中国画背景、Q 版师徒、木桌与宣纸木框，原 SVG 占位稿仍保留供比较。

沿用 **0.1.2-weather3** 加入的约 30 秒「薄云 → 微风 → 小雨 → 雨歇」循环：云影缓移、竹叶轻摇、远山薄雾、廊外雨线与檐下滴水。右上「切换天气」可快速预览，「静态对比」可关闭环境效果；阅读对白时天气继续，切换效果不会消耗精力或推进养成时辰。

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

键盘 1／2／3 对应修炼／请教／休息；4 切换静态／动态，5 预览下一天气；对话选择时 Esc 可取消。当前没有存档或音效，刷新、重开会开始新一轮。建议使用桌面窗口；手机竖屏布局留待后续。

## 维护入口

- [设计规格](docs/SPEC.md)：已确认方向、视觉要求、人物名单与待定项。
- [决定日志](docs/DECISIONS.md)：决定来源、确认状态和后续变更。
- [开发流程与路线图](docs/DEVELOPMENT.md)：验证记录、用户反馈与下一切片条件。
- [Codex 工作约定](AGENTS.md)：范围和验证规则。
- [概念图索引](docs/concepts/README.md)：三张原始概念图与 SHA256。
- [美术来源](assets/art/v2/source.json)与[天气美术来源](assets/art/weather3/source.json)：运行图层、生成提示与 SHA256。
- `assets/data/weather.json` 调循环时长、雨线密度、竹叶位置与薄雾强度；`scripts/weather.gd` 控天气呈现，`scripts/weather_cycle.gd` 定阶段曲线，养成规则独立。
- `assets/data/characters.json` 是当前姓名表；对白通过人物标识读取称呼。
- `assets/data/layout.json` 调人物位置／面板布局；`rules.json` 调养成数值（行动文案同步 `main.gd`）；`dialogue.json` 改对白。状态结算在 `scripts/demo_state.gd`，界面在 `scripts/main.gd`。
- `tools/make_art.py` 可重新生成原创 SVG 草图。当前界面使用带 OFL 许可的 Noto Serif SC 派生子集 Shu Demo Serif，旧 Sans 子集保留。字体来源、版本与 SHA256 随文件保存；新增汉字时用 `tools/rebuild_font.py` 扩展字库（fontTools 4.60.1，开发工具，运行无需安装）。

养成边界检查：

```powershell
godot --headless --path . --script res://tests/state_test.gd
```

天气切换与真实渲染检查：

```powershell
godot --headless --path . --script res://tests/weather_test.gd
godot --path . --audio-driver Dummy --script res://tests/weather_render.gd
```

渲染检查使用实际 Compatibility 画面，将截图与预热后的本机指标写入 `.local/qa/weather3`；不是无界面测试或跨设备帧率承诺。

每轮先收试玩反馈，再调整布局和节奏。D02 拟增加余观涛互动与第二项养成活动，待本轮验收后推进。


## 制作 skill 与下一轮 tea

养成模式制作入口：[game-cultivation-build](.agents/skills/game-cultivation-build/SKILL.md)，仓库级 0.1.1；支持养成行动、人物互动及 tea 等固定场景支线。运行模块/编辑器插件仍为设计，尚未实现。

[工具包设计](docs/CULTIVATION_MODE.md) · [检查记录](docs/CULTIVATION_MODE_CHECKS.md) · [新 chat 的 tea 交接](docs/TEA_HANDOFF.md)。A/B 委托与两杯调查已接入，D01 养成保持可用；待用户验收后才接阶段 C。
