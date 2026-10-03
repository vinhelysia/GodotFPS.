extends Resource
class_name FactionRelation

## One entry in a Faction's relation_overrides array: "towards `other_faction`,
## I feel `disposition`" — an exception to that Faction's default_disposition.

@export var other_faction: Faction
@export var disposition: Faction.Disposition = Faction.Disposition.NEUTRAL
