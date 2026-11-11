-- ashita/abilityrecast.lua
-- Ability recast timers from the memory manager's IRecast, looked up by timer ID.
--
-- IRecast is indexed by recast slot, not timer ID, so every lookup walks the slots and matches
-- GetAbilityTimerId. The client list holds 31 slots (0..30). Slot 0 is the one-hour slot and
-- reports timer ID 0, which is also what an empty slot reports, so only slots 1..30 are read.
-- Per slot: GetAbilityTimer is the remaining recast in 1/60-second ticks, GetAbilityCalc2 the
-- charge modifier (per-charge recast seconds for charge abilities such as Ready),
-- GetAbilityRecast the recast at the time of use, GetAbilityCalc1 a further charge value.
--
-- Contract: while M.status() is not 'ok', getTimer/getTimerData/getSeconds/scanAll return nil
-- (unknown), never 0 (ready).

local M = {}

local FIRST_SLOT = 1
local LAST_SLOT  = 30

-- Returns the IRecast object, or nil while the memory manager is unavailable.
local function getRecast()
    local memMgr = AshitaCore:GetMemoryManager()
    if memMgr == nil then return nil end
    return memMgr:GetRecast()
end

-- Availability of recast memory: 'ok' (the IRecast object is available) or 'pending'.
function M.status()
    if getRecast() == nil then return 'pending' end
    return 'ok'
end

-- Returns the raw recast timer (1/60th-second units) for the given timer ID,
-- 0 if the slot is not active (ability is ready), or nil when unavailable.
function M.getTimer(timerId)
    local recast = getRecast()
    if not recast then return nil end
    if not timerId then return 0 end

    for i = FIRST_SLOT, LAST_SLOT do
        if recast:GetAbilityTimerId(i) == timerId then
            return recast:GetAbilityTimer(i)
        end
    end

    return 0  -- not in active slots = ability is ready
end

-- Returns both the modifier (int16) and raw recast (uint32) for a timer ID.
-- modifier adjusts the base recast for merit-upgradeable abilities (e.g. Ready).
-- Returns {modifier=0, recast=0} if the slot is not active (ability is ready), or nil when
-- unavailable.
function M.getTimerData(timerId)
    local recast = getRecast()
    if not recast then return nil end
    if not timerId then return { modifier = 0, recast = 0 } end

    for i = FIRST_SLOT, LAST_SLOT do
        if recast:GetAbilityTimerId(i) == timerId then
            return { modifier = recast:GetAbilityCalc2(i), recast = recast:GetAbilityTimer(i) }
        end
    end

    return { modifier = 0, recast = 0 }
end

-- Reused scan tables: scanAll() runs every frame while a pet is active, so it
-- clears and repopulates these module-level tables instead of allocating fresh
-- ones per call. subTablePool holds one {modifier, recast} entry per slot;
-- each pass assigns at most one pooled entry per slot position.
local scanCache = {}
local subTablePool = {}
for i = FIRST_SLOT, LAST_SLOT do
    subTablePool[i] = { modifier = 0, recast = 0 }
end

-- Scans every slot in one pass and returns {[timerId] = {modifier, recast}}.
-- Call once per frame and reuse the result for O(1) lookups instead of calling
-- getTimer/getTimerData per ability (which each walk the slots).
-- Returns the same reused table every call — read it within the same frame;
-- do not hold a reference to it (or its sub-tables) across calls.
-- Returns nil when recast memory is unavailable (see M.status()).
function M.scanAll()
    for k in pairs(scanCache) do scanCache[k] = nil end
    local recast = getRecast()
    if not recast then return nil end
    for i = FIRST_SLOT, LAST_SLOT do
        local slotId = recast:GetAbilityTimerId(i)
        if slotId ~= 0 then
            local entry = subTablePool[i]
            entry.modifier = recast:GetAbilityCalc2(i)
            entry.recast   = recast:GetAbilityTimer(i)
            scanCache[slotId] = entry
        end
    end
    return scanCache
end

-- Returns remaining seconds (rounded up), 0 if ready, or nil when unavailable.
function M.getSeconds(timerId)
    local raw = M.getTimer(timerId)
    if raw == nil then return nil end
    if raw <= 0 then return 0 end
    return math.ceil(raw / 60)
end

-- Returns true when the IRecast object is available.
function M.isReady()
    return getRecast() ~= nil
end

-- Returns raw debug info for a timer ID: slot index, rawRecast, modifier, and Recast (initial).
-- Returns nil if the ability is not in the active recast list (i.e. fully ready).
function M.getDebugInfo(timerId)
    if not timerId then return nil end
    local recast = getRecast()
    if not recast then return nil end

    for i = FIRST_SLOT, LAST_SLOT do
        if recast:GetAbilityTimerId(i) == timerId then
            return {
                slotIndex     = i,
                rawRecast     = recast:GetAbilityTimer(i),
                modifier      = recast:GetAbilityCalc2(i),
                initialRecast = recast:GetAbilityRecast(i),
                calc1         = recast:GetAbilityCalc1(i),
            }
        end
    end

    return nil
end

return M
