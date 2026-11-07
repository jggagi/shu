# 山道遇袭 · 来源审查

本页记录保留的 **18816 首轮战斗候选**。后续五名人物已统一重建，不再在战斗中载入旧 study GLB；当前人物来源与验证见[人物修订切片](P3_AMBUSH_CHARACTERS_SLICE.md)及 `assets/art/mountain_ambush/source.json`。下表的旧模型与 CMU 说明只适用于首轮包。

日期：2026-10-24。授权：用户明确选择并要求实现《蜀》的小队战斗切片，沿用此前两仓系统选择性适配授权。

| 项目 | 固定来源 | 本轮处理 |
| --- | --- | --- |
| 离散格子与空间战斗 | `jggagi/chengping` / `a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`，`src/combat/grid.gd`、`combat_controller.gd`、`objectives.gd` | 参考四邻接搜索、预告、击退／打断和目标判定，编写限定本遭遇的纯规则模块；不导入全局状态、旧人物／剧情、UI 或素材。承平原创代码未声明统一 LICENSE，依据用户适配授权，不冒称 MIT／CC0。 |
| 养成、城镇和安全存档 | 《蜀》`7c992c578b1fe4a1624c769812425b38080771d3`，`addons/cultivation_mode` 与 `games/shu_town_walk` | 原宿主子类接入；新包复制既有内容并隔离 ID／存档；原包保持。继承的声音、画景和城镇来源声明仍随项目保存。 |
| 江砚秋模型 | `assets/art/sword_jiang/study.glb`，既有原创角色候选 | 仅用于江砚秋，保留 `source.json`、`README.txt` 与 `CMU-DATA-LICENSE.txt`。既有 CMU 动作来源与模型认可边界保持；没有将角色候选称为获批固定暖色模型。 |
| 同门、敌人、地形和特效 | `ambush_actor.gd`、`ambush_stage.gd` | 本轮原创程序几何，作为可玩切片美术候选；非外部素材包，没有新上传或生成费用。 |
| 字体 | 既有 Noto Serif SC 原始变量字体，SHA256 `050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9` | 用本机已有 fontTools 生成独立重命名字体 `ShuAmbushSerif.ttf`，不改旧字库；来源、工具版本、覆盖与派生 SHA 见 `assets/fonts/source-ambush.json`，许可沿用 OFL。 |

原有 3D 城镇的 Godot MIT 来源通知仍在原脚本中。新山道没有复制外部场景、角色、游戏截图或受版权保护的对白。所有本轮运行输入与实际产物 SHA256 由独立构建的 `build-info.json` 记录；该清单证明字节，不代替视觉和玩法验收。
