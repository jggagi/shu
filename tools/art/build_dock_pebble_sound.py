"""Rebuild the original deterministic water plop; no external recording/assets."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[2]


def main():
    out = ROOT / "assets/audio/dock_pebble/plop.wav"
    out.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20261113)
    rate = 22050
    samples = []
    phase = smooth = 0.0
    for i in range(int(rate * .48)):
        t = i / rate
        phase += 2 * math.pi * (240 + 680 * math.exp(-t * 36)) / rate
        smooth = .68 * smooth + .32 * rng.uniform(-1, 1)
        value = .42 * math.sin(phase) * math.exp(-t * 29)
        value += .31 * smooth * math.exp(-t * 13) * (1 - math.exp(-t * 120))
        if t > .055:
            value += .10 * math.sin(2 * math.pi * 410 * (t - .055)) * math.exp(-(t - .055) * 35)
        value *= min(1, t / .002)
        samples.append(round(max(-.95, min(.95, value)) * 32767))
    with wave.open(str(out), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes(struct.pack("<%dh" % len(samples), *samples))


if __name__ == "__main__":
    main()
