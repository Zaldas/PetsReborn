-- elements/targetFrame.lua
-- Pet's target sub-window: name, distance, HP bar, HP%.
-- Positioned directly below the pet frame by petFrame.lua.
-- Hidden when pet has no target or pet is inactive.

local uiContainer  = require('libs/spui/uiContainer')
local uiBackground = require('libs/spui/uiBackground')
local uiBar        = require('libs/spui/uiBar')
local uiText       = require('libs/spui/uiText')
local Utils        = require('utils')

local resY   = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local VIS_TOKEN = Utils.VIS_TOKEN

local M = {}

local L        = nil
local root     = nil
local bg       = nil
local hpBar    = nil
local hpText   = nil
local nameText = nil
local distText = nil

-- Section extras: img/bg elements created from layout sections.
-- Keyed by section name, each entry = { img, imgBind, bg, bgBind }.
local extras = {}

-- Add element as a child of root at layout-space relative position.
local function addElement(element, relX, relY)
    element.posX = relX
    element.posY = relY
    root:addChild(element)
    element:createPrimitives()
    element:hide(VIS_TOKEN)
end

function M.setAnchor(x, y)
    if root then root:pos(x, y) end
end

function M.initialize(eng, fullLayout, ax, ay, scale)
    local s = scale or uiScale
    root = uiContainer.new()
    root:scale(s, s)
    root:pos(ax or 0, ay or 0)

    L = fullLayout.targetFrame
    if not L then return end

    -- Background
    if L.background then
        bg = uiBackground.new(L.background, eng)
        root:addChild(bg)
        bg:createPrimitives()
        bg:hide(VIS_TOKEN)
    end

    local hpX, hpY = 0, 0
    if L.hp then
        hpX = L.hp.pos[1]
        hpY = L.hp.pos[2]

        hpBar = uiBar.new(L.hp.bar, eng)
        addElement(hpBar, hpX + L.hp.bar.pos[1], hpY + L.hp.bar.pos[2])

        hpText = uiText.new(L.hp.txt)
        addElement(hpText, hpX + L.hp.txt.pos[1], hpY + L.hp.txt.pos[2])
    end

    if L.name then
        nameText = uiText.new(L.name.txt)
        addElement(nameText, L.name.pos[1] + L.name.txt.pos[1], L.name.pos[2] + L.name.txt.pos[2])
    end

    if L.distance then
        distText = uiText.new(L.distance.txt)
        addElement(distText, L.distance.pos[1] + L.distance.txt.pos[1], L.distance.pos[2] + L.distance.txt.pos[2])
    end

    -- Section extras: create optional img/bg elements for each section.
    extras = {}
    extras['hp']       = Utils.createSectionExtras(L.hp,       eng, hpX, hpY, root, VIS_TOKEN)
    if L.name then
        extras['name'] = Utils.createSectionExtras(L.name, eng, L.name.pos[1], L.name.pos[2], root, VIS_TOKEN)
    end
    if L.distance then
        extras['distance'] = Utils.createSectionExtras(L.distance, eng, L.distance.pos[1], L.distance.pos[2], root, VIS_TOKEN)
    end
end

function M.update(tokens)
    if not hpBar or not L then return end

    if L.name     then Utils.applyBinds(nameText, L.name.txt.bind,     tokens, VIS_TOKEN) end
    if L.distance then Utils.applyBinds(distText, L.distance.txt.bind, tokens, VIS_TOKEN) end
    Utils.applyBinds(hpBar,  L.hp.bar.bind, tokens, VIS_TOKEN, L.hp.thresholds)
    Utils.applyBinds(hpText, L.hp.txt.bind, tokens, VIS_TOKEN, L.hp.thresholds)

    if bg then
        local show = tokens['target.active'] == true and tokens['ui.showTargetBar'] ~= false
        if show then bg:show(VIS_TOKEN); bg:update() else bg:hide(VIS_TOKEN) end
    end

    -- Section extras (img/bg elements declared in layout sections)
    Utils.updateSectionExtras(extras, tokens, VIS_TOKEN)
end

function M.destroy()
    if root then root:dispose(); root = nil end
    L        = nil
    bg       = nil
    hpBar    = nil
    hpText   = nil
    nameText = nil
    distText = nil
    extras   = {}
end

return M
