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

# --- Goldfish mood (boredom, happiness, stress) ----------------------------
# Tank comfort = sum of decoration comfort / (alive fish x COMFORT_PER_FISH).
# 100% comfort means there is enough decoration for every fish.
const COMFORT_PER_FISH: float = 5.0
const JOY_START: float = 20.0
const JOY_GAIN_COMFORT: float = 4.0     # per second at 100% tank comfort
const JOY_GAIN_NEAR: float = 0.35       # per second per comfort point of decorations the fish is next to
const JOY_DECAY: float = 1.5            # boredom creeping in, per second
const HAPPY_AT: float = 60.0
const UNHAPPY_AT: float = 40.0
const BORED_PENALTY_TIME: float = 45.0  # bored this long -> cheaper coins (babies stop making coins)
const STRESS_PER_WITNESS: float = 30.0  # seeing a tank mate get eaten
const STRESS_SELF_ATTACKED: float = 20.0
const STRESS_WITNESS_NEAR: float = 4.5  # fish closer than this feel the full shock
const STRESSED_AT: float = 50.0
const CALM_AT: float = 20.0
const STRESS_DECAY_BASE: float = 1.0
const STRESS_DECAY_COMFORT: float = 1.5
const STRESS_DECAY_NEAR: float = 0.5    # per comfort point of a decoration the fish hides next to
const COIN_INTERVAL_HAPPY: float = 0.85
const COIN_INTERVAL_STRESSED: float = 1.6

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


# --- Difficulty -----------------------------------------------------------
# Chosen on the main menu before Endless (Engine meta "difficulty"). The tutorial always
# plays on Medium. Hard uses the base numbers above as they are.
const DIFFICULTIES: Array[String] = ["easy", "medium", "hard"]
const DIFFICULTY_NAMES := {"easy": "Easy", "medium": "Medium", "hard": "Hard"}
const PRICE_MULT := {"easy": 0.7, "medium": 1.0, "hard": 1.0}
const CAREFUL_BY_DIFFICULTY := {"easy": 20.0, "medium": 12.0, "hard": 7.0}


static func difficulty() -> String:
	if str(Engine.get_meta("game_mode", "endless")) == "tutorial":
		return "medium"
	var d := str(Engine.get_meta("difficulty", "medium"))
	return d if d in DIFFICULTIES else "medium"


static func difficulty_name() -> String:
	return String(DIFFICULTY_NAMES.get(difficulty(), "Medium"))


## Applies the difficulty discount to any base price (fish, plants, upgrades, crab, decorations).
static func price(base: int) -> int:
	if base <= 0:
		return base
	return maxi(1, int(roundf(float(base) * float(PRICE_MULT.get(difficulty(), 1.0)) / 5.0)) * 5)


## Easy: fish have no mood and are always happy.
static func moods_enabled() -> bool:
	return difficulty() != "easy"


# Mood numbers: Medium is more forgiving, Hard uses the base values above.
static func bored_limit() -> float:
	return 90.0 if difficulty() == "medium" else BORED_PENALTY_TIME


static func stress_per_witness() -> float:
	return 18.0 if difficulty() == "medium" else STRESS_PER_WITNESS


static func stress_self_attacked() -> float:
	return 12.0 if difficulty() == "medium" else STRESS_SELF_ATTACKED


static func joy_decay() -> float:
	return 1.0 if difficulty() == "medium" else JOY_DECAY


static func comfort_per_fish() -> float:
	return 3.5 if difficulty() == "medium" else COMFORT_PER_FISH


static func peaceful_duration(wave: int) -> float:
	if wave <= 1:
		return FIRST_PEACEFUL_DURATION
	return maxf(PEACEFUL_MIN, PEACEFUL_BASE - float(wave - 2))


static func careful_duration(_wave: int) -> float:
	return float(CAREFUL_BY_DIFFICULTY.get(difficulty(), CAREFUL_DURATION))


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
	return price(COST_ARCHER_BASE + owned * COST_ARCHER_STEP)
