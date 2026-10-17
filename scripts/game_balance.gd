extends RefCounted

## Central difficulty and economy tuning for the whole game.
## Every number that controls how hard the game is lives here, so the
## difficulty curve can be adjusted in one place. Also read by the Encyclopedia.
## NOTE FOR FUTURE DEVELOPERS: Never use or put any emojis anywhere in the game.

# --- Economy -------------------------------------------------------------
const STARTING_COINS: int = 250
const STARTING_FISH: int = 2
const COST_BABY_FISH: int = 100
const COST_DUCKWEED: int = 90
const COST_ARCHER_BASE: int = 150
const COST_ARCHER_STEP: int = 75

# --- Goldfish hunger -----------------------------------------------------
const FISH_FED_MIN: float = 16.0
const FISH_FED_MAX: float = 24.0
const FISH_STARVE_TIME: float = 30.0
const FISH_COIN_INTERVAL: float = 8.0

# --- Wave timing (seconds) ----------------------------------------------
const FIRST_PEACEFUL_DURATION: float = 60.0
const PEACEFUL_BASE: float = 40.0
const PEACEFUL_MIN: float = 28.0
const CAREFUL_DURATION: float = 12.0
const ATTACK_BASE: float = 20.0
const ATTACK_PER_WAVE: float = 1.5
const ATTACK_MAX: float = 34.0

# --- Kingfisher scaling --------------------------------------------------
const BIRD_HP_BASE: float = 110.0
const BIRD_HP_PER_WAVE: float = 12.0
const BIRD_WAVES_PER_EXTRA: int = 3      # one extra bird every 3 waves
const BIRD_MAX_COUNT: int = 6
const BIRD_SPEED_PER_WAVE: float = 0.03
const BIRD_SPEED_MAX: float = 1.30
const BIRD_AGGRESSION_FULL_WAVE: int = 13  # wave where birds reach full aggression

# --- Player defense ------------------------------------------------------
const PLAYER_CLICK_DAMAGE: float = 30.0


static func peaceful_duration(wave: int) -> float:
	if wave <= 1:
		return FIRST_PEACEFUL_DURATION
	return maxf(PEACEFUL_MIN, PEACEFUL_BASE - float(wave - 2))


static func careful_duration(_wave: int) -> float:
	return CAREFUL_DURATION


static func attack_duration(wave: int) -> float:
	return minf(ATTACK_MAX, ATTACK_BASE + float(maxi(wave - 1, 0)) * ATTACK_PER_WAVE)


static func bird_count(wave: int) -> int:
	return clampi(1 + int(floorf(float(maxi(wave, 1) - 1) / float(BIRD_WAVES_PER_EXTRA))), 1, BIRD_MAX_COUNT)


static func bird_hp(wave: int) -> float:
	return BIRD_HP_BASE + float(maxi(wave - 1, 0)) * BIRD_HP_PER_WAVE


static func bird_speed(wave: int) -> float:
	return minf(BIRD_SPEED_MAX, 1.0 + float(maxi(wave - 1, 0)) * BIRD_SPEED_PER_WAVE)


## 0.0 on wave 1 (slow dives, long snatch time) up to 1.0 at the full aggression wave.
static func bird_aggression(wave: int) -> float:
	return clampf(float(maxi(wave - 1, 0)) / float(BIRD_AGGRESSION_FULL_WAVE - 1), 0.0, 1.0)


static func archer_cost(owned: int) -> int:
	return COST_ARCHER_BASE + owned * COST_ARCHER_STEP
