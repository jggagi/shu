# 城镇整合：GitHub归档与本地开发入口

2026-10-24，America/Los_Angeles。用户先授权“保存到GitHub，并告诉我合并后的本地开发路径”，源码归档为 `a25f6fb` 并创建 PR #13；随后明确要求“清理其他 branch，让 main 作为 source of truth”。据后续授权，[PR #13](https://github.com/jggagi/shu/pull/13) 已采用 merge 合入 `main`，合并提交为 `34051e42a3f446fbc7681dc74ad6380b7141c58d`，保留全部已有提交历史。未公开部署本次城镇版本。

| 项目 | 当前入口 |
| --- | --- |
| 后续主开发副本 | **`/home/x1-lite/games/shu`**，X1 Lite／Fedora，Bash，用户`x1-lite` |
| GitHub仓库 | [jggagi/shu](https://github.com/jggagi/shu) |
| 唯一源码基准 | `main` / `origin/main`；本地主副本跟踪并同步远端，不强推 |
| 新混合场景源码入口 | `scenes/demos/cultivation_engine_v05_town_hd2d.tscn` |
| 原P1b简绘对照入口 | `scenes/demos/cultivation_engine_v04_town_walk.tscn` |
| 固定引擎 | `/opt/agent-creator/godot/bin/godot`，4.7.2.stable.official.ed1daf0bf，Compatibility |
| 来源项目 | `/home/x1-lite/games/chengping`，固定a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6，只读参考；仍是独立仓库 |

“整合后”指城镇能力与混合表现已经接入Shu，并已合入 `main`。主工作副本已切回并快进同步 `main`；没有另建合并目录、把Chengping改成主项目或恢复Mac mini开发。

清理前逐个确认分支 head 可从合并后的 `main` 到达，已删除8个远端功能分支：`codex/animation-options-lab`、`codex/back-mountain-clouds-v1`、`codex/hero-martial-sword-fist-v1`、`codex/mountain-gate-courtyard-v1`、`codex/stream-teahouse-v1.3`、`codex/tea-object-interaction`、`codex/tingyu-ambient-life-v1`、`codex/x1-shu-integration-plan`。本地城镇功能分支也已删除，历史提交未丢失。

远端保留 `main` 和 `gh-pages`。后者仍是 GitHub Pages 的既有发布源，只存放已发布的Web构建，不是第二份开发源码；其 head `ee6030db47167774fd7e01315d11431fa5466b8e` 与发布配置保持，避免破坏原在线试玩。后续功能可使用短期 `codex/` 分支，获授权合并后清理，收尾回到 `main`。

保存范围包括P1b严格位置／互动合同、独立内容包、原生与跨进程检查、2D／3D场景表现、原创四向人物、来源／许可及本片文档。`.local`日志／截图／构建、`.godot`缓存、用户存档与凭据不提交。

最终试玩仍使用已验证的独立`stage-a1adc95d2b7a`，195个输入的SHA256与归档源码一致；构建时HEAD为e1e682a加dirty候选，归档不将旧收据改写成“提交后重新构建”。PR合并后的完整源码tree与`a25f6fb`相同；本次另补主分支工作约定和入口文档，不改变运行代码或资源。最新实际提交可用`git log -1`复核，远端与本地应一致且工作区干净。

已验证：1065状态、85旧stage兼容、两尺寸384原生输入、192导出PCK输入均通过。浏览器实操、设备听感、Windows、Steam Deck、物理输入及用户视觉认可按[混合场景记录](P1B_TOWN_HD2D_SLICE.md)保留边界。

当前X1本机试玩：旧18814下的[同源升级入口](http://127.0.0.1:18814/hd2d/)，以及隔离origin的[18815](http://127.0.0.1:18815/)。新原生窗口《蜀·山下集镇》直接运行最终Linux独立程序，沿用P1b原生用户目录和存档；旧试玩入口保留。临时服务不保证机器重启后仍运行。
