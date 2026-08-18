-- data/petAbilities.lua
-- Static ability slot definitions per pet type.
-- id = ability recast timer ID for direct memory read via abilityrecast lib
-- displayName = shown in UI
-- isChargeAbility, maxCharges, baseSecondsPerCharge = charge-based ability config (e.g. Ready)
-- level = minimum job level required (filtered against GetMainJobLevel() for level sync support)
-- requiresPet = row is hidden while no pet is out. The pet-acquiring abilities (Activate,
--   Call Beast, Call Wyvern, Charm) stay listed either way so their recast keeps counting
--   down with the pet out. Avatar rows are deliberately ungated: SMN summons by spell, so
--   gating that list would leave the frame empty rather than shorter.
local slots = {
    avatar = {
        { id = 173, displayName = 'BP: Rage', job = 'SMN', level =  1 },
        { id = 174, displayName = 'BP: Ward', job = 'SMN', level =  1 },
        -- { id = 175, displayName = 'Elemental Siphon', job = 'SMN', level = 50 },  -- cd:05:00
        -- { id = 176, displayName = "Avatar's Favor",   job = 'SMN', level = 55 },  -- cd:05:00
        -- { id = 108, displayName = 'Apogee',           job = 'SMN', level = 70 },  -- cd:03:00
    },
    wyvern = {
        { id = 163, displayName = 'Call Wyvern', job = 'DRG', level =  1 },
        { id = 162, displayName = 'Spirit Link', job = 'DRG', level = 25, requiresPet = true },
        { id =  70, displayName = 'Steady Wing', job = 'DRG', level = 30, requiresPet = true }, -- Horizon Era+ lv30
        -- { id = 149, displayName = 'Spirit Bond',      job = 'DRG', level = 65 },  -- cd:01:00
        -- { id = 164, displayName = 'Deep Breathing',   job = 'DRG', level = 75 },  -- cd:05:00
        -- { id =  58, displayName = 'Dragon Breaker',   job = 'DRG', level = 87 },  -- cd:05:00
        -- { id = 238, displayName = 'Smiting Breath',   job = 'DRG', level = 90 },  -- cd:01:00
        -- { id = 239, displayName = 'Restoring Breath', job = 'DRG', level = 90 },  -- cd:01:00
    },
    automaton = {
        { id = 205, displayName = 'Activate',   job = 'PUP', level =  1 },
        { id = 206, displayName = 'Repair',     job = 'PUP', level = 15, requiresPet = true },
        { id = 207, displayName = 'Deploy',     job = 'PUP', level =  1, requiresPet = true },
        { id = 208, displayName = 'Deactivate', job = 'PUP', level =  1, requiresPet = true },
        { id = 209, displayName = 'Retrieve',   job = 'PUP', level = 10, requiresPet = true },
        { id = 115, displayName = 'Deus Ex Automata', job = 'PUP', level = 40 }, -- Horizon lv40
        -- { id = 214, displayName = 'Maintenance',      job = 'PUP', level = 30 },  -- cd:01:30
        -- { id = 211, displayName = 'Role Reversal',    job = 'PUP', level = 75 },  -- cd:02:00
        -- { id = 212, displayName = 'Ventriloquy',      job = 'PUP', level = 75 },  -- cd:01:00
        -- { id = 213, displayName = 'Tactical Switch',  job = 'PUP', level = 79 },  -- cd:03:00
        -- { id = 114, displayName = 'Cooldown',         job = 'PUP', level = 95 },  -- cd:05:00
    },
    jug = {
        { id = 103, displayName = 'Reward',     job = 'BST', level = 12, requiresPet = true },
        { id =  57, displayName = 'Stay',       job = 'BST', level = 15, requiresPet = true,
            isHealTimer = true, tokenKey = 'bst.stayTicks', fallback = '--' },
        { id = 104, displayName = 'Call Beast', job = 'BST', level = 23 },
        { id =  97, displayName = 'Charm',      job = 'BST', level =  1 },
        { id = 102, displayName = 'Ready',      job = 'BST', level = 25, requiresPet = true,
            isChargeAbility = true, maxCharges = 3, baseSecondsPerCharge = 45 },
        -- { id = 107, displayName = 'Snarl',            job = 'BST', level = 45 },  -- cd:00:30
        -- { id = 105, displayName = 'Feral Howl',       job = 'BST', level = 75 },  -- cd:05:00
        -- { id = 106, displayName = 'Killer Instinct',  job = 'BST', level = 75 },  -- cd:05:00
        -- { id =  45, displayName = 'Spur',             job = 'BST', level = 83 },  -- cd:03:00
        -- { id =  46, displayName = 'Run Wild',         job = 'BST', level = 93 },  -- cd:15:00
    },
    charm = {
        { id = 103, displayName = 'Reward',     job = 'BST', level = 12, requiresPet = true },
        { id =  57, displayName = 'Stay',       job = 'BST', level = 15, requiresPet = true,
            isHealTimer = true, tokenKey = 'bst.stayTicks', fallback = '--' },
        { id = 104, displayName = 'Call Beast', job = 'BST', level = 23 },
        { id =  97, displayName = 'Charm',      job = 'BST', level =  1 },
        { id = 102, displayName = 'Sic',        job = 'BST', level = 25, requiresPet = true },
        -- { id = 107, displayName = 'Snarl',            job = 'BST', level = 45 },  -- cd:00:30
        -- { id = 105, displayName = 'Feral Howl',       job = 'BST', level = 75 },  -- cd:05:00
        -- { id = 106, displayName = 'Killer Instinct',  job = 'BST', level = 75 },  -- cd:05:00
        -- { id =  45, displayName = 'Spur',             job = 'BST', level = 83 },  -- cd:03:00
        -- { id =  46, displayName = 'Run Wild',         job = 'BST', level = 93 },  -- cd:15:00
    },
}
return slots
