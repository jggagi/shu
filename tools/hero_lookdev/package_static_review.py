#!/usr/bin/env python3
"""Package a three-view static Jiang Yanqiu look-development review.

The three render PNGs are retained byte-for-byte. The contact sheet uses one
uniform scale and the complete transparent source canvases, so the feet keep
their shared baseline. This tool does not render or alter the model.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


VIEW_NAMES = ("front", "side", "back")
CAPTIONS = {"front": "正面", "side": "侧面", "back": "背面"}
STATUS = "静态造型候选，待确认"
MANIFEST_NAME = "sha256-manifest.json"
SHEET_NAME = "three-view-review.png"
MAX_VIEW_SIZE = (560, 660)
TILE_WIDTH = 600
MARGIN = 44
GAP = 28
CAPTION_HEIGHT = 66
FOOTER_HEIGHT = 54
IVORY = (246, 242, 231)
CARD_IVORY = (250, 247, 238)
INK = (57, 51, 43)
MUTED_INK = (112, 103, 89)
RULE = (220, 211, 193)

MAC_CJK_FONTS = (
    Path("/System/Library/Fonts/PingFang.ttc"),
    Path("/System/Library/Fonts/STHeiti Medium.ttc"),
    Path("/System/Library/Fonts/AppleSDGothicNeo.ttc"),
    Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
    Path("/Library/Fonts/Arial Unicode.ttf"),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_verified(source: Path, destination: Path) -> str:
    """Copy one file and verify that its bytes stayed unchanged."""
    before = sha256_file(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    copied = sha256_file(destination)
    after = sha256_file(source)
    if before != copied or before != after:
        raise RuntimeError("Input changed during copy: {}".format(source))
    return copied


def require_png(path: Path, label: str, require_rgba: bool = False) -> tuple[int, int, str]:
    if not path.is_file():
        raise ValueError("Missing {}: {}".format(label, path))
    try:
        with Image.open(path) as image:
            if image.format != "PNG":
                raise ValueError("{} is not a PNG file".format(label))
            size = image.size
            mode = image.mode
            image.verify()
        with Image.open(path) as image:
            image.load()
    except (OSError, ValueError) as exc:
        raise ValueError("Could not read {}: {}".format(path, exc)) from exc
    if require_rgba and mode != "RGBA":
        raise ValueError("{} must be RGBA, got {}".format(label, mode))
    return size[0], size[1], mode


def load_font(size: int) -> tuple[ImageFont.ImageFont, str]:
    for path in MAC_CJK_FONTS:
        if not path.is_file():
            continue
        try:
            return ImageFont.truetype(str(path), size=size, index=0), str(path)
        except (OSError, ValueError):
            continue
    try:
        fallback = ImageFont.load_default(size=size)
    except TypeError:
        fallback = ImageFont.load_default()
    return fallback, "Pillow default font (no macOS CJK font found)"


def build_contact_sheet(view_paths: dict[str, Path], destination: Path) -> tuple[tuple[int, int], str]:
    sizes = []
    for name in VIEW_NAMES:
        with Image.open(view_paths[name]) as image:
            sizes.append(image.size)
    if len(set(sizes)) != 1:
        raise ValueError("Front, side, and back PNGs must have identical canvas dimensions")
    source_width, source_height = sizes[0]
    scale = min(MAX_VIEW_SIZE[0] / source_width, MAX_VIEW_SIZE[1] / source_height)
    display_width = max(1, round(source_width * scale))
    display_height = max(1, round(source_height * scale))
    image_area_height = MAX_VIEW_SIZE[1]

    sheet_width = MARGIN * 2 + TILE_WIDTH * len(VIEW_NAMES) + GAP * (len(VIEW_NAMES) - 1)
    sheet_height = MARGIN + CAPTION_HEIGHT + image_area_height + FOOTER_HEIGHT + MARGIN
    sheet = Image.new("RGB", (sheet_width, sheet_height), IVORY)
    draw = ImageDraw.Draw(sheet)
    caption_font, font_path = load_font(34)
    footer_font, _ = load_font(22)
    resampling = getattr(Image, "Resampling", Image)

    for index, name in enumerate(VIEW_NAMES):
        tile_x = MARGIN + index * (TILE_WIDTH + GAP)
        caption_box = draw.textbbox((0, 0), CAPTIONS[name], font=caption_font)
        caption_width = caption_box[2] - caption_box[0]
        caption_x = tile_x + (TILE_WIDTH - caption_width) // 2
        caption_y = MARGIN + (CAPTION_HEIGHT - (caption_box[3] - caption_box[1])) // 2 - caption_box[1]
        draw.text((caption_x, caption_y), CAPTIONS[name], fill=INK, font=caption_font)

        image_y = MARGIN + CAPTION_HEIGHT
        image_box = (tile_x, image_y, tile_x + TILE_WIDTH, image_y + image_area_height)
        draw.rounded_rectangle(image_box, radius=10, fill=CARD_IVORY, outline=RULE, width=2)
        with Image.open(view_paths[name]) as source:
            source.load()
            rgba = source.convert("RGBA")
            if (display_width, display_height) != rgba.size:
                rgba = rgba.resize((display_width, display_height), resampling.LANCZOS)
            x = tile_x + (TILE_WIDTH - display_width) // 2
            y = image_y + (image_area_height - display_height) // 2
            sheet.paste(rgba, (x, y), rgba.getchannel("A"))

    footer = "{}  ·  三视图共用等比例画布".format(STATUS)
    footer_box = draw.textbbox((0, 0), footer, font=footer_font)
    footer_width = footer_box[2] - footer_box[0]
    footer_x = (sheet_width - footer_width) // 2
    footer_y = MARGIN + CAPTION_HEIGHT + image_area_height + (FOOTER_HEIGHT - (footer_box[3] - footer_box[1])) // 2 - footer_box[1]
    draw.text((footer_x, footer_y), footer, fill=MUTED_INK, font=footer_font)

    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, format="PNG", optimize=False, compress_level=9)
    return sheet.size, font_path


def copy_render_sources(render_dir: Path, source_dir: Path) -> list[str]:
    """Copy every ordinary file already bundled in the renderer's source tree."""
    source_root = render_dir / "source"
    copied: list[str] = []
    if not source_root.is_dir():
        return copied
    for root, directories, filenames in os.walk(source_root, followlinks=False):
        root_path = Path(root)
        directories[:] = sorted(
            name for name in directories
            if not (root_path / name).is_symlink()
        )
        for filename in sorted(filenames):
            path = root_path / filename
            if path.is_symlink() or not path.is_file():
                continue
            relative = path.relative_to(source_root)
            copy_verified(path, source_dir / relative)
            copied.append(relative.as_posix())
    return copied


def copy_root_reconstruction_script(render_dir: Path, source_dir: Path) -> str | None:
    destination = source_dir / "build_static_review.py"
    if destination.is_file():
        return "source/build_static_review.py"

    candidates = (
        render_dir / "source" / "build_static_review.py",
        Path(__file__).resolve().with_name("build_static_review.py"),
    )
    for candidate in candidates:
        if candidate.is_file():
            copy_verified(candidate, destination)
            return "source/build_static_review.py"
    return None


def copy_optional_base_source(base_source: Path | None, source_dir: Path) -> str | None:
    if base_source is None:
        return None
    base_source = base_source.expanduser().resolve()
    if not base_source.is_file():
        raise ValueError("Base source does not exist: {}".format(base_source))
    if base_source.name == "build_static_review.py" and (source_dir / base_source.name).is_file():
        if sha256_file(base_source) == sha256_file(source_dir / base_source.name):
            return "source/build_static_review.py"
    digest = sha256_file(base_source)
    relative = Path("supplemental") / (digest[:12] + "-" + base_source.name)
    destination = source_dir / relative
    copy_verified(base_source, destination)
    return (Path("source") / relative).as_posix()


def make_html(sheet_size: tuple[int, int]) -> str:
    cards = []
    for name in VIEW_NAMES:
        caption = CAPTIONS[name]
        cards.append(
            '<article class="view-card">'
            '<h2>{caption}</h2>'
            '<a class="image-link" href="views/{name}.png" target="_blank" rel="noopener">'
            '<img src="views/{name}.png" alt="江砚秋{caption}静态视图，原始透明 PNG">'
            '</a>'
            '<a class="raw-link" href="views/{name}.png" target="_blank" rel="noopener">'
            '在浏览器中打开原始透明 PNG</a>'
            '</article>'.format(name=name, caption=caption)
        )
    return """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>江砚秋三视图 · 静态造型候选</title>
  <style>
    :root {{ color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "STHeiti", "Noto Sans CJK SC", sans-serif; color: #39332b; background: #f6f2e7; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: clamp(16px, 3vw, 42px); }}
    main {{ max-width: 1900px; margin: 0 auto; }}
    h1 {{ margin: 0 0 12px; font-size: clamp(25px, 3vw, 40px); font-weight: 600; letter-spacing: .08em; }}
    .status {{ display: inline-block; margin: 0 0 28px; padding: 8px 14px; border: 1px solid #d7cbb4; border-radius: 999px; background: #fbf8ef; color: #51483c; }}
    .views {{ display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: clamp(12px, 2vw, 28px); align-items: start; }}
    .view-card {{ min-width: 0; padding: 16px; border: 1px solid #ded4c0; border-radius: 12px; background: #faf7ee; box-shadow: 0 8px 24px rgba(68, 57, 42, .06); }}
    h2 {{ margin: 0 0 12px; text-align: center; font-size: 22px; font-weight: 600; }}
    .image-link {{ display: block; background: #f6f2e7; }}
    .view-card img {{ display: block; width: 100%; height: auto; }}
    .raw-link, a {{ color: #65563f; }}
    .raw-link {{ display: inline-block; margin-top: 12px; font-size: 14px; }}
    .sheet {{ margin: 36px 0; }}
    .sheet img {{ display: block; width: 100%; height: auto; border: 1px solid #ded4c0; border-radius: 12px; }}
    .reference {{ max-width: 560px; margin-top: 34px; }}
    .reference img {{ display: block; max-width: 100%; max-height: 640px; object-fit: contain; background: #faf7ee; border: 1px solid #ded4c0; }}
    .note {{ margin-top: 26px; color: #6e6659; line-height: 1.7; }}
    @media (max-width: 760px) {{ .views {{ grid-template-columns: 1fr; }} }}
  </style>
</head>
<body>
<main>
  <h1>江砚秋 · 正侧背静态审阅</h1>
  <p class="status">{status}</p>
  <section class="views" aria-label="正面、侧面、背面静态视图">
    {cards}
  </section>
  <section class="sheet">
    <h2>三视图接触表</h2>
    <a href="{sheet_name}" target="_blank" rel="noopener">
      <img src="{sheet_name}" width="{sheet_width}" height="{sheet_height}" alt="江砚秋正面、侧面、背面三视图接触表">
    </a>
  </section>
  <section class="reference">
    <h2>参考原画</h2>
    <a href="source/hero-reference.png" target="_blank" rel="noopener">
      <img src="source/hero-reference.png" alt="用于本轮造型参考的项目原画">
    </a>
    <p><a href="source/hero-reference.png" target="_blank" rel="noopener">在浏览器中打开参考原图</a></p>
  </section>
  <p class="note">视图保留原始透明 PNG，可点击图片在浏览器中查看原图。静态造型候选，待确认；动画不属于本次审阅范围。</p>
</main>
</body>
</html>
""".format(
        status=html.escape(STATUS),
        cards="\n    ".join(cards),
        sheet_name=SHEET_NAME,
        sheet_width=sheet_size[0],
        sheet_height=sheet_size[1],
    )


def write_text(path: Path, contents: str) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(contents)


def make_readme(
    render_dir: Path,
    reference: Path,
    root_script: str | None,
    copied_sources: list[str],
    base_source: str | None,
    font_path: str,
    image_size: tuple[int, int],
    sheet_size: tuple[int, int],
) -> str:
    source_lines = ["- `source/painted-hero.blend`：本轮静态模型文件。", "- `source/receipt.json`：本轮渲染与模型收据。"]
    if root_script:
        source_lines.append("- `{}`：重建脚本。".format(root_script))
    else:
        source_lines.append("- 重建脚本：输入目录未提供，仓库同目录也未找到 `build_static_review.py`。")
    if copied_sources:
        source_lines.append("- 渲染包 `source/` 中复制的文件（已跳过符号链接）：" + ", ".join("`source/{}`".format(name) for name in copied_sources) + "。")
    if base_source:
        source_lines.append("- 可选补充脚本：`{}`。".format(base_source))
    source_lines.extend((
        "- `source/hero-reference.png`：原画参考，逐字节复制。",
        "- 三张原始透明图位于 `views/`，SHA256 与输入一致。",
    ))
    return """# 江砚秋三视图静态造型候选

状态：**静态造型候选，待确认**

本包只用于正面、侧面、背面的静态造型审阅。它不包含动画验收结论。

## 来源

- 渲染目录：`{render_dir}`
- 参考原画：`{reference}`
- 原始视图画布：{image_width} × {image_height} 像素；三张图使用相同的缩放比例和完整透明画布，不裁切、不单独拉伸。
- 联系表：`{sheet_name}`，尺寸 {sheet_width} × {sheet_height} 像素；排版字体：`{font_path}`。
- SHA256 清单：`{manifest_name}`，记录除清单自身外的全部交付文件。

## 随包来源文件

{source_files}

## 便携重建

在本包根目录下执行以下命令（需使用现有 Blender 可执行文件）：

```sh
blender --background --threads 4 --python source/build_static_review.py -- --base-source source/base_builder.py --textures source/textures --output NEW_OUTPUT
```

## 审阅门槛

请先确认静态正／侧／背造型。动画表现、角色动作和游戏内接入需要各自单独审阅；本包不代表这些项目已验收。
""".format(
        render_dir=render_dir,
        reference=reference,
        image_width=image_size[0],
        image_height=image_size[1],
        sheet_name=SHEET_NAME,
        sheet_width=sheet_size[0],
        sheet_height=sheet_size[1],
        font_path=font_path,
        manifest_name=MANIFEST_NAME,
        source_files="\n".join(source_lines),
    )


def validate_args(args: argparse.Namespace) -> tuple[Path, Path, Path, Path | None, tuple[int, int]]:
    render_dir = args.render_dir.expanduser().resolve()
    output = args.output.expanduser().absolute()
    reference = args.reference.expanduser().resolve()
    base_source = args.base_source.expanduser().resolve() if args.base_source else None
    if not render_dir.is_dir():
        raise ValueError("Render directory does not exist: {}".format(render_dir))
    if output.exists() or output.is_symlink():
        raise ValueError("Refusing to overwrite existing output: {}".format(output))
    if output.resolve() == render_dir or render_dir in output.resolve().parents:
        raise ValueError("Output must be outside the render directory")
    if not output.parent.is_dir():
        raise ValueError("Output parent directory must already exist: {}".format(output.parent))
    if not reference.is_file():
        raise ValueError("Reference image does not exist: {}".format(reference))
    if base_source is not None and not base_source.is_file():
        raise ValueError("Base source does not exist: {}".format(base_source))

    for name in (*VIEW_NAMES,):
        png = render_dir / (name + ".png")
        width, height, _ = require_png(png, name + ".png", require_rgba=True)
        if name == VIEW_NAMES[0]:
            first_size = (width, height)
        elif first_size != (width, height):
            raise ValueError("Front, side, and back PNGs must have identical canvas dimensions")
    require_png(reference, "reference image")
    for filename in ("receipt.json", "painted-hero.blend"):
        path = render_dir / filename
        if not path.is_file():
            raise ValueError("Missing required render input: {}".format(path))
        if path.stat().st_size == 0:
            raise ValueError("Required render input is empty: {}".format(path))
    try:
        receipt = json.loads((render_dir / "receipt.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Could not read render receipt: {}".format(exc)) from exc
    if not isinstance(receipt, dict):
        raise ValueError("Render receipt must contain a JSON object")
    return render_dir, output, reference, base_source, first_size


def package_review(args: argparse.Namespace) -> None:
    render_dir, output, reference, base_source, image_size = validate_args(args)
    created = False
    try:
        output.mkdir()
        created = True
        view_dir = output / "views"
        source_dir = output / "source"
        view_dir.mkdir()
        source_dir.mkdir()

        view_paths: dict[str, Path] = {}
        for name in VIEW_NAMES:
            source = render_dir / (name + ".png")
            destination = view_dir / (name + ".png")
            copy_verified(source, destination)
            view_paths[name] = destination

        copy_verified(render_dir / "painted-hero.blend", source_dir / "painted-hero.blend")
        copy_verified(render_dir / "receipt.json", source_dir / "receipt.json")
        copy_verified(reference, source_dir / "hero-reference.png")
        copied_sources = copy_render_sources(render_dir, source_dir)
        root_script = copy_root_reconstruction_script(render_dir, source_dir)
        supplemental_source = copy_optional_base_source(base_source, source_dir)

        sheet_path = output / SHEET_NAME
        sheet_size, font_path = build_contact_sheet(view_paths, sheet_path)
        write_text(output / "index.html", make_html(sheet_size))
        write_text(output / "README.md", make_readme(
            render_dir=render_dir,
            reference=reference,
            root_script=root_script,
            copied_sources=copied_sources,
            base_source=supplemental_source,
            font_path=font_path,
            image_size=image_size,
            sheet_size=sheet_size,
        ))

        files = []
        for path in sorted(output.rglob("*")):
            if not path.is_file() or path.name == MANIFEST_NAME:
                continue
            files.append({"path": path.relative_to(output).as_posix(), "sha256": sha256_file(path)})
        manifest = {
            "schema_version": 1,
            "status": STATUS,
            "render_dir": str(render_dir),
            "reference": str(reference),
            "base_source": str(base_source) if base_source else None,
            "files": files,
        }
        write_text(output / MANIFEST_NAME, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    except Exception:
        if created:
            shutil.rmtree(output)
        raise
    print(json.dumps({"status": "DONE", "output": str(output), "view_size": list(image_size),
                      "contact_sheet_size": list(sheet_size), "file_count": len(files)},
                     ensure_ascii=False))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render-dir", required=True, type=Path,
                        help="ROOT render output containing front/side/back PNGs, receipt.json, and painted-hero.blend")
    parser.add_argument("--output", required=True, type=Path,
                        help="new review directory; existing paths are refused")
    parser.add_argument("--reference", required=True, type=Path,
                        help="project hero reference PNG to include in source/")
    parser.add_argument("--base-source", type=Path,
                        help="optional additional reconstruction source file")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        package_review(args)
    except (OSError, RuntimeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
