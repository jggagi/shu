# 新任务：Shu 接入 Chengping 城镇系统

2026-10-24。用户已要求 P1a 收尾、推送 GitHub，并新开 chat 接入承平。本页保留开工时交接。P1b现已完成最小可玩适配并提供新入口18814，当前实施、验证、产物与限制见[P1b切片](P1B_TOWN_WALK_SLICE.md)；以下P1a基础与开工范围仍作为历史起点，不把早期P1a误说成系统已迁入。

## 工作位置与源码

- 只在 X1 Lite / Fedora 原生 Linux 开发，实际用户 `x1-lite`；Shu 主副本 `/home/x1-lite/games/shu`，origin `https://github.com/jggagi/shu.git`，当前 `codex/x1-shu-integration-plan`。从包含本交接的 P1a 收尾提交继续；开始先核对实际 HEAD、远端、dirty 状态，不把 `origin/main` 的旧基线覆盖回来。
- Chengping 是独立参考副本 `/home/x1-lite/games/chengping`，`codex/vertical-slice`，参考提交 `a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`，`0.3.5-alpha`。只选择需要的模块适配到 Shu 并记录固定来源；不要整仓合并、目录覆盖或修改来源项目。
- Mac mini 不继续 Shu 开发；已保存的 Mac 项目路径不作为新任务工作位置。Godot 固定 `/opt/agent-creator/godot/bin/godot`，`4.7.2.stable.official.ed1daf0bf`，GDScript / Compatibility。
- 必读 Shu：`AGENTS.md` → `README.md` → `docs/SPEC.md` → `docs/DECISIONS.md` → `docs/DEVELOPMENT.md`，以及[整合规划](CHENGPING_INTEGRATION_PLAN.md)、[X1 环境](X1_LITE_DEVELOPMENT.md)、[P1a 切片](P1A_TOWN_RETURN_SLICE.md)。适配来源前读取 Chengping 的 AGENTS 和其五份启动／设计／状态／试玩／环境资料；其中旧 Windows／WSL 主开发位置不覆盖本次已确认的 X1 Shu 宿主。

## 已有基础与保留项

P0 已获用户「试玩没问题」反馈。P1a 新包 `shu_town_return` / `0.3.0`，入口 `scenes/demos/cultivation_engine_v03_town.tscn`，已经有听雨廊→山下集镇→听雨廊、每程暂定一时辰、不扣精力、免费环顾、跨日和独立安全存读档；继承原听教、五剑、复命。城镇只是原创路线示意，尚无自由行走、寻路、NPC／出口热点、证据或战斗。

P1a 最终 stage `/home/x1-lite/games/shu/.local/build/x1-p1a-20261024/stage-3ae601dd6b7d`；941 状态＋240 原生窗口＋81 跨进程检查通过，164 消费文件哈希绑定。证据在 `.local/qa/x1-p1a-20261024/`。X1 本机 Web 18813、P0 18812 和原生试玩进程保持交付时状态；新任务先检查是否有用户正在试玩，不覆盖或停止旧入口。

原 `shu_mentor_loop`／`stream_study` JSON、P0 存档、旧正式 DemoState／完整 Tea 和两仓历史保持。浏览器专项、设备听感、Windows、Steam Deck、手柄与长期验证没有因自动检查或用户笼统反馈而补签。

## 下一片 P1b 的具体目标

1. 先审查 Chengping 的 `src/world/location_controller.gd`、`navigation.gd`、`world_state.gd` 及相关数据／测试，写明选择了哪些规则或算法、固定提交、许可、适配处与验证；真正适配需要的能力，不只再做一套按钮场景切换。
2. 只接一张可走的城镇场景。点击地面可移动，路径绕过实际障碍；点击少量人物／物件及返山出口时走近再互动。走动／阅读不自行扣游戏时辰，原明确旅行费用仍由同一个宿主一次结算。
3. 行走模型持有场景内临时移动状态；持久地点／位置、人物回应或返回结果经 Shu EngineSession 的明确内容合同提交与恢复，不导入第二套 Chengping GameState。若需扩展目前严格校验的状态／内容结构，先明确 schema、恢复不变量及不兼容策略。
4. 核对移动角色素材确有全身与方向能力；现有半身室内原画、固定练剑图集不能冒充完整四向移动资源。沿用原创视觉与来源记录，先做足够验证规则的小片，具体构图／美术交付试玩决定。
5. 沿用独立包／用户目录和存档策略，不自动迁 P0／P1a 旧档。验证绕障、走近人物／出口、忙碌与重复操作门禁、位置／日期／属性／旗标的存档恢复、返山后原师徒五剑连续及溪亭隔离。

完成后提供 X1 可用试玩入口、原生画面／输入与存档证据，分开记录状态测试、原生自动输入、浏览器实际操作和用户认可。当前授权覆盖 P1b 实施与试玩交付；P2 证据案、P3 战斗、整部承平剧情、合并 main 或公开部署均不在此片。Git 提交／推送继续按具体当轮授权处理。
