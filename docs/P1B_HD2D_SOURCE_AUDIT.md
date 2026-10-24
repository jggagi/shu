# P1b 集镇混合场景：来源与适配记录

客户端日期：2026-10-24，America/Los_Angeles。用户在原 P1b 简绘切片后授权采用承平的二维人物／三维场景表现；本轮只替换呈现、点击投影和人物资源，原地图坐标、障碍、三个互动目标、Session、养成、旅行费用及存档合同保持。

## 固定来源与审查

主开发仍为 X1 Lite / Fedora 的 `/home/x1-lite/games/shu`，实际用户 `x1-lite`、Bash，分支 `codex/x1-shu-integration-plan`。此前 P1b 的未提交源码与全部旧试玩保留；没有切换 Mac 或把承平改为主仓库，没有 Git 提交／推送、main 合并或公开部署。

承平来源只读固定 `/home/x1-lite/games/chengping`，`codex/vertical-slice` / **`a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6`**。本轮没有在来源导入、生成缓存、改文件、目录覆盖或共享工作树。来源五份必读与两仓工作规则已在前片完整读取，本轮核对当前 Shu 的 README、SPEC、DECISIONS、DEVELOPMENT、整合规划与 P1b 切片变化。

完整审查的三个实现文件及相关 shader／许可如下。SHA256 是固定承平原文件字节。

| 来源文件 | SHA256 | 实际选择与边界 |
| --- | --- | --- |
| `src/world/hd2d_street.gd` | `998754c40f924e5439284a1325fe7b5c3a3eccb25a4b18a6ce37a6c1051b5ccd` | 选择独立 SubViewport、Camera3D、逻辑 X/Z 平面、地面射线反解、受光 Sprite3D、接地影、程序纹理及屋顶遮挡检查；不带其 view.runtime、GameState、地图、角色、同行或昼夜状态 |
| `src/world/street_details.gd` | `966440324c3847250537b688e1ac4d8ce908db8b9b1cf4a93eae5b825c5f43b0` | 选择曲面屋顶的参数化网格、檐口／脊线、木构层次、原创树冠分组方法；重新制作 Shu 实际几何，不复制原街市坐标、商铺内容或整套陈设 |
| `src/world/pixel_art.gd` | `91f04a3afb0eed45a0db139caeea8a81a2b44a83c18cd69de3426bfc774b10ef` | 审查图集、脚点锚与方向帧接口；不移入该适配器、其 teahouse.json、角色图集或原素材依赖 |
| `assets/shaders/roof_fade.gdshader` | `fb5b87abecf1269c07e191bae36bcbc0b3aa875aba70756bf7fdf1d8021de39a` | 适配屋顶投影覆盖角色时的局部、UV锚定抖动渐隐；作为新stage内的短 shader，改为1280×720逻辑尺度，允许同栋墙面局部退让 |
| `assets/shaders/street_depth.gdshader` | `49d0d717cca2bb6f4248ea1d1dfb76491d4a3fb55f812c8dba268e2a70609249` | 已审查；本轮不采用屏幕／深度纹理后处理、景深或泛光，避免额外Web Compatibility开销与透明排序边界 |
| `assets/shaders/street_foliage.gdshader` | `b4f8c453f8eee1a7604eb9ea85c981c5e3989e35f860927e3e8caca9956e1eb4` | 已审查；本轮树冠静态，不导入独立风动shader或另建环境时钟 |
| `assets/art/godot_viewport/README.md` | `c82a9ecb1dbe3fb71cc70b05ba4e0716ecf3006ab1fc601121fce1f589de6ae5` | 记录 Camera3D → SubViewport → 2D texture 的官方demo来源 |
| `assets/art/godot_viewport/MIT-LICENSE.txt` | `0339177149b474f7ff676d32218ecb3a8f2538955610023c3769763720d09e4c` | 对应上述官方demo的完整MIT notice；需随发行文本保留 |

## 许可归属

承平的 viewport README 与 `assets/SOURCES.json` 指向 [Godot 官方 3D-in-2D demo](https://github.com/godotengine/godot-demo-projects/tree/cae8dc567a56d3e7936f171bcb85f0ccb9634ad0/viewport/3d_in_2d)，记录来源最后变更提交 **`cae8dc567a56d3e7936f171bcb85f0ccb9634ad0`**。该部分为MIT，原notice列明：Godot Engine contributors（2014–present）、Juan Linietsky 与 Ariel Manzur（2007–2014）。原文复制条件要求保留著作权与完整许可。本stage头部保留该notice，发行包另须保存文本，不能假定编译后的GDScript仍带注释。

完整许可原始路径为 `/home/x1-lite/games/chengping/assets/art/godot_viewport/MIT-LICENSE.txt`，上述SHA256绑定原始LF字节。主实施者将其作为单个明确文件选入 `assets/art/shanxia_hd2d/GODOT-VIEWPORT-LICENSE.txt`，来源登记并合入发行 `THIRD_PARTY_NOTICES.txt`；不复制整个来源目录。

这个MIT notice只管官方demo来源，不能给承平原创建筑、shader、角色或整仓源码统一标MIT。承平固定提交没有根 `LICENSE`；其原创代码的本次选择性适配依据用户对两仓的明确授权，继续记录来源与改写。没有带入Kenney Nature、Ninja Adventure、承平人物或主街绘景，也没有引入新的第三方运行依赖。

## Shu 实际舞台与坐标合同

舞台文件：[town_hd2d_stage.gd](../addons/cultivation_mode/town_hd2d_stage.gd)。它只消费参数与纹理，不读取Session、不提交位置、不扣时辰或资源、不改旗标／回执。逻辑地图仍由 `walks.json` 与既有寻路／宿主决定。

- 80逻辑像素／米；逻辑 `(x,y)` 映射为世界 `(x,0,z)`，中心 `(640,400)`。Camera3D使用固定斜俯透视，不随走路改变取景；初始化与读档立即对应当前脚点。
- 二维呈现始终为1280×720。内部SubViewport按可用画布缩放采样，`logical_to_screen`／`screen_to_logical`用同一 `DISPLAY / viewport.size` 比例；反解由Camera ray与世界Y=0地面求交，不用二维近似缩放冒充三维点击。
- 建筑只消费已有 `[480,330,220,150]`、`[320,175,540,95]` 障碍，重做前后层次、曲面瓦顶、上翘檐口、门窗、木柱、低台和库存。接地实体留在原障碍及其既有12px角色膨胀范围内；屋檐、悬牌、横梁属于空中结构。
- 树干、背景房屋和上山台阶放在可走地面之外；茶摊目标仍为 `[1010,350]`，只配悬挂牌，不在可走空地新增柜台／实体障碍；街牌 `[710,560]` 以悬挂牌与平面标记呈现，地面仍可走。返山目标 `[160,260]` 保留。
- `geometry`保存原两处建筑footprint；`solid_footprints`与`validate()`记录地面实体是否在原障碍内或整个floor外。它们只作呈现一致性核对，不生成第二套碰撞。
- 暖色DirectionalLight3D、环境填光、普通阴影、程序生成的低对比瓦片／木纹／石纹和贴地影提供空间层次。未建立高级后处理、全屏景深、泛光、独立时间或天气框架；当前暖色为画面基准，不声明自动表现完整游戏昼夜。
- 屋顶与主体的真实三维AABB投影用于局部遮挡判断；只有覆盖角色时，UV稳定的抖动区域渐退。正常人物保留深度测试，不常驻穿墙显示；暂停时不推进渐隐时钟。

人物由主实施者的新Shu资源提供：四向×四帧、80×112、整身，江砚秋保持蓝衣／米白与深发，掌柜为棕衣。stage接收方向Texture2D数组、`world_height`、`frame_size`和`foot_anchor`；Sprite3D使用双线性采样、轻阈值alpha裁切、受光与正常深度；步态索引来自实际移动距离。没有把室内半身图或固定练剑图集改称四向行走。

接口：`setup(walker,font,definition)`、`set_actor_frames(player,npc)`、`sync(player_position,facing,walking,stride_distance,active)`、`texture()`、`logical_to_screen(point,height=0)`、`screen_to_logical(screen)`、`target_screen_position(id)`、`resize_view(size)`。`audit()`提供viewport尺寸、镜头、角色数、建筑数、投影方式和footprint；不进入存档。

## 验证进度与边界

首轮独立小项目使用固定Godot4.7.2实际构建stage，几何`validate()`为空；8个分布脚点的投影／地面反解最大误差0.000137逻辑像素，均在呈现范围内，退出0且无`SCRIPT ERROR`／`ERROR`／警告。首次typed条件数组在生成屋顶时触发运行时类型错误，已改为PackedInt32Array后在同一夹具重跑干净；没有把最初仅有测试结尾、但存在脚本错误的运行计作通过。

独立小项目在 `.local/qa/x1-p1b-hd2d-20261024/stage-module/`。这只证明构造、逻辑投影与几何边界；原生实际渲染、shader编译、构图、billboard脚点、三个目标点击、busy／存读档、返山养成、Web导出／实际浏览器等由最终同源候选另行记录，不把headless结果当作画面或人工认可。

首轮实际1152×720原生捕获已查看：建筑、三处互动与人物可辨，但环境填光／太阳叠加使石板与树冠偏黄、亮部接近裁白，街外42米底板拉伸64像素程序纹理形成明显波纹。按主实施者确认的画面修订，将环境填光改为冷中性 `#c9d4d7`／0.45，太阳改为略暖 `#fff1dc`／0.72；街外底板改无纹理哑色 `#b3b7a4`，石路、屋顶、木纹和树冠保留原表现。人物脚点的额外世界Y余量从0.035降为0.005；Sprite3D.offset仍按 `[40,104]` 脚点锚校准，避免沿世界UP补中心导致斜镜头漂移。固定38°／FOV39°／距离17.1的镜头保持，优先让原可走区域与三个目标完整可见。修订后的最终两尺寸画面与输入由主实施者另核对，不将第一候选图片冒称修订后验收。
