# 武学工坊离线批次 v0.1

六招目录由配方编译，运行时只读取 `catalog.json`。`pierce`、`sweep` 仍对应原有两个战斗技能；掌风、落雁斩、回云掌、镇岳掌均为纯试演。新增动作不会自动获得伤害、范围、门派或学习规则。

```bash
python3 tools/build_martial_workshop.py --check-only
python3 tools/build_martial_workshop.py
python3 tools/build_martial_workshop.py  # 输入不变时六个 cache_hit
```

脚本使用现有 `/usr/bin/blender` 与锁定 Godot，可用 `--blender`、`--godot` 指定已有匹配程序，不安装依赖。Blender 在后台 CPU 导出；Godot 在隔离临时项目中 headless 导入新动作，生成与资源路径匹配的 `.import`。未启动 GPU 渲染。当前机器所需 OCIO 兼容配置如已存在会被进程级复用；其它机器应提供自己的兼容 `OCIO`。

批处理先验证全部配方、22骨骼来源及 SHA、资源、模板和时间轴，再进行生产。`--check-only` 不创建产物；显式 `--report` 可写检查回执。错误配方、缺少资源或不兼容骨架会以非零退出码停止。

每个任务的输出位于 `assets/art/martial_workshop/generated/<id>/<fingerprint>/`。指纹包含规范化配方、profile、所有输入资源 SHA、批处理器/动作编译器/只读数学辅助源码 SHA，以及 Blender/Godot 可执行文件 SHA。缓存命中时继续校验实际产物 SHA，不能只凭文件存在判断成功。原始角色模型和既有三招动画仅校验复用，不重写。编辑用完整 Blend 放在 `.local/sources/martial-workshop/`；日志放 `.local/qa/martial-workshop/`。

## 扩展配方

复制同模板的一份 JSON，设置全新 `move.id` 和 `animation.clip`，调整动作关键帧、表现参数和时间轴。无需向 Python/GDScript 增加招式 ID 分支。使用临时配方目录可先单独生产：

```bash
python3 tools/build_martial_workshop.py \
  --recipes-dir /path/to/recipes \
  --output /path/to/output/generated
```

`--output` 是任务目录的直接父目录：上例会生成 `/path/to/output/generated/<id>/<fingerprint>/motion.glb`，目录文件位于 `/path/to/output/generated/catalog.json`，不会替换默认六招目录。项目可见目录中的输出使用实际 `res://` 路径；项目外或隐藏目录输出使用便携资源前缀 `res://generated/<id>/<fingerprint>/motion.glb`。接入时把上例 `output/generated/` 内的各个 `<id>/` 目录复制到消费者 Godot 项目的 `generated/` 下，不能再套一层 `generated/`；将该批 `catalog.json` 另外复制到消费者实际读取的目录位置。目录外依赖的既有角色、手型、音效和纹理仍须按其原 `res://` 路径提供。

配方 `mode` 为 `reuse` 或 `generate`。`generate` 支持以下三个模板，均由同一个 pose-key 编译器求解：

| 模板 | 当前实例 | 特征 |
| --- | --- | --- |
| `sword_path` | 落雁斩 | 右腕轨迹和剑轴方向，左手配合，双脚固定 |
| `palm_sweep` | 回云掌 | 左掌横扫与回收，右剑保持原朝向 |
| `palm_guard` | 镇岳掌 | 沉身立掌，在两个关键帧间持守 |

`motion.keys` 使用 Blender Z-up、朝前 −Y 的原模型坐标，字段为 `t`、`hip_yaw`、`chest_yaw`、`lean`、`shift[3]`、`left`、`right`、`right_direction`、`palm_open`、`palm_yaw`。腕位置或方向可写 `"neutral"`。角度单位为度。首尾必须为完整 neutral。新动作长度为 1.2–1.6 秒，100fps 密集采样。模板决定手/剑控制方式，招式 ID 仅用于目录与路径，不参与动作算法。当前剑模板使用 Jiang 原有持剑网格估计剑轴，只支持已登记的两个固定22骨骼 profile，尚不支持任意人体重定向。

`timing.source_map` 是播放器秒到原始 clip 秒的单调分段映射；身体、锚点、特效和声音由运行时同一个时钟驱动。新三招使用源秒等速；旧两剑保留原短 clip 的映射。`duration` 是身体完成时间，`total` 是含特效收尾的总时长，`release` 与 `impact` 均为播放器秒，必须满足 `0 < release < impact <= duration <= total`。

## 目录和绑定

顶层为 `schema_version:1`、`profiles` 字典和有序 `moves` 数组。每招包含共享合同的动画、时间、表现、音效、镜头字段，以及：

- `animation.sha256`：实际 GLB 字节哈希。
- `resource_sha256`：原模型、动作、手型、纹理、音效等实际输入资源路径到 SHA256 的映射。
- `resource_hash`：包含上述映射的 move 规范化 JSON SHA256，计算时不包含 `resource_hash` 自身，作为该招的生产资源指纹。

当前运行时审阅记录按整批 `catalog_sha256` 绑定，该值来自目录文件的原始 JSON 字节。目录包含每招 `resource_hash`，任何一招资源或目录内容变化都会使整批重新待审；当前没有按每招 `resource_hash` 独立保留/失效的审阅逻辑。

`profiles.json` 保存来源模型/哈希、22骨骼名、浮点容差、锚点与手型。`tinglan22` 的 open-palm 网格复用既有 `TinglanOpenPalm`，新动画 GLB 不复制手和角色网格。手掌锚点是 `hand.L` 骨骼局部 `(0,.055,.018)`。剑锚点的 `skinned_landmark` 是原网格坐标，运行时应通过既有 Skin 逆绑定和 `hand.R` 当前姿态变换，不能当作骨骼局部点直接相加。

新 GLB 仅包含同源骨架、一个 clip 和不可见三顶点 Skin carrier。运行时按骨骼名映射动画后释放 carrier；22骨骼、层级、rest、轨道类型和长度均须验证。导入必须100fps、保留不可变轨道、关闭 optimizer。浮点往返允许 rest/bind 最大 `2e-5`、idle 最大 `5e-5`；不能声称数值逐位相同。

来源和制作许可见每任务 `manifest.json`、生成任务 `source-motion.json` 及原素材来源文件。新招式编排为项目原创；原角色、工具纹理、声音继续遵守既有来源条款。数值约束通过仅说明可绑定、脚不滑和目标可达；动作自然度、衣袖遮挡、视觉区分与声音仍需工坊实景审核。
