-- elements/configWindow.lua
-- ImGui configuration window for PetsReborn.
-- Toggle with /pr (no args). Drawn every frame from petsreborn.lua d3d_present.

local imgui       = require('imgui')
local petAbilities = require('data/petAbilities')
local layoutEditor = require('libs/spui/layoutEditor')

local M = {}

-- ImGuiWindowFlags_NoResize = 2
local IMGUI_NO_RESIZE = 2

local open      = false
local styleList = {}
local currentTab = 'General'

local DEBUG_TYPES = { 'avatar', 'wyvern', 'automaton', 'jug', 'charm' }

-- Values of prSettings.automatonHpDisplay, shown verbatim in the dropdown.
local HP_DISPLAY_MODES = { 'value', 'percent' }
local TAB_WIDTHS = {
    General = 240,
    Display = 240,
    Layout = 300,
}

-- Returns true if the file's header comment block contains the literal
-- substring '@unsupported' within its first 10 lines.
local function isUnsupportedLayout(filePath)
    local f = io.open(filePath, 'r')
    if not f then return false end
    local unsupported = false
    for _ = 1, 10 do
        local line = f:read('*l')
        if not line then break end
        if line:find('@unsupported', 1, true) then
            unsupported = true
            break
        end
    end
    f:close()
    return unsupported
end

local function scanStyles(layoutsPath)
    local results = {}
    local path = layoutsPath:gsub('/', '\\')
    local dir = path:sub(-1) == '\\' and path or (path .. '\\')
    local files = ashita.fs.get_dir(path, '.*.lua', false)
    if files then
        for _, fname in pairs(files) do
            local name = fname:match('^(.+)%.lua$')
            if name then
                results[#results + 1] = {
                    name = name,
                    unsupported = isUnsupportedLayout(dir .. fname),
                }
            end
        end
    end
    return results
end

-----------------------------------------------------------------------
-- Style helpers (matching SkillchainCalc)
-----------------------------------------------------------------------

-- Blue gradient fade subheading (solid left → transparent right).
local function drawGradientHeader(text, width, helpText)
    local drawlist    = imgui.GetWindowDrawList()
    local x, y       = imgui.GetCursorScreenPos()
    local lineH       = imgui.GetTextLineHeightWithSpacing()
    local gradWidth   = width * 0.75
    local colLeft     = { 0.25, 0.40, 0.85, 1.00 }
    local colRight    = { colLeft[1], colLeft[2], colLeft[3], 0.00 }
    local colLeftU32  = imgui.GetColorU32(colLeft)
    local colRightU32 = imgui.GetColorU32(colRight)

    drawlist:AddRectFilledMultiColor(
        { x, y },
        { x + gradWidth, y + lineH },
        colLeftU32, colRightU32, colRightU32, colLeftU32
    )

    imgui.SetCursorScreenPos({ x + 4, y + 2 })
    imgui.Text(text)
    if helpText then
        imgui.SameLine()
        imgui.TextDisabled('(?)')
        if imgui.IsItemHovered() then
            imgui.SetTooltip(helpText)
        end
    end

    local _, newY = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ x, newY })
    imgui.Spacing()
end

-- Rounded primary (blue) or ghost (transparent) button.
local function styledButton(label, size, isPrimary)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0)

    if isPrimary then
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.25, 0.40, 0.85, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.30, 0.48, 0.95, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.18, 0.32, 0.70, 1.00 })
    else
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.00, 0.00, 0.00, 0.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 1.00, 1.00, 1.00, 0.12 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 1.00, 1.00, 1.00, 0.20 })
    end

    local clicked = imgui.Button(label, size)
    imgui.PopStyleColor(3)
    imgui.PopStyleVar(1)
    return clicked
end

-----------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------

function M.initialize(layoutsPath, preserveOpen)
    styleList = scanStyles(layoutsPath)
    if not preserveOpen then open = false end
end

function M.toggle()
    open = not open
end

function M.close()
    open = false
end

function M.isOpen()
    return open
end

function M.destroy()
    open = false
    currentTab = 'General'
end

-- Draw the config window. Call every frame from d3d_present BEFORE the visibility guard.
-- prSettings: the addon settings table (read for current values)
-- cb: callbacks table with keys: onAlwaysShow, onAlignBottom, onStyle, onScale,
--     onDebugView, onResetPosition, onPrintState
-- debugViewType: current debug view string or nil
function M.draw(prSettings, cb, debugViewType)
    if not open then return end

    local windowWidth = TAB_WIDTHS[currentTab] or 240
    if currentTab == 'Layout' and layoutEditor.isRegistered() and layoutEditor.getSuggestedWidth then
        windowWidth = layoutEditor.getSuggestedWidth()
    end
    imgui.SetNextWindowSize({windowWidth, 0}, 1)  -- per-tab width; height=0 auto-fits content

    local visible = { true }
    if imgui.Begin('PetsReborn.' .. addon.version, visible, IMGUI_NO_RESIZE) then

        local avail  = imgui.GetContentRegionAvail()
        local availW = type(avail) == 'table' and avail[1] or avail
        local itemW  = availW * 0.80
        local pad    = (availW - itemW) * 0.5
        local indent = 6

        if imgui.BeginTabBar('pr_tabs') then

            -- ============================================================
            -- General tab: Style + Preview, Options, Utilities.
            -- ============================================================
            if imgui.BeginTabItem('General') then
                currentTab = 'General'

                -- Style ------------------------------------------------
                drawGradientHeader('Style', availW)

                imgui.SetCursorPosX(imgui.GetCursorPosX() + pad)
                imgui.SetNextItemWidth(itemW)
                local currentStyle = prSettings.layout or 'ffxi'
                if imgui.BeginCombo('##style', currentStyle) then
                    for _, s in ipairs(styleList) do
                        local selected = (s.name == currentStyle)
                        local label = s.unsupported and (s.name .. ' (unsupported)') or s.name
                        if imgui.Selectable(label, selected) then
                            if s.name ~= currentStyle then cb.onStyle(s.name) end
                        end
                        if selected then imgui.SetItemDefaultFocus() end
                    end
                    imgui.EndCombo()
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                imgui.Text('Preview:')
                imgui.SameLine()
                imgui.TextDisabled('(?)')
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(
                        'Render fake pet data to preview the window without an active pet.\n' ..
                        'Active while the config is open; clears when you close it.'
                    )
                end

                local currentDV = debugViewType or 'avatar'
                imgui.SetCursorPosX(imgui.GetCursorPosX() + pad)
                imgui.SetNextItemWidth(itemW)
                if imgui.BeginCombo('##debugview', currentDV) then
                    for _, t in ipairs(DEBUG_TYPES) do
                        local selected = (t == currentDV)
                        if imgui.Selectable(t, selected) then
                            cb.onDebugView(t)
                        end
                        if selected then imgui.SetItemDefaultFocus() end
                    end
                    imgui.EndCombo()
                end

                imgui.Spacing()

                -- Options ----------------------------------------------
                drawGradientHeader('Options', availW)

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local alwaysShow = { prSettings.alwaysShow == true }
                if imgui.Checkbox('Always show recasts', alwaysShow) then
                    cb.onAlwaysShow(alwaysShow[1])
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Show ability cooldowns even without an active pet')
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local alignBottom = { prSettings.alignBottom == true }
                if imgui.Checkbox('Align bottom', alignBottom) then
                    cb.onAlignBottom(alignBottom[1])
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Anchor point is bottom-left; window grows upward')
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local verbose = { prSettings.verbose ~= false }
                if imgui.Checkbox('Verbose', verbose) then
                    cb.onVerbose(verbose[1])
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Print confirmation messages when running commands like /pr reload.')
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local lockPosition = { prSettings.lockPosition == true }
                if imgui.Checkbox('Lock position', lockPosition) then
                    cb.onLockPosition(lockPosition[1])
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Disable drag-to-move so the window cannot be accidentally repositioned.')
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local customScaleOn = { (prSettings.scale or 0) > 0 }
                if imgui.Checkbox('Custom scale', customScaleOn) then
                    if customScaleOn[1] then cb.onScale(1.0) else cb.onScale(0) end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Override the automatic scale (based on resolution) with a manual multiplier.')
                end

                if customScaleOn[1] then
                    local scaleVal = { prSettings.scale > 0 and prSettings.scale or 1.0 }
                    imgui.SetCursorPosX(imgui.GetCursorPosX() + pad)
                    imgui.SetNextItemWidth(itemW)
                    if imgui.SliderFloat('##scaleslider', scaleVal, 0.25, 2.5, 'Scale: %.2f') then
                        cb.onScale(scaleVal[1])
                    end
                end

                imgui.Spacing()

                -- Utilities --------------------------------------------
                drawGradientHeader('Utilities', availW)

                imgui.SetCursorPosX(imgui.GetCursorPosX() + pad)
                if styledButton('Reload##reloadbtn', {itemW, 0}, true) then
                    cb.onReload()
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(
                        'Reload layout and settings from disk.\n' ..
                        'Use this to apply changes made to layout files.'
                    )
                end

                imgui.Spacing()

                imgui.SetCursorPosX(imgui.GetCursorPosX() + pad)
                if styledButton('Reset Position##resetbtn', {itemW, 0}, false) then
                    cb.onResetPosition()
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(
                        'Snap window to position (100, 100).\n' ..
                        'Use this if the window has moved off-screen.'
                    )
                end

                imgui.EndTabItem()
            end

            -- ============================================================
            -- Display tab: General Elements (cross-job), then per-job subs.
            -- ============================================================
            if imgui.BeginTabItem('Display') then
                currentTab = 'Display'

                -- General Elements (all jobs) --------------------------
                drawGradientHeader(
                    'General Elements',
                    availW,
                    'Choose which shared display elements are visible in the pet window.'
                )

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local showMp = { prSettings.showMpBar ~= false }
                if imgui.Checkbox('MP bar', showMp) then
                    cb.onShowMpBar(showMp[1])
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local showTp = { prSettings.showTpBar ~= false }
                if imgui.Checkbox('TP bar', showTp) then
                    cb.onShowTpBar(showTp[1])
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local showTargetBar = { prSettings.showTargetBar ~= false }
                if imgui.Checkbox('Target bar', showTargetBar) then
                    cb.onShowTargetBar(showTargetBar[1])
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local showRecasts = { prSettings.showRecasts ~= false }
                if imgui.Checkbox('Recast rows', showRecasts) then
                    cb.onShowRecasts(showRecasts[1])
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local showManeuvers = { prSettings.showManeuvers ~= false }
                if imgui.Checkbox('Maneuver column', showManeuvers) then
                    cb.onShowManeuvers(showManeuvers[1])
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Show the PUP maneuver and overload column. Automaton only.')
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local hideStatusWhenEmpty = { prSettings.hideStatusWhenEmpty ~= false }
                if imgui.Checkbox('Hide status when empty', hideStatusWhenEmpty) then
                    cb.onHideStatusWhenEmpty(hideStatusWhenEmpty[1])
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Hide status effect icons when pet has no active effects.')
                end

                imgui.Spacing()

                -- Recasts -----------------------------------------------
                drawGradientHeader(
                    'Recasts',
                    availW,
                    'Choose which pet job recast abilities are visible in the pet window.'
                )

                local RECAST_TYPES = {
                    { key = 'avatar',    label = 'Avatar (SMN)'    },
                    { key = 'wyvern',    label = 'Wyvern (DRG)'    },
                    { key = 'automaton', label = 'Automaton (PUP)' },
                    { key = 'jug',       label = 'Jug Pet (BST)'   },
                    { key = 'charm',     label = 'Charm (BST)'     },
                }

                if not prSettings.recastVisible then prSettings.recastVisible = {} end

                for _, typeEntry in ipairs(RECAST_TYPES) do
                    local petType  = typeEntry.key
                    local abilities = petAbilities[petType] or {}
                    if #abilities > 0 then
                        imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                        if imgui.TreeNode(typeEntry.label) then
                            local typeVis = prSettings.recastVisible[petType] or {}
                            for _, slot in ipairs(abilities) do
                                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent * 2)
                                local slotVis = { typeVis[tostring(slot.id)] ~= false }
                                if imgui.Checkbox(slot.displayName .. '##rc_' .. petType .. '_' .. slot.id, slotVis) then
                                    cb.onRecastVisible(petType, slot.id, slotVis[1])
                                end
                            end
                            imgui.TreePop()
                        end
                    end
                end

                imgui.Spacing()

                -- Automaton ---------------------------------------------
                drawGradientHeader(
                    'Automaton',
                    availW,
                    'Settings that apply to the PUP automaton only.'
                )

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                imgui.Text('HP readout:')
                imgui.SameLine()
                imgui.TextDisabled('(?)')
                if imgui.IsItemHovered() then
                    -- No '%' in this string: SetTooltip is printf-style, so a literal percent
                    -- sign is read as a format specifier.
                    imgui.SetTooltip(
                        'Value shows the automaton\'s exact HP, which only PUP reports.\n' ..
                        'Percent shows HP percent instead, matching every other pet type.'
                    )
                end

                local currentHpDisplay = prSettings.automatonHpDisplay or 'value'
                imgui.SetCursorPosX(imgui.GetCursorPosX() + pad)
                imgui.SetNextItemWidth(itemW)
                if imgui.BeginCombo('##automatonhp', currentHpDisplay) then
                    for _, mode in ipairs(HP_DISPLAY_MODES) do
                        local selected = (mode == currentHpDisplay)
                        if imgui.Selectable(mode, selected) then
                            if mode ~= currentHpDisplay then cb.onAutomatonHpDisplay(mode) end
                        end
                        if selected then imgui.SetItemDefaultFocus() end
                    end
                    imgui.EndCombo()
                end

                imgui.EndTabItem()
            end

            local activeLayoutName = prSettings.layout or 'ffxi'
            if imgui.BeginTabItem('Layout') then
                currentTab = 'Layout'
                if layoutEditor.isRegistered() then
                    imgui.Text(string.format('Editing layout: %s', activeLayoutName))
                    layoutEditor.draw()
                else
                    imgui.TextDisabled('Layout editor not initialized.')
                end
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
    end
    imgui.End()

    -- Window close button: also clears debug view if active
    if not visible[1] then
        if debugViewType then cb.onDebugView(nil) end
        open = false
    end
end

return M
