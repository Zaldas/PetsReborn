-- petsreborn.lua
-- Pet window HUD for FFXI (Ashita v4)
-- Supports: SMN (avatar), DRG (wyvern), PUP (automaton), BST (jug/charm)
--
-- Commands:
--   /petsreborn reload        -- reload layout and settings
--   /petsreborn debug         -- print current pet state to chat
--   /pr                       -- alias for /petsreborn (toggles config window)

addon.name    = 'PetsReborn'
addon.author  = 'Zaldas'
addon.version = '1.1'
addon.desc    = 'Comprehensive pet window HUD for all pet jobs'
addon.link    = 'https://github.com/Zaldas/PetsReborn'

require('common')
local chat  = require('chat')
local statusLib = require('libs/status/status')
statusLib.init({ addonPath = addon.path, addonName = addon.name, enableAuditLog = false })

-- Addon modules
local settings  = require('settings')
local State     = require('state')
local data         = require('data')
local packets   = require('packets')
local sprites   = require('libs/spui/sprites')
local layoutEditor = require('libs/spui/layoutEditor')
local petFrame     = require('elements/petFrame')
local configWindow = require('elements/configWindow')
local ManeuverBurden = require('modules/maneuverBurden')
local automatonIcd   = require('modules/automatonIcd')

-- Default settings (Ashita settings library manages config/addons/petsreborn/settings.json)
local defaultSettings = T{
    layout      = 'ffxi',      -- which style file to load from layouts/ ('ffxi', 'xiv', ...)
    visible     = true,
    anchor      = T{ x = 100, y = 100 },
    alignBottom    = false,     -- when true, anchor is bottom-left; window grows upward
    alwaysShow     = false,     -- when true, show recasts even without an active pet
    lockPosition   = false,     -- when true, dragging is disabled
    scale          = 0,         -- 0 = auto (resY/1440); >0 = user multiplier (0.25-2.5)
    verbose        = true,      -- when false, suppress command confirmation messages
    -- Per-component visibility toggles
    showMpBar          = true,
    showTpBar          = true,
    showTargetBar      = true,
    showRecasts        = true,
    showManeuvers      = true,
    showAutomatonIcd   = true,   -- automaton head cooldown + attachment recast rows
    -- Per-ability recast visibility: [petType][abilityId] = false to hide, nil/absent = show
    recastVisible = T{
        avatar    = T{},
        wyvern    = T{},
        automaton = T{},
        jug       = T{},
        charm     = T{},
    },
    layoutOverrides = T{},      -- [styleName][keypath] = value
    hideStatusWhenEmpty = true,   -- hide status effects strip when no effects are active
    -- Automaton HP readout: 'value' (exact HP from the 0x0044 PUP packet) or 'percent'.
    -- Only the automaton has an exact figure to show, so no other pet type reads this.
    automatonHpDisplay = 'value',
    -- Charm duration persistence (os.time() expiry; 0 = none)
    charmExpireTime    = 0,
    charmTotalDuration = 0,
    -- Jug duration persistence (os.time() expiry; 0 = none)
    jugExpireTime = 0,
    jugDuration   = 0,
}

local prSettings   = defaultSettings
local layout       = nil        -- merged layout table

-- Cutscene / interface-hidden detection.
local pGameMenu        = ashita.memory.find('FFXiMain.dll', 0, "8B480C85C974??8B510885D274??3B05", 16, 0)
local pEventSystem     = ashita.memory.find('FFXiMain.dll', 0, "A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3", 0, 0)
local pInterfaceHidden = ashita.memory.find('FFXiMain.dll', 0, "8B4424046A016A0050B9????????E8????????F6D81BC040C3", 0, 0)

local menuCheckCounter = 0
local cachedMenuHidden = false

local function getMenuName()
    if pGameMenu == 0 then return '' end
    local subPointer = ashita.memory.read_uint32(pGameMenu)
    if subPointer == 0 then return '' end
    local subValue   = ashita.memory.read_uint32(subPointer)
    if subValue == 0 then return '' end
    local menuHeader = ashita.memory.read_uint32(subValue + 4)
    local menuName   = ashita.memory.read_string(menuHeader + 0x46, 16)
    -- selene: allow(bad_string_escape)
    return string.gsub(tostring(menuName), '\x00', '')
end

-- Returns true during cutscenes, NPC dialogue, world map, and player-hidden HUD.
-- pInterfaceHidden checked before getMenuName to avoid the string.gsub allocation on early exit.
local function isGameInterfaceHidden()
    if pEventSystem ~= 0 then
        local ptr = ashita.memory.read_uint32(pEventSystem + 1)
        if ptr ~= 0 and ashita.memory.read_uint8(ptr) == 1 then return true end
    end
    if pInterfaceHidden ~= 0 then
        local ptr = ashita.memory.read_uint32(pInterfaceHidden + 10)
        if ptr ~= 0 and ashita.memory.read_uint8(ptr + 0xB4) == 1 then return true end
    end
    menuCheckCounter = (menuCheckCounter + 1) % 10
    if menuCheckCounter == 0 then
        cachedMenuHidden = string.match(getMenuName(), 'map') ~= nil
    end
    return cachedMenuHidden
end

-- Minimal token set that causes all pet window modules to hide their sprites.
local HIDDEN_TOKENS = { ['pet.active'] = false, ['pet.alwaysShow'] = false }

-- Shared read-only empty table for the no-pet status-token branch; never mutated
-- (statusEffects.lua only reads these tokens via ipairs/pairs).
local EMPTY_STATUS_TABLE = {}

-- Debug view: when set, bypasses Ashita memory and renders fake data instead.
local debugViewType = nil
local debugTimerSnapshot = nil -- real State.* timer values captured on debug-view entry; restored on exit

-- Maneuver preview data, indexed by data/maneuvers.lua element order:
-- 1 fire, 2 ice, 3 wind, 4 earth, 5 thunder, 6 water, 7 light, 8 dark.
-- The counts total 6, above the live maneuvers.MAX_ACTIVE of 3: the preview exercises all
-- three cluster sizes at once, which no real session shows.
-- Thunder carries burden with no maneuver up -- the residual case, where the percentage is
-- decoupled from pip state and the row draws an outline pip AND a number.
local DEBUG_MANEUVER_COUNTS = { [1] = 3, [4] = 2, [7] = 1 }
local DEBUG_MANEUVER_PCT    = { [1] = 78, [4] = 42, [5] = 15 }

-- Seconds until each element's soonest maneuver drops. Fire sits inside the layout's blink
-- threshold so the preview shows the expiry pulse on its LAST pip -- the one that vanishes at
-- the drop -- while earth and light stay well clear. These do not count down: populateFakeState
-- re-stamps them every frame, and the pulse animates off the wall clock.
local DEBUG_MANEUVER_REMAINING = { [1] = 8, [4] = 40, [7] = 55 }

-- Built once and reused: populateFakeState runs every frame, so ManeuverBurden.new() here
-- would allocate eight tables at 60Hz.
local debugBurdenModel = nil
local _callbacks       = nil   -- built once; closures capture prSettings upvalue so always current
local prevPetServerId  = 0     -- tracks last pet server ID; used for clearEntity on pet change
local lastPlayerLevel  = -1    -- tracks player level for ability slot filtering on level sync changes
local lastIcdSignature = nil   -- tracks automaton head/frame/attachments for internal-cooldown rows
local isZoning         = true  -- suppresses frame until first valid data (cleared on load too)
local zoneInReceived   = true  -- true at startup (treat as already arrived); false between 0x00B and 0x00A

-- Mouse state: updated every mouse event; used for status icon hover tooltip.
local mouseX = 0
local mouseY = 0

local function printStateSnapshot()
    print(chat.header(addon.name) .. chat.message(string.format('active=%s type=%s name=%s hpp=%d mpp=%d tp=%d dist=%.1f',
        tostring(State.active), tostring(State.petType), State.name,
        State.hpp, State.mpp, State.tp, State.dist)))
    -- 2hr timer state
    if State.avatar.afRemaining and State.avatar.afRemaining > 0 then
        print(chat.message(string.format('  AstralFlow: %.0fs remaining', State.avatar.afRemaining)))
    end
    if State.wyvern.ssRemaining and State.wyvern.ssRemaining > 0 then
        print(chat.message(string.format('  SpiritSurge: %.0fs remaining', State.wyvern.ssRemaining)))
    end
    if State.automaton.odRemaining and State.automaton.odRemaining > 0 then
        print(chat.message(string.format('  Overdrive: %.0fs remaining', State.automaton.odRemaining)))
    end
    if State.petType == 'automaton' then
        -- nil until a 0x0044 arrives; maxMp 0 means the frame has no MP pool
        -- (Valoredge/Sharpshot). Compare hp/mp against hpp/mpp above to spot a stale packet.
        local a = State.automaton
        print(chat.message(string.format('  automaton hp=%s/%s mp=%s/%s',
            tostring(a.hp), tostring(a.maxHp), tostring(a.mp), tostring(a.maxMp))))
    end
    print(chat.message(string.format('  alwaysShow=%s', tostring(prSettings.alwaysShow))))
    if State.petType and State[State.petType] then
        local recasts = State[State.petType].recasts or {}
        for i, r in ipairs(recasts) do
            print(chat.message(string.format('  recast[%d] %s: %.1fs %s',
                i, r.name, r.remaining, r.ready and '(Ready)' or '')))
        end
    end
    if State.target.active then
        print(chat.message(string.format('  target: %s hpp=%d dist=%.1f',
            State.target.name, State.target.hpp, State.target.dist)))
    end
end

-- Captures the current real State.* timer values before debug view overwrites them.
local function snapshotTimerState()
    return {
        charmExpireTime    = State.charm.expireTime,
        charmTotalDuration = State.charm.totalDuration,
        charmKnown         = State.charm.known,
        charmRemaining     = State.charm.remaining,
        charmMobLevel      = State.charm.mobLevel,
        jugPetName         = State.jug.petName,
        jugExpireTime      = State.jug.expireTime,
        jugRemaining       = State.jug.remaining,
        jugDuration        = State.jug.duration,
        familiarExpireTime = State.familiar.expireTime,
        familiarRemaining  = State.familiar.remaining,
        familiarElapsed    = State.familiar.elapsed,
        bstStayExpiry      = State.bst.stayExpiry,
        -- The live model instance, not its contents. The preview swaps a separate instance
        -- into this field, so the real per-element burden and Overload expiry survive it.
        burdenModel        = State.automaton.burdenModel,
        -- The preview fakes a Harlequin's vitals, which would otherwise overwrite the real
        -- figures -- notably the 0 maxMp a Valoredge or Sharpshot reports, leaving the live
        -- MP bar showing.
        automatonHp        = State.automaton.hp,
        automatonMaxHp     = State.automaton.maxHp,
        automatonMp        = State.automaton.mp,
        automatonMaxMp     = State.automaton.maxMp,
    }
end

-- Restores real State.* timer values captured by snapshotTimerState(). No-op when snap is nil.
local function restoreTimerState(snap)
    if snap == nil then return end
    State.charm.expireTime    = snap.charmExpireTime
    State.charm.totalDuration = snap.charmTotalDuration
    State.charm.known         = snap.charmKnown
    State.charm.remaining     = snap.charmRemaining
    State.charm.mobLevel      = snap.charmMobLevel
    State.jug.petName         = snap.jugPetName
    State.jug.expireTime      = snap.jugExpireTime
    State.jug.remaining       = snap.jugRemaining
    State.jug.duration        = snap.jugDuration
    State.familiar.expireTime = snap.familiarExpireTime
    State.familiar.remaining  = snap.familiarRemaining
    State.familiar.elapsed    = snap.familiarElapsed
    State.bst.stayExpiry      = snap.bstStayExpiry
    State.automaton.burdenModel = snap.burdenModel
    State.automaton.hp          = snap.automatonHp
    State.automaton.maxHp       = snap.automatonMaxHp
    State.automaton.mp          = snap.automatonMp
    State.automaton.maxMp       = snap.automatonMaxMp
end

-- Preview type the config window opens on: the pet the player's current job owns, falling
-- back to DEBUG_TYPES[1] in configWindow.lua when neither job has one. Every type
-- detectPetType can return is in that list. BST resolves through the same jug/charm fallback
-- the live path uses, so it previews whichever was last out.
local DEBUG_VIEW_FALLBACK = 'avatar'

local function defaultDebugView()
    local memMgr = AshitaCore and AshitaCore:GetMemoryManager()
    local party  = memMgr and memMgr:GetParty()
    if not party then return DEBUG_VIEW_FALLBACK end
    local mainJob = party:GetMemberMainJob(0) or 0
    if mainJob == 0 then return DEBUG_VIEW_FALLBACK end
    local subJob = party:GetMemberSubJob(0) or 0
    return data.detectPetType(mainJob, subJob, nil) or DEBUG_VIEW_FALLBACK
end

local function applyDebugView(typeOrNil)
    local entering = typeOrNil ~= nil and debugViewType == nil
    local leaving  = typeOrNil == nil and debugViewType ~= nil

    if entering then
        debugTimerSnapshot = snapshotTimerState()
    elseif leaving then
        restoreTimerState(debugTimerSnapshot)
        debugTimerSnapshot = nil
    end
    debugViewType = typeOrNil

    -- petFrame relayouts on three triggers only: an alwaysShow transition, an mp/tp
    -- visibility change, and a change in visible row count. Crossing into or out of the
    -- debug view is none of them, and switchModule fires only on a pet TYPE change, so
    -- previewing the type already out leaves the previous layout in place.
    if entering or leaving then
        petFrame.requestRelayout()
    end
end

-- Print only when verbose is enabled.
local function vprint(msg)
    if prSettings.verbose ~= false then
        print(msg)
    end
end

-- Populates the shared State table with fake data for a given pet type.
-- Debug path calls this instead of data.refreshState(); the rest of the pipeline
-- (buildTokenTable, switchModule, update) is then identical to the live path.
-- Recasts are generated from data.abilitySlots so debug stays in sync with live slot config.
local function populateFakeState(petType)
    State.reset()

    State.active   = true
    State.petType  = petType
    State.name     = ''
    State.hpp      = 75
    State.mpp      = 0
    State.tp       = 800
    State.dist     = 6.2
    State.serverId = 0

    State.target.active   = true
    State.target.name     = 'Goblin Lancer'
    State.target.hpp      = 62
    State.target.dist     = 8.4
    State.target.serverId = 1

    -- Generate fake recasts from abilitySlots -- always in sync with live slot config.
    -- Odd slots shown as ready (green), even slots shown as cooling down (white).
    -- norm = fraction elapsed (>0.70 = orange, ready = green, else white)
    local slots     = data.getFilteredSlots(petType) or {}
    local typeState = State[petType]
    if typeState then
        typeState.recasts = {}
        for i, slot in ipairs(slots) do
            local ready      = (i % 2 == 1)
            local maxCharges = slot.maxCharges or 0
            typeState.recasts[i] = {
                name       = slot.displayName,
                remaining  = ready and 0 or (25 + i * 10),
                norm       = ready and 0 or 0.30,
                ready      = ready,
                charges    = maxCharges > 0 and (ready and maxCharges or 1) or 0,
                maxCharges = maxCharges,
            }
        end
    end

    if petType == 'avatar' then
        State.name = 'Carbuncle'
        State.mpp  = 68
        State.avatar.afRemaining = 120   -- 2:00 Astral Flow

    elseif petType == 'wyvern' then
        State.name = 'Wyvern'
        State.hpp  = 100
        State.tp   = 0
        State.wyvern.ssRemaining = 90    -- 1:30 Spirit Surge

    elseif petType == 'automaton' then
        State.name = 'Automaton'
        State.mpp  = 85
        State.automaton.odRemaining = 60 -- 1:00 Overdrive

        -- Overdrive and Overload both on. They are not mutually exclusive: Overdrive raises
        -- OVERLOAD_THRESH by 5000 so no NEW overload can start, but an Overload already
        -- running keeps its duration. This is the layout case overload.raisedOffset covers:
        -- the OVERLOAD label lifts clear of the Overdrive countdown sharing the 2hr slot.
        local a = State.automaton

        -- Harlequin at 75. A frame with an MP pool is the case worth previewing: the Valoredge
        -- and Sharpshot layout is this one minus the MP row. Derived from the fake percentages
        -- so resolveVital reads the figures out rather than treating them as a stale packet.
        a.maxHp = 1859
        a.maxMp = 246
        a.hp    = math.floor(a.maxHp * State.hpp / 100)
        a.mp    = math.floor(a.maxMp * State.mpp / 100)
        a.overdriveOn       = true
        a.overloadOn        = true
        a.overloadRemaining = 23        -- 0:23 left, shown on the strip's recast row in red
        a.maneuverRecast    = 6         -- recast row is replaced by the Overload countdown
        a.maneuverCount     = 3         -- live value is capped at maneuvers.MAX_ACTIVE

        for i = 1, 8 do
            a.maneuverCounts[i]    = DEBUG_MANEUVER_COUNTS[i] or 0
            a.maneuverRemaining[i] = DEBUG_MANEUVER_REMAINING[i] or 0
        end

        -- A dedicated instance, never the live one: the real model holds per-element burden
        -- and the Overload expiry that must survive the preview. restoreTimerState puts the
        -- real reference back on exit.
        if debugBurdenModel == nil then
            debugBurdenModel = ManeuverBurden.new()
        end
        a.burdenModel = debugBurdenModel

        -- Re-stamped every frame so decay never accumulates against these entries: a
        -- preview holds still. Stamping mutates in place and allocates nothing.
        local burdenNow = os.time()
        for i, pct in pairs(DEBUG_MANEUVER_PCT) do
            debugBurdenModel.stamp(i, pct)
        end

        -- The countdown reads a.overloadRemaining above, but pet.overloadTimer renders '--'
        -- unless the model also holds an expiry -- that flag is what separates "addon loaded
        -- mid-Overload, duration unknown" from a real countdown. setOverload takes the
        -- reported chance, which is the remaining seconds plus OVERLOAD_OFFSET.
        debugBurdenModel.setOverload(
            a.overloadRemaining + debugBurdenModel.OVERLOAD_OFFSET, burdenNow)

    elseif petType == 'jug' then
        State.name = 'CourierCarrie'
        State.hpp  = 90
        State.tp   = 300
        State.jug.petName        = 'CourierCarrie'
        State.jug.remaining      = 270   -- 4:30 left
        State.jug.duration       = 1800
        State.familiar.expireTime = 1    -- non-nil triggers Familiar branch
        State.familiar.remaining  = 180  -- 3:00 Familiar

    elseif petType == 'charm' then
        State.name = 'Goblin Mugger'
        State.hpp  = 62
        State.mpp  = 65
        State.tp   = 1500
        State.charm.known         = true
        State.charm.remaining     = 185   -- 3:05 left
        State.charm.totalDuration = 600   -- 10 min charm duration for norm calc
        State.familiar.expireTime = 1     -- non-nil triggers Familiar branch
        State.familiar.remaining  = 180   -- 3:00 Familiar
    end
end

-- Load layout from layouts/ directory.
-- Each style file is a complete standalone layout; no base+override merging.
local function loadLayout()
    local styleName = prSettings.layout or 'ffxi'
    local layoutPath = addon.path .. 'layouts/' .. styleName .. '.lua'
    if not ashita.fs.exists(layoutPath) then
        layoutPath = addon.path .. 'layouts/ffxi.lua'
    end
    local fn = loadfile(layoutPath)
    if fn then
        local ok, result = pcall(fn)
        if ok and type(result) == 'table' then
            return result
        end
    end
    return { name = styleName }
end

local resY = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local function getEffectiveScale()
    if prSettings.scale and prSettings.scale > 0 then
        return prSettings.scale
    end
    return resY / 1440
end

local function statusEffectsOpts()
    return {
        addonName = addon.name,
        onMissing = function(statusId, path)
            if prSettings.verbose ~= false then
                print(chat.header(addon.name) .. chat.warning(
                    string.format('missing status icon: id=%d  %s', statusId, path)))
            end
        end,
    }
end

local function rebuildWindow()
    layout = loadLayout()
    local styleName = prSettings.layout or 'ffxi'
    local styleOverrides = prSettings.layoutOverrides and prSettings.layoutOverrides[styleName]
    if styleOverrides and next(styleOverrides) then
        layoutEditor.applyOverrides(layout, styleOverrides)
    end
    petFrame.destroy()
    petFrame.initialize(sprites, layout, prSettings.anchor, prSettings.alignBottom, getEffectiveScale(), statusEffectsOpts())
    -- If debug view is active, reload the type module immediately so the new layout/style is
    -- visible right away.
    -- savedVis must be passed: recastRows.create resets recastVisible to whatever it gets,
    -- and slotEnabled treats a missing entry as shown, so omitting it un-hides every row the
    -- user turned off.
    if debugViewType then
        local savedVis = prSettings.recastVisible and prSettings.recastVisible[debugViewType]
        petFrame.switchModule(debugViewType, savedVis)
    end
end

local function buildCallbacks()
    return {
        onAlwaysShow = function(v)
            prSettings.alwaysShow = v
            settings.save()
        end,
        onAlignBottom = function(v)
            prSettings.alignBottom = v
            petFrame.setAlignBottom(v)
            settings.save()
        end,
        onStyle = function(name)
            prSettings.layout = name
            settings.save()
            rebuildWindow()
        end,
        onScale = function(v)
            prSettings.scale = v
            settings.save()
            rebuildWindow()
        end,
        onDebugView = applyDebugView,
        onShowMpBar = function(v)
            prSettings.showMpBar = v
            settings.save()
        end,
        onShowTpBar = function(v)
            prSettings.showTpBar = v
            settings.save()
        end,
        onRecastVisible = function(petType, id, val)
            if not prSettings.recastVisible then prSettings.recastVisible = T{} end
            if not prSettings.recastVisible[petType] then prSettings.recastVisible[petType] = T{} end
            prSettings.recastVisible[petType][tostring(id)] = val
            petFrame.setRecastVisible(petType, id, val)
            settings.save()
        end,
        onShowTargetBar = function(v)
            prSettings.showTargetBar = v
            settings.save()
        end,
        onShowRecasts = function(v)
            prSettings.showRecasts = v
            settings.save()
        end,
        -- automaton.update applies the ui.showManeuvers transition itself, shrinking the frame
        -- around the hidden column; rebuildWindow() follows this file's idiom for
        -- geometry-affecting settings (onStyle, onScale).
        onShowManeuvers = function(v)
            prSettings.showManeuvers = v
            settings.save()
            rebuildWindow()
        end,
        -- Needs no rebuildWindow: the toggle moves automatonIcd's signature, which the
        -- present loop already re-packs the recast rows on.
        onShowAutomatonIcd = function(v)
            prSettings.showAutomatonIcd = v
            settings.save()
        end,
        onHideStatusWhenEmpty = function(v)
            prSettings.hideStatusWhenEmpty = v
            settings.save()
        end,
        onAutomatonHpDisplay = function(v)
            prSettings.automatonHpDisplay = v
            settings.save()
        end,
        onVerbose = function(v)
            prSettings.verbose = v
            settings.save()
        end,
        onLockPosition = function(v)
            prSettings.lockPosition = v
            settings.save()
        end,
        onReload = function()
            prSettings = settings.load(defaultSettings)
            data.init()
            rebuildWindow()
            configWindow.initialize(addon.path .. 'layouts/', true)
            vprint(chat.header(addon.name) .. chat.message('Reloaded.'))
        end,
        onResetPosition = function()
            prSettings.anchor = T{ x = 100, y = 100 }
            petFrame.setAnchor(100, 100)
            settings.save()
            vprint(chat.header(addon.name) .. chat.message('Position reset.'))
        end,
    }
end

-- addon load
ashita.events.register('load', 'petsreborn_load_cb', function()
    data.init()
    prSettings = settings.load(defaultSettings)
    layout     = loadLayout()

    -- Restore charm duration from last session if it hasn't expired yet
    if prSettings.charmExpireTime and prSettings.charmExpireTime > os.time() then
        State.charm.expireTime    = prSettings.charmExpireTime
        State.charm.totalDuration = prSettings.charmTotalDuration or 0
        State.charm.known         = true
    end

    -- Restore jug duration from last session if it hasn't expired yet
    if prSettings.jugExpireTime and prSettings.jugExpireTime > os.time() then
        State.jug.expireTime = prSettings.jugExpireTime
        State.jug.duration   = prSettings.jugDuration or 0
    end

    configWindow.initialize(addon.path .. 'layouts/')
    rebuildWindow()

    layoutEditor.register({
        displayName = 'PetsReborn',
        getLayout = function()
            return layout
        end,
        getBase = function()
            return loadLayout()
        end,
        getOverrides = function()
            local style = prSettings.layout or 'ffxi'
            if not prSettings.layoutOverrides then
                return nil
            end
            return prSettings.layoutOverrides[style]
        end,
        setOverride = function(path, value)
            local style = prSettings.layout or 'ffxi'
            if not prSettings.layoutOverrides then
                prSettings.layoutOverrides = T{}
            end
            if not prSettings.layoutOverrides[style] then
                prSettings.layoutOverrides[style] = T{}
            end
            prSettings.layoutOverrides[style][path] = value
            settings.save()
            rebuildWindow()
        end,
        deleteOverride = function(path)
            local style = prSettings.layout or 'ffxi'
            local styleOverrides = prSettings.layoutOverrides and prSettings.layoutOverrides[style]
            if styleOverrides then
                styleOverrides[path] = nil
                if next(styleOverrides) == nil then
                    prSettings.layoutOverrides[style] = nil
                end
            end
            settings.save()
            rebuildWindow()
        end,
        clearOverrides = function()
            local style = prSettings.layout or 'ffxi'
            if not prSettings.layoutOverrides then
                prSettings.layoutOverrides = T{}
            end
            prSettings.layoutOverrides[style] = nil
            settings.save()
            rebuildWindow()
        end,
    })

    -- Register for settings changes (e.g., user edits settings.json externally)
    settings.register('settings', 'petsreborn_settings_update', function(s)
        if s then
            prSettings = s
            rebuildWindow()
        end
    end)

    print(chat.header(addon.name) .. chat.message('Loaded. /petsreborn or /pr for commands.'))
end)

-- addon unload
ashita.events.register('unload', 'petsreborn_unload_cb', function()
    ashita.events.unregister('d3d_present', 'petsreborn_present_cb')
    ashita.events.unregister('packet_in', 'petsreborn_packet_in_cb')
    ashita.events.unregister('packet_out', 'petsreborn_packet_out_cb')
    ashita.events.unregister('command', 'petsreborn_command_cb')
    ashita.events.unregister('mouse', 'petsreborn_mouse_cb')
    statusLib.SaveState()
    statusLib.Dispose()
    configWindow.destroy()
    petFrame.destroy()
    settings.save()
end)

-- Main render loop
ashita.events.register('d3d_present', 'petsreborn_present_cb', function()
    -- Config window draws regardless of pet window visibility
    if _callbacks == nil then _callbacks = buildCallbacks() end
    configWindow.draw(prSettings, _callbacks, debugViewType)

    if not prSettings.visible then return end

    -- Hide during cutscenes, NPC dialogue, world map, and player-hidden HUD.
    if isGameInterfaceHidden() then
        petFrame.update(HIDDEN_TOKENS)
        return
    end

    -- Ahead of both paths: this decides which rows getFilteredSlots returns, and the debug
    -- view builds its preview from that same list.
    automatonIcd.setEnabled(prSettings.showAutomatonIcd ~= false)

    -- Populate State: debug writes fake data; live reads from Ashita memory.
    -- Both paths then share the same buildTokenTable -> tokens -> petFrame pipeline.
    if debugViewType then
        populateFakeState(debugViewType)
    else
        -- Suppress frame while zoning: wait until the player entity is spawned in the new zone.
        -- GetMemberTargetIndex(0) == 0 means the player character doesn't exist yet (loading screen).
        if isZoning then
            -- Between 0x00B (zone-out) and 0x00A (zone-in): entity may still be alive in
            -- memory, so don't check it -- suppress unconditionally until arrival packet fires.
            if not zoneInReceived then
                petFrame.update(HIDDEN_TOKENS)
                return
            end
            -- Arrived in new zone; wait for player entity to spawn before resuming.
            local zonePty = AshitaCore:GetMemoryManager():GetParty()
            if not zonePty or (zonePty:GetMemberTargetIndex(0) or 0) == 0 then
                petFrame.update(HIDDEN_TOKENS)
                return
            end
            isZoning = false
        end

        if not data.refreshState(State) then
            petFrame.update(HIDDEN_TOKENS)
            return
        end

        -- Internal cooldowns follow the automaton entity, so one automaton's timers are never
        -- read against the next. Live path only: the debug view must not touch real timers.
        local icdPetId = 0
        if State.petType == 'automaton' and State.active then
            icdPetId = State.serverId or 0
        end
        automatonIcd.trackPet(icdPetId)

        -- alwaysShow: when pet is not active, detect type from job and populate recasts
        if prSettings.alwaysShow and not State.active then
            local p = AshitaCore:GetMemoryManager():GetParty()
            local jobType = p and data.detectPetType(p:GetMemberMainJob(0) or 0, p:GetMemberSubJob(0) or 0, nil)
            if jobType then
                State.petType = jobType
                local typeState = State[jobType]
                if typeState then
                    -- Reuses refreshState's scan for this frame. A PUP with no pet out scans
                    -- for the shared maneuver recast, so omitting the cache here costs a
                    -- second 31-slot pass. nil (any non-PUP) falls back to a fresh scan.
                    typeState.recasts = data.getAbilityRecasts(jobType, data.getFrameRecastCache())
                end
            end
        end
    end

    local tokens      = State.buildTokenTable(State)
    local currentType = State.petType
    tokens['pet.alwaysShow'] = prSettings.alwaysShow == true and not State.active and State.petType ~= nil

    -- Pet status effects tokens: populated here so debug mode can inject fake data.
    if debugViewType then
        local now = os.time()
        tokens['pet.statusIds']  = { 1, 3, 4, 33, 43, 65 }
        tokens['pet.statusTimes'] = {
            [1]  = now + 245,
            [3]  = now + 47,
            [4]  = now + 120,
            [33] = now + 180,
            [43] = now + 30,
            [65] = now + 90,
        }
    else
        local sid = State.serverId or 0
        if sid ~= prevPetServerId then
            if prevPetServerId ~= 0 then
                statusLib.clearTrackedEntity(prevPetServerId)
            end
            prevPetServerId = sid
        end
        if State.active and sid ~= 0 then
            tokens['pet.statusIds']  = statusLib.GetStatusIdsById(sid) or {}
            tokens['pet.statusTimes'] = statusLib.GetStatusTimesById(sid) or {}
        else
            tokens['pet.statusIds']  = EMPTY_STATUS_TABLE
            tokens['pet.statusTimes'] = EMPTY_STATUS_TABLE
        end
    end

    -- UI visibility tokens: applied after token build for both debug and live paths
    tokens['ui.showMpBar']     = prSettings.showMpBar ~= false
    tokens['ui.showTpBar']     = prSettings.showTpBar ~= false
    tokens['ui.showTargetBar'] = prSettings.showTargetBar ~= false
    tokens['ui.showRecasts']   = prSettings.showRecasts ~= false
    tokens['ui.showManeuvers'] = prSettings.showManeuvers ~= false
    -- Ungated by pet type: for everything but the automaton, buildTokenTable already set
    -- pet.hpText to pet.hppPct, so this is a no-op. hppPct carries the outOfRange '???'.
    if prSettings.automatonHpDisplay == 'percent' then
        tokens['pet.hpText'] = tokens['pet.hppPct']
    end
    -- pet.statusActive: true when effects are present OR user chose not to hide the empty strip.
    -- pet.active is the outer gate (in layout bind.visible); this token only owns the effects/setting part.
    local statusIds = tokens['pet.statusIds']
    tokens['pet.statusActive'] = (statusIds and #statusIds > 0) or (prSettings.hideStatusWhenEmpty == false)

    -- Detect level changes (main or sub) for level sync; reinit module to refilter ability slots.
    -- Encode both levels into one value so either changing triggers a reinit.
    local playerMem  = AshitaCore:GetMemoryManager():GetPlayer()
    local mainLv     = playerMem and playerMem:GetMainJobLevel() or -1
    local subLv      = playerMem and playerMem:GetSubJobLevel()  or -1
    local curLevel   = mainLv * 1000 + subLv
    local levelChanged = mainLv ~= -1 and curLevel ~= lastPlayerLevel
    if levelChanged then lastPlayerLevel = curLevel end

    -- Switch type module when pet type changes or level changed (refilters slots).
    -- The automaton's internal-cooldown rows depend on its head and attachments, which a
    -- 0x0044 can change at any time, and the head also decides the order they render in.
    local icdSignature = automatonIcd.signature()
    local icdChanged   = icdSignature ~= lastIcdSignature
    if icdChanged then lastIcdSignature = icdSignature end

    if petFrame.getActiveType() ~= currentType or levelChanged or icdChanged then
        local savedVis = prSettings.recastVisible and prSettings.recastVisible[currentType]
        petFrame.switchModule(currentType, savedVis)
    end

    -- Update all pet window elements from tokens
    petFrame.update(tokens)

    -- Status icon hover tooltip
    petFrame.drawStatusTooltip(mouseX, mouseY)

    -- Persist charm and jug durations across reloads (live path only)
    if not debugViewType then
        local cet = State.charm.expireTime or 0
        local jet = State.jug.expireTime   or 0
        local charmChanged = cet ~= (prSettings.charmExpireTime or 0)
            or State.charm.totalDuration ~= (prSettings.charmTotalDuration or 0)
        local jugChanged = jet ~= (prSettings.jugExpireTime or 0)
            or State.jug.duration ~= (prSettings.jugDuration or 0)
        if charmChanged or jugChanged then
            prSettings.charmExpireTime    = cet
            prSettings.charmTotalDuration = State.charm.totalDuration or 0
            prSettings.jugExpireTime      = jet
            prSettings.jugDuration        = State.jug.duration or 0
            settings.save()
        end
    end

    -- Persist anchor position if user dragged the window
    local newAnch = petFrame.getAnchor()
    if newAnch then
        prSettings.anchor.x = newAnch.x
        prSettings.anchor.y = newAnch.y
        settings.save()
    end
end)

-- Packet handlers
ashita.events.register('packet_in', 'petsreborn_packet_in_cb', function(e)
    if e.id == 0x000B then
        -- Zone-out: player is leaving. Clear zoneInReceived so d3d_present suppresses
        -- unconditionally until 0x00A arrives (entity may still be alive when this fires).
        isZoning       = true
        zoneInReceived = false
        petFrame.update(HIDDEN_TOKENS)
        -- Close config window and clear debug view on zone transition.
        applyDebugView(nil)
        configWindow.close()
    elseif e.id == 0x000A then
        -- Zone-in: arrived in new zone. Allow d3d_present to use entity check to clear isZoning.
        isZoning       = true
        zoneInReceived = true
    end
    packets.handlePacketIn(e, State, petFrame.getActiveModule())
end)

ashita.events.register('packet_out', 'petsreborn_packet_out_cb', function(e)
    packets.handlePacketOut(e, State)
end)

-- Command handler
ashita.events.register('command', 'petsreborn_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or (args[1] ~= '/petsreborn' and args[1] ~= '/pr') then return end
    e.blocked = true

    local cmd = args[2] and args[2]:lower() or ''

    if cmd == 'help' then
        print(chat.header(addon.name) .. chat.message('/pr          Toggle config window'))
        print(chat.header(addon.name) .. chat.message('/pr reload   Reload settings and rebuild window'))
        print(chat.header(addon.name) .. chat.message('/pr debug    Print state snapshot to chat'))
    elseif cmd == 'reload' then
        prSettings = settings.load(defaultSettings)
        data.init()
        rebuildWindow()
        configWindow.initialize(addon.path .. 'layouts/', true)
        vprint(chat.header(addon.name) .. chat.message('Reloaded.'))
    elseif cmd == 'debug' then
        printStateSnapshot()
    elseif cmd == '' then
        configWindow.toggle()
        if configWindow.isOpen() then
            applyDebugView(defaultDebugView())
        else
            applyDebugView(nil)
        end
    else
        print(chat.header(addon.name) .. chat.warning('Unknown command: ' .. cmd .. '. Use /pr help for usage.'))
    end
end)

-- Mouse handler for drag-to-move
ashita.events.register('mouse', 'petsreborn_mouse_cb', function(e)
    mouseX = e.x
    mouseY = e.y
    if not prSettings.visible then return end
    if not prSettings.lockPosition then
        petFrame.handleMouse(e)
    end
end)
