-- PetsReborn: Job ability buff durations (HorizonXI values)
-- Maps ability ID (action.Param for type-6 JA packets) → duration in seconds.
-- Kept separate from spellDurations because ability IDs and spell IDs
-- share the same action.Param field but occupy different ID spaces; some IDs
-- overlap (e.g. ability 51 = Last Resort, spell 51 = Shell IV).

return {
    -- ── Beastmaster ───────────────────────────────────────────────────────
    -- Ability 52 (LSB abilities.sql: Charm) also fires as a type-6 JA from the Morrigan trust,
    -- applying BIND (11) to the target mob.
    [52]  = 60,   -- Charm      → BIND (11) from Morrigan trust, 60s est.

    -- ── Monk ──────────────────────────────────────────────────────────────
    [39]  = 180,  -- Boost      (HorizonXI: 3 min, buff 45)
    [37]  = 180,  -- Dodge      (HorizonXI: 3 min, buff 60)

    -- ── Dark Knight ───────────────────────────────────────────────────────
    [51]  = 60,   -- Last Resort (HorizonXI: doubled 30→60s, buff 64)

    -- ── Corsair ───────────────────────────────────────────────────────────
    [131] = 90,   -- Light Shot → SLEEP_I (2), 90s pre-resist [era corsair.lua: 90 * resist]
}
-- NOTE: Shield Bash (46), Weapon Bash (77), and Shadowbind (57) are NOT declared here —
-- LSB abilities.sql confirms they fire as action.Type==3, not 6, so this table's type-6
-- gate never sees them. They live in physicalJaDebuffs instead.
-- Crimson Howl (548, SMN/Ifrit) is also not declared here — it's an avatar pact and is
-- tracked via wardBuffDurations (type-13 path), which is the one that actually fires.
