extends RefCounted

# Presentation time is independent of cultivation turns and dialogue.
static func sample(seconds: float, duration: float = 30.0) -> Dictionary:
	var t := fposmod(seconds, duration) * 30.0 / duration
	var clearing := 1.0 - smoothstep(25.0, 30.0, t)
	var cloud := smoothstep(0.0, 4.0, t) * clearing
	var wind := smoothstep(5.0, 10.0, t) * clearing
	var rain := smoothstep(12.0, 17.0, t) * (1.0 - smoothstep(23.0, 29.0, t))
	var phase := "薄云过境" if t < 7.0 else ("微风拂竹" if t < 14.0 else ("山间小雨" if t < 25.0 else "雨歇云散"))
	return {"cloud": cloud, "wind": wind, "rain": rain, "phase": phase}
