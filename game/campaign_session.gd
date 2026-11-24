extends RefCounted

const LAST := 100
# Only the contiguous prefix can be completed. Its length represents the set
# of unique completed IDs without storing separate unlock flags.
var _cleared := 0

func completed_count() -> int:
	return _cleared

func is_completed(id: int) -> bool:
	return id >= 1 and id <= _cleared

func can_play(id: int) -> bool:
	return id >= 1 and id <= mini(_cleared + 1, LAST)

func next_incomplete() -> int:
	return _cleared + 1 if _cleared < LAST else 0

func record_completion(id: int) -> bool:
	if not can_play(id) or is_completed(id):
		return false
	_cleared += 1
	return true
