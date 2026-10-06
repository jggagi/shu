# 《两盏茶》GitHub 归档与交接

2026-10-06，用户明确要求总结当前状态并提交到 GitHub，以便新 chat 继续开发（D039）。候选 **0.1.9-tea-past-local / tea-past-local-1**；当前方向认可与源码归档授权不等于完整体验验收。

## 归档范围

`codex/tea-full-past-scenes` 基于 main `07bd2ee`（已合入独立后山橘猫）。本轮保存阶段C至完整支线、过去场景、阅读布局／输入保护、调查与添茶节奏、字体、美术来源／提示／运行背景、测试与文档。后山代码及原稿不纳入新改动，候选图、凭据、缓存、日志、原生截图、Web／Windows产物保持本机`.local`／`art/work`。

新chat首先读 [当前交接](TEA_HANDOFF.md)。核心规则、对白快照和最终人物选择保持；`assets/data/tea-full-source.json` SHA256 `8fe564cb9455c8006e2441560bbd1d64c9053b46ae79691b5797bd4f4a319afc`，历史稿不迁移。修正来源元数据中旧演出决定编号为D033／D034／D037，不改剧情快照。

## 本次归档副本复核

锁定Godot4.7.2 stable、GDScript、Compatibility。隔离工作树复制后，运行代码／数据／九张背景与本机已验证候选的SHA256一致；测试等待及来源标签、交接文档的修改单独记录。

- 项目导入：exit0，无错误；选定美术SHA256、现有字体来源和全部新本地文档链接核对。
- 核心养成 `state_test`：PASS。
- 完整宿主 `tea_full_state_test`：153项、0失败。首跑6处连锁失败源于旧测试只等待SceneTreeTimer1.25秒便调用现实时间门槛；测试现在按单调真实时钟等待至少宿主配置时长＋50ms，再执行一次添茶并保留早填／重复／错杯／陈旧回调检查。游戏宿主和1.2秒门槛字节不变，首跑与重跑日志保留。
- 回忆专项 `tea_memory_ui_test`：619项、0失败；后山共享宿主 `back_mountain_training_test`：PASS。
- `git diff --check`、提交范围、素材／来源哈希与源码引用复核；提交不包含`.local`、`art/work`或个人凭据。

此前当前候选验证：完整UI2257项、原生2359项、26张原生实帧，以及真实Web全流程通过；Web／Windows导出exit0，本机回忆专项619项通过。见 [完整演出验证](TEA_PAST_ALL_VALIDATION.md)。本轮仅归档及文档／测试等待修正，没有重新导出，也没有把旧日志冒充此次新构建。Windows实机、移动端、声音、长时运行仍未验证。

## 远端与继续边界

本轮创建提交并推送上述分支，使用草稿PR便于核对；准确提交与推送状态以该分支Git记录及PR为准。不合并／不发布Pages；线上根入口仍0.1.4。本机canonical checkout与其他dirty修改保留，新chat先核对，不reset／clean。下一步只收取完整调查节奏、最新四个过去画面及双杯结尾的试玩反馈，再选一个小修订。
