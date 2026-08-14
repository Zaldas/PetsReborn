-- data/maneuvers.lua
-- Static PUP maneuver data: the eight elements in ability-id order plus the shared
-- recast, buff, ability and message ids the maneuver column reads.
-- Pure data -- no Ashita calls; the lookup maps are built once at load.
--
-- name        = token/element identifier (lowercase, used by pet.maneuver[N].element)
-- displayName = shown in UI
-- abilityId   = 0x0028 action-packet ability id (cmd_arg)
-- buffId      = player status id present while the maneuver is up
-- isDark      = Dark Maneuver, whose worst-case burden add is lower than the other seven
--
-- Trap: ability id is NOT the recast id. Maneuvers are abilities 141-148 but all eight
-- share recast timer 210, and data.abilitySlots[].id elsewhere in this addon holds the
-- *recast* id (Activate is stored there as 205 though its ability id is 136).
local M = {}

M.elements = {
    { index = 1, name = 'fire',    displayName = 'Fire',    abilityId = 141, buffId = 300, isDark = false },
    { index = 2, name = 'ice',     displayName = 'Ice',     abilityId = 142, buffId = 301, isDark = false },
    { index = 3, name = 'wind',    displayName = 'Wind',    abilityId = 143, buffId = 302, isDark = false },
    { index = 4, name = 'earth',   displayName = 'Earth',   abilityId = 144, buffId = 303, isDark = false },
    { index = 5, name = 'thunder', displayName = 'Thunder', abilityId = 145, buffId = 304, isDark = false },
    { index = 6, name = 'water',   displayName = 'Water',   abilityId = 146, buffId = 305, isDark = false },
    { index = 7, name = 'light',   displayName = 'Light',   abilityId = 147, buffId = 306, isDark = false },
    { index = 8, name = 'dark',    displayName = 'Dark',    abilityId = 148, buffId = 307, isDark = true  },
}

-- O(1) lookups built once at load.
M.byAbilityId = {}
M.byBuffId    = {}
for i = 1, #M.elements do
    local element = M.elements[i]
    M.byAbilityId[element.abilityId] = element
    M.byBuffId[element.buffId]       = element
end

-- Shared maneuver recast timer: one 10s cooldown covers all eight abilities.
M.RECAST_ID      = 210
M.RECAST_SECONDS = 10

-- Concurrent-maneuver cap across all eight elements COMBINED, not per element
-- (scripts/globals/pets/automaton.lua:594). A fourth maneuver overwrites the oldest.
M.MAX_ACTIVE = 3

M.OVERLOAD_BUFF  = 299
M.OVERDRIVE_BUFF = 166

-- Activate is the only burden-reset signal. Deactivate despawns the automaton and the
-- next Activate constructs a fresh one, so it needs no counterpart here.
M.ACTIVATE_ABILITY = 136

-- 0x0028 result message ids: 798 reports the overload chance, 799 reports an overload.
M.MSG_OVERLOAD_CHANCE = 798
M.MSG_OVERLOADED      = 799

return M
