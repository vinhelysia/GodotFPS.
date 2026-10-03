extends Resource
class_name AIProfile

## Skill-level AI tuning — independent of whichever weapon is equipped AND
## independent of faction/disposition (see Faction.gd for who's hostile to
## whom). This Resource only holds "how good/alert/careful is this AI", so the
## same weapon feels different in different hands, and the same skill profile
## can be reused by NPCs of different factions.
##
## Create one .tres per skill archetype (e.g. scav_profile.tres,
## elite_profile.tres) and assign it to a HostileNPC's `ai_profile` export —
## no script changes needed, just a new profile (and optionally a different
## weapon/faction).

@export_group("Vision")
@export_range(10.0, 360.0, 1.0, "suffix:°") var fov_degrees: float = 110.0
@export var sight_range: float = 25.0
@export var eye_height: float = 1.6

@export_group("Hearing")
## Effective hearing range = sound loudness * hear_k. Higher = better ears.
@export var hear_k: float = 0.6
## In COMBAT, ignore sounds quieter than this (own footsteps/movement chatter).
@export var combat_hearing_loudness: float = 30.0

@export_group("Alertness")
## Seconds after losing sight before COMBAT decays to SUSPICIOUS.
@export var combat_hold: float = 4.0
## Loudness of the squad callout ("contact!") shouted the moment this NPC
## first enters COMBAT. Same-faction listeners within loudness*hear_k react
## (see scav_perception.gd); other factions ignore it entirely.
@export var callout_loudness: float = 35.0

@export_group("Combat Movement")
## Consecutive shots fired before the tree switches to a strafe/reposition
## beat. Keeps the fight from being a stationary shootout.
@export var strafe_after_shots: int = 2

@export_group("Detection")
## Seconds of continuous visibility to reach full detection (1.0) when the
## target is very close (near 0 m). Scales up to time_to_detect_far at
## sight_range distance.
@export var time_to_detect_close: float = 0.2
## Seconds of continuous visibility to reach full detection (1.0) when the
## target is at max sight_range.
@export var time_to_detect_far: float = 2.0
## How fast the detection accumulator (0-1) falls per second once the target
## is no longer visible.
@export var detect_decay_per_sec: float = 0.5

@export_group("Combat Skill")
## Marksmanship, 0-1. 0.0 = terrible (max spread), 1.0 = perfect (no spread).
## Converted internally to a spread magnitude: spread = max_spread * (1 - accuracy).
@export_range(0.0, 1.0, 0.01) var accuracy: float = 0.2
## Spread magnitude (~tan of deviation angle) at accuracy = 0.0 — i.e. the
## worst-case spread a 0-skill shooter has. Tune this once per weapon "class"
## feel; accuracy is what you actually dial per-faction.
@export var max_spread: float = 0.6
## One-time pause before the first shot of an engagement.
@export var reaction_delay: float = 0.3
## Multiplies the equipped weapon's cyclic rate. 1.0 = fires as fast as the gun
## allows; <1.0 = hesitant/poor trigger control (fires slower than the weapon
## is capable of); >1.0 is not physically meaningful and should be avoided.
@export_range(0.1, 1.0, 0.01) var fire_rate_skill: float = 1.0
## Seconds to reload (skill/training, independent of magazine size).
@export var reload_time: float = 2.5
## Seconds of tolerated line-of-sight loss before bailing from a shot to chase.
@export var los_grace: float = 0.4
## Extra distance tolerated past preferred_engage_range before bailing to chase.
@export var range_margin: float = 2.0
## Tactical engagement distance this AI tries to hold/fight from. Deliberately
## NOT derived from the weapon's wieldable_range (which represents max
## theoretical travel/falloff distance, not a sane in-level engagement choice).
@export var preferred_engage_range: float = 18.0

@export_group("Burst Fire")
## Rounds fired per burst before a deliberate pause (trigger discipline, not
## a full reposition — see strafe_after_shots for the larger movement beat).
@export var burst_rounds_min: int = 2
@export var burst_rounds_max: int = 4
## Seconds paused between bursts before firing the next one.
@export var burst_pause_min: float = 0.3
@export var burst_pause_max: float = 0.8


## Spread magnitude used by bt_shoot — derived from accuracy so higher always
## means "better shooter" regardless of how spread is implemented internally.
func spread() -> float:
	return max_spread * (1.0 - accuracy)
