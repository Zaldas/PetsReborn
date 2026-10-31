-- Physical JA debuffs (type 3): weapon-based player abilities that apply status effects
-- server-side via addStatusEffect(). Fire as action type 3 (not type 6), so the normal
-- abilityDurations path never fires for them.
-- Keyed by ability ID (action.Param). Applied when damage > 0 (hit confirmed).

return {
    [46] = { statusId = 10, duration = 6 },   -- Shield Bash (PLD) → STUN (10), fixed 6s
    [77] = { statusId = 10, duration = 8 },   -- Weapon Bash (DRK) → STUN (10), random 2-8s; max
    [57] = { statusId = 11, duration = 30 },  -- Shadowbind (RNG) → BIND (11), fixed 30s [LSB abilities.sql: actionType=3, not 6]
    [170] = { statusId = 149, duration = 30 }, -- Angon (DRG) → DEFENSE_DOWN (149), 15s + 15s/merit; 30s = one merit [dragoon.lua useAngon]
}
