-- Weapon skill debuffs applied on hit (action type 3, damage message). Keyed by weapon skill
-- ID (action.Param). Type 3 carries both weapon skills and the physical JAs, but the two key
-- sets do not overlap, so physicalJaDebuffs and this table are looked up independently.
-- Applied only when ability.Param (damage) > 0, so a miss leaves no timer.

return {
    [83]  = { statusId  = 149, duration = 180 },          -- Armor Break     → Defense Down
    [181] = { statusId  = 149, duration = 180 },          -- Shell Crusher   → Defense Down
    [85]  = { statusId  = 147, duration = 180 },          -- Weapon Break    → Attack Down
    [87]  = { statusIds = { 149, 147 }, duration = 180 }, -- Full Break      → Defense + Attack Down
    [80]  = { statusId  = 148, duration = 180 },          -- Shield Break    → Evasion Down
    [107] = { statusId  = 147, duration = 180 },          -- Infernal Scythe → Attack Down
    [35]  = { statusId  = 10,  duration = 5   },          -- Flat Blade      → Stun
    [115] = { statusId  = 10,  duration = 5   },          -- Leg Sweep       → Stun
    [145] = { statusId  = 10,  duration = 5   },          -- Tachi: Hobaku   → Stun
    [162] = { statusId  = 10,  duration = 5   },          -- Brainshaker     → Stun
    [2]   = { statusId  = 10,  duration = 5   },          -- Shoulder Tackle → Stun
    [65]  = { statusId  = 10,  duration = 5   },          -- Smash Axe       → Stun
    [16]  = { statusId  = 3,   duration = 90  },          -- Wasp Sting      → Poison
    [17]  = { statusId  = 3,   duration = 90  },          -- Viper Bite      → Poison
    [18]  = { statusId  = 11,  duration = 30  },          -- Shadowstitch    → Bind
}
