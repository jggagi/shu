"""Rebuild the original editable orange-cat pose sheet; standard library only."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art/ambient_life"


def head(dx=0, dy=0, awake=False):
    eyes = ('<ellipse cx="67" cy="37" rx="2.4" ry="3" fill="#514235"/>'
            '<ellipse cx="79" cy="37" rx="2.4" ry="3" fill="#514235"/>'
            '<circle cx="67.7" cy="36" r=".7" fill="#fff0cf"/>'
            '<circle cx="79.7" cy="36" r=".7" fill="#fff0cf"/>') if awake else (
            '<path d="M63 37 Q67 40 71 37 M75 37 Q79 40 83 37" fill="none"/>')
    return f'''<g transform="translate({dx},{dy})">
<path fill="url(#fur)" d="M56 29 Q54 15 59 17 L67 24 L78 24 L85 17 Q91 17 88 31 Z"/>
<path fill="#eac2a0" stroke="none" d="M58 22 L60 28 L64 26 Z M85 22 L81 26 L87 28 Z"/>
<ellipse fill="url(#fur)" cx="72" cy="36" rx="18" ry="16"/>
<path fill="#f0d8aa" stroke="none" d="M56 39 Q57 51 72 51 Q87 51 89 39 Q81 43 73 41 Q64 43 56 39 Z"/>
<path stroke="#a9713d" opacity=".8" fill="none" d="M67 24 L69 29 L72 26 L75 29 L77 24 M57 32 L61 33 M85 32 L89 31"/>
{eyes}
<path fill="#b47c64" stroke="none" d="M69 41 Q73 39 76 41 L73 44 Z"/>
<path fill="none" stroke-width=".9" d="M73 43 L73 45 Q69 48 67 45 M73 45 Q77 48 79 45 M59 42 L53 41 M59 45 L53 46 M85 42 L92 40 M85 45 L92 46"/>
</g>'''


def pose(index):
    shadow = '<ellipse fill="#655d48" stroke="none" opacity=".17" cx="46" cy="66" rx="42" ry="4"/>'
    tail = ('<path fill="url(#fur)" d="M22 53 C4 55 2 38 8 30 Q13 27 15 33 Q8 45 25 54 Z"/>') if index == 3 else (
           '<path fill="url(#fur)" d="M23 55 C6 48 1 58 8 64 Q17 70 43 65 L43 60 Q17 65 14 60 Q13 57 24 61 Z"/>')
    if index == 5:
        return shadow + '''<g stroke="#795b40" stroke-width="1.3" stroke-linejoin="round">
<path fill="url(#fur)" d="M28 58 Q6 53 10 35 Q15 29 18 35 Q12 49 34 51 Z"/>
<ellipse fill="url(#fur)" cx="44" cy="49" rx="30" ry="17"/>
<ellipse fill="#f0d8aa" stroke="none" cx="46" cy="47" rx="21" ry="12"/>
<path fill="#eed7ad" d="M28 45 Q21 32 28 30 Q35 29 35 43 M47 42 Q44 28 51 29 Q57 30 54 43 M30 58 Q24 51 21 56 Q19 63 28 64"/>
''' + head(0, 9, awake=True) + '</g>'
    body = '''<ellipse fill="url(#fur)" cx="40" cy="47" rx="31" ry="18"/>
<path fill="#eecb92" opacity=".85" stroke="none" d="M16 52 Q34 61 59 49 Q63 62 46 64 L25 64 Q17 60 16 52 Z"/>
<path fill="none" stroke="#a9713d" opacity=".7" stroke-width="2.1" d="M21 35 Q27 40 27 45 M34 30 L37 39 M45 30 L48 39 M11 48 L19 50"/>
<path fill="#f0d8aa" d="M47 56 Q45 64 52 65 L64 65 Q69 62 62 60 L58 58 Z"/>
'''
    if index == 4:
        body += '<path fill="#f0d8aa" d="M56 59 Q59 46 68 43 Q74 42 72 49 L64 62 Z"/>'
    elif index == 6:
        body += '<path fill="#f0d8aa" d="M60 55 Q76 56 82 61 Q86 65 78 65 L60 62 Z"/>'
        body += '<path fill="#a99b58" stroke="#847a4c" stroke-width=".6" d="M85 61 Q88 53 95 55 Q94 64 85 61 Z"/>'
    else:
        body += '<path fill="#f0d8aa" d="M62 56 Q61 63 69 64 L80 64 Q84 61 77 59 L72 57 Z"/>'
    shifts = {1: (0, -3), 2: (-2, -5), 4: (-3, 1), 7: (2, -1)}
    dx, dy = shifts.get(index, (0, 0))
    return shadow + '<g stroke="#795b40" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">' + tail + body + head(dx, dy, awake=index in (1, 2, 6)) + '</g>'


def main():
    sheet = '''<svg xmlns="http://www.w3.org/2000/svg" width="768" height="72" viewBox="0 0 768 72">
<defs><linearGradient id="fur" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e2b06d"/><stop offset="1" stop-color="#c78c4e"/></linearGradient></defs>
'''
    sheet += ''.join(f'<g transform="translate({i * 96},0)">{pose(i)}</g>\n' for i in range(8)) + '</svg>\n'
    (ART / 'cat.svg').write_text(sheet)
    source = json.loads((ART / 'source.json').read_text())
    source['version'] = max(3, source.get('version', 0))
    source['animation']['cat.svg'] = 'Eight original 96x72 orange-tabby poses: resting, head lift, glance, tail flick, grooming, rolling, pawing a leaf, pet response.'
    # Rebuilding the retained SVG must preserve the active raster's acceptance.
    if 'raster_cat' not in source:
        source['generator'] = 'tools/make_orange_cat.py (standard library only); editable SVG artwork'
        source['selection'] = 'Orange cat interaction local playtest candidate; not user accepted.'
    for name, entry in source['files'].items():
        entry['sha256'] = hashlib.sha256((ART / name).read_bytes()).hexdigest()
    (ART / 'source.json').write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
