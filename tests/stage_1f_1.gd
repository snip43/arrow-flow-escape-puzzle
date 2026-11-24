extends SceneTree

const Layout := preload("res://ui/safe_layout.gd")

func _initialize() -> void:
	var size := Vector2(1080,1920)
	var window := Rect2(0,0,720,1280)
	var base := Vector4(48,44,48,44)
	var cases := [
		[window,window,base],
		[window,Rect2(0,60,720,1120),Vector4(48,90,48,150)],
		[Rect2(100,200,720,1280),Rect2(150,260,600,1120),Vector4(75,90,105,150)],
		[window,Rect2(),base],
		[window,Rect2(-100,-100,1000,1500),base]
	]
	var failures := 0
	for test in cases:
		var actual := Layout.mobile_margins(size,test[0],test[1])
		if not actual.is_equal_approx(test[2]):
			printerr("Expected ",test[2]," got ",actual)
			failures += 1
	print("STAGE 1F.1: ",cases.size()," safe area checks, ",failures," failures")
	quit(1 if failures else 0)
