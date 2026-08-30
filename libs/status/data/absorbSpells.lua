-- Absorb-* (dark magic). The action packet carries the drain message and the DEBUFF applied to
-- the target. The matching BOOST on the caster is applied server-side with no message and no
-- entry of its own (absorb_spell.lua: caster:addStatusEffect after the target's), so it never
-- appears unless it is modelled here. Automatons cast Absorb-INT (automaton_spells row 270),
-- which is where the missing boost is most visible.
--
-- The drain messages (329-335, 533) are NOT in statusOnMes and must not be added: their
-- ability.Param carries the drained amount, not a status ID.
--
-- LSB duration is 180 + (darkMagicSkill - 490.5) / 5, landing near 120s at 75-era skill. A
-- pet's dark magic skill is not readable, so this is an estimate -- worth measuring.
--
-- Keyed by spell ID -> { message, down = status on target, boost = status on caster }

return {
    [266] = { message = 329, down = 136, boost = 80, duration = 120 },  -- Absorb-STR  → STR Down / STR Boost
    [267] = { message = 330, down = 137, boost = 81, duration = 120 },  -- Absorb-DEX  → DEX Down / DEX Boost
    [268] = { message = 331, down = 138, boost = 82, duration = 120 },  -- Absorb-VIT  → VIT Down / VIT Boost
    [269] = { message = 332, down = 139, boost = 83, duration = 120 },  -- Absorb-AGI  → AGI Down / AGI Boost
    [270] = { message = 333, down = 140, boost = 84, duration = 120 },  -- Absorb-INT  → INT Down / INT Boost
    [271] = { message = 334, down = 141, boost = 85, duration = 120 },  -- Absorb-MND  → MND Down / MND Boost
    [272] = { message = 335, down = 142, boost = 86, duration = 120 },  -- Absorb-CHR  → CHR Down / CHR Boost
    -- Absorb-ACC (242, message 533) is WotG content and not castable at TOAU.
}
