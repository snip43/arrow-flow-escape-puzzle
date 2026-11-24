extends RefCounted

const Catalog := preload("res://levels/level_catalog.gd")
const Model := preload("res://game/board_model.gd")
const Economy := preload("res://game/economy.gd")
const CATALOG_ID := "5401de5a357fba34ca8e0c2c03c78a1431dcc46ecf0929ab827416f4255d14ff"
static var catalog_digest := ""

static func catalog_id() -> String:
	if catalog_digest.is_empty(): catalog_digest = FileAccess.get_sha256(Catalog.FILE)
	return catalog_digest

var catalog := Catalog.new()
var levels := {}

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and low<=value and value<=high and floor(value)==value

# Decode only stable states. Rebuild occupancy from the trusted catalogue.
func decode(value: Dictionary, count: int) -> Dictionary:
	if value.size()!=11 or value.get("catalog")!=CATALOG_ID or catalog_id()!=CATALOG_ID: return {}
	if not integer(value.get("level"),2,mini(100,count+1)): return {}
	if not integer(value.get("errors"),0,2147483647) or not integer(value.get("lives"),0,Economy.ATTEMPT_LIVES): return {}
	var level := int(value.level)
	var errors := int(value.errors)
	var lives := int(value.lives)
	if errors<Economy.ATTEMPT_LIVES and lives!=Economy.ATTEMPT_LIVES-errors: return {}
	if errors>=Economy.ATTEMPT_LIVES and lives>Economy.CONTINUE_LIVES: return {}
	if value.get("state")!=("failed" if lives==0 else "active"): return {}
	if value.get("origin") not in ["menu","levels"] or value.get("kind") not in ["hint","continue"]: return {}
	var op = value.get("operation")
	if not op is String or op.length()!=32 or not op.is_valid_hex_number(false) or op.begins_with("-") or op.begins_with("+") or op!=op.to_lower(): return {}
	if not value.get("used_hint") is bool or not value.get("hint") is String: return {}
	if value.kind=="hint" and not value.used_hint: return {}
	if value.kind=="continue" and (errors<Economy.ATTEMPT_LIVES or value.hint!=""): return {}
	if not value.get("removed") is Array or value.removed.size()>100: return {}
	if not levels.has(level): levels[level] = catalog.get_level(level)
	var data: Dictionary = levels[level]
	if data.has("error") or value.removed.size()>=data.paths.size(): return {}
	var board := Model.new()
	if not board.load_level(data.size,data.paths): return {}
	for id in value.removed:
		if not id is String or not board.remove(id): return {}
	if lives==0 and board.ids().all(func(id): return board.can_exit(id)): return {}
	if value.hint!="":
		if lives==0 or not board.can_exit(value.hint): return {}
		var remaining := board.ids()
		remaining.sort()
		for id in remaining:
			if board.can_exit(id):
				if value.hint!=id: return {}
				break
	if value.kind=="hint" and value.hint=="" and lives>0 and value.removed.is_empty(): return {}
	var normalized := value.duplicate(true)
	normalized.level = level
	normalized.errors = errors
	normalized.lives = lives
	return normalized
