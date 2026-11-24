extends RefCounted

static func apply(screen: Control, layout: Control, max_width := 0.0) -> void:
	var margins := Vector4(48,44,48,44)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		if safe.has_area():
			var local := screen.get_screen_transform().affine_inverse() * Rect2(safe)
			margins = Vector4(maxf(48,local.position.x), maxf(44,local.position.y),
				maxf(48,screen.size.x-local.end.x), maxf(44,screen.size.y-local.end.y))
	if max_width > 0:
		var extra := maxf(0,(screen.size.x-margins.x-margins.z-max_width)/2)
		margins.x += extra
		margins.z += extra
	layout.offset_left = margins.x
	layout.offset_top = margins.y
	layout.offset_right = -margins.z
	layout.offset_bottom = -margins.w
