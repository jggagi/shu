# 掌风试演：Material Maker 原创纹理

`palm-materials.ptex` 是可编辑的 Material Maker 1.8 工程。两个固定种子的内置 Value Noise 节点连接原创合成节点，输出白色 RGB 与独立 alpha 的烟尘、风环；运行时由 Godot 轻染颜色。没有外部图片、社区素材或云端生成输入。

用官方 Material Maker 1.8 打开 `.ptex` 可以修改噪声频率、Opacity、Wind width 和合成节点代码。工具固定来源为 [1.8 官方发布](https://github.com/RodZill4/material-maker/releases/tag/1.8)，对应源码 `7d6daae3c74c09720afe4138ce09699ab3591ce1`，MIT 许可原文随本目录保留。该许可描述制作工具；本目录的图和纹理是新制作的《蜀》项目资产。

## 重现

从项目根目录执行：

```sh
python3 tools/hero_lookdev/build_palm_material_textures.py --prepare
python3 tools/hero_lookdev/build_palm_material_textures.py --export --source-runner
```

第一条只写 `.ptex` JSON 和导出计划。第二条调用下面准备的 Material Maker 固定源码 GPU 导出器，输出 `palm-dust.png`、`palm-wind.png`；Python 不生成或修改纹理像素。已有 Pillow 仅用于只读检查 PNG 的 alpha、尺寸与边界。使用项目已有 Godot 4.7.2，无需全局安装或升级。

## 隔离工具的准备与补丁

官方 Linux 便携包的固定下载为 `https://github.com/RodZill4/material-maker/releases/download/1.8/material_maker_1_8_linux.tar.gz`，SHA256 为 `8e8eb7050e75086cfafeb4ddc0b09c4fe117f529693e611d6fccca1651e913b3`。本机实际官方二进制能生成两张 PNG，但两轮都在 120 秒后超时；第一轮未产图，第二轮两图完整。保留该失败事实，不将产图成功当作正常退出。

为得到可结束的离线命令，使用固定官方源码，并仅在隔离副本应用本目录的 `material-maker-1.8-cli-shutdown.patch`：CLI 入口跳过 Steam／身份 API，等待本地 RenderingDevice 就绪后加载工程，导出完成后显式停止渲染线程。官方 GUI 的退出路径已有同类线程关闭调用。噪声、GLSL 与 PNG 导出函数不改。`material-maker-1.8-source-runner.json` 固定源码包、补丁和两份补丁后文件的 SHA；完整来源包不需要放进游戏。

首次在仓库根目录准备工具（下载前可先查看以下固定来源；命令不会修改全局工具）：

```sh
python3 - <<'PY'
from pathlib import Path
import hashlib, shutil, subprocess, tarfile, urllib.request

repo = Path.cwd()
tool = repo / '.local/tools/martial-vfx-authoring/MaterialMaker'
tool.mkdir(parents=True, exist_ok=True)
archive = tool / 'source-1.8.tar.gz'
url = 'https://api.github.com/repos/RodZill4/material-maker/tarball/7d6daae3c74c09720afe4138ce09699ab3591ce1'
if not archive.exists():
    urllib.request.urlretrieve(url, archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest() == '40a89ef34874cc1da738769958bf4a7e3fcd90367d00203871d51d875fc9c1a0'
original = tool / 'source-1.8'
runner = tool / 'source-runner-1.8'
assert not runner.exists(), '保留已有工具，不覆盖；先核对其来源与补丁'
if not original.exists():
    with tarfile.open(archive) as bundle:
        bundle.extractall(original, filter='data')
shutil.copytree(original / 'RodZill4-material-maker-7d6daae', runner)
patch = repo / 'assets/art/mountain_ambush/palm_lab/material_maker/material-maker-1.8-cli-shutdown.patch'
subprocess.run(['git', 'apply', '-p1', '--directory='+str(runner.relative_to(repo)), str(patch)], cwd=repo, check=True)
PY
/opt/agent-creator/godot/bin/godot --headless --editor --quit --path .local/tools/martial-vfx-authoring/MaterialMaker/source-runner-1.8
python3 tools/hero_lookdev/build_palm_material_textures.py --export --source-runner
```

首次 headless 导入只准备工具的 Godot 缓存，官方自带 HDR／样例 OBJ 的导入提示与工具退出清理提示需单独记录；不能据此宣称整个第三方工具导入无警告，也不等同于游戏工程的构建结果。

底层命令为：

```sh
/opt/agent-creator/godot/bin/godot --export-material --target 'Shu/Palm PNG' --size 512 --output-file palm -o /absolute/path/to/output /absolute/path/to/palm-materials.ptex
```

上述底层命令的工作目录必须是补丁后的 `source-runner-1.8`。导出需要 Vulkan/RenderingDevice，可使用现有桌面 GPU；不以 `--headless` 的 Dummy 渲染替代。脚本在自己的 `.local/tools/martial-vfx-authoring/MaterialMaker/isolated-source-user/` 隔离 XDG 配置、数据与缓存。实际命令、返回码、完整日志及输入输出哈希保存在 `.local/qa/palm-vfx-material-maker/`；本目录 `source.json` 记录冻结资产和验证边界。

## 实际工具验证与边界

修订后的固定源码命令实际返回 0，两个 PNG 与官方便携版生成物逐字节一致；512×512 RGBA、白色 RGB、非空连续 alpha 和全透明边缘共 10 项检查通过。最后一次导出没有 Steam 初始化、脚本错误或无效 shader 提示。工具退出仍报告 6 个 ObjectDB 泄漏和 1 个资源未释放，以及可选 `user://export_targets` 目录不存在的提示。这些是离线第三方制作工具的未解决清理问题，不能称作工具全无警告；Material Maker 不随游戏运行，也不据此推断浏览器性能或玩家画面验收。
