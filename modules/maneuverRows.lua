-- modules/maneuverRows.lua
-- PUP maneuver column: a shared recast row, then eight fixed element rows, each a cluster of
-- same-size element diamonds and that element's overload chance.
-- Rendering only -- every burden figure reaches this module as a token, so nothing here
-- reads state, packets or Ashita memory. Each ManeuverRows.new() call produces fully
-- independent instance state.
--
-- Row count and order come from data/maneuvers.lua's element list.
--
-- Pip geometry is layout data end to end: pipOffsets[k] is pip k's offset from the row origin
-- and maxPips caps how many a row may draw, so a cluster, a vertical line and a horizontal run
-- are all layout edits. Pips fill in index order up to min(count, maxPips, #pipOffsets).
--
-- The main pip is always drawn, in its element's own colour: filled when the element has at
-- least one maneuver up, outline when it has none. Nothing greys out. The percentage hangs off
-- pip 1 (pctOffset, with pctAlign deciding which of its edges lands on that point) and is
-- independent of the pip state, so an element with residual burden and no maneuver renders an
-- outline pip AND a percentage.
--
-- Expiry warning: with a `blink` section authored, an element whose soonest maneuver is inside
-- the threshold pulses the alpha of its LAST-drawn pip -- the pip that disappears when that
-- instance drops. The percentage never pulses.
--
-- The column owns its own optional background (petFrame.maneuvers.background); the pet frame's
-- background is never resized to cover the column. That panel spans the FRAME's height, which
-- petFrame pushes in through setFrameHeight because the column lays itself out before the
-- frame's height exists -- computeLayoutHeight reads the registry entry this module has only
-- just written. The shared recast row sits above both panels' top edge, unpainted. The registry
-- rect and the background rect are therefore two different rectangles: the registry entry
-- bounds everything drawn, because the frame's drag hit-rect is built from it, while the panel
-- follows the frame.

local socket       = require('socket')
local uiText       = require('libs/spui/uiText')
local uiImage      = require('libs/spui/uiImage')
local uiBackground = require('libs/spui/uiBackground')
local Utils        = require('utils')
local maneuvers    = require('data/maneuvers')

local VIS_TOKEN     = Utils.VIS_TOKEN
local ELEMENTS      = maneuvers.elements
local ELEMENT_COUNT = #ELEMENTS

local TOK_ACTIVE       = 'pet.active'
local TOK_SHOW         = 'ui.showManeuvers'
local TOK_RECAST       = 'pet.maneuverRecast'
local TOK_READY        = 'pet.maneuverReady'
local TOK_OVERLOAD     = 'pet.overloadActive'
local TOK_OVERLOAD_TIME = 'pet.overloadTimer'

-- Untinted fallback: uiImage tints multiplicatively, so white leaves the sprite as authored.
local WHITE = { r = 255, g = 255, b = 255, a = 255 }

-- Every pip in a cluster renders at this size.
local DEFAULT_ICON_SIZE = { 12, 12 }

-- Used only when the layout declares no pipOffsets: one pip on the row origin, no cluster.
local DEFAULT_PIP_OFFSETS = { { 0, 0 } }

-- Fallback percentage clearance, used only when the layout declares no pctOffset: the number's
-- right edge sits this far left of the leftmost pip the row can draw, so a full cluster never
-- overdraws it.
local DEFAULT_PCT_GAP = 6

-- Which edge of the percentage lands on its anchor point. gdifonts aligns AT position_x, so
-- 'right' puts the right edge there.
local PCT_ALIGNS = { left = true, center = true, right = true }
local DEFAULT_PCT_ALIGN = 'right'

-- Percentage text, used when the layout declares neither key. Both are string.format
-- patterns taking the integer chance. '~' marks a derived figure: an Overdrive worst-case
-- add or the Activate spawn seed.
local DEFAULT_PCT_FORMAT       = '%d%%'

-- A layout format string reaches string.format on the d3d_present path, where a pattern
-- string.format rejects ('%d %d') throws on every visible frame. Validated once at create,
-- keeping the hot path free of pcall; a bad pattern degrades to the shipped default.
local function resolveFormat(fmt, fallback)
    if type(fmt) ~= 'string' then return fallback end
    if not pcall(string.format, fmt, 0) then return fallback end
    return fmt
end

local function resolvePctAlign(align)
    if type(align) == 'string' and PCT_ALIGNS[align] then return align end
    return DEFAULT_PCT_ALIGN
end

-- Expiry-pulse config, resolved once at create so the render path carries no validation. A
-- layout without a `blink` section, or with a nonsensical one, returns nil and the column
-- renders at full alpha forever -- the feature is entirely opt-in.
-- period is the full cycle in seconds and divides the clock every frame, so zero or negative is
-- rejected here. alphaFloor is a 0..1 MULTIPLIER on the element colour's authored alpha, not a
-- replacement for it, so a translucent palette stays translucent; it is clamped because a floor
-- above 1 brightens the pip past what the layout authored and a negative one drives the alpha
-- byte below 0.
local function resolveBlink(b)
    if type(b) ~= 'table' then return nil end

    local threshold = tonumber(b.threshold)
    local period    = tonumber(b.period)
    local floor     = tonumber(b.alphaFloor)
    if not threshold or threshold <= 0 then return nil end
    if not period    or period    <= 0 then return nil end
    if not floor then return nil end

    if floor < 0 then floor = 0 elseif floor > 1 then floor = 1 end
    return { threshold = threshold, period = period, floor = floor }
end

local ManeuverRows = {}

function ManeuverRows.new()
    local rows        = {}     -- [1..8] = { pips, pctText, path, keys }
    local recastText  = nil    -- shared maneuver recast row, above element row 1
    local columnBg    = nil    -- optional 3-slice panel behind the column
    local layout      = nil    -- full layout table
    local posRegistry = nil
    local created     = false
    local enabled     = true

    local base    = { x = 0, y = 0 }   -- resolved anchor, layout space
    local metrics = { x = 0, y = 0, h = 0 }
    -- The frame background's own height, layout space, pushed in by petFrame after it has
    -- computed it. Only the panel reads it; posRegistry keeps using metrics.
    local frameH  = 0

    local elementColors  = {}
    local pctBaseColor   = WHITE      -- txt.color, parsed once; the ramp's non-nil fallback
    local recastColor    = WHITE      -- recastTxt.color, parsed once
    local overloadColor  = nil        -- recastTxt.overloadColor; nil = reuse recastColor
    local readyLabel     = nil        -- recastTxt.readyLabel; nil = show the formatted timer

    local pctFormat       = DEFAULT_PCT_FORMAT        -- validated once in create

    -- { threshold, period, floor }, resolved once in create; nil = the layout wants no pulse.
    local blink = nil

    -- pipOffsets[k] = {x, y} of pip k from the row origin, already clamped to maxPips, so
    -- #pipOffsets is the per-row pip count. pipOneX/pipOneY are pip 1's own offset, cached
    -- because the percentage hangs off it.
    local pipOffsets = {}
    local pipOneX, pipOneY = 0, 0
    local pctOffsetX, pctOffsetY = 0, 0
    local pctAlign = DEFAULT_PCT_ALIGN

    local iconActivePath   = ''
    local iconResidualPath = ''

    local self = {}

    local function section()
        return layout and layout.petFrame and layout.petFrame.maneuvers
    end

    local function positionAt(element, relX, relY)
        element.posX = relX
        element.posY = relY
        element:layoutElement()
    end

    local function setVis(el, show)
        if show then el:show(VIS_TOKEN) else el:hide(VIS_TOKEN) end
    end

    local function hideAll()
        if columnBg then setVis(columnBg, false) end
        if recastText then setVis(recastText, false) end
        for i = 1, #rows do
            local row = rows[i]
            for k = 1, #row.pips do setVis(row.pips[k], false) end
            if row.pctText then setVis(row.pctText, false) end
        end
    end

    -- Layout coordinate contract, declared in both layout files:
    --   origin O             = resolved anchor + firstRowPos
    --   row origin of row i  = O + (0, (i-1) * rowHeight)
    --   pip k of row i       = row i + pipOffsets[k]
    --   percentage of row i  = row i + pipOffsets[1] + pctOffset
    --   shared recast text   = O + recastTxt.pos
    -- Everything hangs off O, not off the raw anchor -- firstRowPos[1] is negative, so
    -- anchoring the recast row on the raw anchor puts it inside the frame.
    -- recastTxt.pos is read as authored and never derived from the percentage position.
    local function origin(L)
        return base.x + L.firstRowPos[1], base.y + L.firstRowPos[2]
    end

    local function rowOrigin(L, i)
        local ox, oy = origin(L)
        return ox, oy + (i - 1) * L.rowHeight
    end

    local function iconSizeOf(L)
        return L.iconSize or DEFAULT_ICON_SIZE
    end

    -- Resolved once, in create. maxPips past the end of pipOffsets is a layout error and
    -- clamps to the offsets that actually exist; without the clamp the render path indexes nil.
    local function resolvePips(L)
        pipOffsets = {}

        local src = L.pipOffsets
        if type(src) ~= 'table' or #src == 0 then src = DEFAULT_PIP_OFFSETS end

        local count = #src
        if type(L.maxPips) == 'number' and L.maxPips < count then count = L.maxPips end
        for k = 1, count do
            local o = src[k]
            pipOffsets[k] = { (o and o[1]) or 0, (o and o[2]) or 0 }
        end

        pipOneX, pipOneY = 0, 0
        if pipOffsets[1] then
            pipOneX = pipOffsets[1][1]
            pipOneY = pipOffsets[1][2]
        end
    end

    -- The percentage is placed relative to PIP 1, not to the row origin, so pctOffset {0, 0}
    -- with pctAlign 'center' centres the number on the main pip. With no pctOffset the fallback
    -- clears the leftmost pip the row can draw by DEFAULT_PCT_GAP and centres the line on pip
    -- 1's height, both read off the resolved offsets. Resolved once, in create.
    local function resolvePctOffset(L)
        if type(L.pctOffset) == 'table' then
            pctOffsetX = L.pctOffset[1] or 0
            pctOffsetY = L.pctOffset[2] or 0
            return
        end

        local leftmost = pipOneX
        for k = 1, #pipOffsets do
            if pipOffsets[k][1] < leftmost then leftmost = pipOffsets[k][1] end
        end

        local iconSize = iconSizeOf(L)
        local fontSize = (L.txt and L.txt.size) or 12
        pctOffsetX = (leftmost - pipOneX) - DEFAULT_PCT_GAP
        pctOffsetY = math.floor((iconSize[2] - fontSize) / 2)
    end

    local function pipPos(rowX, rowY, k)
        local o = pipOffsets[k]
        return rowX + o[1], rowY + o[2]
    end

    local function pctPos(rowX, rowY)
        return rowX + pipOneX + pctOffsetX, rowY + pipOneY + pctOffsetY
    end

    -- Layout-space bounds of the whole column: recast row through the last element row.
    -- petFrame.computeLayoutHeight reads y + h off the registry entry, so y must be the
    -- topmost edge and h the full span, not just the element rows. recastTxt.pos[2] is
    -- negative, so the recast row is what sets the top edge.
    -- A cluster can overhang its row origin in either direction, so the bounds come from the
    -- pips that are actually drawn, not from the row bands alone: the highest offset on row 1
    -- can raise the top edge, the lowest on the last row can push past the bottom.
    local function computeMetrics(L)
        local ox, oy   = origin(L)
        local iconSize = iconSizeOf(L)
        local top      = oy
        local bottom   = oy + ELEMENT_COUNT * L.rowHeight

        local lastRowY = oy + (ELEMENT_COUNT - 1) * L.rowHeight
        for k = 1, #pipOffsets do
            local dy = pipOffsets[k][2]
            if oy + dy < top then top = oy + dy end
            local pipBottom = lastRowY + dy + iconSize[2]
            if pipBottom > bottom then bottom = pipBottom end
        end

        if L.recastTxt and L.recastTxt.pos then
            local rcTop = oy + L.recastTxt.pos[2]
            local rcBot = rcTop + (L.recastTxt.size or 12)
            if rcTop < top    then top    = rcTop end
            if rcBot > bottom then bottom = rcBot end
        end

        metrics.x = ox
        metrics.y = top
        metrics.h = bottom - top + (L.marginBottom or 0)
    end

    -- Position and size the optional column background. Width is authored in the slice sizes --
    -- uiBackground only derives the vertical axis -- and the span derived here is the FRAME's,
    -- not the column's: layout y 0 through frameH is exactly the span petFrame gives its own
    -- background, so the two panels line up top and bottom.
    -- background.pos is measured from the row origin's X and the frame's top edge; extraHeight
    -- pads the bottom edge past the frame's.
    local function layoutBackground(L)
        if not columnBg or not L.background then return end
        local bgL = L.background
        positionAt(columnBg,
            metrics.x + (bgL.pos and bgL.pos[1] or 0),
            (bgL.pos and bgL.pos[2] or 0))
        columnBg:setHeight(frameH + (bgL.extraHeight or 0))
    end

    -- The registry entry is what makes petFrame.computeLayoutHeight grow the frame for the
    -- column, so a disabled column must clear it: hiding the sprites alone would leave the
    -- background sized around empty space.
    local function register()
        if not posRegistry then return end
        if enabled and created then
            posRegistry['maneuvers'] = { x = metrics.x, y = metrics.y, h = metrics.h }
        else
            posRegistry['maneuvers'] = nil
        end
    end

    function self.create(eng, root, fullLayout, posReg, _scale)
        layout      = fullLayout
        posRegistry = posReg
        rows        = {}
        recastText  = nil
        columnBg    = nil
        created     = false

        local L = fullLayout and fullLayout.petFrame and fullLayout.petFrame.maneuvers
        if not root or not L or not L.firstRowPos or not L.rowHeight then
            register()
            return
        end

        local anchor = Utils.resolveAnchor(L.anchor, posReg)
        base.x = anchor.x
        base.y = anchor.y
        -- Before computeMetrics: the column's vertical bounds are read off the resolved pips.
        resolvePips(L)
        resolvePctOffset(L)
        pctAlign = resolvePctAlign(L.pctAlign)
        computeMetrics(L)

        -- The ramp's fallback is the text's own authored colour. All three bundled layouts end
        -- their ramp in a `{ below = 1.01 }` catch-all -- selene's mixed_table rule rejects the
        -- `default` key resolveThreshold would otherwise accept -- so this only fires for a
        -- custom layout with a partial ramp.
        pctBaseColor   = Utils.hexToColor(L.txt and L.txt.color) or WHITE
        recastColor    = Utils.hexToColor(L.recastTxt and L.recastTxt.color) or WHITE
        overloadColor  = Utils.hexToColor(L.recastTxt and L.recastTxt.overloadColor)

        -- Names the row while no countdown is running. Without it the row shows the timer's
        -- own ready text, which reads as a state rather than saying what is ready.
        readyLabel = nil
        if type(L.recastTxt) == 'table' and type(L.recastTxt.readyLabel) == 'string' then
            readyLabel = L.recastTxt.readyLabel
        end

        for i = 1, ELEMENT_COUNT do
            elementColors[i] = Utils.hexToColor(L.elementColors and L.elementColors[i]) or WHITE
        end

        pctFormat       = resolveFormat(L.pctFormat,       DEFAULT_PCT_FORMAT)
        blink           = resolveBlink(L.blink)

        -- A missing PNG degrades silently: sprites.lua returns a nil texture and the render
        -- loop skips it, so absent artwork needs no guard here.
        iconActivePath   = L.iconActive   or ''
        iconResidualPath = L.iconResidual or ''
        if iconActivePath   == '' then iconActivePath   = iconResidualPath end
        if iconResidualPath == '' then iconResidualPath = iconActivePath   end

        local originX, originY = origin(L)

        -- Built before the icons and text: sprites.lua renders in creation order, so anything
        -- meant to sit behind them has to be the first primitive this module makes.
        -- The three slice tables are required because uiBackground:init indexes them unguarded,
        -- and this section is hand-authored by users.
        if L.background and L.background.imgTop and L.background.imgMid and L.background.imgBottom then
            columnBg = uiBackground.new(L.background, eng)
            root:addChild(columnBg)
            columnBg:createPrimitives()
            columnBg:hide(VIS_TOKEN)
            layoutBackground(L)
        end

        if L.recastTxt then
            recastText      = uiText.new(L.recastTxt)
            recastText.posX = originX + (L.recastTxt.pos and L.recastTxt.pos[1] or 0)
            recastText.posY = originY + (L.recastTxt.pos and L.recastTxt.pos[2] or 0)
            root:addChild(recastText)
            recastText:createPrimitives()
            recastText:hide(VIS_TOKEN)
        end

        -- A {w, h} pair, fed to uiImage's size field directly. Every pip in a cluster uses it.
        local iconSize = iconSizeOf(L)

        -- pctAlign, not txt.align, owns which edge of the number lands on its anchor point.
        -- The layout table is shared and outlives this instance, so the font block is copied
        -- rather than written through.
        local pctCfg = nil
        if L.txt then
            pctCfg = {}
            for key, value in pairs(L.txt) do pctCfg[key] = value end
            pctCfg.align = pctAlign
        end

        for i = 1, ELEMENT_COUNT do
            local rowX, rowY = rowOrigin(L, i)

            -- Pip 1 carries the outline state, so it is built with the residual sprite and
            -- swaps path with the count. Pips 2+ are always the filled sprite: a row needs 2
            -- maneuvers before the second one shows, so they only appear alongside a filled
            -- pip 1.
            local pips = {}
            for k = 1, #pipOffsets do
                local path
                if k == 1 then path = iconResidualPath else path = iconActivePath end
                local pip = uiImage.new({
                    path   = path,
                    size   = iconSize,
                    zOrder = L.iconZOrder,
                }, eng)
                pip.posX, pip.posY = pipPos(rowX, rowY, k)
                root:addChild(pip)
                pip:createPrimitives()
                pip:hide(VIS_TOKEN)
                pips[k] = pip
            end

            local pctText = nil
            if pctCfg then
                pctText = uiText.new(pctCfg)
                pctText.posX, pctText.posY = pctPos(rowX, rowY)
                root:addChild(pctText)
                pctText:createPrimitives()
                pctText:hide(VIS_TOKEN)
            end

            -- Scratch colour for the pulsing pip, one per row and reused every frame: the
            -- element hue is fixed at create and only the alpha byte moves. It is a COPY --
            -- writing the pulse into elementColors[i] would dim every pip on the row and never
            -- come back, since that table is also what restores full alpha.
            local ec = elementColors[i]
            local prefix = 'pet.maneuver[' .. i .. ']'
            rows[i] = {
                pips       = pips,
                pctText    = pctText,
                path       = iconResidualPath,
                pulseColor = { r = ec.r, g = ec.g, b = ec.b, a = ec.a },
                keys       = {
                    pct       = prefix .. '.pct',
                    norm      = prefix .. '.norm',
                    count     = prefix .. '.count',
                    remaining = prefix .. '.remaining',
                },
            }
        end

        created = true
        register()
    end

    function self.reposition()
        local L = section()
        if not created or not L then return end

        computeMetrics(L)
        layoutBackground(L)

        local originX, originY = origin(L)

        if recastText and L.recastTxt then
            positionAt(recastText,
                originX + (L.recastTxt.pos and L.recastTxt.pos[1] or 0),
                originY + (L.recastTxt.pos and L.recastTxt.pos[2] or 0))
        end

        for i = 1, #rows do
            local row = rows[i]
            local rowX, rowY = rowOrigin(L, i)
            for k = 1, #row.pips do
                local px, py = pipPos(rowX, rowY, k)
                positionAt(row.pips[k], px, py)
            end
            if row.pctText then
                local tx, ty = pctPos(rowX, rowY)
                positionAt(row.pctText, tx, ty)
            end
        end
    end

    -- The column's elements are children of the caller's root container, so root:pos() in
    -- automaton.setAnchor already applies the window move; the coordinates are unused here and
    -- only the layout-space reposition is needed.
    function self.setAnchor(_x, _y)
        self.reposition()
    end

    -- Config toggle. Drops the registry entry as well as the sprites, so the frame stops
    -- reserving the column's height while it is off.
    function self.setEnabled(v)
        enabled = v ~= false
        if not enabled then hideAll() end
        register()
    end

    -- Layout-space height of the column, recast row through the last element row.
    function self.getHeight()
        if not created then return 0 end
        return metrics.h
    end

    -- Second layout pass, driven by petFrame.relayout once the frame's own height is known.
    -- The column cannot derive that figure itself: computeLayoutHeight produces it and runs on
    -- a registry this module writes during finalizeLayout, one step earlier.
    -- h is layout-space, the same units the panel and petFrame's background are sized in --
    -- not the scaled window height.
    function self.setFrameHeight(h)
        frameH = h or 0
        local L = section()
        if not created or not L then return end
        layoutBackground(L)
    end

    function self.finalizeLayout(posReg)
        posRegistry = posReg or posRegistry

        local L = section()
        if not created or not L then
            register()
            return
        end

        local anchor = Utils.resolveAnchor(L.anchor, posRegistry)
        base.x = anchor.x
        base.y = anchor.y
        self.reposition()
        -- petFrame.relayout() wipes posRegistry and rebuilds it from a fixed branch list
        -- that has no 'maneuvers' case, so this is the only place the entry comes back.
        -- Without it computeLayoutHeight stops accounting for the column after a relayout.
        register()
    end

    function self.update(tokens)
        if not created then return end
        local L = section()
        if not L then return end

        -- Both terms are load-bearing: maneuver tokens are emitted for every job and
        -- burdenModel survives a job change, so a BST can legitimately carry pct > 0 until the
        -- player next Activates.
        -- The layout's own bind is ANDed on top, so a layout can narrow the gate but never
        -- widen it -- a bind key arriving as nil hides the column.
        local show = enabled and tokens[TOK_ACTIVE] == true and tokens[TOK_SHOW] ~= false
        local bind = L.bind
        if show and bind then
            show = (not bind.visible    or tokens[bind.visible]    == true)
               and (not bind.visibleAnd or tokens[bind.visibleAnd] == true)
        end

        if not show then
            hideAll()
            return
        end

        if columnBg then
            setVis(columnBg, true)
            columnBg:update()
        end

        if recastText then
            setVis(recastText, true)
            -- Overload blocks maneuvers outright -- onManeuverCheck returns error 71 for the
            -- whole time the player holds it -- so while it is up the row shows the Overload
            -- countdown, not a recast that has already finished.
            if tokens[TOK_OVERLOAD] == true then
                recastText:update(tokens[TOK_OVERLOAD_TIME] or '')
                recastText:color(overloadColor or recastColor)
            elseif readyLabel and tokens[TOK_READY] == true then
                recastText:update(readyLabel)
                recastText:color(recastColor)
            else
                recastText:update(tokens[TOK_RECAST] or '')
                recastText:color(recastColor)
            end
        end

        local thresholds = L.thresholds

        -- One cosine per frame, shared by every row: the pulse reads the clock, not each
        -- element's own remaining, so two warning pips breathe together instead of beating
        -- against each other. Full alpha at the period boundary, the floor at the half, phase
        -- continuous -- a pip that starts or stops pulsing does it from full, never mid-fade.
        -- socket.gettime() is sub-second; os.time() would quantise this into a visible step.
        -- pulse nil is the feature's off switch.
        local pulse, blinkAt = nil, 0
        if blink then
            local phase = (socket.gettime() % blink.period) / blink.period
            local wave  = 0.5 * (1 + math.cos(2 * math.pi * phase))  -- 1 at phase 0, 0 at 0.5
            pulse   = blink.floor + (1 - blink.floor) * wave
            blinkAt = blink.threshold
        end

        for i = 1, #rows do
            local row   = rows[i]
            local keys  = row.keys
            local count = tokens[keys.count] or 0
            local color = elementColors[i]

            -- Filled with a maneuver up, outline without. The element colour is on the main pip
            -- in both states, so nothing in the strip ever greys out.
            local wantPath
            if count > 0 then wantPath = iconActivePath else wantPath = iconResidualPath end
            local mainPip = row.pips[1]
            if mainPip and wantPath ~= row.path then
                mainPip:path(wantPath)
                row.path = wantPath
            end

            -- Pip k stands for maneuver k, so the row draws min(count, maxPips, #pipOffsets)
            -- of them -- #row.pips is already that clamp. Pip 1 is the exception and is drawn
            -- at any count: at 0 it is the outline holding the element's place in the column.
            local drawn = count
            if drawn > #row.pips then drawn = #row.pips end

            -- The pip that pulses is the LAST one drawn, which is precisely the pip the soonest
            -- expiry takes away: a 45s/25s/8s stack warns on one diamond and leaves the other
            -- two steady. An element carrying residual burden with no maneuver up renders its
            -- outline pip exactly as it does with the feature off.
            local pulseIndex = 0
            if pulse and count > 0 then
                local remaining = tokens[keys.remaining] or 0
                if remaining > 0 and remaining <= blinkAt then pulseIndex = drawn end
            end

            for k = 1, #row.pips do
                local pip = row.pips[k]
                -- The alpha pulse scales the element colour's AUTHORED alpha, so a translucent
                -- palette stays translucent; hue never moves. Every pip that is not pulsing is
                -- rewritten at full alpha on every visible frame, which is what restores a pip
                -- whose count changed, whose remaining climbed back over the threshold, or
                -- whose element dropped -- there is no separate restore path.
                if k == pulseIndex then
                    local pulseColor = row.pulseColor
                    pulseColor.a = math.floor(color.a * pulse)
                    pip:color(pulseColor)
                else
                    pip:color(color)
                end
                setVis(pip, k == 1 or k <= drawn)
                -- Unconditional: uiImage:update() drains the initFrames counter setPath arms
                -- on the first path set, and the sprite stays hidden by VIS_INIT until it
                -- reaches 0. Gating this on a state change leaves every sprite permanently
                -- invisible, with no error.
                pip:update()
            end

            local pctText = row.pctText
            if pctText then
                local pct = math.floor(tokens[keys.pct] or 0)
                if pct > 0 then
                    -- The '%' suffix comes from the layout's format pattern.
                    pctText:update(string.format(pctFormat, pct))

                    -- Colour is by overload RISK, not by element: the pips carry the
                    -- element identity, the numbers carry the danger.
                    if thresholds then
                        -- pctBaseColor is an already parsed colour table and the non-nil
                        -- fallback: a ramp with no catch-all and no thresholds.default would
                        -- otherwise resolve to nil and leave the last colour stuck on.
                        pctText:color(Utils.resolveThreshold(thresholds, tokens[keys.norm] or 0, pctBaseColor))
                    else
                        pctText:color(pctBaseColor)
                    end

                    setVis(pctText, true)
                else
                    -- 0% draws nothing: no dash, no placeholder.
                    setVis(pctText, false)
                end
            end
        end
    end

    function self.destroy(posReg)
        -- Elements are children of the caller's root container and are disposed with it.
        -- uiElement:dispose clears isEnabled and every entry point guards on it, so disposing
        -- the background here as well is a no-op if the container got there first.
        if columnBg then columnBg:dispose() end
        columnBg    = nil
        rows        = {}
        recastText  = nil
        created     = false
        if posReg then posReg['maneuvers'] = nil end
        if posRegistry then posRegistry['maneuvers'] = nil end
        posRegistry = nil
        layout      = nil
    end

    return self
end

return ManeuverRows
