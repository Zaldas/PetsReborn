-- modules/maneuverBurden.lua
-- Pure model of PUP maneuver burden and the derived Overload countdown.
--
-- Nothing here computes an overload chance. The server volunteers the exact figure
-- in the 0x0028 action packet and this model only stamps and decays it, which keeps
-- the display immune to OVERLOAD_THRESH gear and to the per-maneuver burden add.
--
-- The module touches no Ashita API, no globals and no clock of its own: advance()
-- takes the time and the inputs the decay rate depends on, every other method is
-- time-free. Each ManeuverBurden.new() call produces fully independent instance state.

local ELEMENT_COUNT = 8

-- Burden decays once per server regen tick, and that tick is 3 seconds
-- (zone_entities.cpp:2154). The tick is a zone-wide clock, not aligned to any stamp,
-- so the first decay after a stamp lands anywhere in (0, 3s]. advance() counts whole
-- ticks from its own anchor and so undercounts by at most one, which over-reports --
-- the safe direction.
local DECAY_SECONDS = 3

-- Heatsink's BURDEN_DECAY contribution, indexed by active WATER maneuvers -- an
-- attachment scales with its own element only, and Heatsink holds a Water slot. Measured
-- in game; Horizon matches neither base LSB ({2,4,5,6}) nor the era module
-- ({1,1,1,1}). No other source exists -- no item grants the mod, and Tactical
-- Processor's OVERLOAD_THRESH lands on the pet, where addBurden never reads it.
local HEATSINK_DECAY = { [0] = 0, [1] = 1, [2] = 2, [3] = 3 }

-- Server floor: clamp(1 + mods, 1, burden) can never shed less than 1 per tick.
local BASE_DECAY = 1

-- An automaton spawns with burden in every element, not 0, so Overload is in reach on
-- the very first maneuver. Horizon seeds 30, not the 35 of
-- scripts/globals/pets/automaton.lua:616-620 -- measured across three Activate/first-
-- maneuver pairs with the burden adds pinned from the same logs (water 20, light 19).
--
-- Displayed spawn chance is seed - thresh + 5, i.e. 35 - thresh, and only the
-- difference is observable: threshold gear would shift it the same way a seed change
-- does. This constant is the no-gear value; +5 threshold gear makes the truth 0, which
-- this over-reports -- the safe direction, and it drains within 15s either way. The
-- four items carrying the mod at this era are PUP. Dastanas (14930/15030) and
-- Buffoon's Collar (16281/16282).
local SPAWN_PCT = 5

-- Deus Ex Automata seeds far higher, so every element sits a single maneuver from a
-- near-certain Overload for the ~4 minutes it takes to drain. Horizon-only: base LSB
-- seeds both summons from the same spawnPet path.
--
-- Bracketed, not pinned. Three DEA/first-maneuver pairs share the one unknown seed: two
-- Light give seed + lightAdd = 99-100, one Dark on a Stormwaker frame gives
-- seed + darkAdd = 94-95. LSB's flat Dark add for that frame is 14 and Horizon runs its
-- other branch 2 high, so darkAdd is 14 or 16 and the seed is 79-81.
local DEA_SPAWN_PCT = 80

-- With thresh = 30 + OVERLOAD_THRESH, the server sets the Overload duration to
-- burden - thresh and reports the chance as burden - thresh + 5. thresh cancels
-- between the two, so the countdown is the reported pct minus 5 whatever
-- OVERLOAD_THRESH gear is worn. Confirmed against 72 logged overloads.
local OVERLOAD_OFFSET = 5

local ManeuverBurden = {}

ManeuverBurden.DECAY_SECONDS   = DECAY_SECONDS
ManeuverBurden.SPAWN_PCT       = SPAWN_PCT
ManeuverBurden.DEA_SPAWN_PCT   = DEA_SPAWN_PCT
ManeuverBurden.OVERLOAD_OFFSET = OVERLOAD_OFFSET
ManeuverBurden.BASE_DECAY      = BASE_DECAY

-- Burden points shed per tick. Heatsink scales with the live Water Maneuver count, so
-- the rate changes as water maneuvers are fired and expire -- which is why decay is
-- integrated by advance() rather than derived from the age of a stamp.
function ManeuverBurden.decayRate(heatsinkEquipped, waterManeuvers)
    if not heatsinkEquipped then
        return BASE_DECAY
    end

    local count = waterManeuvers or 0
    if count < 0 then
        count = 0
    elseif count > 3 then
        count = 3
    end

    return BASE_DECAY + HEATSINK_DECAY[count]
end

function ManeuverBurden.new()
    -- Allocated once per instance and mutated in place: all 8 entries are read every
    -- frame, so no method may allocate.
    local burden = {}
    for i = 1, ELEMENT_COUNT do
        burden[i] = { pct = 0, decayAt = 0 }
    end

    -- Total burden points shed since this instance started counting. Decay is
    -- identical across all eight elements, so one counter serves them all and an entry
    -- only needs the value it was stamped against.
    local decayTotal = 0
    local tickAnchor = nil

    local overloadExpiry = nil

    local self = {}

    self.DECAY_SECONDS   = DECAY_SECONDS
    self.SPAWN_PCT       = SPAWN_PCT
    self.DEA_SPAWN_PCT   = DEA_SPAWN_PCT
    self.OVERLOAD_OFFSET = OVERLOAD_OFFSET

    -- Advances the shared decay counter by the whole ticks elapsed since the last
    -- call. The anchor moves by whole ticks only, so the remainder carries forward
    -- instead of being lost to rounding on every frame.
    --
    -- The rate is sampled per call, not per tick, so a water maneuver gained or lost
    -- inside one call's gap is charged at the new rate for that whole gap. Called once
    -- per frame, that gap is a frame.
    function self.advance(now, heatsinkEquipped, waterManeuvers)
        if not now then return end

        if tickAnchor == nil then
            tickAnchor = now
            return
        end

        local elapsed = now - tickAnchor
        if elapsed < 0 then
            tickAnchor = now
            return
        end

        local ticks = math.floor(elapsed / DECAY_SECONDS)
        if ticks > 0 then
            decayTotal = decayTotal + ticks * ManeuverBurden.decayRate(heatsinkEquipped, waterManeuvers)
            tickAnchor = tickAnchor + ticks * DECAY_SECONDS
        end
    end

    -- Drops the tick anchor so the next advance() re-anchors without charging the gap.
    -- Called while no automaton is owned: the server is not decaying a burden array
    -- that does not exist, and a confirmed Activate reseeds every element anyway.
    function self.resetClock()
        tickAnchor = nil
    end

    -- Last stamped value less the decay charged since it was stamped, clamped at 0.
    function self.displayPct(index)
        local entry = burden[index]
        if not entry then return 0 end
        if entry.pct <= 0 then return 0 end

        local pct = entry.pct - (decayTotal - entry.decayAt)
        if pct < 0 then return 0 end
        return pct
    end

    -- Server truth: replaces the stored value outright.
    -- Not capped at 100 -- the server clamps the reported chance to 0..255, so values
    -- above 100 are real and capping would discard them.
    function self.stamp(index, pct)
        local entry = burden[index]
        if not entry or not pct then return end
        if pct < 0 then pct = 0 end

        entry.pct     = pct
        entry.decayAt = decayTotal
    end

    -- Sets every element to baselinePct (0 when omitted), anchored against the decay
    -- charged so far so the baseline decays from here rather than from zero.
    function self.resetAll(baselinePct)
        local pct = baselinePct or 0
        if pct < 0 then pct = 0 end

        for i = 1, ELEMENT_COUNT do
            local entry = burden[i]
            entry.pct     = pct
            entry.decayAt = decayTotal
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
