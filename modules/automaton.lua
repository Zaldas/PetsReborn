-- modules/automaton.lua
-- PUP automaton-specific elements: MP bar + ability recast rows + the maneuver column.
-- Registers 'mp' in posRegistry so core.lua can anchor TP dynamically.
-- The Overload banner lives in modules/core.lua, which is never swapped: petFrame.switchModule
-- destroys this module when petType goes nil (straight after Deactivate), which is exactly when
-- the Overload countdown still matters.

local PetModule    = require('modules/petModule')
local ManeuverRows = require('modules/maneuverRows')

local M, base = PetModule.new({ mp = true, mpNeedsHasMp = true })

local maneuverRows = ManeuverRows.new()

-- Mirrors ui.showManeuvers so update() can act on the transition rather than every frame.
-- Both this and the maneuverRows instance survive a rebuildWindow (module locals are cached
-- by require), so the two never drift apart.
local maneuversEnabled = true

-- petFrame requires this module at load, so a top-level require of it here would recurse.
-- update() only ever runs from inside petFrame.update, so the module is always in the
-- require cache by the time this fires.
local function requestRelayout()
    local petFrame = package.loaded['elements/petFrame']
    if petFrame and petFrame.requestRelayout then petFrame.requestRelayout() end
end

function M.setAnchor(x, y)
    base.recastRows.reposition(nil)
    maneuverRows.setAnchor(x, y)
    if base.root then base.root:pos(x, y) end
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
    local layout = base.layout
    local L = layout and layout.petFrame and layout.petFrame.maneuvers
    if not L or not L.columnWidth or not L.firstRowPos or not L.rowHeight then return nil end
    if not maneuversEnabled then return nil end
    return L.columnWidth
end

local baseInitialize = M.initialize
function M.initialize(eng, fullLayout, ax, ay, posReg, slots, scale, savedVis)
    baseInitialize(eng, fullLayout, ax, ay, posReg, slots, scale, savedVis)
    maneuverRows.create(eng, base.root, fullLayout, posReg, base.scale)
end

local baseUpdate = M.update
function M.update(tokens)
    if not base.layout then return end
    baseUpdate(tokens)

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

local baseFinalizeLayout = M.finalizeLayout
function M.finalizeLayout(posReg)
    baseFinalizeLayout(posReg)
    maneuverRows.finalizeLayout(posReg)
end

-- Second layout pass: petFrame calls this after finalizeLayout, once the frame's height is
-- known, so the maneuver column's panel can match the frame's own background.
function M.setFrameHeight(h)
    maneuverRows.setFrameHeight(h)
end

local baseDestroy = M.destroy
function M.destroy()
    local posReg = base.posRegistry
    baseDestroy()
    maneuverRows.destroy(posReg)
end

return M
