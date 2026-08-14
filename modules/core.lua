-- modules/core.lua
-- Core pet frame elements: HP bar, TP bar, name, distance, timer, special label.
-- All pet types use these elements.
-- Populates posRegistry with 'hp', 'tp', 'timer' so other modules can anchor to them.

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

-- Cached timer layout-space position (for cascade when TP moves)
local timerX = 0
local timerY = 0

-- Cached special label layout-space position (resolved from window.bottom after relayout)
local specialX = 0
local specialY = 0

-- Cached Overload banner layout-space position (resolved from window.bottom after relayout)
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

-- Reposition timer from current registry state and re-register.
local function repositionTimer()
    if not timerText or not M.layout or not M.layout.petTimer then return end
    local L  = M.layout
    local tb = Utils.resolveAnchor(L.petTimer.anchor, posRegistry)
    timerX = tb.x + L.petTimer.pos[1] + L.petTimer.txt.pos[1]
    timerY = tb.y + L.petTimer.pos[2] + L.petTimer.txt.pos[2]
    positionAt(timerText, timerX, timerY)
    if posRegistry then
        posRegistry['petTimer'] = { x = timerX, y = timerY, h = (L.petTimer.txt.size or 12) + (L.petTimer.marginBottom or 0) }
    end
end

local function repositionTwoHour(posReg)
    if not M.layout or not M.layout.special then return end
    local L  = M.layout
    local tb = Utils.resolveAnchor(L.special.anchor, posReg)
    specialX = tb.x + L.special.pos[1]
    specialY = tb.y + L.special.pos[2]
    if specialText then positionAt(specialText, specialX + L.special.txt.pos[1], specialY + L.special.txt.pos[2]) end
    if posReg then
        posReg['special'] = { x = specialX, y = specialY, h = (L.special.txt.size or 12) + (L.special.marginBottom or 0) }
    end
end

-- raisedOffset is optional: absent, Overload never leaves the 2hr slot and simply overlaps
-- the 2hr label when both are up.
local function repositionOverload(posReg)
    if not M.layout or not M.layout.overload then return end
    local L  = M.layout
    local tb = Utils.resolveAnchor(L.overload.anchor, posReg)
    local ro = L.overload.raisedOffset
    local rx, ry = 0, 0
    if ro and overloadRaised then rx = ro[1] or 0; ry = ro[2] or 0 end
    overloadX = tb.x + L.overload.pos[1] + rx
    overloadY = tb.y + L.overload.pos[2] + ry
    if overloadText then positionAt(overloadText, overloadX + L.overload.txt.pos[1], overloadY + L.overload.txt.pos[2]) end
    if posReg then
        posReg['overload'] = { x = overloadX, y = overloadY, h = (L.overload.txt.size or 12) + (L.overload.marginBottom or 0) }
    end
end

-- Sets all elements' anchor and recomputes absolute positions.
function M.setAnchor(x, y)
    if not root then return end
    -- Sync tpPos from registry: TP shifts when MP becomes available (avatar/automaton).
    local tp = posRegistry and posRegistry['tp']
    if tp and M.tpPos then M.tpPos.x = tp.x; M.tpPos.y = tp.y end
    -- Update TP element positions (may have changed since last relayout).
    if tpBar  and M.layout and M.layout.tp then
        positionAt(tpBar,  M.tpPos.x + M.layout.tp.bar.pos[1], M.tpPos.y + M.layout.tp.bar.pos[2])
    end
    if tpText and M.layout and M.layout.tp then
        positionAt(tpText, M.tpPos.x + M.layout.tp.txt.pos[1], M.tpPos.y + M.layout.tp.txt.pos[2])
    end
    root:pos(x, y)
end

M.layout = nil
M.hpPos  = nil
M.tpPos  = nil

function M.initialize(eng, fullLayout, ax, ay, posReg, scale)
    M.layout    = fullLayout.petFrame
    posRegistry = posReg

    local s = scale or uiScale
    root = uiContainer.new()
    root:scale(s, s)
    root:pos(ax or 0, ay or 0)

    local L = M.layout

    -- Cache colors from layout
    if L.tp then
        tpFullColor    = L.tp.bar.tpFullColor and Utils.hexToColor(L.tp.bar.tpFullColor) or nil
        tpDefaultColor = L.tp.bar.imgBar      and Utils.hexToColor(L.tp.bar.imgBar.color) or { r = 142, g = 180, b = 249, a = 255 }
    end

    -- Name
    if L.name then
        if posReg then
            posReg['name'] = { x = L.name.pos[1], y = L.name.pos[2], h = (L.name.txt.size or 12) + (L.name.marginBottom or 0) }
        end
        nameText = uiText.new(L.name.txt)
        addElement(nameText, L.name.pos[1] + L.name.txt.pos[1], L.name.pos[2] + L.name.txt.pos[2])
    end

    -- Distance
    if L.distance then
        if posReg then
            posReg['distance'] = { x = L.distance.pos[1], y = L.distance.pos[2], h = (L.distance.txt.size or 12) + (L.distance.marginBottom or 0) }
        end
        distText = uiText.new(L.distance.txt)
        addElement(distText, L.distance.pos[1] + L.distance.txt.pos[1], L.distance.pos[2] + L.distance.txt.pos[2])
    end

    -- HP
    if L.hp then
        local hpAnchor = Utils.resolveAnchor(L.hp.anchor, posReg)
        M.hpPos = { x = hpAnchor.x + L.hp.pos[1], y = hpAnchor.y + L.hp.pos[2] }
        if posReg then
            posReg['hp'] = { x = M.hpPos.x, y = M.hpPos.y, h = L.hp.bar.imgFg.size[2] + (L.hp.marginBottom or 0) }
        end
        hpBar = uiBar.new(L.hp.bar, eng)
        addElement(hpBar, M.hpPos.x + L.hp.bar.pos[1], M.hpPos.y + L.hp.bar.pos[2])
        hpText = uiText.new(L.hp.txt)
        addElement(hpText, M.hpPos.x + L.hp.txt.pos[1], M.hpPos.y + L.hp.txt.pos[2])
    end

    -- TP (initial position; may shift when MP registers later)
    if L.tp then
        local tpBase = Utils.resolveAnchor(L.tp.anchor, posReg)
        M.tpPos = { x = tpBase.x + L.tp.pos[1], y = tpBase.y + L.tp.pos[2] }
        if posReg then
            posReg['tp'] = { x = M.tpPos.x, y = M.tpPos.y, h = L.tp.bar.imgFg.size[2] + (L.tp.marginBottom or 0) }
        end
        tpBar = uiBar.new(L.tp.bar, eng)
        addElement(tpBar, M.tpPos.x + L.tp.bar.pos[1], M.tpPos.y + L.tp.bar.pos[2])
        tpText = uiText.new(L.tp.txt)
        addElement(tpText, M.tpPos.x + L.tp.txt.pos[1], M.tpPos.y + L.tp.txt.pos[2])
    end

    -- Timer (2hr/familiar countdown)
    if L.petTimer then
        timerText = uiText.new(L.petTimer.txt)
        root:addChild(timerText)
        timerText:createPrimitives()
        timerText:hide(VIS_TOKEN)
        repositionTimer()
    end

    -- Special label (window.bottom-anchored; final position set by finalizeLayout)
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
    if L.name     then sectionExtras['name']     = Utils.createSectionExtras(L.name,     eng, L.name.pos[1],     L.name.pos[2],     root, VIS_TOKEN) end
    if L.distance then sectionExtras['distance'] = Utils.createSectionExtras(L.distance, eng, L.distance.pos[1], L.distance.pos[2], root, VIS_TOKEN) end
    if L.hp       then sectionExtras['hp']       = Utils.createSectionExtras(L.hp,       eng, M.hpPos.x,         M.hpPos.y,         root, VIS_TOKEN) end
    if L.tp       then sectionExtras['tp']       = Utils.createSectionExtras(L.tp,       eng, M.tpPos.x,         M.tpPos.y,         root, VIS_TOKEN) end
    if L.petTimer then sectionExtras['petTimer'] = Utils.createSectionExtras(L.petTimer, eng, timerX,             timerY,            root, VIS_TOKEN) end
    if L.special  then sectionExtras['special']  = Utils.createSectionExtras(L.special,  eng, specialX,           specialY,          root, VIS_TOKEN) end
    if L.overload then sectionExtras['overload'] = Utils.createSectionExtras(L.overload, eng, overloadX,          overloadY,         root, VIS_TOKEN) end

    lastTpFull     = false
    overloadRaised = false
end

function M.update(tokens)
    local L = M.layout

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
    if timerText  then Utils.applyBinds(timerText,  L.petTimer and L.petTimer.txt.bind,  tokens, VIS_TOKEN) end

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
-- Resolves window.bottom-anchored elements (special label + its background).
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
        posRegistry['hp']       = nil
        posRegistry['tp']       = nil
        posRegistry['petTimer'] = nil
    end
    posRegistry    = nil
    lastTpFull     = false
    overloadRaised = false
end

function M.onPacket(_) end

return M
