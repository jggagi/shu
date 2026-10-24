# X1 Lite 主开发环境

客户端日期：2026-10-24，America/Los_Angeles。本页是后续工作的本机入口；[原交接快照](X1_LITE_HANDOFF.md)保存 Mac 成果汇合的来源，[整合规划](CHENGPING_INTEGRATION_PLAN.md)保存《蜀》养成与《承平》城镇系统的接入顺序。

## 开发位置与源码基准

- 主开发机：X1 Lite，Fedora 44 KDE 原生 Linux，实际用户 `x1-lite`，当前执行 shell 为 Bash；未发现 PowerShell。
- 《蜀》主工作副本：`/home/x1-lite/games/shu`，origin 为 `https://github.com/jggagi/shu.git`。
- 本次全历史 clone 的基线：`main` / `391689938173e3dc9d8d59fd6d4531a13a5c7e16`，已含 Mac 快照 `bf2afa5` 和原远端 `7ef9ec1`。初始工作区干净；本轮文档分支为 `codex/x1-shu-integration-plan`。
- 《承平》独立参考副本：`/home/x1-lite/games/chengping`，`codex/vertical-slice` / `a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`，版本 `0.3.5-alpha`；本轮 fetch 后与同名远端分支一致，工作区干净。
- 后续功能从当时最新的远端 `main` 建立 `codex/` 分支；上面的 SHA 是本轮可复查快照，不是要求永久停留的版本。已有修改或分叉先审阅，不能强制重置。
- Mac mini 停止《蜀》的后续编辑、构建和功能开发，仅保留既有源码、制作源工程、素材中间件、QA 和存档；可继续作为访问 X1 桌面的客户端。Windows 保留为目标平台，实际验收另行执行。

源码通过 Git 交换已提交内容；每机 `.git`、`.godot`、构建与存档独立。接入《承平》时按清单审查、适配选定模块和数据并保留来源，不以目录覆盖或整仓历史合并代替系统迁移。

## 本轮已实测的工具条件

| 项目 | X1 实测结果 |
| --- | --- |
| Godot | `4.7.2.stable.official.ed1daf0bf`，Standard / GDScript；项目 `.engine-version` 为 `4.7.2` |
| 实际引擎 | `/opt/agent-creator/godot/bin/godot` |
| 命令包装器 | `/home/x1-lite/.local/bin/godot`，指向既有 `set-up/scripts/creator-godot.py`；没有在本轮修改包装器或全局配置 |
| 导出模板 | 已有 `4.7.2.stable`，包含 Web 单线程 release/debug、Linux x86_64 模板；引擎及抽查模板的 SHA256 与既有官方来源 manifest 一致 |
| 基础工具 | Python 3.14.8、Git 2.56.0、Git LFS 3.8.1、Node 24.18.0；Chrome、Firefox、FFmpeg、Inkscape、ImageMagick 已存在 |
| 资源 | Ryzen 7 255 / Radeon 780M，约 29 GiB 内存；检查时磁盘约 800 GiB 可用，属于瞬时容量记录 |
| 桌面 | KDE Wayland 会话活跃；当前 agent shell 未设置 `DISPLAY` / `WAYLAND_DISPLAY`，不代表图形试玩已经通过 |
| 音频 | PipeWire 可访问，检查时只有 `auto_null` 输出；远程设备发声与人物听感未验证 |

现有引擎与模板满足首次验证的版本条件，无需重新安装或升级。运行 Git 中选定的 PNG 图集、JSON、WAV 和字体不需要云端密钥、Blender 或再次生成素材。素材再制作工具及源工程是否齐备是另一项检查，不能从游戏可运行推定。

## 当前游戏入口

| 入口 | 实际范围 |
| --- | --- |
| `scenes/demos/cultivation_engine_v02_mentor.tscn` | 当前接手首验入口，`0.2.2-mentor-loop`；同一 `EngineSession` 运行 `shu_mentor_loop` 与 `stream_study` |
| `games/mentor_loop_catalog.json` | 上述有声师徒包及无声验证包的目录；每包独立存档 |
| `project.godot` 的 F5 / `scenes/main.tscn` | 旧正式五剑养成流程，继续使用 `DemoState`；不能当成新内核整合入口 |
| `scenes/demos/cultivation_engine_v02_tea.tscn` | 新内核《两盏茶》A/B 物件接入；未包含旧正式版完整 C–I / 结局 |

当前师徒新内核已有听教、五剑任一练习、复命、歇息跨日和安全阶段存读档。旧正式版的完整 Tea、天气与生趣尚未整体迁入新内核。具体接口以[运行库 API](../addons/cultivation_mode/README.md)、[内容包说明](../games/README.md)和[师徒整合切片](CULTIVATION_ENGINE_MENTOR_LOOP.md)为准。

## P0 当前结果与复现步骤

规划文档已先提交推送为 `403a254`。随后已完成同源独立 stage 的导入、六组状态测试、两尺寸原生窗口自动流程、跨进程存档、Web 导出与 HTTP 完整读回；详细结果及未验证项见[P0 验证记录](X1_LITE_P0_VALIDATION.md)。目前交付用户试玩，浏览器实际操作／刷新恢复与设备听感仍待确认。以下保留复现方法，不能把命令清单视为未注明项目的通过证明。

### 1. 导入和状态检查

在 X1 Bash 中执行；每轮使用新的日志子目录，保存实际 commit、dirty 状态、命令、完整日志与退出码。

```bash
cd /home/x1-lite/games/shu
pwd
whoami
git status --short --branch
git rev-parse HEAD
GODOT_BIN=/opt/agent-creator/godot/bin/godot
"$GODOT_BIN" --version
"$GODOT_BIN" --headless --path . --editor --quit
"$GODOT_BIN" --headless --path . --script res://tests/cultivation_engine_mentor_loop_test.gd
```

同一候选还需运行已存在的基础、五剑、物件、事件结束与语音专项：`tests/cultivation_engine_test.gd`、`cultivation_engine_motion_test.gd`、`cultivation_engine_quest_test.gd`、`cultivation_engine_event_completion_test.gd`、`cultivation_engine_voice_player_test.gd`（均在 `tests/`）。检查日志中的 `SCRIPT ERROR`、`ERROR`、警告及测试总结，不能只看进程退出码。自动检查使用已有测试的隔离存档目录。

### 2. 原生画面和真实输入

从已登录 X1 远程桌面的终端启动，不向整个系统硬编码显示环境：

```bash
cd /home/x1-lite/games/shu
/opt/agent-creator/godot/bin/godot --windowed --path . res://scenes/demos/cultivation_engine_v02_mentor.tscn
```

真实走通：点师父 → 听教选择 → 后山任选五剑 → 动作收势与唯一结算 → 回廊复命 → 歇息跨日 → 安全阶段保存 → 正常退出并重启 → 继续恢复；再切溪亭包确认两包隔离。记录实际画面尺寸、键鼠、退出行为和资源日志。声音开关和 WAV 解码成功不能代替设备听感验收。

在原仓库直接指定场景不会应用独立构建器的 `--user-dir` 项目覆盖；只用于检查此本机入口。需要与旧正式试玩完全隔离时，以独立 stage 生成的项目为准，并核对其 `project.godot` 用户目录。

### 3. Web 单线程与浏览器存档

```bash
cd /home/x1-lite/games/shu
mkdir -p /home/x1-lite/games/shu/.local/build/x1-mentor-baseline
python3 tools/build_cultivation_engine.py \
  --output /home/x1-lite/games/shu/.local/build/x1-mentor-baseline \
  --entry scenes/demos/cultivation_engine_v02_mentor.tscn \
  --title '蜀山·听教练剑' \
  --app-version 0.2.2-mentor-loop \
  --user-dir shu-cultivation-engine-mentor-loop
```

构建器只准备独立资源闭包，并输出实际 `stage-<id>` 路径；默认入口是 Tea，因此上述显式参数不可省略。用固定 Godot 对输出的 stage 导入，再使用该 stage 的 `Web` 预设导出到它的 `web/index.html`。Linux 首次构建不使用 macOS APFS 专用 `--reuse-stage` 或 `agent-dev` 命令。

在确认端口空闲后，以该 stage 的 `web/` 为目录启动本机 HTTP 服务，再在 X1 浏览器检查加载、真实按钮、保存刷新、两包隔离与控制台。当前 P0 已在 X1 启动 [18812 本机预览](http://127.0.0.1:18812/)，README 历史 `127.0.0.1:88xx` 仍是 Mac 当时的服务。Web 存档依赖浏览器及站点来源，同一候选的刷新恢复使用同一浏览器／来源，换机器、端口或浏览器不视为存档迁移。

## 验收与保留资料

- 先建立 X1 同提交的导入／状态、原生画面／输入、Web／刷新恢复三层基线，再开始城镇系统改动；Mac 既有结果只作来源证据。
- Linux 原生通过不代表 Windows 或 Steam Deck 通过；Web 优先与后续 Windows／Steam 目标保持，主开发机已改为 X1。
- 原 A/B 剧情插件退出问题仍是已知项；当前师徒入口不加载这些插件，不能因此将旧问题标为修复。
- Mac 的 `.local/`、Blender 工程、模型／贴图源、原始生成资料、QA 和试玩存档继续保留。以后确需继续编辑的资料先逐项清点、核对可打开与来源，再另行归档；本次不复制目录、不迁移凭据、不清理 Mac。
- 下一具体任务与后续城镇／战斗切片见[整合规划](CHENGPING_INTEGRATION_PLAN.md)。
