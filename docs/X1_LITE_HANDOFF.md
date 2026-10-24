# X1 Lite 开发交接

客户端日期：2026-10-24。用户授权先将 Mac 本地成果合入并推送远端 `main`，之后以 `https://github.com/jggagi/shu` 的 `main` 为后续开发唯一基准，在 X1 Lite 继续开发。Mac 当前 checkout、制作工程、存档、预览和缓存保留，清理另行安排；本轮没有连接或设置 X1 Lite，也没有部署新的公开试玩。

## 已汇合的源码

- 本地快照 `bf2afa5c656ad07424cd00dc06ac6250354193bb`：五套固定模型剑法、正式宿主循环、养成内核与双内容包、物件支线第一片、师徒有声情节及听教／练剑／复命整合。
- 此前远端 `7ef9ec184ce5cc251b70b4cc8e0c792a1cf2f6e4`：PR #12 的独立剑／拳研究及正式导出资源排除修复。
- 两侧历史都保留；冲突仅涉及文档、技能与素材清单。人物与养成核心代码、两侧选定素材按各自已归档内容保留，不以某一侧的旧文档覆盖另一侧成果。历史 localhost 地址只代表 Mac 当时的预览，不是 X1 或远端服务。

## X1 上从 main 开始

先确认 X1 上的仓库位置、remote、分支和未提交内容；已有改动先保留，不能强制重置。全新 checkout 可使用：

```sh
git clone https://github.com/jggagi/shu.git
cd shu
git status --short --branch
git log -1 --oneline
```

若已有干净、无本地分叉的 main，先 `git fetch origin`，再以 `git merge --ff-only origin/main` 更新。存在未提交内容或分叉时先审阅，不套用覆盖命令。后续功能从最新 main 建立 `codex/` 分支，按仓库 AGENTS 和小型试玩切片工作。

依次阅读 [README](../README.md)、[SPEC](SPEC.md)、[DECISIONS](DECISIONS.md)、[DEVELOPMENT](DEVELOPMENT.md) 和 [AGENTS](../AGENTS.md)。X1 的系统、路径、引擎安装与性能需在该机器实际核对；Mac 的 agent-dev 绝对路径和挂载卷规则不移植到 X1。

## 首个运行与验证目标

使用 `.engine-version` 锁定的 Godot **4.7.2 stable**、GDScript 和 Compatibility；导出 Web 时使用同版本模板，保持单线程预设。先让编辑器完成本机导入，再运行：

```sh
godot --windowed --path . res://scenes/demos/cultivation_engine_v02_mentor.tscn
```

该场景是最新双包整合入口。F5 的项目主场景仍属于原正式养成流程，不将两个入口混为一个版本。试玩顺序：2D 听雨廊点师父→听教选择→后山任选五套剑法→结算→回廊复命→歇息跨日→存档后重启续玩，再切到溪亭包确认存档隔离。

状态专项可运行：

```sh
godot --headless --path . --script res://tests/cultivation_engine_mentor_loop_test.gd
```

[整合切片](CULTIVATION_ENGINE_MENTOR_LOOP.md)保存完整规则与 Mac 验证范围，[运行库 API](../addons/cultivation_mode/README.md)与[内容包说明](../games/README.md)保存制作合同。后续修改依据用户试玩反馈；新对白听感、叶知闲声线、X1 实机与长时表现仍待验收，旧 A/B 插件退出问题也没有因新入口正常退出而视为修复。

Web 构建器 `tools/build_cultivation_engine.py` 使用 Python 3 标准库，只创建独立 stage。指定已存在的绝对输出目录及本片 entry／title／app-version／user-dir；随后仍须用固定 Godot 导入 stage，并将其 Web 预设导出至 stage 的 `web/index.html`，通过本机 HTTP 服务试玩。新机器不用 `--reuse-stage`，该选项仅适用于已有 Mac APFS 缓存。具体参数见整合切片。

## Git 中已有与仍留在 Mac 的资料

运行所需的选定 PNG 图集、帧表、WAV、字体／许可、场景、内容包、内核、测试及制作脚本已纳入 Git。游玩现有内容无需云端凭据、在线模型、Blender 或重新生成图像／配音。

被忽略的 `.local/`、导入缓存、本地 Web 包、QA 原始证据、试玩存档和部分 Blender／生成中间工程不随 clone 获取。离线重做模型动作、重新抠像或生成音频需要各自记录的源工程、模型／贴图、工具版本和已有授权，不能把现有游戏可运行等同于 X1 已具备所有素材再制作能力。Mac 保留这些资料；清理前须先清点并独立归档需要继续编辑的源工程、原始素材、证据与本地存档，不能仅凭 main 已推送就删除它们。凭据继续按设备本地规则保存，不提交到 Git。

本轮交接只验证代码与选定运行素材的汇合，不将 Mac 已有的状态／原生／浏览器结果写成 X1 的通过结果。
