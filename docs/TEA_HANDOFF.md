# 新 chat 交接 prompt

在 `C:\Users\guoqi\GameDev\projects\shu`（GitHub：`https://github.com/jggagi/shu`）继续开发。使用仓库里的 `.agents/skills/godot-cultivation-mode/SKILL.md`；如果当前 chat 未发现 `$godot-cultivation-mode`，直接读取该文件执行，不重新初始化游戏或修改全局 skill 配置。

先检查分支、HEAD、remote 和未提交内容，按 AGENTS.md 依次读取 README、SPEC、DECISIONS、DEVELOPMENT，再读 `docs/TEA_HANDOFF.md` 和 skill 中与支线有关的引用。保留已有用户修改。

现在开始制作养成模式中的 tea 支线《两盏茶》。按现有原稿 `story/sub/tea/README.md`，先交付阶段 A「归剑问天」与 B「第一次看见两只杯子」的小型可玩切片：接受归还旧剑的委托 → 访问固定剑坪场景 → 两只杯子都可调查 → 结束或取消后回到养成面板继续修炼/休息。开头只显示《归剑问天》，不提前透露失忆真相、后事公文或最终标题。

故事约束：江砚秋是见证者，不绑定主角身世或主线谜团；顾青萝与谢长安的既定人物选择及结局保持。茶杯使用稳定 ID，后续结尾复用同一物件。不要强加修为/装备奖励或未定日期门槛。原稿仍保留历史路径；新支线原稿按规则进 `jggagi/sub`，不自动迁移旧稿。

技术基线：Godot 4.7.2 stable + GDScript + Compatibility，同工程 Web/Windows。保留宋式中国画、Q 版人物、固定背景面板；天气独立于养成时间，UI 不参与环境光照。当前可玩基线是 D01-weather3；`addons/cultivation_mode` 与其接口仍是设计，尚未实现。检查实际代码后，只补本切片必要能力，不先搭完整插件或通用剧情引擎。素材从仓库现有资源与来源记录开始，必要时补最小固定场景美术，明确占位与完成状态。

验收：行动资格与实际结算正确；两杯可点、重复查看不重复推进或发奖；事件退出后可继续养成；失败对白期间仍锁住其他行动；阅读确认与旧回调不得越过当前节点。先保证当前运行内的支线进度，存档若未实现须如实说明。检查窗口缩放；分别记录自动检查、Web/Windows 构建/启动、真实 UI 试玩，未验证项明确标注。

工作方式：Codex 做小型可玩切片 → 我试玩拍板 → Codex 修订并维护决定与下一步。先建简短任务卡，保留原剧情信息顺序；交付可用预览或试玩包、试玩步骤、验证结果和下一验收点。后续提交/推送按新 chat 中的授权执行。
