-- data.lua
-- Memory access layer for PetsReborn.
-- Only this file calls Ashita APIs. All other code reads from State.

local data   = {}
local socket = require('socket')
local abilityRecast = require('libs/ashita/abilityrecast')
local charmGear     = require('data/charmGear')
local maneuvers     = require('data/maneuvers')
local statusHelpers = require('libs/status/statushelpers')

-- Job IDs (only pet-granting jobs needed)
local JOB_BST = 9
local JOB_DRG = 14
local JOB_SMN = 15
local JOB_PUP = 18

-- Pet type -> owning job ID (consumed by getPetJobLevel for level-gating slots)
data.typeToJob = {
    avatar    = JOB_SMN,
    wyvern    = JOB_DRG,
    automaton = JOB_PUP,
    jug       = JOB_BST,
    charm     = JOB_BST,
}

-- Shared fallback entries for recast cache misses. Read-only at both call sites.
local EMPTY_CHARGE_ENTRY = { modifier = 0, recast = 0 }
local EMPTY_RECAST_ENTRY = { recast = 0 }

-- The scanAll() result refreshState took this frame, or nil when it took none. Published
-- through data.getFrameRecastCache(); refreshState's own copy is a function local.
local frameRecastCache = nil

-- Pre-allocated recast row pool: getAbilityRecasts() runs every frame while a pet
-- is active, so rows are reused in place. MAX_RECAST_SLOTS is duplicated in state.lua;
-- the two must stay in step.
local MAX_RECAST_SLOTS = 6
local recastRowPool = {}
for i = 1, MAX_RECAST_SLOTS do
    recastRowPool[i] = {
        name            = '',
        remaining       = 0,
        max             = 0,
        norm            = 0,
        ready           = false,
        charges         = 0,
        maxCharges      = 0,
        isChargeAbility = nil,
        isHealTimer     = nil,
    }
end

local MANEUVER_COUNT = #maneuvers.elements

-- Pet target server id -> entity index. The pet sync packet names the target by server id,
-- but Name/HPPercent/Distance all come from the entity, so the id has to be resolved.
-- statusHelpers.GetIndexFromId walks up to 0x8FF entities on a miss, so the result is cached:
-- a hit costs one GetServerId read to confirm the index still holds that entity (indices are
-- recycled across zones). A target the entity table does not hold -- out of render range, or
-- not yet loaded -- cannot be cached, so those lookups are retried on a timer.
local TARGET_LOOKUP_RETRY  = 1.0
local cachedTargetServerId = 0
local cachedTargetIndex    = 0
local nextTargetRetry      = 0

-- Returns the entity index for a non-zero server id, or 0 when it cannot be resolved.
local function resolveTargetIndex(serverId, entityMgr)
    if serverId == cachedTargetServerId then
        if cachedTargetIndex > 0 and entityMgr:GetServerId(cachedTargetIndex) == serverId then
            return cachedTargetIndex
        end
        local now = socket.gettime()
        if now < nextTargetRetry then return 0 end
        nextTargetRetry = now + TARGET_LOOKUP_RETRY
    else
        cachedTargetServerId = serverId
        nextTargetRetry      = socket.gettime() + TARGET_LOOKUP_RETRY
    end

    cachedTargetIndex = statusHelpers.GetIndexFromId(serverId) or 0
    return cachedTargetIndex
end

-- GetStatusTimers() decoding. Raw values are absolute expiry times in 1/60-second units since
-- the Vanadiel epoch (Unix 0x3C307D70). 0x7FFFFFFF means infinite or hidden, and 0 means no
-- timer at all; neither is a countdown. The counter is a uint32 and wraps roughly every 2.3
-- years, and the wrapped value must be corrected on read, as the client does.
local VANA_EPOCH = 0x3C307D70
local TIMER_INF  = 0x7FFFFFFF

-- Jug pet name hash table and duration table (O(1) lookup) -- populated in data.init()
local jugPetNames     = {}
local jugPetDurations = {}  -- name -> duration in seconds

local DEFAULT_JUG_DURATION = 3600  -- 60 min fallback for unrecognised pets

-- Last known BST pet type ('jug' or 'charm'); used by detectPetType() when petName is nil.
local lastKnownBstType = 'charm'

-- Jug pet name -> duration_minutes (maintained in data/jugPets.lua; add new HorizonXI pets there)
local JUG_PET_LIST = require('data/jugPets')


-- Ability slot definitions per pet type: loaded from data/petAbilities.lua.
-- Add new pet types or abilities there without modifying this file.
data.abilitySlots = require('data/petAbilities')

-- Initialize: build jug pet lookup tables
function data.init()
    jugPetNames     = {}
    jugPetDurations = {}
    for name, durationMin in pairs(JUG_PET_LIST) do
        jugPetNames[name]     = true
        jugPetDurations[name] = durationMin * 60
    end
end

-- Detect pet type from player main/sub job and optional pet entity name.
-- Main job takes priority; sub job checked as fallback.
-- petName may be nil (no active pet): BST falls back to lastKnownBstType.
-- Note: /DRG does NOT grant a wyvern; wyvern is main job DRG only.
-- Returns: 'avatar' | 'wyvern' | 'automaton' | 'jug' | 'charm' | nil
function data.detectPetType(mainJob, subJob, petName)
    local function bstType()
        -- An empty name carries no more information than nil: the pet entity exists but has
        -- not resolved yet (notably the frame a jug pet respawns after a zone). Guessing
        -- 'charm' there tears down a live jug countdown.
        if petName == nil or petName == '' then return lastKnownBstType end
        return jugPetNames[petName] and 'jug' or 'charm'
    end

    if     mainJob == JOB_SMN then return 'avatar'
    elseif mainJob == JOB_DRG then return 'wyvern'
    elseif mainJob == JOB_PUP then return 'automaton'
    elseif mainJob == JOB_BST then return bstType()
    elseif subJob  == JOB_SMN then return 'avatar'
    elseif subJob  == JOB_PUP then return 'automaton'
    elseif subJob  == JOB_BST then return bstType()
    end
    return nil
end

-- Returns total CHARM_TIME bonus from currently equipped gear.
-- Each point contributes 5% to charm duration (see packets._calcCharmDuration).
function data.getCharmGearBonus()
    local total  = 0
    local memMgr = AshitaCore and AshitaCore:GetMemoryManager()
    if not memMgr then return 0 end
    local inv = memMgr:GetInventory()
    if not inv then return 0 end
    for i = 0, 15 do
        local equipped = inv:GetEquippedItem(i)
        if equipped then
            local idx = bit.band(equipped.Index, 0x00FF)
            if idx > 0 then
                local container = bit.rshift(bit.band(equipped.Index, 0xFF00), 8)
                local item = inv:GetContainerItem(container, idx)
                if item and charmGear.CHARM_GEAR[item.Id] then
                    total = total + charmGear.CHARM_GEAR[item.Id]
                end
            end
        end
    end
    return total
end

-- Returns the player's effective job level for the job that owns petType
-- (main job level if it matches, sub job level if that matches, else 99 so
-- no ability slots get level-gated away when the job can't be determined).
function data.getPetJobLevel(petType)
    local memMgr    = AshitaCore and AshitaCore:GetMemoryManager()
    local playerMem = memMgr and memMgr:GetPlayer()
    if not playerMem then return 99 end
    local petJobId = data.typeToJob[petType]
    if not petJobId then return 99 end
    if playerMem:GetMainJob() == petJobId then
        return playerMem:GetMainJobLevel()
    elseif playerMem:GetSubJob() == petJobId then
        return playerMem:GetSubJobLevel()
    end
    return 99
end

-- Level-filtered slot list for petType, rebuilt only when the owning job's level changes.
-- Every consumer must index THIS list: pet.recast[N] tokens are written by position, so a
-- consumer that filters differently shifts each row's label and timer against each other.
local filteredSlotCache = {}   -- [petType] = { level = n, slots = {...} }

function data.getFilteredSlots(petType)
    local allSlots = data.abilitySlots[petType]
    if not allSlots then return nil end

    local level  = data.getPetJobLevel(petType)
    local cached = filteredSlotCache[petType]
    if cached and cached.level == level then return cached.slots end

    local slots = {}
    for _, slot in ipairs(allSlots) do
        if not slot.level or slot.level <= level then
            slots[#slots + 1] = slot
        end
    end
    filteredSlotCache[petType] = { level = level, slots = slots }
    return slots
end

-- Per-frame PUP maneuver state: which maneuvers are up, Overload, Overdrive, and the shared
-- maneuver recast.
--
-- Every field here is PLAYER state, not pet state, so refreshState calls this above every
-- pet-presence early return. Overload outlives the automaton -- onAbilityUseDeactivate never
-- touches it (scripts/globals/job_utils/puppetmaster.lua:511-523) -- and onManeuverCheck
-- returns 71 until it wears, so the countdown is what the player needs with no pet out.
-- Recast timer 210 lives in player recast memory and stays readable the same way.
--
-- This is the sole writer of all six fields, on one gate: the zeroing here runs every frame,
-- so a read placed behind a pet-presence gate makes the row report Ready for the remainder of
-- a live cooldown after a Deactivate.
--
-- Every field is cleared when the player does not own an automaton, so changing job cannot
-- strand a live Overload banner, and buildTokenTable emits these tokens with no petType
-- branch. State only -- burdenModel's own burden and overload-expiry state survive, and are
-- reset only by a confirmed Activate.
local function refreshManeuverBuffs(State, player, ownsAutomaton, recastCache)
    local a         = State.automaton
    local counts    = a.maneuverCounts
    local remaining = a.maneuverRemaining

    -- Zeroed in place: this runs every frame, so nothing here allocates.
    for i = 1, MANEUVER_COUNT do
        counts[i]    = 0
        remaining[i] = 0
    end
    a.maneuverCount  = 0
    a.maneuverRecast = 0

    if not ownsAutomaton then
        a.overloadOn        = false
        a.overdriveOn       = false
        a.overloadRemaining = 0
        return
    end

    local total       = 0
    local overloadOn  = false
    local overdriveOn = false

    -- The buff array carries one entry per stack, so duplicate ids ARE the stack count and
    -- must not be de-duplicated. It carries no expiry data; the per-element countdowns come
    -- from the separate status-icon/timer pair read below.
    local buffs = player:GetBuffs()
    if buffs then
        for _, buffId in pairs(buffs) do
            local element = maneuvers.byBuffId[buffId]
            if element then
                counts[element.index] = counts[element.index] + 1
                total = total + 1
            elseif buffId == maneuvers.OVERLOAD_BUFF then
                overloadOn = true
            elseif buffId == maneuvers.OVERDRIVE_BUFF then
                overdriveOn = true
            end
        end
    end

    a.maneuverCount = math.min(total, maneuvers.MAX_ACTIVE)
    a.overloadOn    = overloadOn
    a.overdriveOn   = overdriveOn

    -- Per-element seconds until the soonest-expiring maneuver of that element drops.
    --
    -- GetStatusIcons() and GetStatusTimers() are a parallel pair -- entry i of one describes
    -- entry i of the other -- and both are a DIFFERENT array from GetBuffs() above, with its
    -- own ordering. A timer read at a buff-array index silently returns another effect's
    -- expiry, so entries are matched by status id and the timer is taken from the icon array's
    -- own index. Ids fit: the array is int16_t and maneuvers are 300-307, above the 255
    -- no-icon sentinel.
    --
    -- One array entry per stack, exactly like the buff array, so an element with three
    -- maneuvers up has three independent expiries -- the smallest is the one that drops next.
    --
    -- ceil, not floor: a maneuver with half a second left must not report 0, which is this
    -- token's "no maneuver up" value.
    local now    = os.time()
    local icons  = player:GetStatusIcons()
    local timers = player:GetStatusTimers()
    if icons and timers then
        local comparand = (now - VANA_EPOCH) * 60   -- now, in the timers' 1/60s units
        for j = 1, 32 do
            local icon    = icons[j]
            local element = icon and maneuvers.byBuffId[icon]
            if element then
                local raw = timers[j]
                if raw and raw ~= 0 and raw ~= TIMER_INF then
                    local ticks = raw - comparand
                    while ticks < -2147483648 do
                        ticks = ticks + 0x100000000
                    end
                    if ticks > 0 then
                        local seconds = math.ceil(ticks / 60)
                        local current = remaining[element.index]
                        if current == 0 or seconds < current then
                            remaining[element.index] = seconds
                        end
                    end
                end
            end
        end
    end

    -- Dot calls, never colon: a colon passes the model table as the first argument.
    local model = a.burdenModel
    if overloadOn then
        a.overloadRemaining = model.overloadRemaining(now)
    else
        -- Buff absence only wins once the derived countdown has also elapsed. Message 799
        -- stamps the expiry at least one frame before the status-effect packet puts buff 299
        -- into the buff array; clearing on bare absence destroys the expiry inside that gap
        -- and leaves the banner with no countdown for the whole Overload.
        if model.overloadRemaining(now) <= 0 then
            model.clearOverload()
        end
        a.overloadRemaining = 0
    end

    -- All eight maneuvers share recast timer 210. Raw values are 1/60-second ticks, matching
    -- getSeconds(); a missing key means the timer is not in the active list, i.e. ready, which
    -- the zeroing above already covers.
    --
    -- ceil, not floor: any remainder under one tick-second is still a second the server will
    -- reject the ability in. Flooring reports Ready while up to 59 ticks remain, so the row
    -- goes green ahead of the game.
    local entry = recastCache and recastCache[maneuvers.RECAST_ID]
    if entry and entry.recast > 0 then
        a.maneuverRecast = math.ceil(entry.recast / 60)
    end
end

-- Populate State from current Ashita memory. Called every frame before rendering.
-- @param State the shared state table from state.lua
-- Returns true when player data is valid (not zoning, not on title screen).
-- Returns false when the caller should suppress all rendering (send HIDDEN_TOKENS).
function data.refreshState(State)
    -- Cleared up front so getFrameRecastCache() never hands a later caller a scan from an
    -- earlier frame when one of the guards below returns early.
    frameRecastCache = nil

    -- Nil guards: bail out if game APIs are unavailable (title screen, etc.)
    if not AshitaCore then
        State.active = false
        return false
    end
    local memMgr = AshitaCore:GetMemoryManager()
    if not memMgr then
        State.active = false
        return false
    end

    local entityMgr = memMgr:GetEntity()
    local party     = memMgr:GetParty()
    local player    = memMgr:GetPlayer()

    if not entityMgr or not party or not player then
        State.active = false
        return false
    end

    -- 2hr timers: player-state timers that tick even when no pet is active.
    -- Placed before all pet-specific early returns so dismiss/recall doesn't freeze them.
    local function tick2hr(s, expireKey, remainingKey)
        if s[expireKey] then
            local remaining = s[expireKey] - os.time()
            if remaining > 0 then
                s[remainingKey] = remaining
            else
                s[expireKey]    = nil
                s[remainingKey] = 0
            end
        else
            s[remainingKey] = 0
        end
    end
    tick2hr(State.avatar,    'afExpireTime', 'afRemaining')
    tick2hr(State.wyvern,    'ssExpireTime', 'ssRemaining')
    tick2hr(State.automaton, 'odExpireTime', 'odRemaining')

    -- Jug countdown: also ticked ahead of the pet-presence early returns below, because on
    -- HorizonXI the jug pet's lifetime is absolute wall-clock from its original Call Beast.
    -- It keeps burning while the pet is unloaded -- across a zone line, and while the pet is
    -- suppressed entirely in a city zone. Absence must never freeze or restart this clock.
    if State.jug.expireTime then
        local jugRemaining = State.jug.expireTime - os.time()
        if jugRemaining > 0 then
            State.jug.remaining = jugRemaining
        else
            State.jug.expireTime = nil
            State.jug.remaining  = 0
            State.jug.duration   = 0
        end
    end

    -- mainJob == 0: no valid player data (title screen, disconnected, etc.)
    local mainJob = party:GetMemberMainJob(0) or 0
    if mainJob == 0 then
        State.active = false
        return false  -- signal caller to suppress rendering
    end
    local subJob = party:GetMemberSubJob(0) or 0

    -- Maneuver state is player state, read ahead of every pet-presence early return below: an
    -- Overload countdown keeps running after Deactivate, and so does the shared maneuver
    -- recast. Ownership goes through detectPetType, so a BST/PUP counts as a BST here as it
    -- does everywhere else. The scan below is this frame's only one: it is taken solely when a
    -- PUP needs timer 210, and getAbilityRecasts reuses it further down.
    local ownsAutomaton = data.detectPetType(mainJob, subJob, nil) == 'automaton'
    local recastCache   = nil
    if ownsAutomaton then
        recastCache = abilityRecast.scanAll()
    end
    frameRecastCache = recastCache
    refreshManeuverBuffs(State, player, ownsAutomaton, recastCache)

    -- Get player entity to find pet via PetTargetIndex property
    local playerIdx = party:GetMemberTargetIndex(0)
    if not playerIdx or playerIdx == 0 then
        State.active = false
        return true
    end

    -- GetPlayerEntity() is an Ashita global that returns the player entity object
    local playerEntity = GetPlayerEntity()
    if not playerEntity or playerEntity.PetTargetIndex == 0 then
        State.active              = false
        State.petType             = nil
        State.bst.stayExpiry      = nil   -- pet gone, cancel stay
        -- Jug clock intentionally left running: no pet entity is the normal state in a city
        -- zone, and the pet returns with its remaining time when you step back into the field.
        State.target.active       = false
        State.target.serverId     = 0    -- clear so target bar doesn't linger on next charm
        State.target.pktServerId  = nil
        return true
    end

    local petIdx = playerEntity.PetTargetIndex
    local petEntity = GetEntity(petIdx)
    if not petEntity or petEntity.ActorPointer == 0 then
        -- PetTargetIndex is set but entity not loaded: pet is out of range (> 50 yalms).
        -- Keep the window showing with frozen HP/name; update TP/MP from player memory
        -- (player struct still exposes pet vitals even when the entity is unloaded).
        if State.active and State.petType then
            State.outOfRange = true
            State.mpp  = math.min(100, player:GetPetMPPercent() or 0)
            local rawTp = player:GetPetTP() or 0
            State.tp = (rawTp > 3000) and 0 or rawTp
            -- Recasts come from ability memory, not entity memory -- still readable.
            local recasts = data.getAbilityRecasts(State.petType, recastCache)
            State[State.petType].recasts = recasts
            -- Charm countdown ticks from expireTime (wall-clock, works out of range).
            -- Jug is already ticked above, ahead of every pet-presence branch.
            if State.petType == 'charm' and State.charm.expireTime then
                State.charm.remaining = math.max(0, State.charm.expireTime - os.time())
                State.charm.known     = true
            end
            -- Target bar requires entity data -- clear while out of range.
            State.target.active = false
        else
            -- No prior pet state (loaded while already out of range): fully clear.
            State.active           = false
            State.outOfRange       = false
            State.petType          = nil
            State.bst.stayExpiry = nil
            State.target.active    = false
            State.target.serverId  = 0
            State.target.pktServerId = nil
        end
        return true
    end

    -- Dead state: GetStatus returns 2 or 3 when entity is dead.
    -- Catches pet death faster than waiting for ActorPointer to clear.
    local petStatus = entityMgr:GetStatus(petIdx)
    if petStatus == 2 or petStatus == 3 then
        State.active          = false
        State.petType         = nil
        State.bst.stayExpiry  = nil
        -- Death genuinely ends a jug pet's lifetime, unlike mere absence above.
        State.jug.expireTime  = nil
        State.jug.duration    = 0
        State.jug.remaining   = 0
        State.target.active   = false
        State.target.serverId = 0
        State.target.pktServerId = nil
        return true
    end

    -- Pet is alive and present (in range)
    State.active     = true
    State.outOfRange = false
    State.name       = petEntity.Name or ''
    State.serverId = petEntity.ServerId or 0
    State.hpp      = math.min(100, petEntity.HPPercent or 0)
    State.dist     = math.sqrt(math.max(0, petEntity.Distance or 0))

    -- MP: use Player memory object (entity doesn't expose pet MP directly)
    State.mpp = math.min(100, player:GetPetMPPercent() or 0)

    -- TP: use Player memory object; values >3000 are memory garbage
    local rawTp = player:GetPetTP() or 0
    State.tp = (rawTp > 3000) and 0 or rawTp

    -- Pet type detection (subJob read above, ahead of the maneuver buff read)
    local detectedType = data.detectPetType(mainJob, subJob, State.name)
    State.petType = detectedType

    -- Cache BST type so detectPetType() can fall back to it when petName is nil
    if detectedType == 'jug' or detectedType == 'charm' then
        lastKnownBstType = detectedType
    end

    -- Pet level
    if State.petType == 'charm' then
        State.petLevel = State.charm.mobLevel or 0
    elseif State.petType then
        -- avatar/wyvern/automaton/jug all scale with player level
        State.petLevel = player:GetMainJobLevel() or 0
    else
        State.petLevel = 0
    end

    -- Recast data for current type
    if State.petType then
        local recasts = data.getAbilityRecasts(State.petType, recastCache)
        State[State.petType].recasts = recasts
    end

    -- Update jug pet name for token display
    if State.petType == 'jug' then
        State.jug.petName = State.name
    end

    -- Start the jug countdown. The duration is name-derived, so it resolves only once the pet
    -- entity has loaded, but the trigger is a confirmed Call Beast / Bestial Loyalty
    -- (pendingCall), not mere appearance: a pet that reappeared after a zone or a city visit
    -- keeps the clock it already had.
    -- The expireTime == nil arm is the cold-start fallback -- addon loaded (or reloaded past
    -- the persisted expiry) with a pet already out, so no summon was ever observed -- and
    -- assumes a freshly called pet.
    if State.petType == 'jug' and State.active and State.name ~= ''
        and (State.jug.pendingCall or State.jug.expireTime == nil) then
        local durSec = jugPetDurations[State.name] or DEFAULT_JUG_DURATION
        State.jug.expireTime  = os.time() + durSec
        State.jug.duration    = durSec
        State.jug.remaining   = durSec
        State.jug.pendingCall = false
    end

    -- A different pet type is out, so whatever jug owned this clock is long gone. Requires a
    -- positively resolved type: an unresolved nil must not tear down a live countdown, since
    -- detection briefly comes up empty while a respawning pet's name loads.
    if State.petType ~= nil and State.petType ~= 'jug' and State.jug.expireTime ~= nil then
        State.jug.expireTime  = nil
        State.jug.duration    = 0
        State.jug.remaining   = 0
        State.jug.pendingCall = false
    end

    -- Pet target, from two sources in priority order.
    --   1. The 0x0067/0x0068 pet sync packet (State.target.pktServerId), which the server
    --      populates authoritatively.
    --   2. Entity memory. GetTargetedIndex is documented "[Not always populated]"
    --      (AshitaSdk/ffxi/entity.h:181) and reads 0 for pets in practice; it covers only the
    --      window the packet cannot -- addon load or /reload mid-fight, before the first sync
    --      arrives.
    -- nil means no sync has been seen yet, so fall through to memory; 0 means the server
    -- reported no target and the bar must clear rather than hold the last one.
    local pktTargetId = State.target.pktServerId
    local targetIdx
    if pktTargetId == nil then
        targetIdx = entityMgr:GetTargetedIndex(petIdx)
    elseif pktTargetId ~= 0 then
        targetIdx = resolveTargetIndex(pktTargetId, entityMgr)
    end

    if targetIdx and targetIdx > 0 then
        local targetEntity = GetEntity(targetIdx)
        if targetEntity and targetEntity.ActorPointer ~= 0 and (targetEntity.HPPercent or 0) > 0 then
            State.target.name          = targetEntity.Name or ''
            State.target.hpp           = targetEntity.HPPercent or 0
            State.target.dist          = math.sqrt(math.max(0, targetEntity.Distance or 0))
            State.target.serverId = targetEntity.ServerId or 0
            State.target.active   = true
        else
            State.target.active   = false
            State.target.serverId = 0
        end
    else
        State.target.active   = false
        State.target.serverId = 0
    end

    -- Stay counter: per-frame movement check and tick reset
    -- First tick = 20s (set by packet handler), subsequent ticks = 10s each.
    -- Cancel if pet moves after the 1s grace period (stayExpiry - now < 19).
    if (State.petType == 'charm' or State.petType == 'jug') and State.bst.stayExpiry ~= nil then
        local petMovement = entityMgr:GetLocalMoveCount(petIdx)
        local remaining   = State.bst.stayExpiry - socket.gettime()
        if petMovement ~= 0 and remaining < 19 then
            State.bst.stayExpiry = nil        -- pet moved, cancel stay
        elseif remaining <= 0 then
            State.bst.stayExpiry = socket.gettime() + 10  -- tick done, start next 10s tick
        end
    end

    -- Update charm countdown from expireTime (set by packet handler on each charm cast)
    if State.petType == 'charm' and State.active and State.charm.expireTime then
        State.charm.remaining = math.max(0, State.charm.expireTime - os.time())
        State.charm.known     = true
    elseif State.petType ~= 'charm' and State.charm.known then
        -- Pet changed type or left -- clear stale charm state
        State.charm.expireTime    = nil
        State.charm.totalDuration = 0
        State.charm.remaining     = 0
        State.charm.known         = false
    end

    -- Familiar timer: countdown then count-up while pet alive; clear when pet dies
    if State.familiar.expireTime then
        if not State.active then
            -- Pet died or left: clear familiar state
            State.familiar.expireTime = nil
            State.familiar.remaining  = 0
            State.familiar.elapsed    = 0
        else
            local now       = os.time()
            local remaining = State.familiar.expireTime - now
            if remaining > 0 then
                State.familiar.remaining = remaining
                State.familiar.elapsed   = 0
            else
                -- Familiar expired, pet still alive: count up
                State.familiar.remaining = 0
                State.familiar.elapsed   = now - State.familiar.expireTime
            end
        end
    end

    return true  -- data is valid; caller may proceed with rendering
end


-- Returns the scanAll() result refreshState took this frame, or nil when it took none
-- (it only scans for a PUP, to read the shared maneuver recast).
--
-- Lets a caller outside this file feed the scan straight back into getAbilityRecasts and keep
-- the frame to a single 31-slot pass -- refreshState's copy is a function local, and
-- abilityrecast.lua publishes no accessor for the table scanAll() reuses. PetsReborn.lua's
-- alwaysShow branch is the one caller.
--
-- nil is a safe return: getAbilityRecasts falls back to its own scan. The table is reused per
-- frame -- never store it.
function data.getFrameRecastCache()
    return frameRecastCache
end

-- Returns [{name, remaining, max, norm, ready, charges, active}] for petType.
-- Scans all 31 recast slots once via scanAll(), then does O(1) lookups per ability.
-- @param recastCache optional scanAll() result for the current frame. Callers that already
--        hold one pass it so a frame never scans twice; omitting it takes a fresh scan.
--        abilityrecast.lua reuses that table, so it must not be stored across frames.
function data.getAbilityRecasts(petType, recastCache)
    local slots = data.getFilteredSlots(petType)
    if not slots then return {} end

    -- Cap to the pool size: recastRowPool only has MAX_RECAST_SLOTS entries, so any
    -- slot list longer than that must be silently truncated (petFrame.lua already
    -- warns once per pet-type switch; this runs every frame, so no warning here).
    local slotCount = math.min(#slots, MAX_RECAST_SLOTS)

    local cache = recastCache or abilityRecast.scanAll()   -- single 31-slot pass for this frame
    for i = 1, slotCount do
        local slot = slots[i]
        local row = recastRowPool[i]
        if slot.isChargeAbility then
            -- Charge-based ability (e.g. Ready): compute charges from raw timer.
            -- RecastCalc2 (modifier) stores the effective per-charge recast time in seconds.
            local entry      = cache[slot.id] or EMPTY_CHARGE_ENTRY
            local modifier   = entry.modifier
            local rawRecast  = entry.recast
            local maxCharges = slot.maxCharges or 3
            local basePerChg = slot.baseSecondsPerCharge or 45

            -- Use RecastCalc2 directly as per-charge seconds; fall back to baseSecondsPerCharge
            -- if modifier is unexpectedly 0 (ability not in active recast list).
            --
            -- UNITS: raw recast values read from ability memory via scanAll()
            -- (libs/ashita/abilityrecast.lua) are in 1/60-second ticks. The `* 60`
            -- below converts per-charge seconds to ticks so chargeValue matches
            -- rawRecast's unit, and the `/ 60` further down converts the remaining
            -- ticks back to whole seconds. Both are tick<->second unit conversions.
            local perChargeSec = modifier ~= 0 and modifier or basePerChg
            local chargeValue  = perChargeSec * 60

            local charges, nextSec
            if rawRecast <= 0 then
                charges = maxCharges
                nextSec = 0
            else
                local recharging = math.ceil(rawRecast / chargeValue)
                charges  = math.max(0, maxCharges - recharging)
                nextSec  = math.floor(((rawRecast - 1) % chargeValue + 1) / 60)
            end

            row.name            = slot.displayName
            row.remaining       = nextSec
            row.max             = perChargeSec
            row.norm            = nextSec > 0 and nextSec / math.max(1, perChargeSec) or 0
            row.ready           = charges >= maxCharges
            row.charges         = charges
            row.maxCharges      = maxCharges
            row.isChargeAbility = true
            row.isHealTimer     = nil
        elseif slot.isHealTimer then
            -- Timer is driven by bst.stayTicks token at render time; no memory read needed.
            row.name            = slot.displayName
            row.remaining       = 0
            row.max             = 0
            row.norm            = 0
            row.ready           = false
            row.charges         = 0
            row.maxCharges      = 0
            row.isChargeAbility = nil
            row.isHealTimer     = true
        else
            local entry        = cache[slot.id] or EMPTY_RECAST_ENTRY
            local remainingSec = entry.recast > 0 and math.floor(entry.recast / 60) or 0
            row.name            = slot.displayName
            row.remaining       = remainingSec
            row.max             = 0
            row.norm            = 0
            row.ready           = remainingSec == 0
            row.charges         = 0
            row.maxCharges      = 0
            row.isChargeAbility = nil
            row.isHealTimer     = nil
        end
    end
    -- result is a fresh array of *references* to pooled rows (cheap); only rows are pooled.
    local result = {}
    for i = 1, slotCount do
        result[i] = recastRowPool[i]
    end
    return result
end

return data
