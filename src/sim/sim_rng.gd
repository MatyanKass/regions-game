# Xorshift32. Deliberately hand-rolled instead of RandomNumberGenerator so that the
# exact bit pattern is part of this repository and can never change under us with an
# engine update - map generation has to stay identical on both phones.
class_name SimRng
extends RefCounted

const MASK := 0xFFFFFFFF

var _state: int

func _init(seed_value: int) -> void:
	_state = seed_value & MASK
	if _state == 0:
		_state = 0x9E3779B9

func next_uint() -> int:
	var x := _state
	x = (x ^ (x << 13)) & MASK
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & MASK
	_state = x
	return x

# Uniform enough for map generation; the modulo bias over small ranges is irrelevant here.
func next_range(n: int) -> int:
	if n <= 1:
		return 0
	return next_uint() % n
