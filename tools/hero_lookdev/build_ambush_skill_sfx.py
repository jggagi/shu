"""Rebuild four original mono PCM skill cues using only the Python stdlib.

No input recording, model, cloud service, codec package or third-party sample.
The seeds and synthesis parameters below define these small procedural sounds.
"""
from __future__ import annotations

import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/art/mountain_ambush/skills/sfx"
RATE = 22050
CUES = {
    "pierce-whoosh": (17021, 0.36, "air", 1.0),
    "pierce-hit": (17022, 0.15, "metal", 1.0),
    "sweep-whoosh": (17031, 0.42, "air", 0.68),
    "sweep-hit": (17032, 0.18, "metal", 0.73),
}


def synth(seed: int, duration: float, kind: str, pitch: float) -> list[float]:
    rng = random.Random(seed)
    values: list[float] = []
    slow_noise = 0.0
    previous = 0.0
    phase = 0.0
    for frame in range(round(RATE * duration)):
        t = frame / RATE
        u = t / duration
        noise = rng.uniform(-1.0, 1.0)
        slow_noise += (noise - slow_noise) * (0.12 if pitch < 0.8 else 0.25)
        bright_noise = noise - previous
        previous = noise
        # A zero-edge window prevents clicks, including the sharp hit cue.
        edge = min(1.0, t / 0.004, (duration - t) / 0.012)
        if kind == "air":
            envelope = math.sin(math.pi * u) ** 1.6
            envelope *= 0.45 + 0.55 * u
            frequency = pitch * (240.0 + 920.0 * u)
            phase += math.tau * frequency / RATE
            body = slow_noise * 0.77 + bright_noise * 0.13 * pitch
            body += math.sin(phase) * 0.07
            body *= 0.80 + 0.20 * math.sin(math.tau * (13.0 * t + u * u))
            value = body * envelope
        else:
            # Inharmonic damped sine pairs suggest light metal, without a
            # brittle full-scale transient or a sampled commercial weapon.
            metallic = 0.0
            for frequency, gain, decay in [(1560, 0.32, 40), (2471, 0.20, 48),
                                            (3817, 0.13, 60), (5311, 0.06, 75)]:
                metallic += math.sin(math.tau * frequency * pitch * t) * gain * math.exp(-decay * t)
            thump = math.sin(math.tau * (118.0 * pitch) * t) * math.exp(-32 * t) * 0.30
            value = metallic + thump + slow_noise * math.exp(-55 * t) * 0.20
        values.append(value * max(0.0, edge))
    peak = max(abs(v) for v in values) or 1.0
    # 0.62 source peak, with a small DC correction; runtime has its own gain.
    mean = sum(values) / len(values)
    return [(v - mean) / peak * 0.62 for v in values]


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = []
    for name, (seed, duration, kind, pitch) in CUES.items():
        values = synth(seed, duration, kind, pitch)
        path = OUTPUT / (name + ".wav")
        pcm = b"".join(struct.pack("<h", max(-32767, min(32767, round(v * 32767)))) for v in values)
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(pcm)
        rms = math.sqrt(sum(v * v for v in values) / len(values))
        records.append({"path": path.relative_to(ROOT).as_posix(), "seed": seed,
                        "kind": kind, "pitch_factor": pitch, "frames": len(values),
                        "sample_rate": RATE, "channels": 1, "pcm_bits": 16,
                        "duration_seconds": len(values) / RATE, "peak": max(abs(v) for v in values),
                        "rms": rms, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    script = Path(__file__).resolve()
    manifest = {"author": "Original Shu procedural audio by Codex",
                "method": "Seeded filtered noise plus damped inharmonic sine synthesis, Python stdlib wave",
                "input_recordings": [], "third_party_samples": [], "new_cloud_calls": 0,
                "new_dependency_installs": 0, "cost_rmb": 0,
                "generator": script.relative_to(ROOT).as_posix(),
                "generator_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
                "rebuild": "python3 tools/hero_lookdev/build_ambush_skill_sfx.py",
                "cues": records,
                "verification_boundary": "PCM encoding, peaks and reproducibility checked separately from device listening."}
    path = OUTPUT.parent / "source-sfx.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"cues": len(records), "bytes": sum((ROOT / r["path"]).stat().st_size for r in records),
                      "manifest": path.relative_to(ROOT).as_posix()}))


if __name__ == "__main__":
    main()
