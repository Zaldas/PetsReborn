-- modules/maneuverBurden.lua
-- Pure model of PUP maneuver burden and the derived Overload countdown.
--
-- Nothing here computes an overload chance. The server volunteers the exact figure
-- in the 0x0028 action packet and this model only stamps and decays it, which keeps
-- the display immune to OVERLOAD_THRESH gear and to the per-maneuver burden add.
--
-- The module touches no Ashita API, no globals and no clock of its own: every method
-- that needs the time takes `now` as a parameter. Each ManeuverBurden.new() call
-- produces fully independent instance state.

local ELEMENT_COUNT = 8

-- Burden regenerates 1 point per server regen tick, and that tick is 3 seconds.
-- BURDEN_DECAY gear on the master or the automaton decays it faster than 1 per tick
-- and is invisible to this model, so a decayed value over-reports while such gear is
-- worn. Known limitation, not a wrong constant.
local DECAY_SECONDS = 3

-- An automaton spawns with 35 burden in every element, not 0
-- (`scripts/globals/pets/automaton.lua:616-618`; era's onMobSpawn override calls
-- super first, so the seed is live). Overload is therefore in reach on the very first
-- maneuver.
--
-- Displayed spawn chance is `35 - thresh + 5`, i.e. `10 - OVERLOAD_THRESH`. Unlike
-- OVERLOAD_OFFSET, thresh does not cancel here, so this constant encodes the no-gear
-- default only: +5 threshold gear makes the truth 5 (this over-reports, the safe
-- direction), Tactical Processor's -5 makes it 15 (this under-reports). The client
-- cannot read OVERLOAD_THRESH, so seeded entries are flagged estimated.
local SPAWN_PCT = 10

-- Upper bounds on a single maneuver's burden add. Used only during Overdrive, where
-- OVERLOAD_THRESH +5000 makes the server's reported chance a known-useless 0%.
local WORST_ADD      = 20
local WORST_ADD_DARK = 14

-- With `thresh = 30 + OVERLOAD_THRESH`, the server sets the Overload duration to
-- `burden - thresh` and reports the chance as `burden - thresh + 5`. thresh cancels
-- between the two, so the countdown is the reported pct minus 5 whatever
-- OVERLOAD_THRESH gear is worn.
local OVERLOAD_OFFSET = 5

local ManeuverBurden = {}

ManeuverBurden.DECAY_SECONDS   = DECAY_SECONDS
ManeuverBurden.SPAWN_PCT       = SPAWN_PCT
ManeuverBurden.WORST_ADD       = WORST_ADD
ManeuverBurden.WORST_ADD_DARK  = WORST_ADD_DARK
ManeuverBurden.OVERLOAD_OFFSET = OVERLOAD_OFFSET

function ManeuverBurden.new()
    -- Allocated once per instance and mutated in place: all 8 entries are read every
    -- frame, so no method may allocate.
    local burden = {}
    for i = 1, ELEMENT_COUNT do
        burden[i] = { pct = 0, stampedAt = 0, estimated = false }
    end

    local overloadExpiry = nil

    local self = {}

    self.DECAY_SECONDS   = DECAY_SECONDS
    self.SPAWN_PCT       = SPAWN_PCT
    self.WORST_ADD       = WORST_ADD
    self.WORST_ADD_DARK  = WORST_ADD_DARK
    self.OVERLOAD_OFFSET = OVERLOAD_OFFSET

    -- Last stamped value decayed to `now`, clamped at 0.
    function self.displayPct(index, now)
        local entry = burden[index]
        if not entry or not now then return 0 end
        if entry.pct <= 0 then return 0 end

        local elapsed = now - entry.stampedAt
        if elapsed < 0 then elapsed = 0 end

        local pct = entry.pct - math.floor(elapsed / DECAY_SECONDS)
        if pct < 0 then return 0 end
        return pct
    end

    -- Server truth: replaces the stored value outright and drops the estimate flag.
    -- Not capped at 100 -- the server clamps the reported chance to 0..255, so values
    -- above 100 are real and capping would discard them.
    function self.stamp(index, pct, now)
        local entry = burden[index]
        if not entry or not pct or not now then return end
        if pct < 0 then pct = 0 end

        entry.pct       = pct
        entry.stampedAt = now
        entry.estimated = false
    end

    -- Adds to the current decayed value, so consecutive Overdrive maneuvers
    -- accumulate rather than overwrite each other.
    function self.stampEstimated(index, addValue, now)
        local entry = burden[index]
        if not entry or not addValue or not now then return end

        local pct = self.displayPct(index, now) + addValue
        if pct < 0 then pct = 0 end

        entry.pct       = pct
        entry.stampedAt = now
        entry.estimated = true
    end

    function self.isEstimated(index)
        local entry = burden[index]
        return entry ~= nil and entry.estimated
    end

    -- Sets every element to `baselinePct` (0 when omitted), anchored at `now`.
    -- `now` is required for any non-zero baseline: an unanchored one decays from the
    -- epoch, so displayPct clamps it to 0 on the first read and the seed does nothing.
    -- A missing `now` therefore clears to 0.
    -- The baseline is not flagged estimated. SPAWN_PCT is derived rather than server-reported,
    -- but it is the same for every element on every Activate, so the estimate marker carries no
    -- information there and only makes the first reading of a fresh automaton look uncertain.
    -- The flag stays reserved for stampEstimated, where the figure really does vary.
    function self.resetAll(now, baselinePct)
        local pct = baselinePct or 0
        if not now or pct < 0 then pct = 0 end
        local stampedAt = now or 0

        for i = 1, ELEMENT_COUNT do
            local entry = burden[i]
            entry.pct       = pct
            entry.stampedAt = stampedAt
            entry.estimated = false
        end
    end

    function self.setOverload(pct, now)
        if not pct or not now then return end
        overloadExpiry = now + pct - OVERLOAD_OFFSET
    end

    function self.overloadRemaining(now)
        if not overloadExpiry or not now then return 0 end
        local remaining = overloadExpiry - now
        if remaining < 0 then return 0 end
        return remaining
    end

    function self.clearOverload()
        overloadExpiry = nil
    end

    -- Lets callers separate "no countdown known" (addon loaded mid-Overload) from a
    -- countdown that has reached 0; the former renders as '--', the latter as 0.
    function self.hasOverloadExpiry()
        return overloadExpiry ~= nil
    end

    return self
end

return ManeuverBurden
