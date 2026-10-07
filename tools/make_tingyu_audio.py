#!/usr/bin/env python3
"""Generate deterministic, original synthetic audio for the Tingyu veranda."""

from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "assets" / "audio" / "tingyu"
SAMPLE_RATE = 24_000
RAIN_SECONDS = 16
RAIN_FRAMES = SAMPLE_RATE * RAIN_SECONDS
RAIN_SEED = 20261006
DROP_SEEDS = (20261017, 20261019)
TARGET_RAIN_RMS = 0.105
RAIN_SOFT_LIMIT = 0.50
RAIN_PEAK_LIMIT = 0.58
LEAF_SECONDS = 12
LEAF_FRAMES = SAMPLE_RATE * LEAF_SECONDS
LEAF_SEEDS = (20261025, 20261027)


def rms(samples: array) -> float:
	return math.sqrt(sum(sample * sample for sample in samples) / max(len(samples), 1))


def peak(samples: array) -> float:
	return max((abs(sample) for sample in samples), default=0.0)


def circular_lowpass(samples: array, cutoff_hz: float) -> array:
	"""One-pole low-pass with a solved periodic state for a loop-safe boundary."""
	coefficient = math.exp(-2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
	input_weight = 1.0 - coefficient
	period_decay = coefficient ** len(samples)
	state = 0.0
	for sample in samples:
		state = coefficient * state + input_weight * sample
	state /= max(1.0 - period_decay, 1e-12)
	filtered = array("d")
	for sample in samples:
		state = coefficient * state + input_weight * sample
		filtered.append(state)
	return filtered


def unit_rms(samples: array) -> array:
	level = max(rms(samples), 1e-12)
	return array("d", (sample / level for sample in samples))


def make_rain_events() -> list[tuple[int, int, int, float, float]]:
	rng = random.Random(RAIN_SEED ^ 0x5A17)
	events = []
	for _ in range(640):
		length = rng.randint(64, 240)  # 2.7–10 ms
		events.append((
			rng.randrange(RAIN_FRAMES),
			length,
			rng.randint(7, 20),
			rng.uniform(75.0, 178.0),
			rng.uniform(0.075, 0.19),
		))
	return events


def make_rain_channel(seed: int, channel_offset: float, events: list[tuple[int, int, int, float, float]]) -> array:
	rng = random.Random(seed)
	white = array("d", (rng.uniform(-1.0, 1.0) for _ in range(RAIN_FRAMES)))
	low_raw = circular_lowpass(white, 125.0)
	low = unit_rms(low_raw)
	low_mid = circular_lowpass(white, 1_250.0)
	mid = unit_rms(array("d", (high - low_sample for high, low_sample in zip(low_mid, low_raw))))
	high_low = circular_lowpass(white, 1_700.0)
	high_high = circular_lowpass(white, 5_200.0)
	high = unit_rms(array("d", (high - low_sample for high, low_sample in zip(high_high, high_low))))
	base = array("d", [0.0]) * RAIN_FRAMES
	for index in range(RAIN_FRAMES):
		time = index / SAMPLE_RATE
		envelope = (
			0.965
			+ 0.022 * math.sin(2.0 * math.pi * time / RAIN_SECONDS + channel_offset)
			+ 0.012 * math.sin(4.0 * math.pi * time / RAIN_SECONDS + 0.7 * channel_offset)
		)
		base[index] = (0.34 * low[index] + 0.62 * mid[index] + 0.16 * high[index]) * envelope

	for start, length, attack_samples, decay_samples, amount in events:
		for offset in range(length):
			index = (start + offset) % RAIN_FRAMES
			attack = math.sin(0.5 * math.pi * min(offset / attack_samples, 1.0))
			end_fade = (1.0 - offset / max(length - 1, 1)) ** 2
			burst = attack * math.exp(-offset / decay_samples) * end_fade
			base[index] += amount * burst * high[index]
	return base


def normalize_rain_stereo(left: array, right: array) -> tuple[array, array]:
	combined_rms = math.sqrt((sum(value * value for value in left) + sum(value * value for value in right)) / (2.0 * RAIN_FRAMES))
	gain = TARGET_RAIN_RMS / max(combined_rms, 1e-12)
	left_limited = array("d", (RAIN_SOFT_LIMIT * math.tanh(value * gain / RAIN_SOFT_LIMIT) for value in left))
	right_limited = array("d", (RAIN_SOFT_LIMIT * math.tanh(value * gain / RAIN_SOFT_LIMIT) for value in right))
	limited_rms = math.sqrt((sum(value * value for value in left_limited) + sum(value * value for value in right_limited)) / (2.0 * RAIN_FRAMES))
	limited_peak = max(peak(left_limited), peak(right_limited))
	final_gain = min(TARGET_RAIN_RMS / max(limited_rms, 1e-12), RAIN_PEAK_LIMIT / max(limited_peak, 1e-12))
	return (
		array("d", (value * final_gain for value in left_limited)),
		array("d", (value * final_gain for value in right_limited)),
	)


def smoothstep(edge0: float, edge1: float, value: float) -> float:
	t = min(max((value - edge0) / (edge1 - edge0), 0.0), 1.0)
	return t * t * (3.0 - 2.0 * t)


def make_drop(seed: int, profile: tuple[float, ...], left_gain: float, right_gain: float) -> tuple[array, array]:
	seconds = 0.45
	frames = int(SAMPLE_RATE * seconds)
	f1, tau1, f2, tau2, f3, tau3, phase2, phase3 = profile
	rng = random.Random(seed)
	noise_filter = 0.0
	noise_coefficient = math.exp(-2.0 * math.pi * 4_200.0 / SAMPLE_RATE)
	mono = array("d")
	for index in range(frames):
		time = index / SAMPLE_RATE
		noise_filter = noise_coefficient * noise_filter + (1.0 - noise_coefficient) * rng.uniform(-1.0, 1.0)
		attack = 1.0 - math.exp(-time / 0.0018)
		end_fade = smoothstep(0.0, 0.075, seconds - time)
		resonance = (
			0.18 * math.sin(2.0 * math.pi * f1 * time) * math.exp(-time / tau1)
			+ 0.12 * math.sin(2.0 * math.pi * f2 * time + phase2) * math.exp(-time / tau2)
			+ 0.075 * math.sin(2.0 * math.pi * f3 * time + phase3) * math.exp(-time / tau3)
		)
		soft_noise = 0.37 * noise_filter * math.exp(-time / 0.018)
		mono.append((resonance + soft_noise) * attack * end_fade)
	peak_level = max(peak(mono), 1e-12)
	scale = 0.26 / peak_level
	return (
		array("d", (sample * scale * left_gain for sample in mono)),
		array("d", (sample * scale * right_gain for sample in mono)),
	)



def make_leaf_events() -> list[tuple[int, int, float]]:
	rng = random.Random(LEAF_SEEDS[0] ^ 0xC11F)
	events = []
	for _ in range(28):
		events.append((
			rng.randrange(LEAF_FRAMES),
			rng.randint(int(SAMPLE_RATE * 0.12), int(SAMPLE_RATE * 0.62)),
			rng.uniform(0.12, 0.24),
		))
	return events


def make_leaf_channel(seed: int, channel_offset: float, events: list[tuple[int, int, float]]) -> array:
	rng = random.Random(seed)
	white = array("d", (rng.uniform(-1.0, 1.0) for _ in range(LEAF_FRAMES)))
	low_raw = circular_lowpass(white, 240.0)
	low = unit_rms(low_raw)
	mid_raw = circular_lowpass(white, 2_800.0)
	mid = unit_rms(array("d", (high - low_sample for high, low_sample in zip(mid_raw, low_raw))))
	high_low = circular_lowpass(white, 2_900.0)
	high_high = circular_lowpass(white, 7_600.0)
	high = unit_rms(array("d", (high - low_sample for high, low_sample in zip(high_high, high_low))))
	base = array("d", [0.0]) * LEAF_FRAMES
	for index in range(LEAF_FRAMES):
		time = index / SAMPLE_RATE
		envelope = 0.95 + 0.035 * math.sin(2.0 * math.pi * time / LEAF_SECONDS + channel_offset)
		envelope += 0.018 * math.sin(4.0 * math.pi * time / LEAF_SECONDS + channel_offset * 0.6)
		base[index] = (0.12 * low[index] + 0.62 * mid[index] + 0.14 * high[index]) * envelope

	for start, length, amount in events:
		for offset in range(length):
			index = (start + offset) % LEAF_FRAMES
			progress = offset / max(length - 1, 1)
			shape = math.sin(math.pi * progress) ** 1.4
			base[index] += amount * shape * (0.72 * mid[index] + 0.22 * high[index])
	return base


def normalize_leaf_stereo(left: array, right: array) -> tuple[array, array]:
	combined_rms = math.sqrt((sum(value * value for value in left) + sum(value * value for value in right)) / (2.0 * LEAF_FRAMES))
	gain = 0.105 / max(combined_rms, 1e-12)
	left_limited = array("d", (0.48 * math.tanh(value * gain / 0.48) for value in left))
	right_limited = array("d", (0.48 * math.tanh(value * gain / 0.48) for value in right))
	limited_rms = math.sqrt((sum(value * value for value in left_limited) + sum(value * value for value in right_limited)) / (2.0 * LEAF_FRAMES))
	limited_peak = max(peak(left_limited), peak(right_limited))
	final_gain = min(0.105 / max(limited_rms, 1e-12), 0.52 / max(limited_peak, 1e-12))
	return (
		array("d", (value * final_gain for value in left_limited)),
		array("d", (value * final_gain for value in right_limited)),
	)


def scale_cue(samples: array, target_peak: float) -> array:
	level = max(peak(samples), 1e-12)
	return array("d", (sample * target_peak / level for sample in samples))


def make_cloth_cue() -> array:
	seconds = 0.38
	frames = int(SAMPLE_RATE * seconds)
	rng = random.Random(20261029)
	white = array("d", (rng.uniform(-1.0, 1.0) for _ in range(frames)))
	low = circular_lowpass(white, 360.0)
	mid_high = circular_lowpass(white, 3_800.0)
	high_low = circular_lowpass(white, 2_600.0)
	high_high = circular_lowpass(white, 7_800.0)
	mono = array("d")
	for index in range(frames):
		time = index / SAMPLE_RATE
		attack = smoothstep(0.0, 0.028, time)
		release = smoothstep(0.0, 0.13, seconds - time)
		flutter = 0.82 + 0.12 * math.sin(2.0 * math.pi * 5.4 * time) + 0.06 * math.sin(2.0 * math.pi * 8.1 * time + 0.7)
		filtered = 0.72 * (mid_high[index] - low[index]) + 0.18 * (high_high[index] - high_low[index])
		mono.append(filtered * attack * release * flutter)
	return scale_cue(mono, 0.14)


def make_purr_cue() -> array:
	seconds = 0.92
	frames = int(SAMPLE_RATE * seconds)
	rng = random.Random(20261031)
	white = array("d", (rng.uniform(-1.0, 1.0) for _ in range(frames)))
	filtered = unit_rms(circular_lowpass(white, 620.0))
	mono = array("d")
	for index in range(frames):
		time = index / SAMPLE_RATE
		attack = smoothstep(0.0, 0.055, time)
		release = smoothstep(0.0, 0.20, seconds - time)
		pulse = 0.47 + 0.53 * max(0.0, math.sin(2.0 * math.pi * 24.0 * time))
		body = 0.54 * filtered[index] + 0.14 * math.sin(2.0 * math.pi * 58.0 * time) + 0.05 * math.sin(2.0 * math.pi * 116.0 * time)
		mono.append(body * pulse * attack * release)
	return scale_cue(mono, 0.13)


def make_bird_cue() -> array:
	seconds = 0.58
	frames = int(SAMPLE_RATE * seconds)
	mono = array("d", [0.0]) * frames
	chirps = ((0.035, 0.155, 2_250.0, 3_050.0), (0.225, 0.345, 2_750.0, 3_550.0), (0.405, 0.535, 3_300.0, 2_650.0))
	for start, end, frequency_start, frequency_end in chirps:
		first = int(start * SAMPLE_RATE)
		last = int(end * SAMPLE_RATE)
		duration = end - start
		for index in range(first, last):
			local_time = (index - first) / SAMPLE_RATE
			progress = local_time / duration
			frequency_delta = frequency_end - frequency_start
			phase = 2.0 * math.pi * (frequency_start * local_time + 0.5 * frequency_delta * local_time * local_time / duration)
			envelope = math.sin(math.pi * progress) ** 1.25
			vibrato = 1.0 + 0.012 * math.sin(2.0 * math.pi * 13.0 * local_time)
			mono[index] += 0.12 * math.sin(phase) * envelope * vibrato
	return scale_cue(mono, 0.12)


def stereo_cue(mono: array, left_gain: float = 0.96, right_gain: float = 1.0) -> tuple[array, array]:
	return (
		array("d", (sample * left_gain for sample in mono)),
		array("d", (sample * right_gain for sample in mono)),
	)

def write_wave(path: Path, left: array, right: array) -> dict[str, float | int]:
	frames = len(left)
	payload = bytearray(frames * 4)
	sum_squares = 0.0
	peak_value = 0.0
	for index, (left_value, right_value) in enumerate(zip(left, right)):
		left_pcm = max(-32768, min(32767, round(left_value * 32767.0)))
		right_pcm = max(-32768, min(32767, round(right_value * 32767.0)))
		struct.pack_into("<hh", payload, index * 4, left_pcm, right_pcm)
		left_float = left_pcm / 32768.0
		right_float = right_pcm / 32768.0
		sum_squares += left_float * left_float + right_float * right_float
		peak_value = max(peak_value, abs(left_float), abs(right_float))
	with wave.open(str(path), "wb") as output:
		output.setnchannels(2)
		output.setsampwidth(2)
		output.setframerate(SAMPLE_RATE)
		output.writeframes(payload)
	return {
		"frames": frames,
		"duration_seconds": frames / SAMPLE_RATE,
		"rms": math.sqrt(sum_squares / (2.0 * frames)),
		"peak": peak_value,
	}


def sha256(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as source:
		for block in iter(lambda: source.read(1024 * 1024), b""):
			digest.update(block)
	return digest.hexdigest()


def file_record(path: Path, audio_stats: dict[str, float | int]) -> dict[str, object]:
	return {
		"path": path.relative_to(ROOT).as_posix(),
		"sha256": sha256(path),
		"format": "WAV PCM signed 16-bit little-endian stereo",
		"sample_rate_hz": SAMPLE_RATE,
		**audio_stats,
	}



def main() -> None:
	OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
	events = make_rain_events()
	left = make_rain_channel(RAIN_SEED, 0.0, events)
	right = make_rain_channel(RAIN_SEED + 1, 0.83, events)
	left, right = normalize_rain_stereo(left, right)
	rain_path = OUTPUT_DIR / "rain-loop.wav"
	rain_stats = write_wave(rain_path, left, right)

	drop_profiles = (
		(510.0, 0.064, 890.0, 0.043, 1_410.0, 0.027, 0.41, 1.02),
		(620.0, 0.058, 1_030.0, 0.038, 1_580.0, 0.024, 0.73, 0.28),
	)
	drop_records = []
	for index, (seed, profile) in enumerate(zip(DROP_SEEDS, drop_profiles), start=1):
		left_gain, right_gain = ((0.96, 0.88) if index == 1 else (0.89, 0.96))
		drop_left, drop_right = make_drop(seed, profile, left_gain, right_gain)
		drop_path = OUTPUT_DIR / f"eave-drop-{index}.wav"
		drop_stats = write_wave(drop_path, drop_left, drop_right)
		drop_records.append(file_record(drop_path, drop_stats))

	leaf_events = make_leaf_events()
	leaf_left = make_leaf_channel(LEAF_SEEDS[0], 0.0, leaf_events)
	leaf_right = make_leaf_channel(LEAF_SEEDS[1], 0.72, leaf_events)
	leaf_left, leaf_right = normalize_leaf_stereo(leaf_left, leaf_right)
	leaf_path = OUTPUT_DIR / "leaf-rustle.wav"
	leaf_stats = write_wave(leaf_path, leaf_left, leaf_right)
	leaf_record = file_record(leaf_path, leaf_stats)

	cue_records = {}
	for name, mono in (("cloth", make_cloth_cue()), ("purr", make_purr_cue()), ("bird", make_bird_cue())):
		cue_left, cue_right = stereo_cue(mono)
		cue_path = OUTPUT_DIR / f"{name}.wav"
		cue_stats = write_wave(cue_path, cue_left, cue_right)
		cue_records[name] = file_record(cue_path, cue_stats)

	script_path = Path(__file__).resolve()
	manifest = {
		"version": "tingyu-audio-v2",
		"date": "2026-10-07",
		"tool_author": "Codex agent (OpenAI)",
		"generator": {
			"script": "tools/make_tingyu_audio.py",
			"script_sha256": sha256(script_path),
			"runtime": "Python 3 standard library only",
			"command": "python3 tools/make_tingyu_audio.py",
		},
		"provenance": "Original procedural synthesis for the shu project. No external recordings, samples, or third-party audio were used.",
		"license": "Project-original synthetic material; no third-party material. This provenance record does not assert a separate legal grant.",
		"format": {
			"sample_rate_hz": SAMPLE_RATE,
			"channels": 2,
			"bit_depth": 16,
			"container": "RIFF/WAVE PCM",
		},
		"rain_loop": {
			"seed": RAIN_SEED,
			"algorithm": "Sixteen seconds of deterministic noise split into lower, mid, and high bands with less low-frequency weight and a lower overall level. Six hundred forty short high-band bursts use independently seeded positions, lengths, envelopes, and strengths for a softer uneven patter. Circular filter state and wrapped bursts keep the loop boundary continuous.",
			"target_rms": TARGET_RAIN_RMS,
			"peak_limit": RAIN_PEAK_LIMIT,
			"file": file_record(rain_path, rain_stats),
		},
		"eave_drops": {
			"seeds": list(DROP_SEEDS),
			"algorithm": "Two distinct 0.45-second original syntheses combine filtered-noise onsets with three quieter damped resonances, a soft attack, and a short tail fade. Stereo levels differ slightly per drop; no sampled source is used.",
			"peak_target": 0.26,
			"peak_limit": 0.32,
			"files": drop_records,
		},
		"leaf_rustle": {
			"seeds": list(LEAF_SEEDS),
			"algorithm": "A twelve-second deterministic stereo loop combines filtered low, mid, and high noise with twenty-eight individually tapered, sparse rustles. Circular filters, wrapped events, and a periodic bed envelope avoid a special end fade.",
			"target_rms": 0.105,
			"file": leaf_record,
		},
		"short_cues": {
			"algorithm": "Three original deterministic procedural clips: a filtered fabric swish, a soft amplitude-pulsed purr, and three shaped frequency-swept bird chirps. All clips use the same stereo PCM format as the ambient loops.",
			"files": cue_records,
		},
	}
	manifest_path = OUTPUT_DIR / "source.json"
	manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

	all_records = [manifest["rain_loop"]["file"], *drop_records, leaf_record, *cue_records.values()]
	for record in all_records:
		print(
			f"{Path(record['path']).name}: {record['sample_rate_hz']} Hz stereo PCM16, "
			f"{record['duration_seconds']:.2f}s, RMS {record['rms']:.4f}, peak {record['peak']:.4f}, "
			f"SHA256 {record['sha256']}"
		)
	print(f"Wrote {manifest_path.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
	main()
