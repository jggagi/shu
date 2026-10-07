# 山门庭院：第三个独立画景的复用案例

日期：2026-10-07。本轮只做时辰／三天气、一阵风、一只橘猫，是 [听雨廊方法案例](tingyu-corridor.md) 的实际新场景适配。用户已确认最新听雨廊Web收尾通过；用户随后在本chat确认「验收通过」，庭院独立试玩认可完成。全部证据与入口见 [庭院切片](../../../../docs/COURTYARD_SLICE.md)。

| 已复用 | 新场景绑定 |
| --- | --- |
| EnvironmentPresenter 的六时辰、天气参数组合、独立平滑过渡 | courtyard_environment.json、CourtyardEnvironment；自己的亮度／色调／雾值、露天雨mask和叶簇mask |
| AmbientLifePresenter 的固定seed机会、居留与天气能力门 | courtyard_ambient_life.json、CourtyardCat；仅声明单猫，檐下石台有遮蔽 |
| 原橘猫两套RGBA图集、atlas crop和脚点 | 新逻辑路径、显示尺度、朝向和移动热点；不复用听雨廊桌面坐标 |
| 多姿态短路径的运动状态机 | 第二真实使用后做最小helper提取，保留听雨廊默认节奏；庭院独立速度和休息时间 |
| 已修订的掌心向下抚摸SVG、指尖 `(8,24)` | 当前姿态可互动范围、Static门和场景释放；不改变其他按钮光标 |
| DemoState 玩法权威 | 独立宿主只提供预览override；表现层只观察，不推进精力／修为／剧情 |

## 这张画暴露的适配问题

- 现有大庭院概念图带地图UI，茶旧院承载既有剧情，所以没有直接复用；先选原创静态构图，再选新画中实际可动叶簇和檐下落脚面。
- 听雨廊雨shader内嵌window_mask、ambient shader绑定茶桌／灯／帘穗坐标，不能换一张背景直接使用。庭院保留Presenter，重新写小型画景shader和露天mask，不复制原控制器再删除效果。
- 两套猫姿态图集cell尺寸不同，直接用相同像素缩放会在站／走／卧之间改变大小。每姿态接触pivot、实际边界和显示尺度需要重新校准；热点也不能复用桌面固定rect。
- 原TingyuCatDeskMotion只有桌面命名与固定速度，逻辑实为Path2D上的纯表现运动。庭院这个实际第二用例才触发最小提取：路径逻辑复用，几何、节奏和能力留在各adapter，不产生addon。
- 檐下石台沿画面有轻微斜率，不用水平虚拟地面；猫脚点沿实际短路径采样，局部→世界→窗口缩放必须一致。雨区绕过整个承托面，不能只为猫挖一个漂浮免雨矩形。
- Static暂停底层相位但呈现可读安静姿态；Resume回到同一位置继续原阶段。显示暂停姿态不能重置原路线或触发新出现事件。

## 验收合同

检查静态构图、同state晴云雨、六时辰、真实窗口叶簇响应与平静间隔、猫两方向脚点和步态、移动热点／实际鼠标抚摸／光标、Static／Resume及Reset。原生捕获、Web输入、自然等待、用户认可分别记录；不得将加速render或导出成功写成自然节奏或跨平台完成。当前不抽取通用addon，也不新增其他动态系统。


## 本轮实际结果

两个Presenter原文件未改，庭院环境及动物各有配置／adapter。导入、独立Web导出、41项猫合同、20张真实Compatibility渲染及Web鼠标通过；庭院用户已在本chat确认「验收通过」。旧听雨廊154项套件的12失败与origin/main未改基线逐项相同，不能称全量通过。原生与Web证据、视口及未验收平台详见庭院任务卡。

集成还暴露两项执行问题：环境preload别名 `Environment` 与Godot内置类同名，改成 `EnvironmentAdapter`；Reset会正常提升既有Tea失效token，表现只读检查应在Reset之前比较完整宿主状态，不能把合法Reset当表现写入。原生窗口被遮挡时await frame_post_draw可能停住，捕获改用显式RenderingServer.force_draw；仍为真实Compatibility渲染，不用headless图替代。
