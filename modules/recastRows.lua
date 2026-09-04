-- modules/recastRows.lua
-- Shared, instantiable recast-row rendering engine used by all 5 pet-type modules
-- (avatar.lua, wyvern.lua, automaton.lua, jug.lua, charm.lua).
-- Each RecastRows.new() call produces fully independent instance state, so multiple
-- pet types can share this one file without sharing row data.

local uiText  = require('libs/spui/uiText')
local uiImage = require('libs/spui/uiImage')
local Utils   = require('utils')

local VIS_TOKEN = Utils.VIS_TOKEN
local MAX_PIPS  = 3

-- Ready and warn states are not layout-driven: recast.timer.thresholds cannot express
-- them, because norm is 0 for every non-charge ability whether or not it is ready.
local COLOR_READY   = { r = 102, g = 255, b = 102, a = 255 }
local COLOR_WARN    = { r = 255, g = 187, b = 68,  a = 255 }
local COLOR_DEFAULT = { r = 240, g = 240, b = 240, a = 255 }

local RecastRows = {}

function RecastRows.new()
    local rows           = {}
    local layout          = nil
    local rcBase          = { x = 0, y = 0 }
    local alwaysShowMode  = false
    local recastVisible   = {}   -- [tostring(id)] = false to hide; nil/absent = show
    local petPresent      = false
    local pipColorFull    = nil
    local pipColorEmpty   = nil
    local timerColor      = COLOR_DEFAULT

    local self = {}

    -- Whether a slot occupies a row right now: config toggle plus the pet-presence gate.
    -- The row list changes length when the pet comes or goes, so reposition() and
    -- getVisibleCount() must agree with update(), or rows render at another row's coordinates.
    local function slotEnabled(slot)
        if not slot then return true end
        if recastVisible[tostring(slot.id)] == false then return false end
        if slot.requiresPet and not petPresent then return false end
        return true
    end

    local function positionAt(element, relX, relY)
        element.posX = relX
        element.posY = relY
        element:layoutElement()
    end

    local function getLabelForSlot(slot, recastLayout)
        local overrides = recastLayout and recastLayout.labelOverrides
        if overrides and slot and slot.displayName then
            local ov = overrides[slot.displayName]
            if ov and ov.text then return ov.text end
        end
        return nil
    end

    local function setVis(el, show)
        if show then el:show(VIS_TOKEN) else el:hide(VIS_TOKEN) end
    end

    function self.create(eng, root, fullLayout, posReg, slots, savedVis)
        layout         = fullLayout
        alwaysShowMode = false
        recastVisible  = savedVis or {}
        petPresent     = false
        rows           = {}

        local L = fullLayout.petFrame

        if L.recast then
            local chL = L.recast.charges

            local rcAnchor = Utils.resolveAnchor(L.recast.anchor, posReg)
            rcBase.x = rcAnchor.x
            rcBase.y = rcAnchor.y
            if posReg then
                posReg['recast'] = { x = rcBase.x + L.recast.firstRowPos[1], y = rcBase.y + L.recast.firstRowPos[2] }
            end

            if chL and chL.pip then
                pipColorFull  = Utils.hexToColor(chL.pip.color)      or { r = 160, g = 200, b = 255, a = 255 }
                pipColorEmpty = Utils.hexToColor(chL.pip.colorEmpty) or { r =  40, g =  40, b =  72, a = 255 }
            end

            timerColor = Utils.hexToColor(L.recast.timer.color) or COLOR_DEFAULT

            for i = 1, #slots do
                local rowX = rcBase.x + L.recast.firstRowPos[1]
                local rowY = rcBase.y + L.recast.firstRowPos[2] + (i - 1) * L.recast.rowHeight

                local nameText = uiText.new(L.recast.txt)
                nameText.posX  = rowX + L.recast.txt.pos[1]
                nameText.posY  = rowY + L.recast.txt.pos[2]
                root:addChild(nameText)
                nameText:createPrimitives()
                nameText:hide(VIS_TOKEN)

                local timerText = uiText.new(L.recast.timer)
                timerText.posX  = rowX + L.recast.timer.pos[1]
                timerText.posY  = rowY + L.recast.timer.pos[2]
                root:addChild(timerText)
                timerText:createPrimitives()
                timerText:hide(VIS_TOKEN)

                local chargesText = nil
                if chL and chL.txt then
                    chargesText = uiText.new(chL.txt)
                    chargesText.posX = rowX + chL.txt.pos[1]
                    chargesText.posY = rowY + chL.txt.pos[2]
                    root:addChild(chargesText)
                    chargesText:createPrimitives()
                    chargesText:hide(VIS_TOKEN)
                end

                local pips = {}
                if chL and chL.pip then
                    local p = chL.pip
                    local pipLayout = { path = p.path, size = p.size, color = p.color, zOrder = p.zOrder }
                    for k = 1, MAX_PIPS do
                        local pip = uiImage.new(pipLayout, eng)
                        pip.posX  = rowX + p.pos[1] + (k - 1) * p.offset[1]
                        pip.posY  = rowY + p.pos[2] + (k - 1) * p.offset[2]
                        root:addChild(pip)
                        pip:createPrimitives()
                        pip:hide(VIS_TOKEN)
                        pips[k] = pip
                    end
                end

                local prefix = 'pet.recast[' .. i .. ']'
                local keys = {
                    name       = prefix .. '.name',
                    time       = prefix .. '.time',
                    norm       = prefix .. '.norm',
                    ready      = prefix .. '.ready',
                    charges    = prefix .. '.charges',
                    maxCharges = prefix .. '.maxCharges',
                    active     = prefix .. '.active',
                }
                rows[i] = { nameText = nameText, timerText = timerText,
                            chargesText = chargesText, pips = pips,
                            prefix = prefix, slot = slots[i], keys = keys }
            end
        end
    end

    function self.reposition(isAlwaysShow)
        if isAlwaysShow ~= nil then alwaysShowMode = isAlwaysShow end
        if not layout then return end
        local L = layout.petFrame
        if not L.recast then return end
        local chL = L.recast.charges
        local baseX, baseY
        if alwaysShowMode and L.recast.alwaysShowFirstRowPos then
            baseX = L.recast.alwaysShowFirstRowPos[1]
            baseY = L.recast.alwaysShowFirstRowPos[2]
        else
            baseX = rcBase.x + L.recast.firstRowPos[1]
            baseY = rcBase.y + L.recast.firstRowPos[2]
        end
        -- Disabled rows are placed too, on the slot the next enabled row will take. They are
        -- hidden, so they draw nothing there; what this prevents is a row keeping a coordinate
        -- from an earlier pack once slotEnabled() flips it back on -- create() indexes by slot
        -- and reposition() by visible position, so a stale coordinate can sit rows below the
        -- frame's own height.
        local visIdx = 0
        for _, row in ipairs(rows) do
            local enabled = slotEnabled(row.slot)
            local rowY = baseY + visIdx * L.recast.rowHeight
            positionAt(row.nameText,  baseX + L.recast.txt.pos[1],   rowY + L.recast.txt.pos[2])
            positionAt(row.timerText, baseX + L.recast.timer.pos[1], rowY + L.recast.timer.pos[2])
            if row.chargesText and chL and chL.txt then
                positionAt(row.chargesText, baseX + chL.txt.pos[1], rowY + chL.txt.pos[2])
            end
            if chL and chL.pip then
                local p = chL.pip
                for k, pip in ipairs(row.pips) do
                    positionAt(pip, baseX + p.pos[1] + (k - 1) * p.offset[1],
                                    rowY  + p.pos[2] + (k - 1) * p.offset[2])
                end
            end
            if enabled then visIdx = visIdx + 1 end
        end
    end

    function self.setVisible(id, val)
        recastVisible[tostring(id)] = val
        self.reposition(nil)
    end

    function self.getVisibleCount()
        local count = 0
        for _, row in ipairs(rows) do
            if slotEnabled(row.slot) then
                count = count + 1
            end
        end
        return count
    end

    function self.finalizeLayout(posReg)
        if not layout or not layout.petFrame.recast then return end
        local rcAnchor = Utils.resolveAnchor(layout.petFrame.recast.anchor, posReg)
        rcBase.x = rcAnchor.x
        rcBase.y = rcAnchor.y
    end

    function self.update(tokens)
        local active      = tokens['pet.active']     == true
        petPresent        = active
        if #rows == 0 then return end

        local alwaysShow   = tokens['pet.alwaysShow'] == true
        local L            = layout and layout.petFrame
        local showRecasts  = tokens['ui.showRecasts'] ~= false

        for _, row in ipairs(rows) do
            local slot    = row.slot
            local slotVis = slotEnabled(slot)

            if slot and slot.isHealTimer then
                local visAnd     = slot.visTokenAnd
                local slotActive = showRecasts and (active or alwaysShow) and slotVis
                                and (visAnd == nil or tokens[visAnd] ~= false)
                setVis(row.nameText,  slotActive)
                setVis(row.timerText, slotActive)
                if row.chargesText then setVis(row.chargesText, false) end
                for _, pip in ipairs(row.pips) do setVis(pip, false) end
                if slotActive then
                    local label = getLabelForSlot(slot, L and L.recast) or slot.displayName
                    row.nameText:update(label)
                    local timerVal = tokens[slot.tokenKey] or slot.fallback or '--'
                    row.timerText:update(timerVal)
                    row.timerText:color(timerColor)
                end
            else
                local keys       = row.keys
                local slotActive = showRecasts and tokens[keys.active] == true and (active or alwaysShow) and slotVis
                local maxCharges = tokens[keys.maxCharges] or 0
                local charges    = tokens[keys.charges]    or 0

                setVis(row.nameText,  slotActive)
                setVis(row.timerText, slotActive)
                if row.chargesText then
                    setVis(row.chargesText, slotActive and maxCharges > 0)
                end
                for k, pip in ipairs(row.pips) do
                    setVis(pip, slotActive and k <= maxCharges)
                end

                if slotActive then
                    local label = getLabelForSlot(slot, L and L.recast) or tokens[keys.name] or ''
                    row.nameText:update(label)
                    row.timerText:update(tokens[keys.time] or '')

                    local norm  = tokens[keys.norm]  or 0
                    local ready = tokens[keys.ready] == true
                    if ready then
                        row.timerText:color(COLOR_READY)
                    elseif norm > 0.70 then
                        row.timerText:color(COLOR_WARN)
                    else
                        row.timerText:color(timerColor)
                    end

                    if row.chargesText and maxCharges > 0 then
                        row.chargesText:update(charges .. '/' .. maxCharges)
                    end

                    if pipColorFull then
                        for k, pip in ipairs(row.pips) do
                            if k <= maxCharges then
                                pip:color(k <= charges and pipColorFull or pipColorEmpty)
                                pip:update()
                            end
                        end
                    end
                end
            end
        end
    end

    function self.destroy(posRegistry)
        rows          = {}
        pipColorFull  = nil
        pipColorEmpty = nil
        if posRegistry then posRegistry['recast'] = nil end
        layout = nil
    end

    return self
end

return RecastRows
