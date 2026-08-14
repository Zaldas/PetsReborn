-- modules/charm.lua
-- BST charm pet-specific elements: MP bar (when mob has MP) + ability recast rows (including Stay as isHealTimer slot).
-- Timer (charm duration countdown) is handled by base.lua via pet.timer token.

local uiContainer = require('libs/spui/uiContainer')
local uiBar       = require('libs/spui/uiBar')
local uiText      = require('libs/spui/uiText')
local RecastRows  = require('modules/recastRows')
local Utils       = require('utils')

local resY   = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local VIS_TOKEN = Utils.VIS_TOKEN

local M = {}

local root       = nil
local mpBar      = nil
local mpText     = nil
local recastRows = RecastRows.new()
local layout     = nil

local mpPos          = { x = 0, y = 0 }
local posRegistry    = nil

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
    if root then root:pos(x, y) end
end

function M.initialize(eng, fullLayout, ax, ay, posReg, slots, scale, savedVis)
    layout      = fullLayout
    posRegistry = posReg

    local s = scale or uiScale
    root = uiContainer.new()
    root:scale(s, s)
    root:pos(ax or 0, ay or 0)

    local L   = fullLayout.petFrame

    -- MP bar + text (only when layout defines an mp section)
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

function M.update(tokens)
    if not layout then return end
    local L = layout.petFrame

    if mpBar  and L.mp then Utils.applyBinds(mpBar,  L.mp.bar.bind, tokens, VIS_TOKEN) end
    if mpText and L.mp then Utils.applyBinds(mpText, L.mp.txt.bind, tokens, VIS_TOKEN) end

    recastRows.update(tokens)
end

function M.finalizeLayout(posReg)
    recastRows.finalizeLayout(posReg)
end

function M.destroy()
    if root then root:dispose(); root = nil end
    mpBar  = nil
    mpText = nil
    recastRows.destroy(posRegistry)
    if posRegistry then posRegistry['mp'] = nil end
    posRegistry = nil
    layout      = nil
end

function M.onPacket(_) end

return M
