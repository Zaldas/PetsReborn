-- modules/core.lua
-- Core pet frame elements: HP bar, TP bar, name, distance, timer, special label.
-- All pet types use these elements.
-- Registers name/distance/hp/tp/petTimer in posRegistry through M.register (at initialize and
-- on every petFrame.relayout), and 'special'/'overload' in finalizeLayout.

local uiContainer  = require('libs/spui/uiContainer')
local uiBar        = require('libs/spui/uiBar')
local uiText       = require('libs/spui/uiText')
local Utils        = require('utils')

local resY   = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local VIS_TOKEN = Utils.VIS_TOKEN

local M = {}

-- Element refs (set in initialize, cleared by root:dispose() in destroy)
local root         = nil
local hpBar        = nil
local hpText       = nil
local tpBar        = nil
local tpText       = nil
local nameText     = nil
local distText     = nil
local timerText    = nil
local specialText = nil
local overloadText = nil

-- Cached color tables (avoid allocations per frame)
local tpFullColor    = nil
local tpDefaultColor = nil

-- Track last tp full state to avoid redundant color sets
local lastTpFull = false

-- Section extras: img/bg elements created from layout sections.
-- Keyed by section name, each entry = { img, imgBind, bg, bgBind }.
local sectionExtras = {}

-- Shared position registry (injected from petFrame.lua)
local posRegistry = nil

-- petFrame layout section and the layout-space origins of the hp/tp/name/distance sections
local layout   = nil
local hpPos    = nil
local tpPos    = nil
local namePos  = { x = 0, y = 0 }
local distPos  = { x = 0, y = 0 }

-- Cached timer layout-space position (re-resolved from its anchor on each relayout)
local timerX = 0
local timerY = 0

-- Cached special label layout-space position (resolved from its anchor in finalizeLayout)
local specialX = 0
local specialY = 0

-- Cached Overload banner layout-space position (resolved from its anchor in finalizeLayout)
local overloadX = 0
local overloadY = 0

-- Whether the Overload label currently sits raised above the 2hr label. Overload is authored
-- into the 2hr slot and yields it whenever a 2hr label is showing, so this tracks the last
-- seen pet.specialActive and gates the reposition to the transition -- positionAt() runs
-- layoutElement(), and update() is on the d3d_present path.
local overloadRaised = false

-- Add element as a child of root at layout-space relative position.
local function addElement(element, relX, relY)
    if not root then return end
    element.posX = relX
    element.posY = relY
    root:addChild(element)
    element:createPrimitives()
    element:hide(VIS_TOKEN)
end

-- Update an element's layout-space position and refresh absolute coords.
-- parent must already be set (via addElement / root:addChild).
local function positionAt(element, relX, relY)
    element.posX = relX
    element.posY = relY
    element:layoutElement()
end

-- Move a section's img/bg extras to base + their own pos, the offsets createSectionExtras uses.
local function positionExtras(name, baseX, baseY)
    local ex  = sectionExtras[name]
    local sec = layout and layout[name]
    if not ex or not sec then return end
    if ex.img then
        positionAt(ex.img, baseX + (sec.img.pos and sec.img.pos[1] or 0), baseY + (sec.img.pos and sec.img.pos[2] or 0))
    end
    if ex.bg then
        positionAt(ex.bg, baseX + (sec.bg.pos and sec.bg.pos[1] or 0), baseY + (sec.bg.pos and sec.bg.pos[2] or 0))
    end
end

-- Reposition timer from current registry state; returns its posRegistry entry.
local function repositionTimer(posReg)
    if not timerText or not layout or not layout.petTimer then return nil end
    local L  = layout
    local tb = Utils.resolveAnchor(L.petTimer.anchor, posReg)
    timerX = tb.x + L.petTimer.pos[1] + L.petTimer.txt.pos[1]
    timerY = tb.y + L.petTimer.pos[2] + L.petTimer.txt.pos[2]
    positionAt(timerText, timerX, timerY)
    positionExtras('petTimer', timerX, timerY)
    return { x = timerX, y = timerY, h = (L.petTimer.txt.size or 12) + (L.petTimer.marginBottom or 0) }
end

local function repositionTwoHour(posReg)
    if not layout or not layout.special then return end
    local L  = layout
    local tb = Utils.resolveAnchor(L.special.anchor, posReg)
    specialX = tb.x + L.special.pos[1]
    specialY = tb.y + L.special.pos[2]
    if specialText then positionAt(specialText, specialX + L.special.txt.pos[1], specialY + L.special.txt.pos[2]) end
    positionExtras('special', specialX, specialY)
    if posReg then
        posReg['special'] = { x = specialX, y = specialY, h = (L.special.txt.size or 12) + (L.special.marginBottom or 0) }
    end
end

-- raisedOffset is optional: absent, Overload never leaves the 2hr slot and simply overlaps
-- the 2hr label when both are up.
local function repositionOverload(posReg)
    if not layout or not layout.overload then return end
    local L  = layout
    local tb = Utils.resolveAnchor(L.overload.anchor, posReg)
    local ro = L.overload.raisedOffset
    local rx, ry = 0, 0
    if ro and overloadRaised then rx = ro[1] or 0; ry = ro[2] or 0 end
    overloadX = tb.x + L.overload.pos[1] + rx
    overloadY = tb.y + L.overload.pos[2] + ry
    if overloadText then positionAt(overloadText, overloadX + L.overload.txt.pos[1], overloadY + L.overload.txt.pos[2]) end
    positionExtras('overload', overloadX, overloadY)
    if posReg then
        posReg['overload'] = { x = overloadX, y = overloadY, h = (L.overload.txt.size or 12) + (L.overload.marginBottom or 0) }
    end
end

local function textEntry(sec, posReg)
    local a = Utils.resolveAnchor(sec.anchor, posReg)
    return { x = a.x + sec.pos[1], y = a.y + sec.pos[2], h = (sec.txt.size or 12) + (sec.marginBottom or 0) }
end

-- Move a text section and its extras to its registry entry, when that entry has moved.
local function syncTextSection(name, elem, cached)
    local entry = posRegistry and posRegistry[name]
    local sec   = layout and layout[name]
    if not elem or not entry or not sec then return end
    if entry.x == cached.x and entry.y == cached.y then return end
    cached.x = entry.x
    cached.y = entry.y
    positionAt(elem, entry.x + sec.txt.pos[1], entry.y + sec.txt.pos[2])
    positionExtras(name, entry.x, entry.y)
end

-- posRegistry entry builders for the elements this module owns, keyed by section name. Each
-- returns nil to leave the element unregistered: vis is petFrame's visibility state, and a nil
-- vis registers unconditionally.
local ENTRY_BUILDERS = {
    name = function(sec, posReg)
        return textEntry(sec, posReg)
    end,
    distance = function(sec, posReg, vis)
        if vis and not vis.showDistance then return nil end
        return textEntry(sec, posReg)
    end,
    hp = function(sec, posReg, vis)
        if vis and not vis.showHp then return nil end
        return Utils.barEntry(sec, posReg)
    end,
    tp = function(sec, posReg, vis)
        if vis and not vis.showTp then return nil end
        return Utils.barEntry(sec, posReg)
    end,
    -- Also moves the timer text and its section extras to the resolved position.
    petTimer = function(_, posReg, vis)
        if vis and not vis.showTimer then return nil end
        return repositionTimer(posReg)
    end,
}

function M.owns(elemName)
    return ENTRY_BUILDERS[elemName] ~= nil
end

-- Writes elemName's posRegistry entry from the layout and the entries it anchors to, and
-- returns it (nil when the layout has no such section or the element is hidden).
function M.register(elemName, posReg, vis)
    local build = ENTRY_BUILDERS[elemName]
    local sec   = layout and layout[elemName]
    if not build or not sec then return nil end
    local entry = build(sec, posReg, vis)
    if entry and posReg then
        posReg[elemName] = entry
    end
    return entry
end

-- Sets all elements' anchor and recomputes absolute positions.
function M.setAnchor(x, y)
    if not root then return end
    syncTextSection('name',     nameText, namePos)
    syncTextSection('distance', distText, distPos)
    local hp = posRegistry and posRegistry['hp']
    if hp and hpPos and layout and layout.hp and (hp.x ~= hpPos.x or hp.y ~= hpPos.y) then
        hpPos.x = hp.x
        hpPos.y = hp.y
        if hpBar then
            positionAt(hpBar, hpPos.x + layout.hp.bar.pos[1], hpPos.y + layout.hp.bar.pos[2])
        end
        if hpText then
            positionAt(hpText, hpPos.x + layout.hp.txt.pos[1], hpPos.y + layout.hp.txt.pos[2])
        end
        positionExtras('hp', hpPos.x, hpPos.y)
    end
    -- Sync tpPos from registry: TP shifts when MP becomes available (avatar/automaton).
    local tp = posRegistry and posRegistry['tp']
    if tp and tpPos then tpPos.x = tp.x; tpPos.y = tp.y end
    -- Update TP element positions (may have changed since last relayout).
    if tpBar  and layout and layout.tp then
        positionAt(tpBar,  tpPos.x + layout.tp.bar.pos[1], tpPos.y + layout.tp.bar.pos[2])
    end
    if tpText and layout and layout.tp then
        positionAt(tpText, tpPos.x + layout.tp.txt.pos[1], tpPos.y + layout.tp.txt.pos[2])
    end
    if layout and layout.tp then
        positionExtras('tp', tpPos.x, tpPos.y)
    end
    root:pos(x, y)
end

function M.initialize(eng, fullLayout, ax, ay, posReg, scale)
    layout      = fullLayout.petFrame
    posRegistry = posReg

    local s = scale or uiScale
    root = uiContainer.new()
    root:scale(s, s)
    root:pos(ax or 0, ay or 0)

    local L = layout

    -- Cache colors from layout
    if L.tp then
        tpFullColor    = L.tp.bar.tpFullColor and Utils.hexToColor(L.tp.bar.tpFullColor) or nil
        tpDefaultColor = L.tp.bar.imgBar      and Utils.hexToColor(L.tp.bar.imgBar.color) or { r = 142, g = 180, b = 249, a = 255 }
    end

    -- Name
    if L.name then
        local e = M.register('name', posReg)
        namePos = { x = e.x, y = e.y }
        nameText = uiText.new(L.name.txt)
        addElement(nameText, namePos.x + L.name.txt.pos[1], namePos.y + L.name.txt.pos[2])
    end

    -- Distance
    if L.distance then
        local e = M.register('distance', posReg)
        distPos = { x = e.x, y = e.y }
        distText = uiText.new(L.distance.txt)
        addElement(distText, distPos.x + L.distance.txt.pos[1], distPos.y + L.distance.txt.pos[2])
    end

    -- HP
    if L.hp then
        local hp = M.register('hp', posReg)
        hpPos = { x = hp.x, y = hp.y }
        hpBar = uiBar.new(L.hp.bar, eng)
        addElement(hpBar, hpPos.x + L.hp.bar.pos[1], hpPos.y + L.hp.bar.pos[2])
        hpText = uiText.new(L.hp.txt)
        addElement(hpText, hpPos.x + L.hp.txt.pos[1], hpPos.y + L.hp.txt.pos[2])
    end

    -- TP (initial position; may shift when MP registers later)
    if L.tp then
        local tp = M.register('tp', posReg)
        tpPos = { x = tp.x, y = tp.y }
        tpBar = uiBar.new(L.tp.bar, eng)
        addElement(tpBar, tpPos.x + L.tp.bar.pos[1], tpPos.y + L.tp.bar.pos[2])
        tpText = uiText.new(L.tp.txt)
        addElement(tpText, tpPos.x + L.tp.txt.pos[1], tpPos.y + L.tp.txt.pos[2])
    end

    -- Timer (2hr/familiar countdown)
    if L.petTimer then
        timerText = uiText.new(L.petTimer.txt)
        root:addChild(timerText)
        timerText:createPrimitives()
        timerText:hide(VIS_TOKEN)
        M.register('petTimer', posReg)
    end

    -- Special label (final position set by finalizeLayout)
    if L.special then
        specialText = uiText.new(L.special.txt)
        addElement(specialText, L.special.txt.pos[1], L.special.txt.pos[2])
    end

    -- PUP Overload banner. Owned here because petFrame.switchModule destroys the type module
    -- when petType goes nil -- the state straight after Deactivate, which the Overload effect
    -- outlives. This module is created once and never swapped. Its bind carries no pet.active
    -- term: data.lua zeroes overloadOn for anyone who does not own an automaton, so it cannot
    -- fire off-PUP.
    if L.overload then
        overloadText = uiText.new(L.overload.txt)
        addElement(overloadText, L.overload.txt.pos[1], L.overload.txt.pos[2])
    end

    -- Section extras: create optional img/bg elements for each section.
    sectionExtras = {}
    if L.name     then sectionExtras['name']     = Utils.createSectionExtras(L.name,     eng, namePos.x,         namePos.y,         root, VIS_TOKEN) end
    if L.distance then sectionExtras['distance'] = Utils.createSectionExtras(L.distance, eng, distPos.x,         distPos.y,         root, VIS_TOKEN) end
    if L.hp       then sectionExtras['hp']       = Utils.createSectionExtras(L.hp,       eng, hpPos.x,           hpPos.y,           root, VIS_TOKEN) end
    if L.tp       then sectionExtras['tp']       = Utils.createSectionExtras(L.tp,       eng, tpPos.x,           tpPos.y,           root, VIS_TOKEN) end
    if L.petTimer then sectionExtras['petTimer'] = Utils.createSectionExtras(L.petTimer, eng, timerX,            timerY,            root, VIS_TOKEN) end
    if L.special  then sectionExtras['special']  = Utils.createSectionExtras(L.special,  eng, specialX,          specialY,          root, VIS_TOKEN) end
    if L.overload then sectionExtras['overload'] = Utils.createSectionExtras(L.overload, eng, overloadX,         overloadY,         root, VIS_TOKEN) end

    lastTpFull     = false
    overloadRaised = false
end

function M.update(tokens)
    local L = layout

    if L.name     then Utils.applyBinds(nameText, L.name.txt.bind,      tokens, VIS_TOKEN) end
    if L.distance then Utils.applyBinds(distText, L.distance.txt.bind,  tokens, VIS_TOKEN) end
    if L.hp then
        Utils.applyBinds(hpBar,  L.hp.bar.bind, tokens, VIS_TOKEN, L.hp.thresholds)
        Utils.applyBinds(hpText, L.hp.txt.bind, tokens, VIS_TOKEN, L.hp.thresholds)
    end
    if L.tp then
        Utils.applyBinds(tpText, L.tp.txt.bind, tokens, VIS_TOKEN)
        Utils.applyBinds(tpBar,  L.tp.bar.bind, tokens, VIS_TOKEN)
    end
    if L.petTimer then Utils.applyBinds(timerText, L.petTimer.txt.bind, tokens, VIS_TOKEN) end

    if L.special then
        Utils.applyBinds(specialText, L.special.txt.bind, tokens, VIS_TOKEN)
    end

    if L.overload then
        Utils.applyBinds(overloadText, L.overload.txt.bind, tokens, VIS_TOKEN)
        -- Overload takes the 2hr slot and yields it back when a 2hr label appears. Overdrive
        -- starts and ends without a relayout, so the slot handover happens here, on the flip
        -- only.
        local raised = tokens['pet.specialActive'] == true
        if raised ~= overloadRaised then
            overloadRaised = raised
            repositionOverload(posRegistry)
        end
    end

    -- Section extras (img/bg elements declared in layout sections)
    Utils.updateSectionExtras(sectionExtras, tokens, VIS_TOKEN)

    -- TP full color: special case not expressible as a bind key
    local active = tokens['pet.active'] == true
    if active and L.tp then
        local tpFull = tokens['pet.tpFull'] == true
        if tpFull ~= lastTpFull then
            lastTpFull = tpFull
            if tpBar then tpBar:setColor(tpFull and tpFullColor or tpDefaultColor) end
        end
    end
end

-- Called by petFrame.relayout() after posRegistry['window'] is set.
-- Places special and overload, whose anchors may name 'window', and their section extras.
function M.finalizeLayout(posReg)
    repositionTwoHour(posReg)
    repositionOverload(posReg)
end

function M.destroy()
    if root then root:dispose(); root = nil end
    hpBar       = nil
    hpText      = nil
    tpBar       = nil
    tpText      = nil
    nameText    = nil
    distText    = nil
    timerText   = nil
    specialText = nil
    overloadText = nil
    sectionExtras = {}
    if posRegistry then
        posRegistry['name']     = nil
        posRegistry['distance'] = nil
        posRegistry['hp']       = nil
        posRegistry['tp']       = nil
        posRegistry['petTimer'] = nil
    end
    posRegistry    = nil
    lastTpFull     = false
    overloadRaised = false
end

return M
