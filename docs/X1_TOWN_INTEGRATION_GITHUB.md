# 城镇整合：GitHub归档与本地开发入口

2026-10-24，America/Los_Angeles。用户在P1b及混合场景交付后明确授权“保存到GitHub，并告诉我合并后的本地开发路径”。本轮归档当前源码与文档，保留全部已有历史；不将此授权扩展为自行合并main或公开部署。

| 项目 | 当前入口 |
| --- | --- |
| 后续主开发副本 | **`/home/x1-lite/games/shu`**，X1 Lite／Fedora，Bash，用户`x1-lite` |
| GitHub仓库 | [jggagi/shu](https://github.com/jggagi/shu) |
| 功能分支 | `codex/x1-shu-integration-plan`；正常推送，不强推 |
| 新混合场景源码入口 | `scenes/demos/cultivation_engine_v05_town_hd2d.tscn` |
| 原P1b简绘对照入口 | `scenes/demos/cultivation_engine_v04_town_walk.tscn` |
| 固定引擎 | `/opt/agent-creator/godot/bin/godot`，4.7.2.stable.official.ed1daf0bf，Compatibility |
| 来源项目 | `/home/x1-lite/games/chengping`，固定a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6，只读参考；仍是独立仓库 |

“整合后”指城镇能力与混合表现已经接入Shu。没有另建合并目录、把Chengping改成主项目或恢复Mac mini开发；现有本地main保持。

保存范围包括P1b严格位置／互动合同、独立内容包、原生与跨进程检查、2D／3D场景表现、原创四向人物、来源／许可及本片文档。`.local`日志／截图／构建、`.godot`缓存、用户存档与凭据不提交。

最终试玩仍使用已验证的独立`stage-a1adc95d2b7a`，195个输入的SHA256与归档源码一致；构建时HEAD为e1e682a加dirty候选，归档不将旧收据改写成“提交后重新构建”。最新实际提交可用`git log -1`复核，远端与工作区在push后再核对。

已验证：1065状态、85旧stage兼容、两尺寸384原生输入、192导出PCK输入均通过。浏览器实操、设备听感、Windows、Steam Deck、物理输入及用户视觉认可按[混合场景记录](P1B_TOWN_HD2D_SLICE.md)保留边界。

当前X1本机试玩：旧18814下的[同源升级入口](http://127.0.0.1:18814/hd2d/)，以及隔离origin的[18815](http://127.0.0.1:18815/)。新原生窗口《蜀·山下集镇》直接运行最终Linux独立程序，沿用P1b原生用户目录和存档；旧试玩入口保留。临时服务不保证机器重启后仍运行。
