-- modules/jug.lua
-- BST jug pet-specific elements: ability recast rows with pips, no MP bar.
-- Timer (jug duration countdown) is handled by base.lua via pet.timer token.

local uiContainer = require('libs/spui/uiContainer')
local RecastRows  = require('modules/recastRows')

local resY   = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local M = {}

local root       = nil
local recastRows = RecastRows.new()

local posRegistry = nil

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
    posRegistry = posReg

    local s = scale or uiScale
    root = uiContainer.new()
    root:scale(s, s)
    root:pos(ax or 0, ay or 0)

    recastRows.create(eng, root, fullLayout, posReg, slots, savedVis)
end

function M.update(tokens)
    recastRows.update(tokens)
end

function M.finalizeLayout(posReg)
    recastRows.finalizeLayout(posReg)
end

function M.destroy()
    if root then root:dispose(); root = nil end
    recastRows.destroy(posRegistry)
    posRegistry = nil
end

function M.onPacket(_) end

return M
