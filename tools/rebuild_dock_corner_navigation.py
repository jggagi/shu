"""Rasterize the authored dock shore into the existing rectangular walk contract.

The conservative 10px cells keep all four corners on stone. Merge only solid
runs; both Session and presenter then consume the same rectangles. No game state.
"""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]

def rebuild():
    layout = json.loads((ROOT / 'assets/data/dock-corner-layout.json').read_text())
    polygon = layout['shore_polygon']
    def inside(x, y):
        result = False
        for (ax, ay), (bx, by) in zip(polygon, polygon[1:] + polygon[:1]):
            if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax:
                result = not result
        return result
    boxes, active = [], {}
    for y in range(30, 650, 10):
        runs, start = [], None
        for x in range(25, 1025, 10):
            blocked = not all(inside(x+dx, y+dy) for dx, dy in [(0.1,.1),(9.9,.1),(.1,9.9),(9.9,9.9)])
            if blocked and start is None:
                start = x
            if start is not None and (not blocked or x == 1015):
                end = x if not blocked else x+10
                runs.append((start, end-start))
                start = None
        next_active = {}
        for key in runs:
            if key in active:
                box = active.pop(key)
                box[3] += 10
            else:
                box = [key[0], y, key[1], 10]
            next_active[key] = box
        boxes.extend(active.values())
        active = next_active
    boxes.extend(active.values())
    path = ROOT / 'games/shu_dock_corner/walks.json'
    data = json.loads(path.read_text())
    data['scenes']['dock_corner']['obstacles'] = boxes + layout['solid_props']
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'obstacles': len(boxes)+len(layout['solid_props']), 'cell_size': 10}))

if __name__ == '__main__':
    rebuild()
