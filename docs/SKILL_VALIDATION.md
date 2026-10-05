# shu 双 skill 验证（2026-10-05，Asia/Shanghai）

本轮范围：先验证 game-cultivation-build 与 game-art 的可用性；未推进阶段 C、未生成美术、未提交或发布。

## 来源与安装

- shu 基线：main / acf2bf8；当前 Mac 独立副本，Godot 4.7.2.stable.official.ed1daf0bf。
- game-cultivation-build：沿用 shu 仓库级 0.1.0，已读必需资料、项目绑定、支线接入与 tea 原稿。
- game-art：来自 https://github.com/jggagi/skills/tree/main/.agents/skills/game-art ，固定读取提交 d97b8e7eda1239f3ebb2e894baa1ac3e93c06517；按 skill 要求安装到 shu 的 .agents/skills/game-art，逐文件字节校验通过。
- 复用 docs/concepts、assets/art、art/prompts；新增 art/config.json、art/.gdignore，忽略 art/work 与 Python 缓存。现有素材、来源记录、剧情原稿与玩法代码保持原字节。
- 使用已有 Python 3.12.9；无需安装依赖或修改全局环境。

## 实际结果

| 项目 | 结果 |
| --- | --- |
| game-cultivation-build 包检查 | PASS：9 个引用、6 个事件节点、10 个阶段；固定原稿版本与 SHA256 校验通过。该结果不代表后续阶段已经实现。 |
| game-art doctor --no-network | PASS：本地目录、配置、写入位置与 Python 有效；Qwen NOT CONFIGURED。 |
| game-art unittest | PASS：35 项；网络请求由 mock 替代，无付费调用。 |
| game-art 跨目录 dry-run | PASS：使用 shu 既有精确提示与概念图，从本 chat 目录调用仍正确解析 shu 路径；未联网、未生成文件。 |
| Godot 导入 | PASS：headless editor 导入，无脚本错误。 |
| 宿主状态 / tea 状态 / tea UI / 天气 | PASS：14 / 73 / 73 / 8 项，共 168 项；均为自动 headless 检查。 |
| 根代理复核 | PASS：安装包与固定来源逐文件一致，检查日志无脚本错误，未修改游戏运行代码和美术。 |

## 使用边界

两个 skill 均可直接按仓库文件读取并执行，不依赖 chat 自动发现。game-art 的本地制作、提示、来源记录与 dry-run 工具可用。

当前会话已提供 Codex 内置 image_gen 工具，核心场景、少量高价值美术和精确编辑可按 game-art 路由使用，无需 OPENAI_API_KEY。本轮只验证工具可用与流程准备，未调用真实生图，故不声称图像质量或生成成功已经验证。

Qwen 当前进程缺少 DASHSCOPE_API_KEY 与 QWEN_IMAGE_ENDPOINT，真实生成尚不可用；没有读取其他进程的凭据、写入凭据或调用付费接口。真实在线生图须另有明确测试请求。

没有 Web/Windows 新构建、浏览器真实点击或用户玩法验收；既有在线 A/B 版本保持。验证日志保存在 shu 的 .local/qa/mac-baseline（不提交）。


## 后续源码归档复核（2026-10-05）

用户后续确认默认分工为 Codex 建立 reference、Qwen 检查小样后生成批量美术，并要求保存到 GitHub；该规则已更新本项目 game-art 的 SKILL 与 provider policy。上文逐字节来源校验和模型路由描述属于最初安装阶段，不代表当前修改后的包仍与上游原提交逐字节相同。此次用现有 Python 3.12.7 重跑 35 项离线 unittest，全部通过；没有新的在线生图调用。项目配置／来源记录保持相对路径且无凭据；art/work 候选和测试日志不提交。
