-- modules/petModule.lua
-- Shared base for the pet type modules petFrame.switchModule swaps in and out.
--
-- Module interface. petFrame tests each entry for presence before calling it, so
-- an absent entry is a no-op, and a module carries only the entries its type uses:
--   initialize(eng, layout, ax, ay, posReg, slots, scale, savedVis)
--   update(tokens)                    every frame, with the full token table
--   relayout(posReg, vis)             optional; called at mp's place in the layout's anchor order
--   finalizeLayout(posReg)            called by petFrame.relayout once every element is placed
--   setFrameHeight(h)                 optional; called once the frame's height is known
--   getColumnWidth()                  optional; layout-space width of a side column
--   repositionRecasts(isAlwaysShow)   isAlwaysShow=true uses alwaysShowFirstRowPos (window-relative)
--   setRecastVisible(id, val)         per-ability visibility; repositions the rows
--   getVisibleRowCount()              visible recast rows, for relayout sizing
--   setAnchor(x, y)
--   destroy()
--
-- PetModule.new(opts) returns (M, base): M implements every entry above except setFrameHeight
-- and getColumnWidth, and relayout only with opts.mp. base holds the instance state (root,
-- recastRows, mp, layout, posRegistry, scale) for a module that overrides entries.
--   opts.mp            build the layout's MP bar and register 'mp' in posRegistry
--   opts.mpNeedsHasMp  relayout registers 'mp' only while vis.hasMp is also set

local uiContainer = require('libs/spui/uiContainer')
local uiBar       = require('libs/spui/uiBar')
local uiText      = require('libs/spui/uiText')
local Utils       = require('utils')
local RecastRows  = require('modules/recastRows')

local resY    = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

local VIS_TOKEN = Utils.VIS_TOKEN

local PetModule = {}

-- MP bar + text from layout.petFrame.mp. Every entry is a no-op when the layout has no mp section.
local function newMpBar(needsHasMp)
    local mp = {}
    local bar, text = nil, nil
    local pos = { x = 0, y = 0 }

    local function place(mpL, posReg)
        local entry = Utils.barEntry(mpL, posReg)
        pos.x = entry.x
        pos.y = entry.y
        return entry
    end

    function mp.create(eng, root, L, posReg)
        local mpL = L.mp
        if not mpL then return end
        local entry = place(mpL, posReg)
        if posReg then
            posReg['mp'] = entry
        end

        bar = uiBar.new(mpL.bar, eng)
        bar.posX = pos.x + mpL.bar.pos[1]
        bar.posY = pos.y + mpL.bar.pos[2]
        root:addChild(bar)
        bar:createPrimitives()
        bar:hide(VIS_TOKEN)

        text = uiText.new(mpL.txt)
        text.posX = pos.x + mpL.txt.pos[1]
        text.posY = pos.y + mpL.txt.pos[2]
        root:addChild(text)
        text:createPrimitives()
        text:hide(VIS_TOKEN)
    end

    function mp.relayout(L, posReg, vis)
        if not L.mp then return end
        if not vis.showMp or (needsHasMp and not vis.hasMp) then
            posReg['mp'] = nil
            return
        end
        posReg['mp'] = place(L.mp, posReg)
    end

    function mp.update(L, tokens)
        if bar  and L.mp then Utils.applyBinds(bar,  L.mp.bar.bind, tokens, VIS_TOKEN) end
        if text and L.mp then Utils.applyBinds(text, L.mp.txt.bind, tokens, VIS_TOKEN) end
    end

    -- The sprites are disposed with the root container; this drops the references.
    function mp.destroy(posReg)
        bar, text = nil, nil
        if posReg then posReg['mp'] = nil end
    end

    return mp
end

function PetModule.new(opts)
    opts = opts or {}
    local base = {
        root        = nil,
        recastRows  = RecastRows.new(),
        mp          = opts.mp and newMpBar(opts.mpNeedsHasMp) or nil,
        layout      = nil,
        posRegistry = nil,
        scale       = nil,
    }
    local mp = base.mp
    local M = {}

    function M.repositionRecasts(isAlwaysShow)
        base.recastRows.reposition(isAlwaysShow)
    end

    function M.setRecastVisible(id, val)
        base.recastRows.setVisible(id, val)
    end

    function M.getVisibleRowCount()
        return base.recastRows.getVisibleCount()
    end

    function M.setAnchor(x, y)
        base.recastRows.reposition(nil)
        if base.root then base.root:pos(x, y) end
    end

    function M.initialize(eng, fullLayout, ax, ay, posReg, slots, scale, savedVis)
        base.layout      = fullLayout
        base.posRegistry = posReg

        local s = scale or uiScale
        base.scale = s
        base.root = uiContainer.new()
        base.root:scale(s, s)
        base.root:pos(ax or 0, ay or 0)

        if mp then
            mp.create(eng, base.root, fullLayout.petFrame, posReg)
        end

        base.recastRows.create(eng, base.root, fullLayout, posReg, slots, savedVis)
    end

    function M.update(tokens)
        if mp then
            if not base.layout then return end
            mp.update(base.layout.petFrame, tokens)
        end
        base.recastRows.update(tokens)
    end

    if mp then
        function M.relayout(posReg, vis)
            if not base.layout then return end
            mp.relayout(base.layout.petFrame, posReg, vis)
        end
    end

    function M.finalizeLayout(posReg)
        base.recastRows.finalizeLayout(posReg)
    end

    function M.destroy()
        if base.root then base.root:dispose(); base.root = nil end
        base.recastRows.destroy(base.posRegistry)
        if mp then
            mp.destroy(base.posRegistry)
        end
        base.posRegistry = nil
        base.layout      = nil
    end

    return M, base
end

return PetModule
