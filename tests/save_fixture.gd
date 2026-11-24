extends RefCounted

const Store := preload("res://game/save_store.gd")
const PREFIX := "af_test_"

static func unique_name() -> String:
	return PREFIX + Crypto.new().generate_random_bytes(16).hex_encode()

static func valid(name: String) -> bool:
	var suffix := name.trim_prefix(PREFIX)
	return name.begins_with(PREFIX) and suffix.length()==32 and suffix.is_valid_hex_number(false)

static func make_store() -> Store:
	return Store.new(unique_name())

static func clean(store: Store) -> bool:
	if not valid(store.directory.get_file()) or store.directory.get_base_dir()!="user://": return false
	if not DirAccess.dir_exists_absolute(store.directory): return true
	for file in DirAccess.get_files_at(store.directory):
		if DirAccess.remove_absolute(store.directory.path_join(file))!=OK: return false
	return DirAccess.remove_absolute(store.directory)==OK
