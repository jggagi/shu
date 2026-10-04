# 蜀（shu）

以《武林群侠传》的养成体验为启发，结合四川／蜀山元素的原创武侠修炼与生活养成游戏。先做 Web，并为后续 Steam 桌面版规划。

**Codex 做可玩 demo → 用户试玩拍板 → Codex 修订 → 更新决定与扩展计划。**

## 当前可玩：D01 听雨廊

江砚秋与叶知闲同处听雨廊。修炼推进时间与修为，请教口诀得到一次修炼加成，休息恢复精力。修为达到 60 完成第一课，可重新开始反复试玩。姓名与整体美术风格已由用户确认；构图、动态强度与数值继续供试玩拍板。当前使用分层生成的中国画背景、Q 版师徒、木桌与宣纸木框，原 SVG 占位稿仍保留供比较。

当前 **0.1.2-weather3** 加入约 30 秒「薄云 → 微风 → 小雨 → 雨歇」循环：云影缓移、竹叶轻摇、远山薄雾、廊外雨线与檐下滴水。右上「切换天气」可快速预览，「静态对比」可关闭环境效果；阅读对白时天气继续，切换效果不会消耗精力或推进养成时辰。

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
