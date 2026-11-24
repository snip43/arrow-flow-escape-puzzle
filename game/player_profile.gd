extends "res://game/campaign_session.gd"

const Economy := preload("res://game/economy.gd")
var coins := Economy.START

func restore_profile(state: Dictionary) -> bool:
	var balance = state.get("coins")
	if not balance is int or balance < 0 or balance > Economy.LIMIT or not restore(state.get("count")):
		return false
	coins = balance
	return true

func first_clear(id: int, perfect: bool) -> Dictionary:
	if not record_completion(id): return {}
	var levels := preload("res://game/level_metrics.gd")
	var tier: String = levels.TIERS[levels.tier(id)]
	var base := mini(Economy.BASE[tier],Economy.LIMIT-coins)
	var bonus := mini(Economy.PERFECT,Economy.LIMIT-coins-base) if perfect and id>1 else 0
	coins += base + bonus
	return {"base":base,"bonus":bonus}
