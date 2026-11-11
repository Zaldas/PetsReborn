-- state.lua
-- Shared state snapshot for PetsReborn.
-- data.lua and packets.lua write here; all rendering code reads from here via buildTokenTable().

local socket         = require('socket')
local maneuvers      = require('data/maneuvers')
local petAbilities   = require('data/petAbilities')
local ManeuverBurden = require('modules/maneuverBurden')

-- Maximum number of recast rows per pet type. Bounds the prebuilt token keys below, so a
-- layout binding any slot up to it always resolves.
local MAX_RECAST_SLOTS = petAbilities.MAX_ROWS

local MANEUVER_COUNT = #maneuvers.elements

-- Pet types that own a recast array at State[typeName].recasts; RECAST_TYPES is the same set
-- keyed by name.
local PET_TYPES = {'avatar', 'jug', 'charm', 'wyvern', 'automaton'}
local RECAST_TYPES = {}
for _, typeName in ipairs(PET_TYPES) do
    RECAST_TYPES[typeName] = true
end

-- Value of each recast token field when its slot is empty.
local RECAST_DEFAULTS = {
    name       = '',
    time       = '',
    norm       = 0,
    ready      = false,
    charges    = 0,
    maxCharges = 0,
    active     = false,
}

-- Pre-built full token key strings to avoid per-frame string concatenation.
-- PET_RECAST_KEYS[i]       = e.g. { name = 'pet.recast[1].name', ... }
-- MANEUVER_KEYS[i]         = e.g. { pct = 'pet.maneuver[1].pct', ... }
-- RECAST_ALIASES[key]      = e.g. RECAST_ALIASES['avatar.recast[1].name'] =
--                            { typeName = 'avatar', petKey = 'pet.recast[1].name', default = '' }
local PET_RECAST_KEYS = {}
local MANEUVER_KEYS = {}
local RECAST_ALIASES = {}
do
    local function buildKeys(prefix)
        return {
            name       = prefix .. '.name',
            time       = prefix .. '.time',
            norm       = prefix .. '.norm',
            ready      = prefix .. '.ready',
            charges    = prefix .. '.charges',
            maxCharges = prefix .. '.maxCharges',
            active     = prefix .. '.active',
        }
    end
    for i = 1, MAX_RECAST_SLOTS do
        PET_RECAST_KEYS[i] = buildKeys(string.format('pet.recast[%d]', i))
    end
    for _, typeName in ipairs(PET_TYPES) do
        for i = 1, MAX_RECAST_SLOTS do
            local typeKeys = buildKeys(string.format('%s.recast[%d]', typeName, i))
            for field, key in pairs(typeKeys) do
                RECAST_ALIASES[key] = {
                    typeName = typeName,
                    petKey   = PET_RECAST_KEYS[i][field],
                    default  = RECAST_DEFAULTS[field],
                }
            end
        end
    end
    for i = 1, MANEUVER_COUNT do
        local prefix = 'pet.maneuver[' .. i .. ']'
        MANEUVER_KEYS[i] = {
            pct       = prefix .. '.pct',
            norm      = prefix .. '.norm',
            count     = prefix .. '.count',
            active    = prefix .. '.active',
            burdened  = prefix .. '.burdened',
            element   = prefix .. '.element',
            remaining = prefix .. '.remaining',
        }
    end
end

-- Builds one State-shaped data table. The live State below is one of these; State.new() builds
-- independent ones that share no table with it.
local function newStateData()
    -- Per-frame element tallies, zeroed and refilled in place by data.lua.
    local maneuverCounts    = {}
    local maneuverRemaining = {}
    for i = 1, MANEUVER_COUNT do
        maneuverCounts[i]    = 0
        maneuverRemaining[i] = 0
    end

    return {
        active      = false,     -- Pet entity present and alive
        petType     = nil,       -- 'avatar' | 'charm' | 'jug' | 'wyvern' | 'automaton' | nil
        outOfRange  = false,     -- True when pet exists but is > 50 yalms (entity unloaded)

        -- Last pet type resolved from a loaded pet entity. Survives a zone, so a pet whose name has
        -- not loaded yet on the far side keeps its type; cleared on character change.
        lastKnownPetType = nil,

        -- Core vitals (all types)
        name        = '',
        hpp         = 0,         -- HP percent (0-100, from pet entity; frozen when outOfRange)
        mpp         = 0,         -- MP percent (0-100; 0 if no MP pool)
        tp          = 0,         -- TP (0-3000)
        dist        = 0.0,       -- Distance in yalms (math.sqrt applied)
        serverId    = 0,
        petLevel    = 0,

        -- Server id of the pet Leave dismissed while its entity lingers; 0 = none. That pet never
        -- starts a jug clock.
        dismissedServerId = 0,

        -- Pet target sub-window
        target = {
            active    = false,
            name      = '',
            hpp       = 0,
            dist      = 0.0,
            serverId  = 0,

            -- Target server id as last reported by the 0x0067/0x0068 pet sync packet. Three
            -- distinct values: nil = no packet seen yet (data.lua falls back to entity memory),
            -- 0 = the server says the pet has no target, >0 = the target's server id.
            -- Not a token; data.lua resolves it to an entity before anything is displayed.
            pktServerId = nil,
        },

        -- Per-type extensions
        avatar = {
            recasts      = {},        -- rows from data.getAbilityRecasts, up to MAX_RECAST_SLOTS
            afExpireTime = nil,       -- os.time() of Astral Flow expiry; nil = inactive
            afRemaining  = 0,         -- seconds remaining (0 when inactive)
        },
        -- Familiar: set when BST uses Familiar (2hr). Shared across charm/jug pet types.
        familiar = {
            expireTime  = nil,  -- os.time() of familiar expiry; nil = inactive
            remaining   = 0,    -- seconds remaining while counting down
            elapsed     = 0,    -- seconds elapsed past expiry (count-up while pet still alive)
            petServerId = 0,    -- server id of the pet it was used on; 0 = binds to the next pet seen
            noPetTime   = 0,    -- seconds of refreshState frames with no pet entity; 0 while one exists
        },
        charm = {
            expireTime    = nil,    -- os.time() of expiry; nil = unknown
            totalDuration = 0,      -- original duration in seconds (for progress bar norm)
            remaining     = 0,
            known         = false,
            mobLevel      = 0,
            petServerId   = 0,      -- server id of the charmed mob; 0 = binds to the next pet seen
            noPetTime     = 0,      -- seconds of refreshState frames with no pet entity
            recasts       = {},
        },
        jug = {
            petName     = '',
            expireTime  = nil,
            remaining   = 0,
            duration    = 0,
            pendingCall = false,  -- set by a confirmed Call Beast / Bestial Loyalty; forces the
                                  -- countdown to restart once the new pet entity resolves
            recasts     = {},
        },
        wyvern = {
            recasts      = {},
            ssExpireTime = nil,       -- os.time() of Spirit Surge expiry; nil = inactive
            ssRemaining  = 0,         -- seconds remaining (wyvern despawned during this)
        },
        automaton = {
            recasts      = {},
            odExpireTime = nil,       -- os.time() of Overdrive expiry; nil = inactive
            odRemaining  = 0,         -- seconds remaining

            -- Vitals as last reported by the 0x0044 PUP packet; nil = none seen yet. maxMp 0 is a
            -- real value, not an absent one: the Valoredge and Sharpshot frames have no MP pool.
            -- The pool sizes are frame configuration rather than pet state, so State.onZone()
            -- leaves all four alone -- zoning does not change the equipped frame.
            hp           = nil,
            maxHp        = nil,
            mp           = nil,
            maxMp        = nil,

            -- PUP maneuver column. burdenModel owns every element's burden and the derived
            -- Overload expiry; there is no burden array or overloadExpiry field here.
            -- packets.lua writes it, state.lua and data.lua read it. Every call is dot-style --
            -- a colon call passes the model table as the index argument and every percentage
            -- silently reads 0.
            burdenModel       = ManeuverBurden.new(),
            maneuverCounts    = maneuverCounts,  -- [1..8] how many of that element are up
            -- [1..8] seconds until that element's soonest-expiring maneuver drops; 0 when the
            -- element has none up or the server sent no timer for it.
            maneuverRemaining = maneuverRemaining,
            maneuverCount     = 0,               -- total maneuvers up (0-3)
            maneuverRecast    = 0,               -- shared 10s recast, seconds remaining (0 = ready)
            maneuverRecastUnknown = false,       -- recast memory unavailable; maneuverRecast is not read
            overdriveOn       = false,
            overloadOn        = false,
            overloadRemaining = 0,               -- derived from burdenModel each frame, like odRemaining
            heatsink          = false,           -- Heatsink attached; the only BURDEN_DECAY source
        },
        bst = {
            stayExpiry = nil,   -- socket.gettime() of current Stay tick expiry; nil = inactive
        },

        -- Charm /check state machine, driven by packets.lua. A Charm use queues a /check
        -- ('sending'); the outgoing 0x00DD is redirected to the charm target ('waiting'); the
        -- 0x0029 reply sizes the charm timer.
        charmCheck = {
            state     = nil,   -- nil | 'sending' | 'waiting'
            started   = 0,     -- socket.gettime() of the outgoing Charm action
            target    = nil,   -- target server id from the outgoing Charm action
            targetIdx = nil,   -- target entity index from the outgoing Charm action
        },
    }
end

local State = newStateData()

-- A fresh State-shaped table with its own burden model and maneuver arrays, carrying none of
-- the functions below. Writes to it never reach the live State.
function State.new()
    return newStateData()
end

-- Lifecycle transitions. Every clear of a pet-owned clock goes through these, so a new field
-- is added in one place.

-- Ends a pet-owned clock. kind: 'jug' | 'charm' | 'familiar' | 'all' (all three plus Stay).
function State.clearPet(kind)
    local all = kind == 'all'
    if all or kind == 'jug' then
        State.jug.expireTime  = nil
        State.jug.remaining   = 0
        State.jug.duration    = 0
        State.jug.pendingCall = false
    end
    if all or kind == 'charm' then
        State.charm.expireTime    = nil
        State.charm.totalDuration = 0
        State.charm.remaining     = 0
        State.charm.known         = false
        State.charm.mobLevel      = 0
        State.charm.petServerId   = 0
        State.charm.noPetTime     = 0
    end
    if all or kind == 'familiar' then
        State.familiar.expireTime  = nil
        State.familiar.remaining   = 0
        State.familiar.elapsed     = 0
        State.familiar.petServerId = 0
        State.familiar.noPetTime   = 0
    end
    if all then
        State.bst.stayExpiry = nil
    end
end

-- No live pet: absent, unloaded with no history, or dead. Pet-owned clocks are left to the
-- caller -- absence alone does not end a jug clock.
function State.clearPresence()
    State.active               = false
    State.petType              = nil
    State.outOfRange           = false
    State.bst.stayExpiry       = nil
    State.target.active        = false
    State.target.serverId      = 0
    State.target.pktServerId   = nil
    State.dismissedServerId    = 0
end

-- Leave: every pet-owned clock ends, and the departing pet is marked so its lingering entity
-- does not start a fresh jug clock.
function State.onLeave()
    State.clearPet('all')
    State.dismissedServerId = State.serverId
end

-- Familiar confirmed: it belongs to the live pet, or to the next one seen when none is known.
function State.startFamiliar(duration)
    State.familiar.expireTime  = os.time() + duration
    State.familiar.remaining   = duration
    State.familiar.elapsed     = 0
    State.familiar.petServerId = State.active and State.serverId or 0
    State.familiar.noPetTime   = 0
end

-- Charm sized by the /check reply: the clock belongs to the charmed mob's server id.
function State.startCharm(mobLevel, duration, serverId)
    State.charm.mobLevel      = mobLevel
    State.charm.expireTime    = os.time() + duration
    State.charm.totalDuration = duration
    State.charm.known         = true
    State.charm.petServerId   = serverId or 0
    State.charm.noPetTime     = 0
end

function State.clearCharmCheck()
    State.charmCheck.state     = nil
    State.charmCheck.target    = nil
    State.charmCheck.targetIdx = nil
end

-- Zone-in. Clears pet presence, vitals, target, recasts, the charm and Familiar clocks, Stay
-- and the charm check.
function State.onZone()
    State.clearPresence()
    State.name        = ''
    State.hpp      = 0
    State.mpp      = 0
    State.tp       = 0
    State.dist     = 0.0
    State.serverId = 0
    State.petLevel = 0

    State.target.name     = ''
    State.target.hpp      = 0
    State.target.dist     = 0.0

    State.avatar.recasts     = {}
    State.avatar.afRemaining = 0   -- recalculated from afExpireTime each frame; expireTime preserved across zone
    State.clearPet('familiar')
    State.clearPet('charm')
    State.charm.recasts       = {}
    State.clearCharmCheck()
    -- Jug timers are deliberately NOT cleared here. On HorizonXI jug pets persist through
    -- zoning and the server restores the ORIGINAL spawn time on the far side, so the countdown
    -- must survive the zone (a pet-less city zone still burns it down). Only Leave, pet death,
    -- expiry, or a fresh Call Beast end a jug clock -- see packets.lua and data.lua.
    -- Charm above IS cleared: charmed pets are despawned unconditionally at the zone line.
    -- lastKnownPetType is kept for the same reason: the jug pet respawns before its name loads.
    State.jug.recasts       = {}
    State.wyvern.recasts     = {}
    State.wyvern.ssRemaining = 0   -- recalculated from ssExpireTime each frame; expireTime preserved across zone
    State.automaton.recasts     = {}
    State.automaton.odRemaining = 0   -- recalculated from odExpireTime each frame; expireTime preserved across zone
    -- Only the per-frame derived maneuver values are cleared. Burden and the Overload expiry
    -- inside burdenModel are NOT reset: the server keeps the automaton entity and its burden
    -- array across a zone line, and Overload is a player debuff that outlives the automaton.
    -- Only a confirmed Activate clears burden -- see packets.lua.
    for i = 1, MANEUVER_COUNT do
        State.automaton.maneuverCounts[i]    = 0
        State.automaton.maneuverRemaining[i] = 0
    end
    State.automaton.maneuverCount     = 0
    State.automaton.maneuverRecast    = 0
    State.automaton.maneuverRecastUnknown = false
    State.automaton.overdriveOn       = false
    State.automaton.overloadOn        = false
    State.automaton.overloadRemaining = 0
end

-- Another character's settings took over. Clears everything a zone keeps that belongs to the
-- previous character; the caller restores the new character's persisted clocks afterwards.
function State.onCharacterChange()
    State.onZone()
    State.clearPet('all')
    State.lastKnownPetType = nil

    State.avatar.afExpireTime    = nil
    State.wyvern.ssExpireTime    = nil
    State.automaton.odExpireTime = nil

    local a = State.automaton
    a.hp, a.maxHp, a.mp, a.maxMp = nil, nil, nil, nil
    a.heatsink = false
    a.burdenModel.resetAll(0)
    a.burdenModel.clearOverload()
    a.burdenModel.resetClock()
end

-- Pre-allocated token table reused every frame to avoid per-frame GC allocation.
-- Callers must consume tokens synchronously (same frame) before the next call clears it.
local _tokenTable = {}

-- Pet type whose recasts filled pet.recast[N] in the last build; nil when none did.
local _recastType = nil

-- Per-type recast tokens (avatar.recast[N].name, jug.recast[N].charges, ...) are not stored:
-- a read resolves to pet.recast[N] when that type is the active one, and to the empty-slot
-- default otherwise. They are therefore absent from pairs() over the table.
setmetatable(_tokenTable, {
    __index = function(t, key)
        local alias = RECAST_ALIASES[key]
        if alias == nil then return nil end
        if alias.typeName == _recastType then return rawget(t, alias.petKey) end
        return alias.default
    end,
})

-- Resolves an automaton vital to a display string, or nil when the pool size is unknown --
-- which leaves the caller's percent display in place.
--
-- `exact` is the 0x0044 figure and `pct` the live entity percent: two transports for the same
-- server-side number. The packet only resends on a server tick where the automaton changed
-- (CAutomatonEntity::PostTick), so a disagreement wider than percent rounding means it went
-- stale and the percent-derived figure is the current one. That fallback also covers the
-- packet reporting full HP for a dead automaton and for no automaton at all.
--
-- The tolerance is the width of one percentage point of the pool plus a floor-rounding slack,
-- which is the largest gap the two transports can show while both are current.
local function resolveVital(exact, max, pct)
    if not max or max <= 0 then return nil end
    local derived = math.floor(max * (pct or 0) / 100)
    if not exact or math.abs(exact - derived) > max / 100 + 1 then
        return tostring(derived)
    end
    return tostring(exact)
end

local function alwaysRunning()
    return true
end

-- 2hr timers are player state: remaining is checked directly, independent of petType.
-- The remaining field can only be > 0 when the corresponding main-job 2hr was used, and the
-- pet may be dismissed or absent while it runs (Spirit Surge despawns the wyvern).
local function twoHourTimer(group, field, special)
    return {
        special = special,
        applies = function(s) return s[group][field] > 0 end,
        timer   = function(s) return State._formatTimer(s[group][field]) end,
        running = alwaysRunning,
    }
end

-- Sources of pet.timer, highest priority first; the first whose applies(s) holds is shown.
-- special names the ability that owns the timer (pet.specialName); nil for the pet's own
-- duration, which leaves pet.specialActive false.
local TIMER_SOURCES = {
    twoHourTimer('avatar',    'afRemaining', 'Astral Flow'),
    twoHourTimer('wyvern',    'ssRemaining', 'Spirit Surge'),
    twoHourTimer('automaton', 'odRemaining', 'Overdrive'),
    -- BST Familiar: overrides the charm/jug duration while active. Once expired with the pet
    -- still alive it counts up the elapsed time.
    {
        special = 'Familiar',
        applies = function(s)
            return (s.petType == 'charm' or s.petType == 'jug') and s.active == true
                   and s.familiar.expireTime ~= nil
        end,
        timer   = function(s)
            if s.familiar.remaining > 0 then return State._formatTimer(s.familiar.remaining) end
            return State._formatElapsed(s.familiar.elapsed)
        end,
        running = alwaysRunning,
    },
    {
        applies = function(s) return s.petType == 'charm' and s.active == true end,
        timer   = function(s) return s.charm.known and State._formatTimer(s.charm.remaining) or '??' end,
        running = function(s) return not s.charm.known or (s.charm.remaining or 0) > 0 end,
    },
    {
        applies = function(s) return s.petType == 'jug' and s.active == true end,
        timer   = function(s) return State._formatTimer(s.jug.remaining) end,
        running = function(s) return (s.jug.remaining or 0) > 0 end,
    },
}

-- Duration tokens owned by one pet type: write(t, s) fills them while that type is active,
-- defaults otherwise.
local TYPE_TOKENS = {
    jug = {
        defaults = {
            ['jug.name']          = '',
            ['jug.remaining']     = '',
            ['jug.remainingNorm'] = 0,
            ['jug.elapsed']       = '',
            ['jug.expired']       = false,
        },
        write = function(t, s)
            t['jug.name']          = s.jug.petName or ''
            t['jug.remaining']     = State._formatTimer(s.jug.remaining)
            t['jug.remainingNorm'] = s.jug.duration > 0 and s.jug.remaining / s.jug.duration or 0
            t['jug.elapsed']       = ''
            t['jug.expired']       = s.jug.expireTime ~= nil and os.time() >= s.jug.expireTime
        end,
    },
    charm = {
        defaults = {
            ['charm.known']         = false,
            ['charm.remaining']     = '',
            ['charm.remainingNorm'] = 0,
            ['charm.elapsed']       = '',
            ['charm.urgent']        = false,
        },
        write = function(t, s)
            t['charm.known']         = s.charm.known == true
            t['charm.remaining']     = s.charm.known and State._formatTimer(s.charm.remaining) or '??'
            t['charm.remainingNorm'] = (s.charm.totalDuration > 0 and (s.charm.remaining or 0) > 0)
                and (s.charm.remaining / s.charm.totalDuration) or 0
            t['charm.elapsed']       = ''
            t['charm.urgent']        = s.charm.known == true and s.charm.remaining ~= nil
                and s.charm.remaining < 60
        end,
    },
}

-- Build a flat token map from the current State snapshot.
-- Every token reads non-nil with a safe default; the per-type recast families are resolved
-- on read rather than stored (see the _tokenTable metatable).
-- Tokens are strings -> numbers, strings, or bools, EXCEPT 'pet.statusIds' and 'pet.statusTimes',
-- which are raw Lua tables consumed directly by modules/statusEffects.lua and must not be used in layout binds.
function State.buildTokenTable(s)
    local t = _tokenTable
    for k in pairs(t) do t[k] = nil end
    s = s or State

    -- Avatars always carry an MP pool, so the bar stays up at 0 MP. Automatons carry one only
    -- on the Harlequin and Stormwaker frames; maxMp nil means no 0x0044 has arrived yet, which
    -- keeps the bar up until one does. A charmed mob may equally have no pool, and
    -- GetPetMPPercent cannot tell that from a drained caster, so charm still falls back to
    -- the value.
    local hasMpPool = s.petType == 'avatar'
                      or (s.petType == 'automaton'
                          and (s.automaton.maxMp == nil or s.automaton.maxMp > 0))
    local mppActive = s.active == true
                      and (hasMpPool or (s.petType == 'charm' and s.mpp > 0))

    t['pet.active']      = s.active == true
    t['pet.serverId']    = s.serverId or 0
    t['pet.type']        = s.petType or ''
    t['pet.name']        = s.name or ''

    -- HP percent family
    t['pet.hpp']         = s.hpp or 0
    if s.outOfRange then
        t['pet.hppNorm'] = 1.0
        t['pet.hppStr']  = '???'
        t['pet.hppPct']  = '???'
        t['pet.hpText']  = '???'
    else
        local hppStr = tostring(math.floor(s.hpp or 0))
        t['pet.hppNorm'] = (s.hpp or 0) / 100
        t['pet.hppStr']  = hppStr
        t['pet.hppPct']  = hppStr .. '%'
        -- Automatons read out as a value: the 0x0044 packet carries the exact figure and the
        -- pool size, and no other pet type has either. The bar still runs off hppNorm.
        local hpVal = nil
        if s.petType == 'automaton' then
            hpVal = resolveVital(s.automaton.hp, s.automaton.maxHp, s.hpp)
        end
        t['pet.hpText'] = hpVal or t['pet.hppPct']
    end

    -- MP
    t['pet.mpp']         = s.mpp or 0
    t['pet.mppNorm']    = (s.mpp or 0) / 100
    t['pet.mppStr']     = tostring(math.floor(s.mpp or 0))
    t['pet.mppActive']  = mppActive
    local mpVal = nil
    if s.petType == 'automaton' then
        mpVal = resolveVital(s.automaton.mp, s.automaton.maxMp, s.mpp)
    end
    t['pet.mpText'] = mpVal or t['pet.mppStr']

    -- TP
    t['pet.tp']          = s.tp or 0
    t['pet.tpNorm']     = math.min((s.tp or 0) / 3000, 1)
    t['pet.tpStr']      = tostring(math.floor(s.tp or 0))
    t['pet.tpPct']      = tostring(math.floor(((s.tp or 0) / 3000) * 100)) .. '%'
    t['pet.tpFull']     = (s.tp or 0) >= 3000

    -- Distance
    if s.outOfRange then
        t['pet.dist']    = '>50'
        t['pet.distNum'] = 50.0
        t['pet.distFar'] = true
    else
        t['pet.dist']    = string.format('%.1f', s.dist or 0)
        t['pet.distNum'] = s.dist or 0
        t['pet.distFar'] = (s.dist or 0) > 20
    end

    -- Level
    t['pet.level'] = (s.petLevel and s.petLevel > 0) and tostring(s.petLevel) or ''

    -- Virtual timer tokens: first matching TIMER_SOURCES entry
    local timer, timerActive, special = '', false, nil
    for _, source in ipairs(TIMER_SOURCES) do
        if source.applies(s) then
            timer, timerActive, special = source.timer(s), source.running(s), source.special
            break
        end
    end
    t['pet.timer']         = timer
    t['pet.timerActive']   = timerActive
    t['pet.specialActive'] = special ~= nil
    t['pet.specialName']   = special or ''

    -- Target tokens
    t['target.active']      = s.target.active == true
    t['target.name']        = s.target.name or ''
    t['target.hpp']         = s.target.hpp or 0
    t['target.hppNorm']    = (s.target.hpp or 0) / 100
    t['target.hppStr']     = tostring(math.floor(s.target.hpp or 0))
    t['target.hppPct']     = tostring(math.floor(s.target.hpp or 0)) .. '%'
    t['target.dist']        = string.format('%.1f', s.target.dist or 0)
    t['target.distNum']    = s.target.dist or 0
    t['target.distFar']    = (s.target.dist or 0) > 20

    -- BST stay tick counter (applies to both charm and jug)
    local bstStayExpiry = s.bst and s.bst.stayExpiry
    if bstStayExpiry ~= nil then
        t['bst.stayActive'] = true
        t['bst.stayTicks']  = tostring(math.max(0, math.ceil(bstStayExpiry - socket.gettime())))
    else
        t['bst.stayActive'] = false
        t['bst.stayTicks']  = '--'
    end

    -- Type-specific duration tokens
    for typeName, typeTokens in pairs(TYPE_TOKENS) do
        if s.petType == typeName then
            typeTokens.write(t, s)
        else
            for key, value in pairs(typeTokens.defaults) do
                t[key] = value
            end
        end
    end

    -- pet.recast[N] tokens, routed from the active type's recasts. The per-type families
    -- resolve through the token table's __index.
    _recastType = RECAST_TYPES[s.petType] and s.petType or nil
    local recasts = _recastType and s[_recastType].recasts
    for i = 1, MAX_RECAST_SLOTS do
        State._writeRecastTokens(t, PET_RECAST_KEYS[i], recasts and recasts[i])
    end

    -- PUP maneuver column.
    -- Emitted with no petType branch: maneuvers, Overload and Overdrive are player buffs, and
    -- Overload outlives the automaton, so the banner must keep counting down after Deactivate
    -- when petType is nil. data.lua reads these ahead of every pet-presence early return and
    -- zeroes them all when the player owns no automaton, so the fields are already correct for
    -- every pet type.
    -- pct is the server's last reported overload chance less the burden decayed since, not a
    -- computed chance, and is left uncapped: the server clamps its own report to 0..255, so a
    -- reading above 100 is real. norm is clamped because it drives a bar fill.
    local a     = s.automaton
    local model = a.burdenModel
    for i = 1, MANEUVER_COUNT do
        local keys  = MANEUVER_KEYS[i]
        local pct   = model.displayPct(i)   -- dot call: a colon passes the model as `index`
        local count = a.maneuverCounts[i] or 0
        t[keys.pct]       = pct
        t[keys.norm]      = math.min(pct / 100, 1)
        t[keys.count]     = count
        t[keys.active]    = count > 0
        t[keys.burdened]  = pct > 0
        t[keys.element]   = maneuvers.elements[i].name   -- identity, not state
        -- Whole seconds, never nil: 0 covers both "none up" and "no timer known".
        t[keys.remaining] = a.maneuverRemaining[i] or 0
    end

    -- overloadRemaining is data.lua's per-frame cache, read here and not recomputed, like
    -- odRemaining above.
    local maneuverRecast = a.maneuverRecast or 0
    local overloadLeft   = a.overloadRemaining or 0
    t['pet.maneuverCount']      = a.maneuverCount or 0
    if a.maneuverRecastUnknown then
        t['pet.maneuverRecast']     = '??'
        t['pet.maneuverRecastNorm'] = 0
        t['pet.maneuverReady']      = false
    else
        t['pet.maneuverRecast']     = State._formatTimer(maneuverRecast)
        t['pet.maneuverRecastNorm'] = math.min(maneuverRecast / maneuvers.RECAST_SECONDS, 1)
        t['pet.maneuverReady']      = maneuverRecast <= 0
    end
    t['pet.maneuverUsable']     = not a.overloadOn
    t['pet.overloadActive']     = a.overloadOn == true
    t['pet.overloadLabel']      = 'OVERLOAD'
    t['pet.overloadRemaining']  = overloadLeft
    t['pet.overloadTimer']      = State._formatOverloadTimer(overloadLeft, model.hasOverloadExpiry())
    t['pet.overdriveActive']    = a.overdriveOn == true

    return t
end

-- Write recast tokens for a specific slot using its prebuilt keys table
-- (PET_RECAST_KEYS[i], with .name/.time/.norm/.ready/.charges/.maxCharges/.active).
function State._writeRecastTokens(t, keys, r)
    if r then
        if r.isHealTimer then
            t[keys.name]       = r.name or ''
            t[keys.active]     = true
            t[keys.time]       = ''   -- renderer reads tokenKey directly
            t[keys.norm]       = 0
            t[keys.ready]      = false
            t[keys.charges]    = 0
            t[keys.maxCharges] = 0
        else
            t[keys.name]       = r.name    or ''
            if r.unknown then
                t[keys.time]   = '??'
            else
                t[keys.time]   = r.ready and 'Ready' or State._formatTimer(r.remaining or 0)
            end
            t[keys.norm]       = r.norm    or 0
            t[keys.ready]      = r.ready   == true
            t[keys.charges]    = r.charges    or 0
            t[keys.maxCharges] = r.maxCharges or 0
            t[keys.active]     = true
        end
    else
        t[keys.name]       = ''
        t[keys.time]       = ''
        t[keys.norm]       = 0
        t[keys.ready]      = false
        t[keys.charges]    = 0
        t[keys.maxCharges] = 0
        t[keys.active]     = false
    end
end

-- Format seconds as M:SS or 'Ready' when 0
function State._formatTimer(seconds)
    if not seconds or seconds <= 0 then return 'Ready' end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format('%d:%02d', m, s)
end

-- Format the Overload countdown as M:SS.
-- Separate from State._formatTimer, which returns 'Ready' at <= 0: the buff outlives the
-- derived expiry (the server's effect container ticks on ~3s granularity, so a 17s prediction
-- can run 18s), and the red banner would read 'OVERLOAD Ready' in that window.
-- hasExpiry false means no countdown is known at all -- addon loaded mid-Overload.
function State._formatOverloadTimer(seconds, hasExpiry)
    if not hasExpiry then return '--' end
    if not seconds or seconds <= 0 then return '0:00' end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format('%d:%02d', m, s)
end

-- Format elapsed seconds as +M:SS (count-up display, always shows even at 0)
function State._formatElapsed(seconds)
    if not seconds or seconds <= 0 then return '+0:00' end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format('+%d:%02d', m, s)
end

return State
