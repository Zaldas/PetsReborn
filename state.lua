-- state.lua
-- Shared state snapshot for PetsReborn.
-- data.lua writes here; all rendering code reads from here via buildTokenTable().

local socket         = require('socket')
local maneuvers      = require('data/maneuvers')
local ManeuverBurden = require('modules/maneuverBurden')

-- Maximum number of recast slots per pet type.
local MAX_RECAST_SLOTS = 6

local MANEUVER_COUNT = #maneuvers.elements

-- Single owner of per-element burden and the derived Overload expiry. Exposed as
-- State.automaton.burdenModel; packets.lua writes it, state.lua and data.lua read it.
-- Every call is dot-style -- a colon call passes the model table as the index argument
-- and every percentage silently reads 0.
local burdenModel = ManeuverBurden.new()

-- Per-frame element tallies, zeroed and refilled in place by data.lua.
local maneuverCounts    = {}
local maneuverRemaining = {}
for i = 1, MANEUVER_COUNT do
    maneuverCounts[i]    = 0
    maneuverRemaining[i] = 0
end

-- Pre-built full token key strings to avoid per-frame string concatenation.
-- RECAST_KEYS[typeName][i] = e.g. { name = 'avatar.recast[1].name', time = 'avatar.recast[1].time', ... }
-- PET_RECAST_KEYS[i]       = e.g. { name = 'pet.recast[1].name', ... }
-- MANEUVER_KEYS[i]         = e.g. { pct = 'pet.maneuver[1].pct', ... }
local RECAST_KEYS = {}
local PET_RECAST_KEYS = {}
local MANEUVER_KEYS = {}
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
    local types = {'avatar', 'jug', 'charm', 'wyvern', 'automaton'}
    for _, typeName in ipairs(types) do
        RECAST_KEYS[typeName] = {}
        for i = 1, MAX_RECAST_SLOTS do
            RECAST_KEYS[typeName][i] = buildKeys(typeName .. '.recast[' .. i .. ']')
        end
    end
    for i = 1, MAX_RECAST_SLOTS do
        PET_RECAST_KEYS[i] = buildKeys('pet.recast[' .. i .. ']')
    end
    for i = 1, MANEUVER_COUNT do
        local prefix = 'pet.maneuver[' .. i .. ']'
        MANEUVER_KEYS[i] = {
            pct       = prefix .. '.pct',
            norm      = prefix .. '.norm',
            count     = prefix .. '.count',
            active    = prefix .. '.active',
            burdened  = prefix .. '.burdened',
            estimated = prefix .. '.estimated',
            element   = prefix .. '.element',
            remaining = prefix .. '.remaining',
        }
    end
end

local State = {
    active      = false,     -- Pet entity present and alive
    petType     = nil,       -- 'avatar' | 'charm' | 'jug' | 'wyvern' | 'automaton' | nil
    outOfRange  = false,     -- True when pet exists but is > 50 yalms (entity unloaded)

    -- Core vitals (all types)
    name        = '',
    hpp         = 0,         -- HP percent (0-100, from pet entity; frozen when outOfRange)
    mpp         = 0,         -- MP percent (0-100; 0 if no MP pool)
    tp          = 0,         -- TP (0-3000)
    dist        = 0.0,       -- Distance in yalms (math.sqrt applied)
    serverId    = 0,
    petLevel    = 0,

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
        recasts      = {},        -- [{name, remaining, max, norm, ready, charges, active}] slots 1-6
        afExpireTime = nil,       -- os.time() of Astral Flow expiry; nil = inactive
        afRemaining  = 0,         -- seconds remaining (0 when inactive)
    },
    -- Familiar: set when BST uses Familiar (2hr). Shared across charm/jug pet types.
    familiar = {
        expireTime = nil,   -- os.time() of familiar expiry; nil = inactive
        remaining  = 0,     -- seconds remaining while counting down
        elapsed    = 0,     -- seconds elapsed past expiry (count-up while pet still alive)
    },
    charm = {
        expireTime    = nil,    -- os.time() of expiry; nil = unknown
        totalDuration = 0,      -- original duration in seconds (for progress bar norm)
        remaining     = 0,
        known         = false,
        mobLevel      = 0,
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
        -- The pool sizes are frame configuration rather than pet state, so State.reset()
        -- leaves all four alone -- zoning does not change the equipped frame.
        hp           = nil,
        maxHp        = nil,
        mp           = nil,
        maxMp        = nil,

        -- PUP maneuver column. burdenModel owns every element's burden and the derived
        -- Overload expiry; there is no burden array or overloadExpiry field here.
        burdenModel       = burdenModel,
        maneuverCounts    = maneuverCounts,  -- [1..8] how many of that element are up
        -- [1..8] seconds until that element's soonest-expiring maneuver drops; 0 when the
        -- element has none up or the server sent no timer for it.
        maneuverRemaining = maneuverRemaining,
        maneuverCount     = 0,               -- total maneuvers up (0-3)
        maneuverRecast    = 0,               -- shared 10s recast, seconds remaining (0 = ready)
        overdriveOn       = false,
        overloadOn        = false,
        overloadRemaining = 0,               -- derived from burdenModel each frame, like odRemaining
    },
    bst = {
        stayExpiry = nil,   -- os.time() of current Stay tick expiry; nil = inactive
    },
}

function State.reset()
    State.active      = false
    State.petType     = nil
    State.outOfRange  = false
    State.name        = ''
    State.hpp      = 0
    State.mpp      = 0
    State.tp       = 0
    State.dist     = 0.0
    State.serverId = 0
    State.petLevel = 0

    State.target.active   = false
    State.target.name     = ''
    State.target.hpp      = 0
    State.target.dist     = 0.0
    State.target.serverId = 0
    State.target.pktServerId = nil

    State.avatar.recasts     = {}
    State.avatar.afRemaining = 0   -- recalculated from afExpireTime each frame; expireTime preserved across zone
    State.familiar.expireTime = nil
    State.familiar.remaining  = 0
    State.familiar.elapsed    = 0
    State.charm.expireTime    = nil
    State.charm.totalDuration = 0
    State.charm.remaining     = 0
    State.charm.known         = false
    State.charm.mobLevel      = 0
    State.charm.recasts       = {}
    State.bst.stayExpiry      = nil
    -- Jug timers are deliberately NOT cleared here. On HorizonXI jug pets persist through
    -- zoning and the server restores the ORIGINAL spawn time on the far side, so the countdown
    -- must survive the zone (a pet-less city zone still burns it down). Only Leave, pet death,
    -- expiry, or a fresh Call Beast end a jug clock -- see packets.lua and data.lua.
    -- Charm above IS cleared: charmed pets are despawned unconditionally at the zone line.
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
    State.automaton.overdriveOn       = false
    State.automaton.overloadOn        = false
    State.automaton.overloadRemaining = 0
end

-- Pre-allocated token table reused every frame to avoid per-frame GC allocation.
-- Callers must consume tokens synchronously (same frame) before the next call clears it.
local _tokenTable = {}

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

-- Build a flat token map from the current State snapshot.
-- All tokens are always present with safe defaults (never nil).
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

    -- Virtual timer tokens (routed by type)
    -- 2hr timers are player state: remaining is checked directly, independent of petType.
    -- afRemaining/ssRemaining/odRemaining can only be > 0 when the corresponding main-job 2hr
    -- was used, and petType is nil briefly during pet dismissal.
    if s.avatar.afRemaining > 0 then
        -- SMN: Astral Flow countdown (avatar may be dismissed or absent while flow is active)
        t['pet.timer']       = State._formatTimer(s.avatar.afRemaining)
        t['pet.timerActive'] = true
        t['pet.specialActive']    = true
        t['pet.specialName']      = 'Astral Flow'
    elseif s.wyvern.ssRemaining > 0 then
        -- DRG: Spirit Surge countdown (wyvern is despawned by this ability)
        t['pet.timer']       = State._formatTimer(s.wyvern.ssRemaining)
        t['pet.timerActive'] = true
        t['pet.specialActive']    = true
        t['pet.specialName']      = 'Spirit Surge'
    elseif s.automaton.odRemaining > 0 then
        -- PUP: Overdrive countdown (automaton may be recalled during overdrive)
        t['pet.timer']       = State._formatTimer(s.automaton.odRemaining)
        t['pet.timerActive'] = true
        t['pet.specialActive']    = true
        t['pet.specialName']      = 'Overdrive'
    elseif (s.petType == 'charm' or s.petType == 'jug') and s.active == true and s.familiar.expireTime ~= nil then
        -- BST: Familiar timer (overrides charm/jug duration display while active)
        if s.familiar.remaining > 0 then
            t['pet.timer'] = State._formatTimer(s.familiar.remaining)
        else
            -- Familiar expired but pet still alive: count up elapsed time
            t['pet.timer'] = State._formatElapsed(s.familiar.elapsed)
        end
        t['pet.timerActive'] = true
        t['pet.specialActive']    = true
        t['pet.specialName']      = 'Familiar'
    elseif s.petType == 'charm' and s.active == true then
        t['pet.timer']            = s.charm.known and State._formatTimer(s.charm.remaining) or '??'
        t['pet.timerActive']      = not s.charm.known or (s.charm.remaining or 0) > 0
        t['pet.specialActive']    = false
        t['pet.specialName']      = ''
    elseif s.petType == 'jug' and s.active == true then
        t['pet.timer']            = State._formatTimer(s.jug.remaining)
        t['pet.timerActive']      = (s.jug.remaining or 0) > 0
        t['pet.specialActive']    = false
        t['pet.specialName']      = ''
    else
        t['pet.timer']       = ''
        t['pet.timerActive'] = false
        t['pet.specialActive']    = false
        t['pet.specialName']      = ''
    end

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

    -- Type-specific recast tokens (routed by active pet type)
    if s.petType == 'avatar' then
        for i = 1, MAX_RECAST_SLOTS do
            State._writeRecastTokens(t, RECAST_KEYS['avatar'][i], s.avatar.recasts and s.avatar.recasts[i])
        end
    elseif s.petType == 'jug' then
        for i = 1, MAX_RECAST_SLOTS do
            State._writeRecastTokens(t, RECAST_KEYS['jug'][i], s.jug.recasts and s.jug.recasts[i])
        end
        t['jug.name']           = s.jug.petName or ''
        t['jug.remaining']      = State._formatTimer(s.jug.remaining)
        t['jug.remainingNorm'] = s.jug.duration > 0 and s.jug.remaining / s.jug.duration or 0
        t['jug.elapsed']        = ''
        t['jug.expired']        = s.jug.expireTime ~= nil and os.time() >= s.jug.expireTime
    elseif s.petType == 'charm' then
        for i = 1, MAX_RECAST_SLOTS do
            State._writeRecastTokens(t, RECAST_KEYS['charm'][i], s.charm.recasts and s.charm.recasts[i])
        end
        t['charm.known']           = s.charm.known == true
        t['charm.remaining']       = s.charm.known and State._formatTimer(s.charm.remaining) or '??'
        t['charm.remainingNorm']  = (s.charm.totalDuration > 0 and (s.charm.remaining or 0) > 0)
            and (s.charm.remaining / s.charm.totalDuration) or 0
        t['charm.elapsed']         = ''
        t['charm.urgent']          = s.charm.remaining ~= nil and s.charm.remaining < 60
    elseif s.petType == 'wyvern' then
        for i = 1, MAX_RECAST_SLOTS do
            State._writeRecastTokens(t, RECAST_KEYS['wyvern'][i], s.wyvern.recasts and s.wyvern.recasts[i])
        end
    elseif s.petType == 'automaton' then
        for i = 1, MAX_RECAST_SLOTS do
            State._writeRecastTokens(t, RECAST_KEYS['automaton'][i], s.automaton.recasts and s.automaton.recasts[i])
        end
    end

    -- Ensure all type-specific tokens have defaults even when that type is not active
    local allTypes = {'avatar', 'jug', 'charm', 'wyvern', 'automaton'}
    for _, typeName in ipairs(allTypes) do
        for i = 1, MAX_RECAST_SLOTS do
            local keys = RECAST_KEYS[typeName][i]
            if t[keys.name] == nil then
                t[keys.name]       = ''
                t[keys.time]       = ''
                t[keys.norm]       = 0
                t[keys.ready]      = false
                t[keys.charges]    = 0
                t[keys.maxCharges] = 0
                t[keys.active]     = false
            end
        end
    end

    -- Ensure jug/charm specific tokens have defaults
    if t['jug.name'] == nil then
        t['jug.name']           = ''
        t['jug.remaining']      = ''
        t['jug.remainingNorm'] = 0
        t['jug.elapsed']        = ''
        t['jug.expired']        = false
    end
    if t['charm.known'] == nil then
        t['charm.known']           = false
        t['charm.remaining']       = ''
        t['charm.remainingNorm']  = 0
        t['charm.elapsed']         = ''
        t['charm.urgent']          = false
    end
    if t['bst.stayTicks'] == nil then t['bst.stayTicks'] = '--' end

    -- Virtual pet.recast[N] tokens (routed from active type-specific recasts)
    local typeKeys = s.petType and RECAST_KEYS[s.petType]
    for i = 1, MAX_RECAST_SLOTS do
        local dstKeys = PET_RECAST_KEYS[i]
        t[dstKeys.name]       = (typeKeys and t[typeKeys[i].name])       or ''
        t[dstKeys.time]       = (typeKeys and t[typeKeys[i].time])       or ''
        t[dstKeys.norm]       = (typeKeys and t[typeKeys[i].norm])       or 0
        t[dstKeys.ready]      = (typeKeys and t[typeKeys[i].ready])      or false
        t[dstKeys.charges]    = (typeKeys and t[typeKeys[i].charges])    or 0
        t[dstKeys.maxCharges] = (typeKeys and t[typeKeys[i].maxCharges]) or 0
        t[dstKeys.active]     = (typeKeys and t[typeKeys[i].active])     or false
    end

    -- PUP maneuver column.
    -- Emitted with no petType branch: maneuvers, Overload and Overdrive are player buffs, and
    -- Overload outlives the automaton, so the banner must keep counting down after Deactivate
    -- when petType is nil. data.lua reads these ahead of every pet-presence early return and
    -- zeroes them all when the player owns no automaton, so the fields are already correct for
    -- every pet type.
    -- pct is the server's last reported overload chance decayed 1 per 3s, not a computed
    -- chance, and is left uncapped: the server clamps its own report to 0..255 and Overdrive
    -- estimates stack past 100. norm is clamped because it drives a bar fill.
    local a     = s.automaton
    local now   = os.time()
    local model = a.burdenModel
    for i = 1, MANEUVER_COUNT do
        local keys  = MANEUVER_KEYS[i]
        local pct   = model.displayPct(i, now)   -- dot call: a colon passes the model as `index`
        local count = a.maneuverCounts[i] or 0
        t[keys.pct]       = pct
        t[keys.norm]      = math.min(pct / 100, 1)
        t[keys.count]     = count
        t[keys.active]    = count > 0
        t[keys.burdened]  = pct > 0
        t[keys.estimated] = model.isEstimated(i) == true
        t[keys.element]   = maneuvers.elements[i].name   -- identity, not state
        -- Whole seconds, never nil: 0 covers both "none up" and "no timer known".
        t[keys.remaining] = a.maneuverRemaining[i] or 0
    end

    -- overloadRemaining is data.lua's per-frame cache, read here and not recomputed, like
    -- odRemaining above.
    local maneuverRecast = a.maneuverRecast or 0
    local overloadLeft   = a.overloadRemaining or 0
    t['pet.maneuverCount']      = a.maneuverCount or 0
    t['pet.maneuverRecast']     = State._formatTimer(maneuverRecast)
    t['pet.maneuverRecastNorm'] = math.min(maneuverRecast / maneuvers.RECAST_SECONDS, 1)
    t['pet.maneuverReady']      = maneuverRecast <= 0
    t['pet.maneuverUsable']     = not a.overloadOn
    t['pet.overloadActive']     = a.overloadOn == true
    t['pet.overloadLabel']      = 'OVERLOAD'
    t['pet.overloadRemaining']  = overloadLeft
    t['pet.overloadTimer']      = State._formatOverloadTimer(overloadLeft, model.hasOverloadExpiry())
    t['pet.overdriveActive']    = a.overdriveOn == true

    return t
end

-- Write recast tokens for a specific slot using its prebuilt keys table
-- (RECAST_KEYS[typeName][i], with .name/.time/.norm/.ready/.charges/.maxCharges/.active).
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
            t[keys.time]       = r.ready and 'Ready' or State._formatTimer(r.remaining or 0)
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
