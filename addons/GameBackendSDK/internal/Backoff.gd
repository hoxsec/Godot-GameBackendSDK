class_name BackendBackoff
extends RefCounted

## Exponential backoff utility for retry delays

var base_ms: int = 100
var max_ms: int = 10000
var multiplier: float = 2.0
var jitter: float = 0.1

func _init(base_milliseconds := 100, max_milliseconds := 10000) -> void:
	base_ms = base_milliseconds
	max_ms = max_milliseconds

## Calculate delay in seconds for the given attempt (0-indexed)
func delay_for_attempt(attempt: int) -> float:
	var delay_ms: float = min(base_ms * pow(multiplier, attempt), max_ms)
	
	# Add jitter: ±10% randomness
	if jitter > 0:
		var jitter_range := delay_ms * jitter
		delay_ms += randf_range(-jitter_range, jitter_range)
	
	return delay_ms / 1000.0

## Reset to initial state (no-op for stateless backoff, but kept for API consistency)
func reset() -> void:
	pass

