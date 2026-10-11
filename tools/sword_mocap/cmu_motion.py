"""Stdlib CMU ASF/AMC converter. See SCHEMA_VERSION and sample_file for JSON schema v1.

Schema v1: schema_version, fps (120), length_unit_metres, source_frame
(sampled AMC frame-number list), bones (root plus ASF metadata), and samples
(each has source_frame and a bones mapping). Bone records contain world-space
head/tail metres and normalized [w,x,y,z] quaternions in Blender Z-up basis.
AMC timing and rotations are preserved; no filtering, retiming or foot locking.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

FPS = 120
BLENDER_BASIS = ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0))


@dataclass(frozen=True)
class RootSpec:
    order: tuple[str, ...]
    axis: str
    position: tuple[float, float, float]
    orientation: tuple[float, float, float]


@dataclass(frozen=True)
class BoneSpec:
    identifier: int
    name: str
    direction: tuple[float, float, float]
    length: float
    axis: tuple[float, float, float]
    axis_order: str
    dofs: tuple[str, ...]
    parent: str


@dataclass(frozen=True)
class SkeletonSpec:
    root: RootSpec
    bones: tuple[BoneSpec, ...]
    length_unit_metres: float


@dataclass(frozen=True)
class MotionFrame:
    source_frame: int
    channels: Mapping[str, tuple[float, ...]]


def _numbers(text: str, count: int, label: str) -> tuple[float, ...]:
    try:
        values = tuple(float(x) for x in text.split())
    except ValueError as exc:
        raise ValueError(f"{label}: expected numeric values") from exc
    if len(values) != count or not all(math.isfinite(x) for x in values):
        raise ValueError(f"{label}: expected {count} finite values")
    return values


def _sections(path: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    section: str | None = None
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith(":"):
            match = re.match(r"^:([A-Za-z_-]+)(?:\s+.*)?$", line)
            if not match:
                raise ValueError(f"{path}:{number}: malformed section")
            section = match.group(1).lower()
            result[section] = []
        elif section:
            result[section].append(line)
    return result


def parse_asf(path: str | Path) -> SkeletonSpec:
    """Parse ASF units, root channels, bone specifications and hierarchy."""
    source = Path(path)
    sections = _sections(source)
    for name in ("units", "root", "bonedata", "hierarchy"):
        if name not in sections:
            raise ValueError(f"{source}: missing :{name} section")

    units = {p[0].lower(): p[1] for line in sections["units"] if len(p := line.split()) == 2}
    try:
        asf_length = float(units["length"])
    except (KeyError, ValueError) as exc:
        raise ValueError(f"{source}: :units must define numeric length") from exc
    if not math.isfinite(asf_length) or asf_length <= 0:
        raise ValueError(f"{source}: ASF length must be positive and finite")
    length_unit_metres = 0.0254 / asf_length

    root_fields = {p[0].lower(): p[1:] for line in sections["root"] if (p := line.split())}
    root_order = tuple(x.upper() for x in root_fields.get("order", []))
    root_axis = (root_fields.get("axis", [""])[0]).upper()
    if root_order != ("TX", "TY", "TZ", "RX", "RY", "RZ") or root_axis != "XYZ":
        raise ValueError(f"{source}: unsupported root order/axis {root_order!r}/{root_axis!r}")
    root = RootSpec(
        root_order, root_axis,
        _numbers(" ".join(root_fields.get("position", ["0", "0", "0"])), 3, "root position"),
        _numbers(" ".join(root_fields.get("orientation", ["0", "0", "0"])), 3, "root orientation"),
    )

    blocks: list[list[str]] = []
    active: list[str] | None = None
    for line in sections["bonedata"]:
        if line.lower() == "begin":
            if active is not None:
                raise ValueError(f"{source}: nested bone block")
            active = []
        elif line.lower() == "end":
            if active is None:
                raise ValueError(f"{source}: bone end without begin")
            blocks.append(active)
            active = None
        elif active is not None:
            active.append(line)
    if active is not None:
        raise ValueError(f"{source}: unterminated bone block")

    raw: dict[str, dict[str, Any]] = {}
    for block in blocks:
        fields: dict[str, Any] = {}
        for line in block:
            p = line.split()
            key = p[0].lower()
            if key == "id":
                fields[key] = int(p[1])
            elif key == "name":
                fields[key] = p[1]
            elif key == "direction":
                fields[key] = _numbers(" ".join(p[1:]), 3, "bone direction")
            elif key == "length":
                fields[key] = _numbers(" ".join(p[1:]), 1, "bone length")[0]
            elif key == "axis":
                if len(p) != 5:
                    raise ValueError(f"{source}: malformed axis line {line!r}")
                fields[key] = _numbers(" ".join(p[1:4]), 3, "bone axis")
                fields["axis_order"] = p[4].upper()
            elif key == "dof":
                fields[key] = tuple(x.lower() for x in p[1:])
        needed = {"id", "name", "direction", "length", "axis", "axis_order"}
        if needed - fields.keys():
            raise ValueError(f"{source}: incomplete bone block, missing {sorted(needed - fields.keys())}")
        name = fields["name"]
        if name in raw:
            raise ValueError(f"{source}: duplicate bone {name!r}")
        if fields["axis_order"] != "XYZ":
            raise ValueError(f"{source}: unsupported axis order for {name}: {fields['axis_order']}")
        dofs = tuple(fields.get("dof", ()))
        if any(d not in ("rx", "ry", "rz") for d in dofs) or len(set(dofs)) != len(dofs):
            raise ValueError(f"{source}: unsupported DOFs for {name}: {dofs}")
        if fields["length"] < 0:
            raise ValueError(f"{source}: negative length for {name}")
        fields["dofs"] = dofs
        raw[name] = fields
    if not raw:
        raise ValueError(f"{source}: no ASF bones")

    parents: dict[str, str] = {}
    hierarchy_on = False
    root_seen = False
    for line in sections["hierarchy"]:
        if line.lower() == "begin":
            hierarchy_on = True
            continue
        if line.lower() == "end":
            hierarchy_on = False
            continue
        if not hierarchy_on:
            continue
        p = line.split()
        if len(p) < 2:
            raise ValueError(f"{source}: malformed hierarchy row {line!r}")
        parent, *children = p
        if parent == "root":
            root_seen = True
        elif parent not in raw:
            raise ValueError(f"{source}: unknown parent {parent!r}")
        for child in children:
            if child not in raw:
                raise ValueError(f"{source}: unknown hierarchy child {child!r}")
            if child in parents:
                raise ValueError(f"{source}: multiple parents for {child!r}")
            parents[child] = parent
    if not root_seen or set(parents) != set(raw):
        raise ValueError(f"{source}: hierarchy does not attach every bone to root")
    for name in raw:
        seen: set[str] = set()
        current = name
        while current != "root":
            if current in seen:
                raise ValueError(f"{source}: hierarchy cycle at {current!r}")
            seen.add(current)
            current = parents[current]
    ids = [int(v["id"]) for v in raw.values()]
    if len(ids) != len(set(ids)):
        raise ValueError(f"{source}: duplicate bone id")

    bones = tuple(
        BoneSpec(int(v["id"]), name, v["direction"], float(v["length"]), v["axis"],
                 v["axis_order"], v["dofs"], parents[name])
        for name, v in sorted(raw.items(), key=lambda item: int(item[1]["id"]))
    )
    return SkeletonSpec(root, bones, length_unit_metres)


def parse_amc(path: str | Path) -> list[MotionFrame]:
    """Parse degree-valued AMC frames and retain original frame numbers/angles."""
    source = Path(path)
    frames: list[MotionFrame] = []
    number: int | None = None
    channels: dict[str, tuple[float, ...]] = {}
    degrees = False

    def finish() -> None:
        nonlocal number, channels
        if number is None:
            return
        if "root" not in channels:
            raise ValueError(f"{source}: frame {number} missing root")
        frames.append(MotionFrame(number, dict(channels)))
        number, channels = None, {}

    for line_no, raw in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith(":"):
            marker = line.upper()
            if marker == ":DEGREES":
                degrees = True
            elif marker == ":RADIANS":
                raise ValueError(f"{source}:{line_no}: radians AMC is unsupported")
            continue
        parts = line.split()
        if len(parts) == 1:
            try:
                next_number = int(parts[0])
            except ValueError as exc:
                raise ValueError(f"{source}:{line_no}: malformed frame number") from exc
            finish()
            if next_number <= 0 or (frames and next_number <= frames[-1].source_frame):
                raise ValueError(f"{source}:{line_no}: frame numbers must increase from 1")
            number = next_number
            continue
        if number is None:
            raise ValueError(f"{source}:{line_no}: channel before frame number")
        name = parts[0]
        if name in channels:
            raise ValueError(f"{source}:{line_no}: duplicate channel {name!r}")
        try:
            values = tuple(float(x) for x in parts[1:])
        except ValueError as exc:
            raise ValueError(f"{source}:{line_no}: invalid channel value") from exc
        if not values or not all(math.isfinite(x) for x in values):
            raise ValueError(f"{source}:{line_no}: channel values must be finite")
        channels[name] = values
    finish()
    if not degrees:
        raise ValueError(f"{source}: missing :DEGREES")
    if not frames:
        raise ValueError(f"{source}: no AMC frames")
    return frames


def _mul(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> tuple[tuple[float, float, float], ...]:
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def _transpose(a: Sequence[Sequence[float]]) -> tuple[tuple[float, float, float], ...]:
    return tuple(tuple(a[j][i] for j in range(3)) for i in range(3))


def _vec(a: Sequence[Sequence[float]], v: Sequence[float]) -> tuple[float, float, float]:
    return tuple(sum(a[i][j] * v[j] for j in range(3)) for i in range(3))


def _rotation(angles: Mapping[str, float]) -> tuple[tuple[float, float, float], ...]:
    # ASF XYZ channel values are fixed-axis sequential X, then Y, then Z: Rz*Ry*Rx.
    x, y, z = (math.radians(angles.get(axis, 0.0)) for axis in ("rx", "ry", "rz"))
    sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
    rx = ((1.0, 0.0, 0.0), (0.0, cx, -sx), (0.0, sx, cx))
    ry = ((cy, 0.0, sy), (0.0, 1.0, 0.0), (-sy, 0.0, cy))
    rz = ((cz, -sz, 0.0), (sz, cz, 0.0), (0.0, 0.0, 1.0))
    return _mul(_mul(rz, ry), rx)


def _quat(matrix: Sequence[Sequence[float]]) -> list[float]:
    m00, m01, m02 = matrix[0]
    m10, m11, m12 = matrix[1]
    m20, m21, m22 = matrix[2]
    trace = m00 + m11 + m22
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        q = [0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s]
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        q = [(m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s]
    elif m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        q = [(m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s]
    else:
        s = math.sqrt(1.0 + m22 - m00 - m11) * 2
        q = [(m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s]
    norm = math.sqrt(sum(x * x for x in q))
    if not math.isfinite(norm) or norm == 0:
        raise ValueError("invalid rotation quaternion")
    q = [x / norm for x in q]
    sign = next((x for x in q if abs(x) > 1e-15), 1.0)
    return [-x for x in q] if sign < 0 else q


def _to_blender_rotation(r: Sequence[Sequence[float]]) -> tuple[tuple[float, float, float], ...]:
    return _mul(_mul(BLENDER_BASIS, r), _transpose(BLENDER_BASIS))


def _angles(values: Sequence[float], dofs: Sequence[str], label: str) -> dict[str, float]:
    if len(values) != len(dofs):
        raise ValueError(f"{label}: expected {len(dofs)} values, got {len(values)}")
    return dict(zip(dofs, values))


def solve_frame(skeleton: SkeletonSpec, frame: MotionFrame) -> dict[str, dict[str, list[float]]]:
    """Solve a full connected skeleton in metres and Blender Z-up coordinates."""
    specs = {b.name: b for b in skeleton.bones}
    expected = {"root", *(name for name, bone in specs.items() if bone.dofs)}
    missing, extra = sorted(expected - set(frame.channels)), sorted(set(frame.channels) - {"root", *specs})
    if missing or extra:
        raise ValueError(f"frame {frame.source_frame}: missing channels {missing}; unknown {extra}")

    root_values = _angles(frame.channels["root"], skeleton.root.order, "root")
    translation = tuple(root_values[a] * skeleton.length_unit_metres for a in ("TX", "TY", "TZ"))
    root_position = _vec(BLENDER_BASIS, translation)
    root_rotation = _rotation({a.lower(): root_values[a] for a in ("RX", "RY", "RZ")})
    solved: dict[str, dict[str, list[float]]] = {
        "root": {"head": list(root_position), "tail": list(root_position),
                 "rotation": _quat(_to_blender_rotation(root_rotation))}
    }
    rotations = {"root": root_rotation}
    tails = {"root": translation}

    def visit(name: str) -> None:
        if name in solved:
            return
        bone = specs[name]
        if bone.parent != "root":
            visit(bone.parent)
        axis_rotation = _rotation(dict(zip(("rx", "ry", "rz"), bone.axis)))
        motion_rotation = _rotation(_angles(frame.channels.get(name, ()), bone.dofs, name))
        local = _mul(_mul(axis_rotation, motion_rotation), _transpose(axis_rotation))
        world = _mul(rotations[bone.parent], local)
        offset = _vec(world, tuple(x * bone.length * skeleton.length_unit_metres for x in bone.direction))
        tail = tuple(tails[bone.parent][i] + offset[i] for i in range(3))
        solved[name] = {
            "head": list(_vec(BLENDER_BASIS, tails[bone.parent])),
            "tail": list(_vec(BLENDER_BASIS, tail)),
            "rotation": _quat(_to_blender_rotation(world)),
        }
        rotations[name], tails[name] = world, tail

    for bone in skeleton.bones:
        visit(bone.name)
    return {name: solved[name] for name in ("root", *(b.name for b in skeleton.bones))}


def _metadata(skeleton: SkeletonSpec) -> list[dict[str, Any]]:
    return [
        {"name": "root", "parent": None, "direction": [0.0, 0.0, 0.0], "length_m": 0.0},
        *[{"name": b.name, "parent": b.parent, "direction": list(b.direction),
           "length_m": b.length * skeleton.length_unit_metres} for b in skeleton.bones],
    ]


def sample_file(asf: str | Path, amc: str | Path, stride: int = 1) -> dict[str, Any]:
    """Return schema-v1 JSON data; stride keeps every Nth original source frame."""
    if not isinstance(stride, int) or isinstance(stride, bool) or stride < 1:
        raise ValueError("stride must be a positive integer")
    skeleton = parse_asf(asf)
    frames = parse_amc(amc)[::stride]
    numbers = [f.source_frame for f in frames]
    return {
        "schema_version": 1,
        "fps": FPS,
        "length_unit_metres": skeleton.length_unit_metres,
        "source_frame": numbers,
        "bones": _metadata(skeleton),
        "samples": [{"source_frame": f.source_frame, "bones": solve_frame(skeleton, f)} for f in frames],
    }


def _main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asf", required=True, type=Path)
    parser.add_argument("--amc", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--stride", type=int, default=1)
    args = parser.parse_args(argv)
    try:
        data = sample_file(args.asf, args.amc, args.stride)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
