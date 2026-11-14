# 成都 Blender 茶铺与庭树源工程

运行仓库 `tools/art/build_chengdu_blender_kit.py` 重建两份 .blend / GLB。单位米；脚本用 Godot Y-up，存入 Blender 时转成 (x,-z,y)，标准 glTF Y-up 导出还原。PNG 图集左上原点，上排灰泥／木／瓦，下排石／叶／瓷；每格16像素留边。GLB 不携带外部图像，运行接 Krita 同合同图集。

两资产均真实通过 Cycles CPU AO 节点离线烘焙到 CORNER Color，灰度乘数 .66+.34*AO；不可把材质底色重复乘入。独立 audit 保存各组原AO与导出范围、几何bounds、三角数和GLB hash。系统 Blender 的 OCIO版本不匹配触发显示fallback，未修改系统；最终色彩以 Godot 实景确认。
