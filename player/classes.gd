class_name PlayerClasses
## The four classes. Flat health (no armor), TFC speeds and loadouts.
## Edit values here to rebalance. Speeds in ups (1 m = 32 units).

enum Id { SCOUT, SOLDIER, MEDIC, DEMOMAN }

const W := WeaponStats.Kind

const DATA := {
	Id.SCOUT: {
		"name": "Scout", "health": 125, "speed_ups": 400,
		"weapons": [W.NAILGUN, W.SHOTGUN], "frags": 0, "concs": 4,
		"blurb": "Fastest. Concs, nailgun, shotgun.",
	},
	Id.SOLDIER: {
		"name": "Soldier", "health": 250, "speed_ups": 240,
		"weapons": [W.ROCKET_LAUNCHER, W.SHOTGUN], "frags": 4, "concs": 0,
		"blurb": "Toughest, slowest. Rockets, shotgun, frags.",
	},
	Id.MEDIC: {
		"name": "Medic", "health": 175, "speed_ups": 320,
		"weapons": [W.SUPER_NAILGUN, W.SHOTGUN, W.MEDKIT], "frags": 4, "concs": 4,
		"blurb": "Heals teammates. Super nailgun, shotgun, concs.",
	},
	Id.DEMOMAN: {
		"name": "Demoman", "health": 200, "speed_ups": 280,
		"weapons": [W.GRENADE_LAUNCHER, W.PIPEBOMB_LAUNCHER, W.SHOTGUN], "frags": 4, "concs": 0,
		"blurb": "Area denial. Grenade launcher, pipe bombs (Mouse 5 detonates).",
	},
}

const TEAM_NAMES := ["Red", "Blue"]
const TEAM_COLORS := [Color(0.85, 0.25, 0.2), Color(0.25, 0.45, 0.9)]


static func stat(id: int, key: String) -> Variant:
	return DATA[id][key]
