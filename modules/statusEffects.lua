-- modules/statusEffects.lua
-- Renders a row of status effect icons with timer labels for the active pet.
-- Pure rendering module: reads pet.statusIds and pet.statusTimes from tokens.
-- Uses uiImage for icons (file-path based, auto-scaled from actual texture dims).
-- Uses gdifonts directly for timer labels below each icon.

local gdi     = require('libs/gdifonts/include')
local uiImage = require('libs/spui/uiImage')
local Utils   = require('utils')

local SE = {}

local engine  = nil
local uiScale = 1
local layout  = nil    -- layout.petFrame.statusEffects sub-table

-- Icon image pool
local MAX_ICONS  = 32
local VIS_TOKEN  = Utils.VIS_TOKEN
local iconImages  = {}  -- [1..poolSize] = uiImage instance
local poolSize    = 0

-- Timer label pool (GDI font objects, parallel to iconImages)
local timerLabels = {}   -- [1..poolSize] = fontObj or nil (nil when no timer layout)

-- Hit-test state
local statusAtSlot = {}  -- [1..poolSize] = statusId or nil
local shownCount   = 0   -- how many slots are currently active

-- Current anchor (top-left of the strip area in screen space)
local anchorX = 0
local anchorY = 0

-- Missing icon audit
local logPath      = nil   -- set in initialize(); nil = no logging
local onMissing    = nil   -- optional callback(statusId, path) for verbose chat
local loggedMissing = {}   -- [statusId] = true; prevents duplicate log entries

-- Icon path cache: existence of an icon file never changes during a session,
-- so resolve (and ashita.fs.exists-check) each statusId only once.
local iconPathCache = {}   -- [statusId] = resolved path string, or '' when missing

-- fakeParent: provides absolutePos and absoluteScale for uiImage layoutElement()
local fakeParent = {
    absolutePos        = { x = 0, y = 0 },
    absoluteScale      = { x = 1, y = 1 },
    absoluteVisibility = true,
}

-------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------

local function positionImage(img, relX, relY)
    img.parent = fakeParent
    img.posX   = relX
    img.posY   = relY
    fakeParent.absolutePos.x = anchorX
    fakeParent.absolutePos.y = anchorY
    img:layoutElement()
end

local function hideImages(from, to)
    for i = from, to do
        if iconImages[i] then iconImages[i]:hide(VIS_TOKEN) end
    end
end

local function hideTimers(from, to)
    for i = from, to do
        if timerLabels[i] then timerLabels[i]:set_visible(false) end
    end
end

-- Format remaining seconds. Returns '' when remaining <= 0 or nil.
-- >= 60s: floor to whole minutes ("1m", "2m", ...)
-- <  60s: raw seconds countdown ("59", "30", "5", ...)
local function formatTimer(remaining)
    if not remaining or remaining <= 0 then return '' end
    if remaining >= 60 then
        return string.format('%dm', math.floor(remaining / 60))
    end
    return tostring(remaining)
end

-- Convert hex color string '#RRGGBBAA' to gdifonts 0xAARRGGBB uint32.
local function hexToGdi(hex)
    hex = (hex or '#FFFFFFFF'):gsub('#', '')
    local r = tonumber(hex:sub(1,2), 16) or 255
    local g = tonumber(hex:sub(3,4), 16) or 255
    local b = tonumber(hex:sub(5,6), 16) or 255
    local a = tonumber(hex:sub(7,8), 16) or 255
    return tonumber(string.format('%02x%02x%02x%02x', a, r, g, b), 16)
end

-------------------------------------------------------------------------------
-- public interface
-------------------------------------------------------------------------------

-- Initialize the module. Call once when petFrame is initialized.
-- @param eng         sprite engine from sprites.newEngine()
-- @param layoutTable the full layout table (reads layoutTable.petFrame.statusEffects)
-- @param ax, ay      initial anchor position (strip top-left in screen space)
-- @param scale       UI scale (resY / 1440)
-- @param opts        optional table: { addonName=string, onMissing=fn(id,path) }
--                    addonName builds the audit log path under config/addons/<name>/
--                    onMissing is called once per missing ID (use for verbose chat output)
function SE.initialize(eng, layoutTable, ax, ay, scale, opts)
    engine  = eng
    uiScale = scale or 1
    anchorX = ax
    anchorY = ay
    layout  = layoutTable and layoutTable.petFrame and layoutTable.petFrame.statusEffects
    if not layout then return end

    loggedMissing = {}
    if opts and opts.addonName then
        logPath   = AshitaCore:GetInstallPath() .. 'config/addons/' .. opts.addonName .. '/missingIcons.log'
        onMissing = opts.onMissing or nil
    else
        logPath   = nil
        onMissing = nil
    end

    fakeParent.absoluteScale.x = uiScale
    fakeParent.absoluteScale.y = uiScale

    poolSize = math.min(MAX_ICONS, layout.maxIcons or MAX_ICONS)

    local timerLayout = layout.timer
    local iconSize    = layout.iconSize or 18

    for i = 1, poolSize do
        -- Icon image: uiImage loads PNG from disk, auto-sets nativeW/H from actual texture dims.
        -- displayW/H = absoluteWidth/Height = iconSize * uiScale → correct scaling regardless of source resolution.
        local img = uiImage.create('', iconSize, iconSize, 0, 0, 1, 1, engine)
        positionImage(img, 0, 0)
        img:createPrimitives()
        img:hide(VIS_TOKEN)
        iconImages[i]   = img
        statusAtSlot[i] = nil

        -- Timer label (only when layout defines a timer section)
        if timerLayout then
            local fontH = math.floor((timerLayout.size or 8) * uiScale)
            timerLabels[i] = gdi:create_object({
                font_family    = timerLayout.font or 'Arial',
                font_height    = fontH,
                font_color     = hexToGdi(timerLayout.color  or '#FFFFFFFF'),
                outline_color  = hexToGdi(timerLayout.stroke or '#000000C8'),
                outline_width  = (timerLayout.strokeWidth or 1) * uiScale,
                font_alignment = 1,   -- center
                font_flags     = 0,
                position_x     = 0,
                position_y     = 0,
                visible        = false,
                text           = '',
                gradient_color = 0x00000000,
                gradient_style = 0,
                box_height     = 0,
                box_width      = 0,
            }, false)
        end
    end
end

-- Update icon display and timer labels from the current token table.
-- Call every frame from petFrame.update().
-- Visibility controlled by layout.bind.visible token (default: 'pet.active').
-- layout.hideWhenEmpty token: when true, hide the strip if no effects are active.
function SE.update(tokens)
    if not layout or poolSize == 0 then return end

    local bind = layout.bind
    local show = (not bind or not bind.visible    or tokens[bind.visible]    == true)
             and (not bind or not bind.visibleAnd or tokens[bind.visibleAnd] == true)

    local ids   = tokens['pet.statusIds']
    local times = tokens['pet.statusTimes']

    if not show or not ids or #ids == 0 then
        hideImages(1, poolSize)
        hideTimers(1, poolSize)
        for i = 1, poolSize do statusAtSlot[i] = nil end
        shownCount = 0
        return
    end

    local timerLayout = layout.timer
    local iconSize    = layout.iconSize or 18
    local iconGap     = layout.iconGap  or 2
    local step        = iconSize + iconGap   -- layout-space step per icon

    -- anchorX/Y is the resolved absolute screen position (layout.pos baked in by petFrame).
    -- Timer offsets in screen space (GDI uses absolute screen coords)
    local timerOffX    = timerLayout and math.floor(((timerLayout.pos and timerLayout.pos[1]) or 0) * uiScale) or 0
    local timerOffY    = timerLayout and math.floor(((timerLayout.pos and timerLayout.pos[2]) or 0) * uiScale) or 0
    local startScreenX = anchorX
    local startScreenY = anchorY
    local stepPx       = math.floor(step * uiScale)   -- screen-space step

    local now   = os.time()
    local shown = 0

    for _, statusId in ipairs(ids) do
        if shown >= poolSize then break end
        shown = shown + 1

        -- Icon image: position in layout-space via fakeParent, path loads + scales automatically.
        local img      = iconImages[shown]
        local iconFile = iconPathCache[statusId]
        if iconFile == nil then
            -- First encounter of this statusId: resolve once, cache for the session.
            iconFile = 'libs/status/icons/XIView/' .. statusId .. '.png'
            if not ashita.fs.exists(addon.path .. iconFile) then
                if not loggedMissing[statusId] then
                    loggedMissing[statusId] = true
                    if logPath then
                        local f = io.open(logPath, 'a')
                        if f then
                            f:write(string.format('[%s] missing icon: statusId=%d path=%s\n',
                                os.date('%Y-%m-%d %H:%M:%S'), statusId, iconFile))
                            f:close()
                        end
                    end
                    if onMissing then onMissing(statusId, iconFile) end
                end
                iconFile = ''   -- blank path → uiImage renders nothing
            end
            iconPathCache[statusId] = iconFile
        end
        positionImage(img, (shown - 1) * step, 0)
        img:path(iconFile)
        img:show(VIS_TOKEN)
        img:update()
        statusAtSlot[shown] = statusId

        -- Timer label (GDI, absolute screen-space coordinates)
        if timerLabels[shown] and timerLayout then
            local expiry    = times and times[statusId]
            local remaining = expiry and math.max(0, expiry - now) or nil
            local label     = formatTimer(remaining)

            if label ~= '' then
                local iconScreenX = startScreenX + (shown - 1) * stepPx
                timerLabels[shown]:set_text(label)
                timerLabels[shown]:set_position_x(iconScreenX + math.floor(iconSize * uiScale / 2) + timerOffX)
                timerLabels[shown]:set_position_y(startScreenY + timerOffY)
                timerLabels[shown]:set_visible(true)
            else
                timerLabels[shown]:set_visible(false)
            end
        end
    end

    -- Clear slot tracking and hide unused pool entries
    for i = shown + 1, poolSize do statusAtSlot[i] = nil end
    shownCount = shown
    hideImages(shown + 1, poolSize)
    hideTimers(shown + 1, poolSize)
end

-- Move the icon strip anchor. Called when the pet window is dragged.
function SE.setAnchor(ax, ay)
    anchorX = ax
    anchorY = ay
end

-- Returns the statusId under screen position (mx, my), or nil.
-- Uses absolutePos/Width/Height set by uiImage:layoutElement() — no allocations.
function SE.getStatusAtPosition(mx, my)
    if not layout then return nil end
    for i = 1, shownCount do
        local img = iconImages[i]
        local sid = statusAtSlot[i]
        if img and sid and img.absolutePos then
            local ax = img.absolutePos.x
            local ay = img.absolutePos.y
            local w  = img.absoluteWidth
            local h  = img.absoluteHeight
            if mx >= ax and mx < ax + w and my >= ay and my < ay + h then
                return sid
            end
        end
    end
    return nil
end

-- Returns the pixel height of the icon strip content (icons + timers + margin).
-- Does NOT include pos offset — that is baked into the anchor by petFrame.
function SE.stripHeight()
    if not layout or poolSize == 0 then return 0 end
    local iconH    = math.floor((layout.iconSize or 18) * uiScale)
    local marginB  = math.floor((layout.marginBottom or 4) * uiScale)
    local timerExt = 0
    if layout.timer then
        local timerOffY  = math.floor(((layout.timer.pos and layout.timer.pos[2]) or 0) * uiScale)
        local timerFontH = math.floor((layout.timer.size or 8) * uiScale)
        local timerBase  = timerOffY + timerFontH
        timerExt = math.max(0, timerBase - iconH)
    end
    return iconH + timerExt + marginB
end

-- Destroy all image instances and font objects.
function SE.destroy()
    for i = 1, poolSize do
        if iconImages[i] then
            iconImages[i]:dispose()
            iconImages[i] = nil
        end
        if timerLabels[i] then
            gdi:destroy_object(timerLabels[i])
            timerLabels[i] = nil
        end
        statusAtSlot[i] = nil
    end
    poolSize   = 0
    shownCount = 0
    engine     = nil
    layout     = nil
end

return SE
