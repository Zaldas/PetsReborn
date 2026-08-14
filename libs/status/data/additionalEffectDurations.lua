-- PetsReborn: Additional effect status durations (keyed by status effect ID)
-- Used when a status is applied via ability.AdditionalEffect (bolt/arrow procs,
-- weapon En-spell procs, etc.) where no spell ID is available for lookup.
--
-- Weapon skill secondary effects (Armor Break, Shield Break, etc.) go through
-- the main ability.Message path and are handled by spellToExpiry instead.
--
-- Sources:
--   BG Wiki   https://www.bg-wiki.com/ffxi/Defense_Down
--             https://www.bg-wiki.com/ffxi/Attack_Down
--   LSB       scripts/globals/additional_effects.lua
--             scripts/enum/effect.lua (status IDs)

return {
    -- ── Stat-down ammo procs (60s confirmed, BG Wiki) ─────────────────────
    -- Acid Bolt / Gashing Bolt / Abrasion Bolt → Defense Down
    [149] = 60,   -- Defense Down

    -- Demon Arrow → Attack Down
    [147] = 60,   -- Attack Down

    -- Acid Arrow / similar → Evasion Down (same duration class as bolt procs)
    [148] = 60,   -- Evasion Down

    -- ── Sleep ammo (Sleep Arrow / Sleep Bolt) ─────────────────────────────
    -- Ammo: item_mods ITEM_ADDEFFECT_DURATION=25 for both sleep_bolt (18149) and sleep arrow (16497).
    -- Mob melee AE: xi.mob.ae.SLEEP maxDuration=45s — but mob sleep AE is rare; 25 is accurate for ammo.
    [2]   = 25,   -- Sleep I  [ammo: 25s fixed; mob melee AE max is 45 — accept underestimate for rare case]

    -- ── Bind ammo ─────────────────────────────────────────────────────────
    [11]  = 90,   -- Bind            [mobs.lua xi.mob.ae.BIND maxDuration: 90s; bind arrows also in range]

    -- ── Blood pact physical additional effects ─────────────────────────────
    -- Carbuncle: Poison Nails → Poison (if addStatusEffect comes through as AdditionalEffect)
    [3]   = 30,   -- Poison          [mobs.lua xi.mob.ae.POISON maxDuration: 30s; Poison Nails: 60s — see abilityDurations]

    -- ── Mob melee additional effects (xi.mob.ae table from mobs.lua) ──────
    -- Applied when a mob has ADD_EFFECT set and lands a standard melee hit.
    -- All durations use maxDuration from mobs.lua so the bar doesn't expire early.
    -- Note: statusIds here may also be triggered by ammo procs — values are compatible unless noted.
    [4]   = 30,   -- Paralysis       [no xi.mob.ae entry; observed from ammo/mob scripts; 30s]
    [5]   = 30,   -- Blindness       [blind arrow item_mods: 30s; no xi.mob.ae entry]
    [6]   = 30,   -- Silence         [mobs.lua xi.mob.ae.SILENCE maxDuration: 30s; silence arrow: 30s]
    [7]   = 45,   -- Petrification   [mobs.lua xi.mob.ae.PETRIFY maxDuration: 45s]
    [9]   = 300,  -- Curse I         [Temenos/Dark_Elemental_E.lua: duration=300; no xi.mob.ae entry]
    [10]  = 5,    -- Stun            [mobs.lua xi.mob.ae.STUN duration: 5s (no maxDuration)]
    [12]  = 45,   -- Weight          [mobs.lua xi.mob.ae.WEIGHT maxDuration: 45s]
    [13]  = 45,   -- Slow            [mobs.lua xi.mob.ae.SLOW maxDuration: 45s]
    [16]  = 30,   -- Amnesia         [mobs.lua xi.mob.ae.ENAMNESIA maxDuration: 30s]
    [28]  = 5,    -- Terror          [mobs.lua xi.mob.ae.TERROR duration: 5s (no maxDuration)]
    [31]  = 60,   -- Plague          [mobs.lua xi.mob.ae.PLAGUE maxDuration: 60s]
}
