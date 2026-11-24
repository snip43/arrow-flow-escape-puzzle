extends RefCounted

const Session := preload("res://game/campaign_session.gd")
const VERSION := 1
const MAX_REVISION := 2147483647
const MAX_BYTES := 16384
const SLOTS := ["save_a.json","save_b.json"]
const FUTURE := "Newer save format. Saving is paused."
const CORRUPT := "Save damaged. Starting a fresh campaign."
const FALLBACK := "Recovered an earlier campaign save."
const CONFLICT := "Conflicting saves. Using the lower progress."
const IO_ERROR := "Save unavailable. Saving is paused."
const UNSAVED := "Progress in memory only. Save will retry."

# Validate the wire spelling too: Godot 4.3's JSON reader accepts trailing
# commas and converts numbers to double before domain validation.
const NUMBER := r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
const WS := r"[ \t\r\n]*"
var numbers := RegEx.create_from_string(NUMBER)
var v1_record: RegEx
var directory: String
var notice := ""

# A profile is one directory name, never a caller-supplied filesystem path.
func _init(profile := "arrow_flow") -> void:
	var field := WS + ":" + WS
	var campaign := '"campaign"' + field + r"\{" + WS + '"completed_count"' + field + NUMBER + WS + r"\}"
	var member := '(?:(?:"schema_version"|"revision")' + field + NUMBER + "|" + campaign + ")"
	v1_record = RegEx.create_from_string(r"\A" + WS + r"\{" + WS + member + "(?:" + WS + "," + WS + member + "){2}" + WS + r"\}" + WS + r"\z")
	if profile.is_valid_identifier():
		directory = "user://" + profile

static func whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float): return false
	return is_finite(value) and value >= low and value <= high and floor(value) == value

# A negative decimal shift is integral only if every shifted-out digit is zero.
func exact_integers(text: String) -> bool:
	for token in numbers.search_all(text):
		var parts := token.get_string().to_lower().trim_prefix("-").split("e")
		var decimal := parts[0].split(".")
		var fraction := decimal[1] if decimal.size() > 1 else ""
		var digits := (decimal[0] + fraction).lstrip("0")
		if digits.is_empty(): continue
		var exponent := 0
		if parts.size() > 1:
			var magnitude := parts[1].trim_prefix("+").trim_prefix("-").lstrip("0")
			if magnitude.length() > 5: return false
			exponent = magnitude.to_int()
			if parts[1].begins_with("-"): exponent = -exponent
		var discarded := fraction.length() - exponent
		if discarded > 0 and discarded > digits.length() - digits.rstrip("0").length():
			return false
	return true

func read_slot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"state":"io" if DirAccess.dir_exists_absolute(path) else "missing"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"state":"io"}
	var length := file.get_length()
	if length <= 0 or length > MAX_BYTES: return {"state":"invalid"}
	var bytes := file.get_buffer(length)
	if bytes.size() != length: return {"state":"io"}
	var content := bytes.get_string_from_utf8()
	if content.to_utf8_buffer() != bytes: return {"state":"invalid"}
	var parser := JSON.new()
	if parser.parse(content)!=OK or not parser.data is Dictionary: return {"state":"invalid"}
	var row: Dictionary = parser.data
	var version = row.get("schema_version")
	if not (version is int or version is float) or not is_finite(version) or floor(version)!=version:
		return {"state":"invalid"}
	# Dispatch future migrations here, before decoding a version-specific payload.
	if version > VERSION: return {"state":"future"}
	if v1_record.search(content)==null or not exact_integers(content): return {"state":"invalid"}
	if version != VERSION or not whole(row.get("revision"),1,MAX_REVISION) or not row.get("campaign") is Dictionary:
		return {"state":"invalid"}
	var count = row.campaign.get("completed_count")
	if not whole(count,0,Session.LAST): return {"state":"invalid"}
	return {"state":"valid","count":int(count),"revision":int(row.revision)}

func inspect() -> Dictionary:
	var active := -1
	var count := 0
	var revision := 0
	var blocked := ""
	var invalid := []
	var conflict := false
	for i in SLOTS.size():
		var slot := read_slot(directory.path_join(SLOTS[i]))
		match slot.state:
			"future": blocked = FUTURE
			"io":
				if blocked.is_empty(): blocked = IO_ERROR
			"invalid": invalid.append(i)
			"valid":
				if slot.revision == revision and slot.count != count:
					conflict = true
				if slot.revision > revision or (slot.revision == revision and slot.count < count):
					active = i
					revision = slot.revision
					count = slot.count
	return {"active":active,"revision":revision,"count":count,"blocked":blocked,
		"invalid":invalid,"conflict":conflict}

func restore() -> int:
	if directory.is_empty():
		notice = IO_ERROR
		return 0
	var state := inspect()
	notice = state.blocked
	if notice.is_empty():
		if state.conflict: notice = CONFLICT
		elif not state.invalid.is_empty(): notice = CORRUPT if state.active < 0 else FALLBACK
	return state.count

# Preserve exact bytes before reusing a damaged or conflicting slot. The digest
# identifies the archive and makes a retry idempotent; it is not authentication.
func archive(slot: int) -> bool:
	var src := directory.path_join(SLOTS[slot])
	var digest := FileAccess.get_sha256(src)
	if digest.is_empty(): return false
	var dst := src + "." + digest + ".bak"
	if not FileAccess.file_exists(dst) and DirAccess.copy_absolute(src,dst)!=OK: return false
	return FileAccess.get_sha256(dst)==digest

func save(count: Variant) -> bool:
	notice = UNSAVED
	if directory.is_empty() or not whole(count,0,Session.LAST): return false
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: return false
	var state := inspect()
	if not state.blocked.is_empty():
		notice = state.blocked
		return false
	if state.revision >= MAX_REVISION or count < state.count: return false
	var target := 1 if state.active == 0 else 0
	for slot in state.invalid:
		if not archive(slot): return false
	if state.conflict and not archive(target): return false
	var revision: int = state.revision + 1
	var path := directory.path_join(SLOTS[target])
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"schema_version":VERSION,"revision":revision,"campaign":{"completed_count":int(count)}}))
	file.flush()
	var wrote := file.get_error()==OK
	file.close()
	var expected := {"state":"valid","count":count,"revision":revision}
	if not wrote or read_slot(tmp)!=expected: return false
	if not publish(tmp,path) or read_slot(path)!=expected: return false
	notice = ""
	return true

func publish(tmp: String, path: String) -> bool:
	return DirAccess.rename_absolute(tmp,path)==OK
