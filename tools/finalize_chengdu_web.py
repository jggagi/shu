"""Keep the exported city canvas anchored when browser focus would scroll the page.

Run after the existing Godot Web export. This only changes the HTML shell; the
compiled PCK/WASM, game rules and checkpoints remain byte-identical.
"""
from pathlib import Path
import argparse
import hashlib
import json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("web_directory", type=Path)
    args = parser.parse_args()
    index = args.web_directory / "index.html"
    markup = index.read_text()
    if '<canvas id="canvas"' not in markup or "</head>" not in markup:
        raise SystemExit("Expected an existing Godot index.html export")
    marker = 'id="shu-city-canvas-shell"'
    before = hashlib.sha256(index.read_bytes()).hexdigest()
    if marker not in markup:
        addition = '''<style id="shu-city-canvas-shell">
html, body { height: 100%; overflow: hidden; overscroll-behavior: none; }
#canvas { position: fixed; inset: 0; }
</style>
<link rel="icon" type="image/png" href="index.png">
'''
        index.write_text(markup.replace("</head>", addition + "</head>", 1))
    print(json.dumps({"tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      "html_before": before, "html_after": hashlib.sha256(index.read_bytes()).hexdigest(),
                      "scope": "HTML canvas anchoring and existing export icon only"}))


if __name__ == "__main__":
    main()
