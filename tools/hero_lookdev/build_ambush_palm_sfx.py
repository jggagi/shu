#!/usr/bin/env python3
"""Rebuild two original palm cues with Python stdlib only.

No recordings, external samples, neural model, cloud call or codec dependency.
The cues are short air/cloth and low ground/wood responses, without metallic
sword modes, sustained chimes or musical notes. Device listening is separate.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/art/mountain_ambush/palm_lab/v2/sfx"
RATE = 22050
SOURCE_PEAK = 0.56
CUES = {
    "palm-release": (260551, 0.28, "air_cloth"),
    "palm-impact": (260552, 0.34, "wood_ground_grit"),
}


def smooth(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def synth(seed: int, duration: float, kind: str) -> list[float]:
    rng = random.Random(seed)
    count = round(RATE * duration)
    low_160 = low_700 = low_2200 = 0.0
    filters = [1.0 - math.exp(-math.tau * hz / RATE) for hz in (160, 700, 2200)]
    raw: list[float] = []
    for i in range(count):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        low_160 += (noise - low_160) * filters[0]
        low_700 += (noise - low_700) * filters[1]
        low_2200 += (noise - low_2200) * filters[2]
        cloth_band = low_2200 - low_700
        air_body = low_700 - low_160
        if kind == "air_cloth":
            # Brief cloth snap followed by a rounded low-mid air push.
            push = math.sin(math.pi * min(1.0, t / duration)) ** 0.85
            push *= math.exp(-t * 4.2)
            snap = math.exp(-((t - 0.027) / 0.014) ** 2)
            body = (0.92 * air_body + 0.22 * low_160) * push
            body += cloth_band * snap * 0.43
            # Broad damped pressure, not a pitched blade whistle.
            body += math.sin(math.tau * (83.0 * t - 36.0 * t * t)) * math.exp(-t * 21.0) * 0.032
        else:
            # Two low damped body modes and woody noise. No high-frequency
            # inharmonic sine bank, metallic resonance or long reverb tail.
            body = math.sin(math.tau * (86.0 * t - 27.0 * t * t)) * math.exp(-t * 18.5) * 0.52
            body += math.sin(math.tau * 55.5 * t) * math.exp(-t * 14.0) * 0.19
            body += low_700 * math.exp(-t * 29.0) * 0.66
            body += air_body * math.exp(-t * 48.0) * 0.28
            # Uneven, finite grit ticks share the seeded noise stream.
            for birth, gain, decay in ((0.010, .29, 115), (0.037, .22, 105),
                                        (0.061, .17, 125), (0.096, .13, 95),
                                        (0.143, .08, 105)):
                age = t - birth
                if age >= 0.0:
                    body += cloth_band * gain * math.exp(-age * decay)
        raw.append(body)
    mean = sum(raw) / len(raw)
    values: list[float] = []
    for i, value in enumerate(raw):
        # One millisecond of literal zero at both ends, with smooth attack
        # and 35ms release. No loop point or endpoint jump.
        attack = smooth((i - 22) / (RATE * 0.003))
        tail = smooth((count - 23 - i) / (RATE * 0.035))
        values.append((value - mean) * attack * tail)
    peak = max(abs(value) for value in values) or 1.0
    return [value / peak * SOURCE_PEAK for value in values]


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = []
    for name, (seed, duration, kind) in CUES.items():
        values = synth(seed, duration, kind)
        pcm_values = [round(value * 32767) for value in values]
        assert max(abs(value) for value in pcm_values) <= round(0.58 * 32767)
        assert pcm_values[0] == pcm_values[-1] == 0
        pcm = struct.pack("<" + "h" * len(pcm_values), *pcm_values)
        path = OUTPUT / (name + ".wav")
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(pcm)
        decoded = [value / 32768.0 for value in pcm_values]
        records.append({"path": path.relative_to(ROOT).as_posix(),
                        "seed": seed, "kind": kind, "frames": len(decoded),
                        "sample_rate": RATE, "channels": 1, "pcm_bits": 16,
                        "duration_seconds": len(decoded) / RATE,
                        "peak": max(abs(value) for value in decoded),
                        "rms": math.sqrt(sum(value * value for value in decoded) / len(decoded)),
                        "first_sample": pcm_values[0], "last_sample": pcm_values[-1],
                        "silent_edge_samples_each_end": 23,
                        "loop": False,
                        "bytes": path.stat().st_size,
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    source = Path(__file__).resolve()
    manifest = {"schema": 1, "author": "Original Shu palm audio authored by Codex",
                "method": "Fixed-seed filtered noise, brief cloth transient, low damped body modes and finite grit ticks; Python stdlib wave",
                "input_recordings": [], "third_party_samples": [],
                "new_cloud_calls": 0, "new_dependency_installs": 0, "cost_rmb": 0,
                "generator": source.relative_to(ROOT).as_posix(),
                "generator_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "rebuild": "python3 tools/hero_lookdev/build_ambush_palm_sfx.py",
                "cues": records,
                "runtime_contract": "V2 only: release at 0.56s, impact at 0.78s, default gain -12dB, share existing 招式声 mute. 2 schedules when enabled, 0 when muted; runtime scheduling must be tested separately.",
                "verification_boundary": "PCM format/levels/zero edges/determinism checked separately from actual device listening or subjective timbre approval; no listening validation claimed."}
    (OUTPUT / "source-palm-sfx.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"cues": len(records), "bytes": sum(row["bytes"] for row in records),
                      "manifest": str((OUTPUT / "source-palm-sfx.json").relative_to(ROOT))}))


if __name__ == "__main__":
    main()
