extends SceneTree

const C := preload("res://levels/level_catalog.gd")
const Gen := preload("res://game/level_generator.gd")
const M := Gen.M
const MAX_SEEDS := 5000

func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var rows := [C.encode(1,C.tutorial())]
	var seen := {}
	for t in range(1,4):
		var selected := []
		var required := 19 if t == 1 else 40
		for attempt in MAX_SEEDS:
			var data := Gen.generate(t,t*100000+attempt)
			if data.has("error"): continue
			var key := M.signature(M.SIZES[t],data.paths)
			if seen.has(key): continue
			seen[key] = true
			selected.append(data)
			if selected.size() == required:
				print("%s: %d accepted / %d seeds" % [M.TIERS[t],required,attempt+1])
				break
		if selected.size()!=required:
			push_error("seed budget exhausted in tier %d: %d accepted" % [t,selected.size()])
			quit(1)
			return
		selected.sort_custom(func(a,b): return a.seed < b.seed if a.metrics.difficulty == b.metrics.difficulty else a.metrics.difficulty < b.metrics.difficulty)
		for data in selected: rows.append(C.encode(rows.size()+1,data))
	var payload := JSON.stringify(rows,"",true,true)+"\n"
	var parsed: Array = JSON.parse_string(payload)
	for i in parsed.size():
		var result := C.decode(i+1,parsed[i])
		if result.has("error"):
			push_error(str(i+1)+" "+result.error)
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(C.FILE.get_base_dir())
	var tmp := C.FILE+".tmp"
	var file := FileAccess.open(tmp,FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(payload)
	file.close()
	if FileAccess.get_sha256(tmp) != payload.sha256_text() or DirAccess.rename_absolute(tmp,C.FILE)!=OK:
		push_error("catalog write failed")
		quit(1)
		return
	print("catalog sha256=",payload.sha256_text()," elapsed_ms=",Time.get_ticks_msec()-started)
	quit()
