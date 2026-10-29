class_name WeaponStats
## Every weapon's numbers in one place. Edit values here to rebalance.
## Distances in meters, speeds in m/s (1 m = 32 units, so 31.25 m/s = 1000 ups),
## times in seconds. clip 0 = no reload (fires straight from reserve, like
## TFC nailguns). reserve -1 = unlimited.

enum Kind { ROCKET_LAUNCHER, SHOTGUN, NAILGUN, SUPER_NAILGUN, GRENADE_LAUNCHER, PIPEBOMB_LAUNCHER, MEDKIT }

const DATA := {
	Kind.ROCKET_LAUNCHER: {
		"name": "ROCKETS", "clip": 4, "reserve": 20, "interval": 0.8,
		"reload_first": 0.92, "reload_each": 0.8,
		"speed": 31.25, "damage": 100.0, "radius": 5.0, "knockback": 0.25, "self_scale": 0.5,
		"view": [Color(0.25, 0.32, 0.22), 0.07, 0.75],
	},
	Kind.SHOTGUN: {
		"name": "SHOTGUN", "clip": 8, "reserve": 40, "interval": 0.5,
		"reload_first": 0.75, "reload_each": 0.5,
		"pellets": 6, "damage": 6.0, "spread_deg": 4.0, "range": 100.0, "knockback": 0.25,
		"view": [Color(0.35, 0.35, 0.38), 0.03, 0.7],
	},
	Kind.NAILGUN: {
		"name": "NAILGUN", "clip": 0, "reserve": 200, "interval": 0.1,
		"speed": 31.25, "damage": 9.0, "knockback": 0.1,
		"view": [Color(0.55, 0.5, 0.3), 0.045, 0.55],
	},
	Kind.SUPER_NAILGUN: {
		"name": "SUPER NAILGUN", "clip": 0, "reserve": 150, "interval": 0.1,
		"speed": 31.25, "damage": 12.0, "knockback": 0.1,
		"view": [Color(0.6, 0.45, 0.25), 0.06, 0.6],
	},
	Kind.GRENADE_LAUNCHER: {
		"name": "GRENADES", "clip": 6, "reserve": 30, "interval": 0.6,
		"reload_first": 1.0, "reload_each": 0.6,
		"speed": 18.75, "pitch_up_deg": 6.0, "fuse": 2.5, "damage": 100.0, "radius": 5.0,
		"knockback": 0.25, "self_scale": 0.5,
		"view": [Color(0.2, 0.25, 0.4), 0.065, 0.55],
	},
	Kind.PIPEBOMB_LAUNCHER: {
		"name": "PIPE BOMBS", "clip": 6, "reserve": 30, "interval": 0.6,
		"reload_first": 1.0, "reload_each": 0.6,
		"speed": 18.75, "pitch_up_deg": 6.0, "damage": 90.0, "radius": 5.0,
		# self_scale: a pipe at your feet costs ~45 HP, so a 200 HP Demoman
		# gets 4 pipe jumps and the 5th kills him. arm_time: seconds after
		# firing before a pipe can be detonated.
		"knockback": 0.25, "self_scale": 0.66, "max_active": 8, "arm_time": 0.25,
		"view": [Color(0.15, 0.4, 0.25), 0.065, 0.55],
	},
	Kind.MEDKIT: {
		"name": "MEDKIT", "clip": 0, "reserve": -1, "interval": 0.4,
		"range": 1.8, "heal": 25.0, "damage": 9.0,
		"view": [Color(0.9, 0.9, 0.9), 0.09, 0.25],
	},
}


static func get_stat(kind: int, key: String) -> Variant:
	return DATA[kind][key]
