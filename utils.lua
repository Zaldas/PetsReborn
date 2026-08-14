-- utils.lua
-- Addon-level utilities for PetsReborn.

local uiBackground = require('libs/spui/uiBackground')
local uiImage      = require('libs/spui/uiImage')

local Utils = {}

-- Visibility token shared by all PetsReborn spui elements.
Utils.VIS_TOKEN = 2

-- Deep merge: override values win, nested tables recurse.
-- Neither base nor override is mutated; returns new table.
function Utils.deepMerge(base, override)
    if type(override) ~= 'table' then return base end
    if type(base) ~= 'table' then return override end

    local result = {}
    for k, v in pairs(base) do
        result[k] = v
    end
    for k, v in pairs(override) do
        if type(v) == 'table' and type(result[k]) == 'table' then
            result[k] = Utils.deepMerge(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

-- Resolve threshold color: checks thresholds table in order, first match wins.
-- Returns matching color table {r,g,b,a} or defaultColor.
-- thresholds = { default='#RRGGBBAA', {below=0.25, color='#RRGGBBAA'}, ... }
-- thresholds.default: color used when no threshold matches (above all thresholds).
-- value = 0..1 normalized number
function Utils.resolveThreshold(thresholds, value, defaultColor)
    if not thresholds or #thresholds == 0 then return defaultColor end
    for _, t in ipairs(thresholds) do
        if value < t.below then
            -- Parse once and cache on the entry; layout tables are rebuilt fresh
            -- on /pr reload, so the cache can never go stale.
            t._color = t._color or Utils.hexToColor(t.color)
            if t._color then return t._color end
        end
    end
    -- No threshold matched — use layout's declared default if present
    if thresholds.default then
        thresholds._defaultColor = thresholds._defaultColor or Utils.hexToColor(thresholds.default)
        return thresholds._defaultColor or defaultColor
    end
    return defaultColor
end

-- Parse hex color '#RRGGBBAA' to {r,g,b,a} table. Returns nil on failure.
function Utils.hexToColor(hex)
    if not hex or #hex < 7 then return nil end
    return {
        r = tonumber(hex:sub(2, 3), 16) or 255,
        g = tonumber(hex:sub(4, 5), 16) or 255,
        b = tonumber(hex:sub(6, 7), 16) or 255,
        a = #hex >= 9 and (tonumber(hex:sub(8, 9), 16) or 255) or 255,
    }
end

-- Apply a layout bind declaration to a UI element for the current token frame.
-- bind:       element's bind table from layout (may be nil — returns immediately)
-- tokens:     current token table from State.buildTokenTable()
-- visToken:   VIS_TOKEN integer used by this module (typically 2)
-- thresholds: optional threshold table from parent layout (for color/barColor = 'threshold')
--
-- Supported bind keys:
--   visible      = 'tokenName'  → show when tokens[key]==true, hide otherwise
--   visibleAnd   = 'tokenName'  → secondary visibility condition ANDed with visible
--   value        = 'tokenName'  → uiBar: setValue+update (animated fill); uiText: display string
--   color        = 'threshold'  → threshold color; uiBar: setColor; uiText: color()
--   colorValue   = 'tokenName'  → normalized value token for color='threshold' lookup
--   defaultColor = '#RRGGBBAA'  → fallback color when above all thresholds (uiText/uiBar)
function Utils.applyBinds(element, bind, tokens, visToken, thresholds)
    if not element or not bind then return end

    -- Visibility: show when both visible and visibleAnd tokens are true (each optional)
    if bind.visible or bind.visibleAnd then
        local show = (not bind.visible    or tokens[bind.visible]    == true)
                 and (not bind.visibleAnd or tokens[bind.visibleAnd] == true)
        if show then element:show(visToken) else element:hide(visToken) end
    end

    -- Value: unified key for both uiText and uiBar.
    -- uiBar  (has setValue): numeric token → setValue + update (animated fill)
    -- uiText (no setValue):  string/format token → update(string)
    --   value = 'tokenName'        → plain token lookup
    --   value = '{tok1} / {tok2}'  → format string; {tokenName} substituted from token table
    if bind.value then
        if element.setValue then
            -- uiBar path
            element:setValue(tokens[bind.value] or 0)
            element:update()
        else
            -- uiText path
            local v = bind.value
            local val
            if v:find('{', 1, true) then
                val = v:gsub('{([^}]+)}', function(key)
                    local tok = tokens[key]
                    return tok ~= nil and tostring(tok) or ''
                end)
            else
                local tok = tokens[v]
                val = tok ~= nil and tostring(tok) or ''
            end
            element:update(val)
        end
    end

    -- Color: unified key for both uiBar and uiText threshold coloring.
    -- uiBar  (has setColor): sets bar fill color from threshold lookup.
    --   Always calls setColor (nil restores original imgBar color).
    -- uiText (has color):    sets text color from threshold lookup.
    --   colorValue token overrides value as the norm input.
    --   defaultColor applied when above all thresholds (prevents stuck color on recovery).
    if bind.color == 'threshold' and thresholds then
        if element.setColor then
            -- uiBar path
            local normKey = bind.colorValue or bind.value
            local norm    = normKey and (tokens[normKey] or 0) or 0
            local default = bind.defaultColor and Utils.hexToColor(bind.defaultColor) or nil
            local color   = Utils.resolveThreshold(thresholds, norm, default)
            element:setColor(color)
        elseif element.color then
            -- uiText path
            local normKey = bind.colorValue or bind.value
            local norm    = normKey and (tokens[normKey] or 0) or 0
            local default = bind.defaultColor and Utils.hexToColor(bind.defaultColor) or nil
            local color   = Utils.resolveThreshold(thresholds, norm, default)
            if color then element:color(color) end
        end
    end
end

-- Resolve anchor base position for a layout element.
-- anchorField: nil | 'none' | string | string-array
-- registry:    { name → {x, y} } in layout-space (relative to window anchor, unscaled)
-- Returns {x, y} of the first resolved anchor, or {x=0, y=0} if nothing resolves.
-- Fall-through order: each name in priority list, then window origin.
--
-- Single-axis form: 'name.x' borrows only the X coordinate (Y = 0).
--                   'name.y' borrows only the Y coordinate (X = 0).
-- Example: anchor = 'hp.y'  →  {x=0, y=<hp's y>}
function Utils.resolveAnchor(anchorField, registry)
    if not anchorField or anchorField == 'none' then return {x = 0, y = 0} end
    local names = type(anchorField) == 'string' and {anchorField} or anchorField
    for _, name in ipairs(names) do
        local base, axis = name:match('^(.+)%.([%a]+)$')
        if base then
            local pos = registry and registry[base]
            if pos then
                if axis == 'x'      then return {x = pos.x,               y = 0    } end
                if axis == 'y'      then return {x = 0,                   y = pos.y} end
                if axis == 'left'   then return {x = pos.x,               y = pos.y} end
                if axis == 'top'    then return {x = pos.x,               y = pos.y} end
                if axis == 'right'  then return {x = pos.x + (pos.w or 0), y = pos.y} end
                if axis == 'bottom' then return {x = pos.x,               y = pos.y + (pos.h or 0)} end
            end
        else
            local pos = registry and registry[name]
            if pos then return {x = pos.x, y = pos.y} end
        end
    end
    return {x = 0, y = 0}
end

-- Build a topologically-sorted list of petFrame element names from the layout.
-- Parses anchor dependencies so relayout can process elements in correct dependency order
-- without hardcoded step numbers. Call once on layout load, store the result.
--
-- Rules:
--   - 'name' is the implicit root: no dependencies, always processed first.
--   - Any top-level table with an 'anchor' field is treated as a layout element.
--   - Axis suffixes (.x, .y, .top, .bottom) are stripped to get the base dep name.
--   - Only deps that are also known elements (present in L or named 'name') are tracked.
function Utils.buildLayoutOrder(L)
    local deps = { name = {} }  -- 'name' is root; no deps

    for elemName, elem in pairs(L) do
        if type(elem) == 'table' and elem.anchor then
            local elemDeps = {}
            local seen = {}
            local anchorList = type(elem.anchor) == 'string' and {elem.anchor} or elem.anchor
            for _, a in ipairs(anchorList) do
                local base = a:match('^(.+)%.[%a]+$') or a
                if not seen[base] and base ~= elemName then
                    seen[base] = true
                    elemDeps[#elemDeps + 1] = base
                end
            end
            deps[elemName] = elemDeps
        end
    end

    -- DFS topological sort; 'name' visited first as the explicit root
    local sorted  = {}
    local visited = {}
    local function visit(name)
        if visited[name] then return end
        visited[name] = true
        for _, dep in ipairs(deps[name] or {}) do
            visit(dep)
        end
        sorted[#sorted + 1] = name
    end
    visit('name')
    for elemName in pairs(deps) do visit(elemName) end

    return sorted
end

-- Creates img and bg elements from a section layout if present.
-- Returns { img, imgBind, bg, bgBind } — nils for absent entries.
-- Only visible/visibleAnd binds are supported; dynamic color/path binding is a future expansion.
-- root:     parent uiContainer the extras are added to
-- visToken: visibility token for show/hide (typically Utils.VIS_TOKEN)
function Utils.createSectionExtras(sectionLayout, eng, baseX, baseY, root, visToken)
    local result = { img = nil, imgBind = nil, bg = nil, bgBind = nil }
    if not sectionLayout or not root then return result end

    if sectionLayout.img then
        local imgEl = uiImage.new(sectionLayout.img, eng)
        imgEl.posX = baseX + (sectionLayout.img.pos and sectionLayout.img.pos[1] or 0)
        imgEl.posY = baseY + (sectionLayout.img.pos and sectionLayout.img.pos[2] or 0)
        root:addChild(imgEl)
        imgEl:createPrimitives()
        imgEl:hide(visToken)
        result.img     = imgEl
        result.imgBind = sectionLayout.img.bind or nil
    end

    if sectionLayout.bg then
        local bgEl = uiBackground.new(sectionLayout.bg, eng)
        bgEl.posX = baseX + (sectionLayout.bg.pos and sectionLayout.bg.pos[1] or 0)
        bgEl.posY = baseY + (sectionLayout.bg.pos and sectionLayout.bg.pos[2] or 0)
        root:addChild(bgEl)
        bgEl:createPrimitives()
        bgEl:hide(visToken)
        result.bg     = bgEl
        result.bgBind = sectionLayout.bg.bind or nil
    end

    return result
end

-- Apply binds for all section extras that exist.
-- extras:   table of { img, imgBind, bg, bgBind } entries (any keys)
-- tokens:   current token table from State.buildTokenTable()
-- visToken: visibility token for show/hide (typically Utils.VIS_TOKEN)
function Utils.updateSectionExtras(extras, tokens, visToken)
    for _, extra in pairs(extras) do
        if extra.img then Utils.applyBinds(extra.img, extra.imgBind, tokens, visToken) end
        if extra.bg  then Utils.applyBinds(extra.bg,  extra.bgBind,  tokens, visToken) end
    end
end

return Utils
