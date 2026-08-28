-- elements/petFrame.lua
-- Pet frame orchestrator: manages spui engine, core module, and type-specific module.
-- Handles drag-to-move and anchor persistence.

local uiBackground        = require('libs/spui/uiBackground')
local coreModule          = require('modules/core')
local targetFrameModule   = require('elements/targetFrame')
local statusEffectsModule = require('modules/statusEffects')
local Utils               = require('utils')
local data                = require('data')
local petAbilities        = require('data/petAbilities')
local chat                = require('chat')
local avatarModule    = require('modules/avatar')
local wyvernModule    = require('modules/wyvern')
local automatonModule = require('modules/automaton')
local jugModule       = require('modules/jug')
local charmModule     = require('modules/charm')
local imgui           = require('imgui')

-- Layout values are authored at 1440p baseline.
local resY   = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local petFrame = {}

local VIS_TOKEN = Utils.VIS_TOKEN

local engine = nil   -- sprite engine (shared by all modules)
local bg     = nil   -- window background

local activeModule = nil
local activeType   = nil

local moduleRegistry = {
    avatar    = avatarModule,
    wyvern    = wyvernModule,
    automaton = automatonModule,
    jug       = jugModule,
    charm     = charmModule,
}

-- Window anchor
local anchorX     = 100
local anchorY     = 100
local anchorDirty = false
local alignBottom = false
local currentAlwaysShow = false

-- Visibility state: mp/tp only; recast sizing handled by module.getVisibleRowCount()
local currentVis  = { showHp=true, showMp=true, showTp=true }
local lastVisHash = -1   -- -1 forces relayout on first update
local lastRowCount = -1  -- -1 forces the recast re-pack on first update

-- Drag state
local dragActive  = false
local dragOffsetX = 0
local dragOffsetY = 0

local layoutRef   = nil
local posRegistry = {}
local layoutOrder = {}

-- Status tooltip cache: [statusId] = { name, desc }
local statusTooltipCache = {}

-- Mouse message IDs (Win32)
local MSG_LBUTTON_DOWN = 513
local MSG_LBUTTON_UP   = 514
local MSG_MOUSEMOVE    = 512

local WIN_WIDTH  = 330
local WIN_HEIGHT = 110

local function computeLayoutHeight()
    local L = layoutRef and layoutRef.petFrame
    if not L then return 110 end

    if currentAlwaysShow and activeType and L.recast and L.recast.alwaysShowFirstRowPos then
        local rc = posRegistry['recast']
        return (rc and (rc.y + (rc.h or 0)) or 0) + (L.marginBottom or 8)
    end

    local contentBottom = 0
    for _, entry in pairs(posRegistry) do
        if entry.h then
            local bottom = entry.y + entry.h
            if bottom > contentBottom then contentBottom = bottom end
        end
    end
    return contentBottom + (L.marginBottom or 8)
end

local function renderY()
    return alignBottom and (anchorY - WIN_HEIGHT) or anchorY
end

-- Screen-pixel leftward extension of the drag rect over a module's side column (PUP
-- maneuvers), so clicking the column moves the window. Affects the hit rectangle only: no
-- sprite is resized and no position offset. Queried per click, so it cannot go stale against
-- the column's own visibility toggle.
local function columnOffsetX()
    if activeModule and activeModule.getColumnWidth then
        local w = activeModule.getColumnWidth()
        if w then return -math.floor(w * uiScale) end
    end
    return 0
end

local function hitTest(x, y)
    local ry = renderY()
    return x >= anchorX + columnOffsetX() and x <= anchorX + WIN_WIDTH
       and y >= ry                        and y <= ry + WIN_HEIGHT
end

local function applyAnchor()
    local ry = renderY()
    if bg then bg:pos(anchorX, ry) end
    coreModule.setAnchor(anchorX, ry)
    if activeModule and activeModule.setAnchor then
        activeModule.setAnchor(anchorX, ry)
    end
    local se = posRegistry['statusEffects']
    if se then
        statusEffectsModule.setAnchor(
            anchorX + math.floor(se.x * uiScale),
            ry      + math.floor(se.y * uiScale))
    else
        statusEffectsModule.setAnchor(anchorX, ry + WIN_HEIGHT)
    end
    local tbL = layoutRef and layoutRef.targetFrame
    local tba = Utils.resolveAnchor(tbL and tbL.anchor, posRegistry)
    -- targetFrame.pos offsets the whole bar from its resolved anchor; absent means flush.
    local tbX, tbY = 0, 0
    if tbL and tbL.pos then
        tbX = tbL.pos[1] or 0
        tbY = tbL.pos[2] or 0
    end
    targetFrameModule.setAnchor(anchorX + math.floor((tba.x + tbX) * uiScale),
                                ry      + math.floor((tba.y + tbY) * uiScale))
end

function petFrame.initialize(sprites, layout, anchor, isAlignBottom, scale, opts)
    layoutRef   = layout
    layoutOrder = Utils.buildLayoutOrder(layout.petFrame)
    anchorX     = anchor and anchor.x or 100
    anchorY     = anchor and anchor.y or 100
    alignBottom = isAlignBottom == true
    anchorDirty = false
    posRegistry = {}
    -- Both caches describe the registry that was just discarded. Left in place they suppress
    -- the relayout the rebuilt window needs.
    lastVisHash  = -1
    lastRowCount = -1

    if scale and scale > 0 then
        uiScale = scale
    else
        uiScale = resY / 1440
    end

    WIN_WIDTH = math.floor((layout.petFrame.baseWidth or 185) * uiScale)

    engine = sprites.newEngine()

    bg = uiBackground.new(layout.petFrame.background, engine)
    bg:scale(uiScale, uiScale)
    bg:pos(anchorX, renderY())
    bg:createPrimitives()
    bg:hide(VIS_TOKEN)

    coreModule.initialize(engine, layout, anchorX, renderY(), posRegistry, uiScale)
    statusEffectsModule.initialize(engine, layout, anchorX, renderY() + WIN_HEIGHT, uiScale, opts)
    targetFrameModule.initialize(engine, layout, anchorX, renderY() + WIN_HEIGHT, uiScale)

    activeModule = nil
    activeType   = nil
end

-- Rebuild posRegistry and resize the window.
local function relayout(vis)
    if not layoutRef then return end
    local L = layoutRef.petFrame

    for k in pairs(posRegistry) do posRegistry[k] = nil end

    for _, elemName in ipairs(layoutOrder) do
        if elemName == 'name' then
            if L.name then
                posRegistry['name'] = { x = L.name.pos[1], y = L.name.pos[2], h = (L.name.txt.size or 12) + (L.name.marginBottom or 0) }
            end

        elseif elemName == 'hp' then
            if vis.showHp and L.hp then
                local a = Utils.resolveAnchor(L.hp.anchor, posRegistry)
                posRegistry['hp'] = { x = a.x + L.hp.pos[1], y = a.y + L.hp.pos[2], h = L.hp.bar.imgFg.size[2] + (L.hp.marginBottom or 0) }
            end

        elseif elemName == 'mp' then
            if activeModule and activeModule.relayout then
                activeModule.relayout(posRegistry, vis)
            end

        elseif elemName == 'tp' then
            if vis.showTp and L.tp then
                local a = Utils.resolveAnchor(L.tp.anchor, posRegistry)
                posRegistry['tp'] = { x = a.x + L.tp.pos[1], y = a.y + L.tp.pos[2], h = L.tp.bar.imgFg.size[2] + (L.tp.marginBottom or 0) }
            end

        elseif elemName == 'recast' then
            if activeType and L.recast then
                local rows = activeModule and activeModule.getVisibleRowCount and activeModule.getVisibleRowCount() or 0
                local rc = L.recast
                local rcX, rcY
                if currentAlwaysShow and rc.alwaysShowFirstRowPos then
                    rcX = rc.alwaysShowFirstRowPos[1]
                    rcY = rc.alwaysShowFirstRowPos[2]
                else
                    local a = Utils.resolveAnchor(rc.anchor, posRegistry)
                    rcX = a.x + rc.firstRowPos[1]
                    rcY = a.y + rc.firstRowPos[2]
                end
                posRegistry['recast'] = { x = rcX, y = rcY, h = rows * rc.rowHeight + (rc.marginBottom or 0) }
            end

        elseif elemName == 'statusEffects' then
            local seL = L.statusEffects
            if seL then
                local a = Utils.resolveAnchor(seL.anchor, posRegistry)
                local seTimerExt = 0
                if seL.timer then
                    local timerBase = ((seL.timer.pos and seL.timer.pos[2]) or 0) + (seL.timer.size or 8)
                    seTimerExt = math.max(0, timerBase - (seL.iconSize or 18))
                end
                posRegistry['statusEffects'] = {
                    x = a.x + (seL.pos and seL.pos[1] or 0),
                    y = a.y + (seL.pos and seL.pos[2] or 0),
                    h = (seL.iconSize or 18) + seTimerExt + (seL.marginBottom or 4),
                }
            end
        end
    end

    if activeModule and activeModule.finalizeLayout then
        activeModule.finalizeLayout(posRegistry)
    end

    local layoutH = computeLayoutHeight()
    WIN_HEIGHT = math.floor(layoutH * uiScale)
    posRegistry['window'] = { x = 0, y = 0, h = layoutH }
    if bg then bg:setHeight(layoutH) end
    -- Runs after the frame's own height, not in finalizeLayout: a module painting a panel
    -- beside the frame needs the figure computeLayoutHeight produces from the registry that
    -- finalizeLayout has only just written.
    if activeModule and activeModule.setFrameHeight then
        activeModule.setFrameHeight(layoutH)
    end
    coreModule.finalizeLayout(posRegistry)
    applyAnchor()
end
petFrame.relayout = relayout

-- Relayout with the current visibility state, for callers that have no vis table of their
-- own. Modules reach this through package.loaded['elements/petFrame'] -- a top-level require
-- would recurse, since this file requires the modules.
function petFrame.requestRelayout()
    relayout(currentVis)
end

-- Switch to a new type module. savedVis is the persisted recastVisible table for this type.
function petFrame.switchModule(newType, savedVis)
    -- The new module builds its rows with the pet-presence gate still closed, so the relayout
    -- below packs only the rows that survive it. update() opens the gate a moment later and the
    -- row-count check is what re-packs the rest -- but the count it compares against belongs to
    -- the module being replaced, and two types that show the same number of rows would leave
    -- the pet-gated rows on their build-time coordinates.
    lastRowCount = -1

    if activeModule then
        activeModule.destroy()
        activeModule = nil
    end

    activeType = newType

    if newType and moduleRegistry[newType] then
        local mod = moduleRegistry[newType]

        -- Copied, not referenced: the truncation below must not mutate data.lua's cached list,
        -- which getAbilityRecasts() indexes to build the pet.recast[N] tokens these rows read.
        local slots = {}
        for i, slot in ipairs(data.getFilteredSlots(newType) or {}) do
            slots[i] = slot
        end

        local MAX_RECAST_SLOTS = petAbilities.MAX_ROWS
        if #slots > MAX_RECAST_SLOTS then
            print(chat.header(addon.name) .. chat.warning(string.format('%s has %d recast slots, showing only the first %d', newType, #slots, MAX_RECAST_SLOTS)))
            for i = #slots, MAX_RECAST_SLOTS + 1, -1 do
                slots[i] = nil
            end
        end

        mod.initialize(engine, layoutRef, anchorX, renderY(), posRegistry, slots, uiScale, savedVis)
        activeModule = mod

        relayout(currentVis)

        if currentAlwaysShow and activeModule.repositionRecasts then
            activeModule.repositionRecasts(true)
        end
    end
end

-- Update a single recast visibility entry in the active module and trigger relayout.
-- Called by petsreborn when a config checkbox changes.
function petFrame.setRecastVisible(petType, id, val)
    if activeType == petType and activeModule and activeModule.setRecastVisible then
        activeModule.setRecastVisible(id, val)
        relayout(currentVis)
    end
end

-- Whether the frame's background should be drawn at all.
--
-- With a pet out it always is. Without one, alwaysShow leaves only the recast rows that survive
-- the pet-presence gate, plus what core.lua keeps counting down past the pet: the 2hr timer and
-- the PUP Overload banner, which both outlive a Deactivate. With none of those the background
-- would be an empty box.
local function backgroundVisible(tokens, rowCount)
    if tokens['pet.active'] == true then return true end
    if tokens['pet.alwaysShow'] ~= true then return false end
    if tokens['pet.timerActive'] == true or tokens['pet.overloadActive'] == true then
        return true
    end
    return tokens['ui.showRecasts'] ~= false and rowCount > 0
end

function petFrame.update(tokens)
    local newAlwaysShow = tokens['pet.alwaysShow'] == true
    if newAlwaysShow ~= currentAlwaysShow then
        currentAlwaysShow = newAlwaysShow
        relayout(currentVis)
        if activeModule and activeModule.repositionRecasts then
            activeModule.repositionRecasts(currentAlwaysShow)
        end
    end

    local h = (tokens['ui.showMpBar'] ~= false and 2 or 0)
            + (tokens['ui.showTpBar'] ~= false and 4 or 0)
            + (tokens['pet.mppActive'] == true  and 1 or 0)
    if h ~= lastVisHash then
        lastVisHash = h
        currentVis = {
            showHp = true,
            showMp = tokens['ui.showMpBar'] ~= false,
            showTp = tokens['ui.showTpBar'] ~= false,
            hasMp  = tokens['pet.mppActive'] == true,
        }
        relayout(currentVis)
    end

    coreModule.update(tokens)
    if activeModule then activeModule.update(tokens) end

    -- Pet-requiring rows appear and disappear as the pet comes and goes, so the row list
    -- changes length during the module's update. Resize the frame around the new count;
    -- relayout's applyAnchor re-packs the rows themselves.
    local rowCount = (activeModule and activeModule.getVisibleRowCount)
                        and activeModule.getVisibleRowCount() or 0
    if rowCount ~= lastRowCount then
        lastRowCount = rowCount
        relayout(currentVis)
    end

    -- Drawn after the row count is known, because in alwaysShow the row count is the only
    -- thing that decides whether the frame has anything in it.
    if bg then
        if backgroundVisible(tokens, rowCount) then bg:show(VIS_TOKEN) else bg:hide(VIS_TOKEN) end
    end
    statusEffectsModule.update(tokens)
    targetFrameModule.update(tokens)
end

function petFrame.getStatusAtPosition(mx, my)
    return statusEffectsModule.getStatusAtPosition(mx, my)
end

-- Render the status icon hover tooltip if the mouse is over a status icon.
function petFrame.drawStatusTooltip(mouseX, mouseY)
    local hoveredStatus = petFrame.getStatusAtPosition(mouseX, mouseY)
    if hoveredStatus then
        local info = statusTooltipCache[hoveredStatus]
        if info == nil then
            local resMgr = AshitaCore:GetResourceManager()
            local name   = resMgr:GetString('buffs.names', hoveredStatus)
            local icon   = resMgr:GetStatusIconByIndex(hoveredStatus)
            local desc   = (icon and icon.Description and icon.Description[1]) or ''
            info = { name = name or '???', desc = desc }
            statusTooltipCache[hoveredStatus] = info
        end
        imgui.BeginTooltip()
        imgui.Text(info.name .. ' (#' .. hoveredStatus .. ')')
        if info.desc ~= '' then imgui.Text(info.desc) end
        imgui.EndTooltip()
    end
end

function petFrame.getActiveType()
    return activeType
end

function petFrame.getActiveModule()
    return activeModule
end

function petFrame.getAnchor()
    if anchorDirty then
        anchorDirty = false
        return { x = anchorX, y = anchorY }
    end
    return nil
end

function petFrame.setAnchor(x, y)
    anchorX = x
    anchorY = y
    applyAnchor()
end

function petFrame.setAlignBottom(val)
    alignBottom = val == true
    applyAnchor()
end

function petFrame.handleMouse(e)
    if e.message == MSG_LBUTTON_DOWN then
        if hitTest(e.x, e.y) then
            dragActive  = true
            dragOffsetX = e.x - anchorX
            dragOffsetY = e.y - anchorY
            e.blocked   = true
        end

    elseif e.message == MSG_LBUTTON_UP then
        if dragActive then
            dragActive  = false
            anchorDirty = true
            e.blocked   = true
        end

    elseif e.message == MSG_MOUSEMOVE then
        if dragActive then
            local newX = e.x - dragOffsetX
            local newY = e.y - dragOffsetY
            if newX ~= anchorX or newY ~= anchorY then
                anchorX = newX
                anchorY = newY
                applyAnchor()
            end
            e.blocked = true
        end
    end
end

function petFrame.destroy()
    if bg then bg:dispose(); bg = nil end
    coreModule.destroy()
    statusEffectsModule.destroy()
    targetFrameModule.destroy()
    if activeModule then
        activeModule.destroy()
        activeModule = nil
        activeType   = nil
    end
    if engine then
        engine:destroy()
        engine = nil
    end
    posRegistry = {}
end

return petFrame
