-- Blood pact debuffs/buffs on the pet or enemies: avatar pacts that apply status effects
-- server-side in ways the normal action packet paths cannot track.  Two sub-formats:
--
--   Physical hit path  { statusId, duration }
--     Avatar physical attack calls addStatusEffect() server-side.  Status does not appear
--     in AdditionalEffect bits.  Triggered only when ability.Param (damage) > 0 (hit
--     confirmed) and the target has no active timer (mirrors LSB hasStatusEffect check).
--
--   Message path  { messages = {[msgId]=true,...}, statuses = {[statusId]=duration,...} }
--     Avatar pact uses a custom result message (not in statusOnMes) and returns 0 from
--     the script, so ability.Param=0.  Triggered when ability.Message matches any entry
--     in messages{}; all statuses{} are applied simultaneously.
--
-- Keyed by ability ID (action.Param for type 13).

return {
    -- ── Physical hit pacts ────────────────────────────────────────────────────
    [513] = { statusId = 3,  duration = 60  },  -- Poison Nails  (Carbuncle) → Poison (3),      60s  [physical hit]
    [528] = { statusId = 5,  duration = 30  },  -- Moonlit Charge(Fenrir)    → Blindness (5),   30s  [physical hit]
    [529] = { statusId = 4,  duration = 90  },  -- Crescent Fang (Fenrir)    → Paralysis (4),   90s  [physical hit]
    [578] = { statusId = 12, duration = 120 },  -- Tail Whip     (Leviathan) → Weight (12),    120s  [physical hit, resist-scaled]
    [624] = { statusId = 10, duration = 2   },  -- Shock Strike  (Ramuh)     → Stun (10),        2s  [physical hit]
    [627] = { statusId = 4,  duration = 60  },  -- Thunderspark  (Ramuh)     → Paralysis (4),   60s  [physical hit; thunderspark.lua]
    [630] = { statusId = 10, duration = 15  },  -- Chaotic Strike(Ramuh)     → Stun (10),        3 hits × 0-5s; max 15s [horizonffxi.wiki/Chaotic_Strike]
    [657] = { statusId = 12, duration = 120 },  -- Somnolence    (Diabolos)  → Weight (12),    120s  [physical hit; somnolence.lua]
    -- ── Message-triggered pacts (custom msg, script returns 0) ────────────────
    -- Ecliptic Growl (Fenrir): msg 364/365 (STATUS_BOOST/_2) → 7 stat boosts, 180s
    [532] = { messages = {[364]=true, [365]=true}, statuses = {[80]=180, [81]=180, [82]=180, [83]=180, [84]=180, [85]=180, [86]=180} },
    -- Ecliptic Howl (Fenrir): msg 146/147 (ACC_EVA_BOOST/_2) → ACCURACY_BOOST(90) + EVASION_BOOST(92), 180s
    [533] = { messages = {[146]=true, [147]=true}, statuses = {[90]=180, [92]=180} },
}
