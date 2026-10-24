# HD2D 的 Web 存档来源与兼容边界

2026-10-24，America/Los_Angeles。结论来自固定引擎源码与实际 P1b 导出脚本检查；**尚未用浏览器实际继续、保存和刷新验证**。本轮 CUA inventory 仍为 `apps: [] / browsers: []`。

## 保留入口

在同一浏览器／配置文件中，旧入口 `http://127.0.0.1:18814/` 与拟提供的 [HD2D 同源入口](http://127.0.0.1:18814/hd2d/) 具有相同 origin；URL 子路径不参与本导出模板的数据库命名。根据下述证据，HD2D 应读取原 P1b 的同一存档文件键。这是明确的源码与产物推断，不能写成浏览器验收通过。IndexedDB 按 origin 隔离，见 [MDN 的 same-origin 说明](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API/Using_IndexedDB#security)。

[18815 独立预览](http://127.0.0.1:18815/) 的端口不同，属于另一 origin，其浏览器存档独立；不自动复制或迁移旧 origin 的数据库。原生 HD2D 沿用 P1b 的 custom user dir 和 SaveStore base，不更改人工档。

旧 origin 的交付方式是在旧 Web 根目录新增 `hd2d` 符号链接，指向新 Web 目录；原 `index.html`、引擎文件和其余原资源保留字节。链接建立与旧文件哈希保持由最终交付收据证明，本页不提前宣称已完成该操作。

## 固定引擎证据

引擎：`4.7.2.stable.official.ed1daf0bf`。以下 Godot 链接均固定到该提交。

| 层 | 实际规则与来源 |
| --- | --- |
| 启动配置 | [config.js 第118行](https://github.com/godotengine/godot/blob/ed1daf0bf/platform/web/js/engine/config.js#L118) 默认 `persistentPaths: ['/userfs']`。旧 `index.html` 未覆盖该值。 |
| 虚拟文件系统 | 实际旧 `index.js` 的 `GodotFS.init` 对每个 persistent path 执行 `FS.mount(IDBFS,{},path)`，随后读取持久数据；没有把页面 pathname 加入 mountpoint。 |
| IndexedDB 数据库名 | 实际旧 `index.js` 的 `IDBFS.getRemoteSet` 以 `mount.mountpoint` 调用 `getDB`；`getDB` 以该 name 打开 IndexedDB。因此本模板的数据库名是 `/userfs`。其结构也对应 [Emscripten 官方 IDBFS](https://github.com/emscripten-core/emscripten/blob/main/src/lib/libidbfs.js) 的 `getRemoteSet/getDB`，实际交付字节优先于该上游动态链接。 |
| 用户目录 | [OS::get_user_data_dir 第318行起](https://github.com/godotengine/godot/blob/ed1daf0bf/core/os/os.cpp#L318) 在启用 custom dir 时使用 `custom_user_dir_name`；[OS_Web 第198行起](https://github.com/godotengine/godot/blob/ed1daf0bf/platform/web/os_web.cpp#L198) 将它接到 `/userfs` 下，没有按页面路径另造目录。 |

实际检查的旧脚本：`.local/build/x1-p1b-20261024/stage-998cc78b3722/web/index.js`，279,815 字节，SHA256：

```text
33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba
```

P1b 与 HD2D 均使用 `config/use_custom_user_dir=true`、`config/custom_user_dir_name="shu-cultivation-engine-town-walk"`；两入口的 `save_base_dir` 均为 `user://cultivation_engine_town_walk`。同源时预期的文件键为：

```text
/userfs/shu-cultivation-engine-town-walk/cultivation_engine_town_walk/shu_town_walk/checkpoint_0.json
/userfs/shu-cultivation-engine-town-walk/cultivation_engine_town_walk/shu_town_walk/checkpoint_1.json
```

因此保留旧 origin、custom name、SaveStore base、包 ID、内容版本／指纹与状态合同，才构成完整兼容条件。仅保留 custom name 不能跨 origin 访问存档；仅保留 origin 但改目录或指纹也不能保证继续。

## 已验证与待验证

跨 stage 工具由真实旧 P1b 进程写出隔离 QA 存档，再由新 stage 的独立进程恢复；同时核对 town JSON 与原核心字节不变。新原生 UI 将该 fixture 逐 SHA256 复制到自己的随机 QA Store 后点击「继续」，不读写人工存档。它验证状态兼容，不验证 IndexedDB 或浏览器刷新。

浏览器可用后，应在同一浏览器配置文件中：旧18814保存 → 关闭旧运行页 → 打开18814/hd2d/点击继续 → 核对位置／日期／属性／旗标 → 保存刷新再继续。18815应单独显示其存档状态。该组实际浏览器操作目前未执行，不能由 Web 导出、HTTP 哈希或原生跨进程结果代替。
