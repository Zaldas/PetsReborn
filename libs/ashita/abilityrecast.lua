-- ashita/abilityrecast.lua
-- Direct memory reader for ability recast timers.
-- Uses the same memory scanning approach as the PetMe / XIUI addons.
--
-- Ashita's built-in GetAbilityTimer(index) is a direct array lookup that
-- does NOT match by timer ID. This scanner instead walks the 31 active
-- recast slots and finds the one whose stored timer ID matches.

local M = {}

local abilityRecastPtr = nil  -- cached once per session

-- Locate the recast structure via pattern scan in FFXiMain.dll.
local function initPointer()
    if abilityRecastPtr ~= nil then return true end

    local ptr = ashita.memory.find(
        'FFXiMain.dll', 0,
        '894124E9????????8B46??6A006A00508BCEE8',
        0x19, 0)

    if ptr == 0 then return false end

    ptr = ashita.memory.read_uint32(ptr)
    if ptr == 0 then return false end

    abilityRecastPtr = ptr
    return true
end

-- Returns the raw recast timer (1/60th-second units) for the given timer ID,
-- or 0 if the slot is not active (ability is ready).
-- Scans up to 31 active recast slots.
function M.getTimer(timerId)
    if not timerId then return 0 end
    if not initPointer() then return 0 end

    for i = 1, 31 do
        local slotId = ashita.memory.read_uint8(abilityRecastPtr + (i * 8) + 3)
        if slotId == timerId then
            return ashita.memory.read_uint32(abilityRecastPtr + (i * 4) + 0xF8)
        end
    end

    return 0  -- not in active slots = ability is ready
end

-- Returns both the modifier (int16) and raw recast (uint32) for a timer ID.
-- modifier adjusts the base recast for merit-upgradeable abilities (e.g. Ready).
-- Returns {modifier=0, recast=0} if the slot is not active (ability is ready).
function M.getTimerData(timerId)
    if not timerId then return { modifier = 0, recast = 0 } end
    if not initPointer() then return { modifier = 0, recast = 0 } end

    for i = 1, 31 do
        local slotId = ashita.memory.read_uint8(abilityRecastPtr + (i * 8) + 3)
        if slotId == timerId then
            local modifier = ashita.memory.read_int16(abilityRecastPtr + (i * 8) + 4)
            local recast   = ashita.memory.read_uint32(abilityRecastPtr + (i * 4) + 0xF8)
            return { modifier = modifier, recast = recast }
        end
    end

    return { modifier = 0, recast = 0 }
end

-- Reused scan tables: scanAll() runs every frame while a pet is active, so it
-- clears and repopulates these module-level tables instead of allocating fresh
-- ones per call. subTablePool holds one {modifier, recast} entry per scan slot
-- (1..31); each pass assigns at most one pooled entry per slot position.
local scanCache = {}
local subTablePool = {}
for i = 1, 31 do
    subTablePool[i] = { modifier = 0, recast = 0 }
end

-- Scans all 31 slots in one pass and returns {[timerId] = {modifier, recast}}.
-- Call once per getAbilityRecasts() invocation; use the result for O(1) lookups
-- instead of calling getTimer/getTimerData per ability (which each scan 31 slots).
-- Returns the same reused table every call — read it within the same frame;
-- do not hold a reference to it (or its sub-tables) across calls.
function M.scanAll()
    for k in pairs(scanCache) do scanCache[k] = nil end
    if not initPointer() then return scanCache end
    for i = 1, 31 do
        local slotId = ashita.memory.read_uint8(abilityRecastPtr + (i * 8) + 3)
        if slotId ~= 0 then
            local entry = subTablePool[i]
            entry.modifier = ashita.memory.read_int16(abilityRecastPtr + (i * 8) + 4)
            entry.recast   = ashita.memory.read_uint32(abilityRecastPtr + (i * 4) + 0xF8)
            scanCache[slotId] = entry
        end
    end
    return scanCache
end

-- Returns remaining seconds (floor), or 0 if ready.
function M.getSeconds(timerId)
    local raw = M.getTimer(timerId)
    if raw <= 0 then return 0 end
    return math.floor(raw / 60)
end

-- Returns true when the pointer has been successfully resolved.
function M.isReady()
    return initPointer()
end

-- Returns raw debug info for a timer ID: slot index, rawRecast, modifier, and Recast (initial).
-- Returns nil if the ability is not in the active recast list (i.e. fully ready).
function M.getDebugInfo(timerId)
    if not timerId then return nil end
    if not initPointer() then return nil end

    for i = 1, 31 do
        local slotId = ashita.memory.read_uint8(abilityRecastPtr + (i * 8) + 3)
        if slotId == timerId then
            return {
                slotIndex    = i,
                rawRecast    = ashita.memory.read_uint32(abilityRecastPtr + (i * 4) + 0xF8),
                modifier     = ashita.memory.read_int16(abilityRecastPtr + (i * 8) + 4),
                initialRecast = ashita.memory.read_uint16(abilityRecastPtr + (i * 8) + 0),
                calc1        = ashita.memory.read_uint8(abilityRecastPtr + (i * 8) + 2),
            }
        end
    end

    return nil
end

return M
