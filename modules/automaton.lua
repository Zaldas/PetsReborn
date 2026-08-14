-- modules/automaton.lua
-- PUP automaton-specific elements: MP bar + 6 ability recast rows + the maneuver column.
-- Registers 'mp' in posRegistry so base.lua can anchor TP dynamically.
-- The Overload banner lives in modules/core.lua, which is never swapped: petFrame.switchModule
-- destroys this module when petType goes nil (straight after Deactivate), which is exactly when
-- the Overload countdown still matters.

local uiContainer  = require('libs/spui/uiContainer')
local uiBar        = require('libs/spui/uiBar')
local uiText       = require('libs/spui/uiText')
local Utils        = require('utils')
local RecastRows   = require('modules/recastRows')
local ManeuverRows = require('modules/maneuverRows')

local resY   = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local VIS_TOKEN = Utils.VIS_TOKEN

local M = {}

local root         = nil
local mpBar        = nil
local mpText       = nil
local recastRows   = RecastRows.new()
local maneuverRows = ManeuverRows.new()
local layout       = nil
local posRegistry  = nil

-- Mirrors ui.showManeuvers so update() can act on the transition rather than every frame.
-- Both this and the maneuverRows instance survive a rebuildWindow (module locals are cached
-- by require), so the two never drift apart.
local maneuversEnabled = true

local mpPos = { x = 0, y = 0 }

-- petFrame requires this module at load, so a top-level require of it here would recurse.
-- update() only ever runs from inside petFrame.update, so the module is always in the
-- require cache by the time this fires.
local function requestRelayout()
    local petFrame = package.loaded['elements/petFrame']
    if petFrame and petFrame.requestRelayout then petFrame.requestRelayout() end
end

function M.repositionRecasts(isAlwaysShow)
    recastRows.reposition(isAlwaysShow)
end

function M.setRecastVisible(id, val)
    recastRows.setVisible(id, val)
end

function M.getVisibleRowCount()
    return recastRows.getVisibleCount()
end

function M.setAnchor(x, y)
    recastRows.reposition(nil)
    maneuverRows.setAnchor(x, y)
    if root then root:pos(x, y) end
end

-- Width of the maneuver column in layout-space pixels (petFrame applies uiScale). Read only
-- to widen the frame's drag hit-rect over the column; no sprite is sized or moved from it.
-- Returns nil when the layout declares no maneuvers section or the column is switched off,
-- which leaves the drag region at the frame's authored width.
--
-- firstRowPos and rowHeight are tested here even though this function does not use them:
-- they are what maneuverRows.create requires before it builds anything, and the two gates must
-- agree. A partial section (layout sections are optional and user-authorable) declaring
-- columnWidth alone would widen the drag region around a column that never renders.
function M.getColumnWidth()
    local L = layout and layout.petFrame and layout.petFrame.maneuvers
    if not L or not L.columnWidth or not L.firstRowPos or not L.rowHeight then return nil end
    if not maneuversEnabled then return nil end
    return L.columnWidth
end

function M.initialize(eng, fullLayout, ax, ay, posReg, slots, scale, savedVis)
    layout      = fullLayout
    posRegistry = posReg

    local s = scale or uiScale
    root = uiContainer.new()
    root:scale(s, s)
    root:pos(ax or 0, ay or 0)

    local L = fullLayout.petFrame

    if L.mp then
        local mpAnchor = Utils.resolveAnchor(L.mp.anchor, posReg)
        mpPos.x = mpAnchor.x + L.mp.pos[1]
        mpPos.y = mpAnchor.y + L.mp.pos[2]
        if posReg then
            posReg['mp'] = { x = mpPos.x, y = mpPos.y, h = L.mp.bar.imgFg.size[2] + (L.mp.marginBottom or 0) }
        end

        mpBar = uiBar.new(L.mp.bar, eng)
        mpBar.posX = mpPos.x + L.mp.bar.pos[1]
        mpBar.posY = mpPos.y + L.mp.bar.pos[2]
        root:addChild(mpBar)
        mpBar:createPrimitives()
        mpBar:hide(VIS_TOKEN)

        mpText = uiText.new(L.mp.txt)
        mpText.posX = mpPos.x + L.mp.txt.pos[1]
        mpText.posY = mpPos.y + L.mp.txt.pos[2]
        root:addChild(mpText)
        mpText:createPrimitives()
        mpText:hide(VIS_TOKEN)
    end

    recastRows.create(eng, root, fullLayout, posReg, slots, savedVis)
    maneuverRows.create(eng, root, fullLayout, posReg, s)
end

function M.update(tokens)
    if not layout then return end
    local L = layout.petFrame

    if mpBar  and L.mp then Utils.applyBinds(mpBar,  L.mp.bar.bind, tokens, VIS_TOKEN) end
    if mpText and L.mp then Utils.applyBinds(mpText, L.mp.txt.bind, tokens, VIS_TOKEN) end

    recastRows.update(tokens)

    -- The toggle reaches this module as a token, one frame after the config callback has
    -- already relayouted, so the transition drives its own relayout: setEnabled drops
    -- posRegistry['maneuvers'], and the frame height derived from it does not change until a
    -- relayout re-runs. Strictly on the transition -- requestRelayout re-enters this module
    -- through relayout/finalizeLayout, so a per-frame call would relayout at 60fps.
    --
    -- An absent token means "no information", NOT "on". The hide path (cutscene, map screen,
    -- zoning) feeds petsreborn's minimal HIDDEN_TOKENS, which carries no ui.* keys at all, so
    -- reading nil as enabled would re-register the column and regrow the frame every time the
    -- frame hides while the setting is off.
    local showManeuvers = tokens['ui.showManeuvers']
    if showManeuvers ~= nil then
        local wantEnabled = showManeuvers ~= false
        if wantEnabled ~= maneuversEnabled then
            maneuversEnabled = wantEnabled
            maneuverRows.setEnabled(wantEnabled)
            requestRelayout()
        end
    end

    maneuverRows.update(tokens)
end

function M.relayout(posReg, vis)
    if not layout then return end
    local L = layout.petFrame
    if not L.mp then return end
    if not vis.showMp or not vis.hasMp then
        posReg['mp'] = nil
        return
    end
    local mpAnchor = Utils.resolveAnchor(L.mp.anchor, posReg)
    mpPos.x = mpAnchor.x + L.mp.pos[1]
    mpPos.y = mpAnchor.y + L.mp.pos[2]
    posReg['mp'] = { x = mpPos.x, y = mpPos.y, h = L.mp.bar.imgFg.size[2] + (L.mp.marginBottom or 0) }
end

function M.finalizeLayout(posReg)
    recastRows.finalizeLayout(posReg)
    maneuverRows.finalizeLayout(posReg)
end

-- Second layout pass: petFrame calls this after finalizeLayout, once the frame's height is
-- known, so the maneuver column's panel can match the frame's own background.
function M.setFrameHeight(h)
    maneuverRows.setFrameHeight(h)
end

function M.destroy()
    if root then root:dispose(); root = nil end
    mpBar    = nil
    mpText   = nil
    recastRows.destroy(posRegistry)
    maneuverRows.destroy(posRegistry)
    if posRegistry then posRegistry['mp'] = nil end
    posRegistry = nil
    layout      = nil
end

function M.onPacket(_) end

return M
