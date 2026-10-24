#!/usr/bin/env python3
"""Package a six- or eight-render static Jiang Yanqiu bust review."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import shutil
import sys
from pathlib import Path
from urllib.parse import quote

from PIL import Image, ImageDraw, ImageFont


VIEW_NAMES = (
    "front-clay",
    "three-quarter-clay",
    "side-clay",
    "front-painted",
    "three-quarter-painted",
    "side-painted",
)
COLUMN_CAPTIONS = ("正面", "四分之三侧面", "侧面")
FOUR_ANGLE_CAPTIONS = COLUMN_CAPTIONS + ("背面",)
ROWS = (
    ("上色候选", "painted", ("front-painted", "three-quarter-painted", "side-painted")),
    ("灰模结构", "clay", ("front-clay", "three-quarter-clay", "side-clay")),
)
STATUS = "头肩胸像候选 · 待确认"
SHEET_NAME = "bust-review.png"
MANIFEST_NAME = "sha256-manifest.json"
MODEL_NAME = "jiang-bust.blend"
RECEIPT_NAME = "receipt.json"

MARGIN = 44
TILE_WIDTH = 540
GAP = 24
TITLE_AREA_HEIGHT = 124
ROW_LABEL_HEIGHT = 48
CAPTION_HEIGHT = 46
IMAGE_AREA_HEIGHT = 650
ROW_GAP = 34
FOOTER_HEIGHT = 62
MAX_DISPLAY_SIZE = (500, 620)
BASE_NOTICE_EXTRA_HEIGHT = 38

IVORY = (246, 243, 235)
CARD_IVORY = (251, 249, 243)
INK = (57, 52, 45)
MUTED_INK = (111, 102, 89)
RULE = (220, 213, 199)
ACCENT = (156, 128, 88)

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
    """Copy one regular file without replacing a different existing file."""
    before = sha256_file(source)
    if destination.exists() or destination.is_symlink():
        if destination.is_file() and not destination.is_symlink() and sha256_file(destination) == before:
            return before
        raise ValueError("Source path collision; refusing to replace: {}".format(destination))
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    copied = sha256_file(destination)
    after = sha256_file(source)
    if before != copied or before != after:
        raise RuntimeError("Input changed during copy: {}".format(source))
    return copied


def require_png(path: Path, label: str) -> tuple[int, int]:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing regular-file {}: {}".format(label, path))
    try:
        with Image.open(path) as image:
            if image.format != "PNG":
                raise ValueError("{} is not a PNG file".format(label))
            size = image.size
            image.verify()
        with Image.open(path) as image:
            image.load()
    except (OSError, ValueError) as exc:
        raise ValueError("Could not read {}: {}".format(path, exc)) from exc
    return size


def select_review_layout(render_dir: Path):
    """Keep the original six views unless both optional back renders exist."""
    back_paths = (render_dir / "back-painted.png", render_dir / "back-clay.png")
    back_present = tuple(path.exists() or path.is_symlink() for path in back_paths)
    if any(back_present) and not all(back_present):
        raise ValueError("Optional back views must be provided as a painted/clay pair")

    if not all(back_present):
        return VIEW_NAMES, COLUMN_CAPTIONS, ROWS

    view_names = VIEW_NAMES + ("back-painted", "back-clay")
    rows = (
        ("上色候选", "painted", ("front-painted", "three-quarter-painted", "side-painted", "back-painted")),
        ("灰模结构", "clay", ("front-clay", "three-quarter-clay", "side-clay", "back-clay")),
    )
    return view_names, FOUR_ANGLE_CAPTIONS, rows


def base_notice_from_receipt(receipt: dict) -> str | None:
    """Format source attribution only when the receipt records a base asset."""
    if "base" not in receipt:
        return None
    base = receipt["base"]
    if not isinstance(base, dict):
        raise ValueError("Receipt base field must be a JSON object")
    name = base.get("name")
    license_name = base.get("license")
    credit = base.get("credit")
    if not all(isinstance(value, str) and value.strip() for value in (name, license_name, credit)):
        raise ValueError("Receipt base must include non-empty name, license, and credit fields")
    if base.get('reused_parts') == ['ear shells only']:
        return '耳部网格裁切重塑自 Snow；脸、眼、发型与服装独立制作 · 静态候选；署名：{credit} · {license}'.format(credit=credit, license=license_name)
    return (
        "基于 {name} 修改的静态候选 · 尚未完成角色绑定或动画就绪；署名：{credit} · {license}"
    ).format(name=name, credit=credit, license=license_name)


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


def draw_centered_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    center_x: int,
    top: int,
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int],
) -> None:
    bounds = draw.textbbox((0, 0), text, font=font)
    width = bounds[2] - bounds[0]
    x = center_x - width // 2
    draw.text((x, top - bounds[1]), text, font=font, fill=fill)


def build_contact_sheet(
    view_paths: dict[str, Path],
    destination: Path,
    column_captions: tuple[str, ...] = COLUMN_CAPTIONS,
    rows: tuple = ROWS,
    base_notice: str | None = None,
) -> tuple[tuple[int, int], str]:
    view_names = tuple(view_paths)
    sizes = [require_png(view_paths[name], name + ".png") for name in view_names]
    if len(set(sizes)) != 1:
        raise ValueError("All render PNGs must have identical canvas dimensions")
    column_count = len(column_captions)
    if not rows or any(len(row_views) != column_count for _, _, row_views in rows):
        raise ValueError("Every contact-sheet row must have the same number of columns")
    source_width, source_height = sizes[0]
    scale = min(MAX_DISPLAY_SIZE[0] / source_width, MAX_DISPLAY_SIZE[1] / source_height)
    display_width = max(1, round(source_width * scale))
    display_height = max(1, round(source_height * scale))

    sheet_width = MARGIN * 2 + TILE_WIDTH * column_count + GAP * (column_count - 1)
    row_content_height = ROW_LABEL_HEIGHT + CAPTION_HEIGHT + IMAGE_AREA_HEIGHT
    footer_height = FOOTER_HEIGHT + (BASE_NOTICE_EXTRA_HEIGHT if base_notice else 0)
    sheet_height = (
        MARGIN * 2 + TITLE_AREA_HEIGHT + row_content_height * len(rows) + ROW_GAP * (len(rows) - 1) + footer_height
    )
    sheet = Image.new("RGB", (sheet_width, sheet_height), IVORY)
    draw = ImageDraw.Draw(sheet)
    title_font, font_path = load_font(38)
    status_font, _ = load_font(23)
    row_font, _ = load_font(27)
    caption_font, _ = load_font(27)
    footer_font, _ = load_font(20)
    resampling = getattr(Image, "Resampling", Image)

    draw_centered_text(
        draw,
        "江砚秋 · 头肩胸像静态审阅",
        sheet_width // 2,
        MARGIN,
        title_font,
        INK,
    )
    status_bounds = draw.textbbox((0, 0), STATUS, font=status_font)
    status_width = status_bounds[2] - status_bounds[0]
    status_height = status_bounds[3] - status_bounds[1]
    pill_width = status_width + 34
    pill_height = status_height + 16
    pill_x = (sheet_width - pill_width) // 2
    pill_y = MARGIN + 59
    draw.rounded_rectangle(
        (pill_x, pill_y, pill_x + pill_width, pill_y + pill_height),
        radius=pill_height // 2,
        fill=CARD_IVORY,
        outline=RULE,
        width=2,
    )
    draw_centered_text(
        draw,
        STATUS,
        sheet_width // 2,
        pill_y + (pill_height - status_height) // 2,
        status_font,
        INK,
    )

    resampling_filter = getattr(resampling, "LANCZOS")
    y = MARGIN + TITLE_AREA_HEIGHT
    for row_label, _, row_views in rows:
        draw.text((MARGIN, y + 5), row_label, font=row_font, fill=ACCENT)
        line_y = y + ROW_LABEL_HEIGHT - 2
        draw.line((MARGIN + 146, line_y, sheet_width - MARGIN, line_y), fill=RULE, width=2)
        caption_y = y + ROW_LABEL_HEIGHT
        image_y = caption_y + CAPTION_HEIGHT
        for column, name in enumerate(row_views):
            tile_x = MARGIN + column * (TILE_WIDTH + GAP)
            draw_centered_text(
                draw,
                column_captions[column],
                tile_x + TILE_WIDTH // 2,
                caption_y + 8,
                caption_font,
                INK,
            )
            draw.rounded_rectangle(
                (tile_x, image_y, tile_x + TILE_WIDTH, image_y + IMAGE_AREA_HEIGHT),
                radius=12,
                fill=CARD_IVORY,
                outline=RULE,
                width=2,
            )
            with Image.open(view_paths[name]) as source:
                source.load()
                rgba = source.convert("RGBA")
                if rgba.size != (display_width, display_height):
                    rgba = rgba.resize((display_width, display_height), resampling_filter)
                paste_x = tile_x + (TILE_WIDTH - display_width) // 2
                paste_y = image_y + (IMAGE_AREA_HEIGHT - display_height) // 2
                sheet.paste(rgba, (paste_x, paste_y), rgba.getchannel("A"))
        y += row_content_height + ROW_GAP

    count_label = {6: "六", 8: "八"}.get(len(view_names), str(len(view_names)))
    footer = "{}张原图画布一致 · 等比例缩放 · 未裁切或拉伸".format(count_label)
    footer_y = sheet_height - MARGIN - footer_height + (12 if base_notice else 18)
    draw_centered_text(draw, footer, sheet_width // 2, footer_y, footer_font, MUTED_INK)
    if base_notice:
        draw_centered_text(
            draw,
            base_notice,
            sheet_width // 2,
            footer_y + 34,
            footer_font,
            MUTED_INK,
        )

    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, format="PNG", optimize=False, compress_level=9)
    return sheet.size, font_path


def copy_render_sources(render_dir: Path, source_dir: Path) -> list[str]:
    """Copy all regular files under render-dir/source without following symlinks."""
    source_root = render_dir / "source"
    if source_root.is_symlink() or not source_root.is_dir():
        raise ValueError("Missing regular source directory: {}".format(source_root))
    copied: list[str] = []
    for root, directories, filenames in os.walk(source_root, followlinks=False):
        root_path = Path(root)
        directories[:] = sorted(
            name for name in directories
            if name != '__pycache__' and not (root_path / name).is_symlink()
        )
        for filename in sorted(filenames):
            path = root_path / filename
            if path.suffix in {'.pyc', '.pyo'} or path.is_symlink() or not path.is_file():
                continue
            relative = path.relative_to(source_root)
            copy_verified(path, source_dir / relative)
            copied.append(relative.as_posix())
    return copied


def html_url(relative: str) -> str:
    return quote(relative, safe="/._-")


def make_html(
    sheet_size: tuple[int, int],
    source_files: list[str],
    column_captions: tuple[str, ...] = COLUMN_CAPTIONS,
    rows: tuple = ROWS,
    view_count: int = len(VIEW_NAMES),
    base_notice: str | None = None,
) -> str:
    row_sections = []
    for row_label, row_key, row_views in rows:
        cards = []
        for column, name in enumerate(row_views):
            caption = column_captions[column]
            relative = "views/{}.png".format(name)
            url = html.escape(html_url(relative), quote=True)
            cards.append(
                '<article class="view-card">'
                '<h3>{caption}</h3>'
                '<a href="{url}" target="_blank" rel="noopener">'
                '<img src="{url}" alt="江砚秋{caption}，{row_label}，原始 PNG">'
                '</a>'
                '<a class="raw-link" href="{url}" target="_blank" rel="noopener">打开原始 PNG</a>'
                '</article>'.format(
                    caption=html.escape(caption),
                    row_label=html.escape(row_label),
                    url=url,
                )
            )
        row_sections.append(
            '<section class="render-row" aria-label="{label}">'
            '<h2>{label}</h2><div class="views views-{columns}">{cards}</div></section>'.format(
                label=html.escape(row_label), columns=len(column_captions), cards="\n".join(cards)
            )
        )

    base_notice_html = (
        '<p class="provenance">{}</p>'.format(html.escape(base_notice))
        if base_notice else ""
    )
    angle_alt = "、".join(column_captions)
    count_label = {6: "六", 8: "八"}.get(view_count, str(view_count))
    sheet_label = "{}视图接触表".format(count_label)

    source_links = [
        '<li><a href="source/{url}">{label}</a></li>'.format(
            url=html.escape(html_url(name), quote=True),
            label=html.escape("source/" + name),
        )
        for name in [MODEL_NAME, RECEIPT_NAME] + source_files
    ]
    return """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>江砚秋头肩胸像 · 静态候选</title>
  <style>
    :root {{ color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "STHeiti", "Noto Sans CJK SC", sans-serif; color: #39342d; background: #f6f3eb; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: clamp(16px, 3vw, 44px); }}
    main {{ max-width: 1760px; margin: 0 auto; }}
    h1 {{ margin: 0 0 12px; font-size: clamp(26px, 3vw, 40px); font-weight: 600; letter-spacing: .06em; }}
    .status {{ display: inline-block; margin: 0 0 26px; padding: 8px 14px; border: 1px solid #dcd5c7; border-radius: 999px; background: #fbf9f3; color: #51483c; }}
    .render-row {{ margin: 0 0 32px; }}
    .render-row h2 {{ margin: 0 0 12px; color: #9c8058; font-size: 23px; font-weight: 600; }}
    .views {{ display: grid; gap: clamp(12px, 1.8vw, 24px); align-items: start; }}
    .views-3 {{ grid-template-columns: repeat(3, minmax(0, 1fr)); }}
    .views-4 {{ grid-template-columns: repeat(4, minmax(0, 1fr)); }}
    .view-card {{ min-width: 0; padding: 14px; border: 1px solid #dcd5c7; border-radius: 12px; background: #fbf9f3; }}
    h3 {{ margin: 0 0 10px; text-align: center; font-size: 20px; font-weight: 600; }}
    .view-card img {{ display: block; width: 100%; height: auto; background: #f6f3eb; }}
    a {{ color: #65563f; }}
    .raw-link {{ display: inline-block; margin-top: 10px; font-size: 14px; }}
    .sheet {{ margin: 38px 0; }}
    .sheet img {{ display: block; width: 100%; height: auto; border: 1px solid #dcd5c7; border-radius: 12px; }}
    .sources {{ margin-top: 36px; padding: 20px 24px; border: 1px solid #dcd5c7; border-radius: 12px; background: #fbf9f3; }}
    .provenance {{ margin: -12px 0 24px; color: #65563f; }}
    .sources ul {{ margin: 10px 0 0; padding-left: 22px; columns: 2; }}
    .sources li {{ margin: 5px 12px 5px 0; overflow-wrap: anywhere; }}
    @media (max-width: 780px) {{ .views {{ grid-template-columns: 1fr; }} .sources ul {{ columns: 1; }} }}
  </style>
</head>
<body>
<main>
  <h1>江砚秋 · 头肩胸像静态审阅</h1>
  <p class="status">{status}</p>
  {base_notice}
  {rows}
  <section class="sheet">
    <h2>{sheet_label}</h2>
    <a href="{sheet_name}" target="_blank" rel="noopener">
      <img src="{sheet_name}" width="{sheet_width}" height="{sheet_height}" alt="上色候选与灰模结构的{angles}">
    </a>
  </section>
  <section class="sources">
    <h2>模型与来源文件</h2>
    <ul>{source_links}</ul>
    <p>{count_label}张原始 PNG 位于 views/；SHA256 清单位于 sha256-manifest.json。</p>
  </section>
</main>
</body>
</html>
""".format(
        status=html.escape(STATUS),
        base_notice=base_notice_html,
        rows="\n".join(row_sections),
        sheet_label=html.escape(sheet_label),
        count_label=count_label,
        angles=html.escape(angle_alt),
        view_count=view_count,
        sheet_name=SHEET_NAME,
        sheet_width=sheet_size[0],
        sheet_height=sheet_size[1],
        source_links="\n".join(source_links),
    )


def markdown_code(value: str) -> str:
    return "`{}`".format(value.replace("`", "\\`").replace("\n", " "))


def make_readme(
    source_files: list[str],
    image_size: tuple[int, int],
    sheet_size: tuple[int, int],
    font_path: str,
    column_captions: tuple[str, ...] = COLUMN_CAPTIONS,
    view_count: int = len(VIEW_NAMES),
) -> str:
    names = [MODEL_NAME, RECEIPT_NAME] + source_files
    source_lines = "\n".join("- {}".format(markdown_code("source/" + name)) for name in names)
    angle_list = "、".join(column_captions)
    count_label = {6: "六", 8: "八"}.get(view_count, str(view_count))
    column_count_label = {3: "三", 4: "四"}.get(len(column_captions), str(len(column_captions)))
    return """# 江砚秋头肩胸像静态审阅包

状态：**{status}**

本包用于离线查看同一头肩胸像候选的 {count_label}张静态渲染图。`index.html` 可直接用本地浏览器打开；点击任一视图即可在浏览器中打开对应的原始 PNG。

## 画面顺序

- 上排：上色候选；下排：灰模结构。
- {column_count_label}列依次为：{angles}。
- {count_label}张输入画布均为 {image_width} × {image_height} 像素。接触表对它们使用相同缩放比例，保留完整画布，不裁切、不拉伸。
- 接触表：`{sheet_name}`，尺寸 {sheet_width} × {sheet_height} 像素；排版字体：{font_path}。

## 随包模型与来源

模型、收据以及渲染目录 `source/` 中的普通文件均已复制到本目录的 `source/`；复制过程跳过符号链接。来源文件如下：

{source_files}

{count_label}张原始 PNG 位于 `views/`，并保持与输入文件逐字节一致。`{manifest_name}` 记录除清单自身外每个交付文件的 SHA256。

## 审阅门槛

本包只呈现头肩胸像的静态造型候选，尚待确认。
""".format(
        status=STATUS,
        count_label=count_label,
        column_count_label=column_count_label,
        angles=angle_list,
        image_width=image_size[0],
        image_height=image_size[1],
        sheet_name=SHEET_NAME,
        sheet_width=sheet_size[0],
        sheet_height=sheet_size[1],
        font_path=markdown_code(Path(font_path).name),
        source_files=source_lines,
        manifest_name=MANIFEST_NAME,
    )


def validate_args(args: argparse.Namespace):
    render_dir = args.render_dir.expanduser().resolve()
    output = args.output.expanduser().absolute()
    output_resolved = output.resolve()
    if not render_dir.is_dir():
        raise ValueError("Render directory does not exist: {}".format(render_dir))
    if output.exists() or output.is_symlink():
        raise ValueError("Refusing to overwrite existing output: {}".format(output))
    if output_resolved == render_dir or render_dir in output_resolved.parents:
        raise ValueError("Output must be outside the render directory")
    if not output.parent.is_dir():
        raise ValueError("Output parent directory must already exist: {}".format(output.parent))

    view_names, column_captions, rows = select_review_layout(render_dir)
    image_size = None
    for name in view_names:
        size = require_png(render_dir / (name + ".png"), name + ".png")
        if image_size is None:
            image_size = size
        elif image_size != size:
            raise ValueError("All render PNGs must have identical canvas dimensions")

    for filename in (MODEL_NAME, RECEIPT_NAME):
        path = render_dir / filename
        if path.is_symlink() or not path.is_file():
            raise ValueError("Missing required render input: {}".format(path))
        if path.stat().st_size == 0:
            raise ValueError("Required render input is empty: {}".format(path))
    try:
        receipt = json.loads((render_dir / RECEIPT_NAME).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Could not read render receipt: {}".format(exc)) from exc
    if not isinstance(receipt, dict):
        raise ValueError("Render receipt must contain a JSON object")
    base_notice = base_notice_from_receipt(receipt)

    source_root = render_dir / "source"
    if source_root.is_symlink() or not source_root.is_dir():
        raise ValueError("Missing regular source directory: {}".format(source_root))
    assert image_size is not None
    return render_dir, output, image_size, view_names, column_captions, rows, base_notice


def package_review(args: argparse.Namespace) -> None:
    render_dir, output, image_size, view_names, column_captions, rows, base_notice = validate_args(args)
    created = False
    try:
        output.mkdir()
        created = True
        view_dir = output / "views"
        source_dir = output / "source"
        view_dir.mkdir()
        source_dir.mkdir()

        view_paths: dict[str, Path] = {}
        for name in view_names:
            source = render_dir / (name + ".png")
            destination = view_dir / (name + ".png")
            copy_verified(source, destination)
            view_paths[name] = destination

        copy_verified(render_dir / MODEL_NAME, source_dir / MODEL_NAME)
        copy_verified(render_dir / RECEIPT_NAME, source_dir / RECEIPT_NAME)
        source_files = copy_render_sources(render_dir, source_dir)

        sheet_size, font_path = build_contact_sheet(
            view_paths,
            output / SHEET_NAME,
            column_captions,
            rows,
            base_notice,
        )
        write_text(
            output / "index.html",
            make_html(sheet_size, source_files, column_captions, rows, len(view_names), base_notice),
        )
        write_text(
            output / "README.md",
            make_readme(source_files, image_size, sheet_size, font_path, column_captions, len(view_names)),
        )

        files = []
        for path in sorted(output.rglob("*")):
            if not path.is_file() or path.name == MANIFEST_NAME:
                continue
            files.append({"path": path.relative_to(output).as_posix(), "sha256": sha256_file(path)})
        manifest = {
            "schema_version": 1,
            "status": STATUS,
            "files": files,
        }
        write_text(output / MANIFEST_NAME, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    except Exception:
        if created:
            shutil.rmtree(output)
        raise
    print(json.dumps({
        "status": "DONE",
        "output": str(output),
        "view_size": list(image_size),
        "view_count": len(view_names),
        "column_count": len(column_captions),
        "contact_sheet_size": list(sheet_size),
        "file_count": len(files),
    }, ensure_ascii=False))


def write_text(path: Path, contents: str) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(contents)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--render-dir",
        required=True,
        type=Path,
        help="render folder containing the six or eight PNG views, jiang-bust.blend, receipt.json, and source/",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="new review folder; existing paths are refused",
    )
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
