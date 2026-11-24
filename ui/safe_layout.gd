extends RefCounted

static func mobile_margins(logical_size: Vector2, window: Rect2, safe: Rect2) -> Vector4:
	var margins := Vector4(48,44,48,44)
	var visible := window.intersection(safe)
	if not visible.has_area() or not window.has_area(): return margins
	# Android safe bounds are display pixels. Canvas stretch already expands
	# the logical root, so convert each inset against the drawable window.
	var scale := logical_size / window.size
	var leading := (visible.position - window.position) * scale
	var trailing := (window.end - visible.end) * scale
	return Vector4(maxf(margins.x,leading.x),maxf(margins.y,leading.y),
		maxf(margins.z,trailing.x),maxf(margins.w,trailing.y))

static func apply(screen: Control, layout: Control, max_width := 0.0) -> void:
	var margins := Vector4(48,44,48,44)
	if OS.has_feature("mobile"):
		var window := Rect2(DisplayServer.window_get_position(),DisplayServer.window_get_size())
		margins = mobile_margins(screen.size,window,Rect2(DisplayServer.get_display_safe_area()))
	if max_width > 0:
		var extra := maxf(0,(screen.size.x-margins.x-margins.z-max_width)/2)
		margins.x += extra
		margins.z += extra
	layout.offset_left = margins.x
	layout.offset_top = margins.y
	layout.offset_right = -margins.z
	layout.offset_bottom = -margins.w
