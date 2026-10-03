extends Resource
class_name Faction

## A faction's identity + how it feels about every OTHER faction (including
## the player's faction). Generic — works for NPC-vs-player AND future
## NPC-vs-NPC combat, since disposition lookup is symmetric machinery, not a
## hardcoded "vs player" special case.
##
## Create one .tres per faction (Scav, Bear, Usec, Raider, Rogue, Ruaf, Black
## Division, Player...) under Scene/Enemies/Factions/. Assign relation
## overrides only for the exceptions — everything else falls back to
## `default_disposition`. Same faction vs itself is always FRIENDLY.

enum Disposition { HOSTILE, NEUTRAL, FRIENDLY }

@export var faction_name: String = ""
## Disposition towards any faction NOT listed in relation_overrides below.
@export var default_disposition: Disposition = Disposition.HOSTILE
## Sparse list of exceptions to default_disposition (e.g. "Bear is FRIENDLY
## towards Usec" even though default_disposition is HOSTILE).
@export var relation_overrides: Array[FactionRelation] = []


## What does THIS faction feel about `other`? Same faction (or null) = FRIENDLY.
func get_disposition_towards(other: Faction) -> Disposition:
	if other == null or other == self:
		return Disposition.FRIENDLY
	for entry in relation_overrides:
		if entry and entry.other_faction == other:
			return entry.disposition
	return default_disposition


func is_hostile_towards(other: Faction) -> bool:
	return get_disposition_towards(other) == Disposition.HOSTILE
