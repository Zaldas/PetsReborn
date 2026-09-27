-- elements/configWindow.lua
-- ImGui configuration window for PetsReborn.
-- Toggle with /pr (no args). Drawn every frame from petsreborn.lua d3d_present.

local imgui       = require('imgui')
local petAbilities = require('data/petAbilities')
local automatonIcd = require('modules/automatonIcd')
local layoutEditor = require('libs/spui/layoutEditor')
local uiTheme      = require('libs/uiTheme')

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
    Automaton = 240,
    Layout = 300,
}

-- A tab bar too wide for its window is clipped and scrolled, not wrapped, so tabs fall off the
-- right edge and become unreachable. These size the floor that stops that.
--
-- ImGui lays a tab out as its label plus FramePadding.x * 2, with ItemInnerSpacing.x between
-- tabs. The style those come from is not reachable from Lua here, so these are the default
-- theme's values -- they only have to be generous enough to stop the clipping.
local TAB_PADDING     = 20
local TAB_SPACING     = 4
local WINDOW_CHROME   = 16
local TAB_BAR_MIN     = 300   -- used when CalcTextSize is unavailable to measure with

-- Driven by TAB_WIDTHS rather than a second list of names, so a tab added there widens the
-- floor with it. The sum does not care what order pairs() hands them back in.
local function minTabBarWidth()
    if imgui.CalcTextSize == nil then
        return TAB_BAR_MIN
    end

    local total = WINDOW_CHROME
    for name in pairs(TAB_WIDTHS) do
        local labelWidth = imgui.CalcTextSize(name)
        total = total + labelWidth + TAB_PADDING + TAB_SPACING
    end

    return total
end

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
--     onDebugView, onResetPosition, onPrintState, onSave
-- debugViewType: current debug view string or nil
function M.draw(prSettings, cb, debugViewType)
    if not open then return end

    local function drawBody()
        if imgui.BeginTabBar('pr_tabs') then

            -- ============================================================
            -- General tab: Style + Preview, Options, action buttons.
            -- ============================================================
            if imgui.BeginTabItem('General') then
                currentTab = 'General'

                -- Style ------------------------------------------------
                uiTheme.header('Style')

                imgui.Indent(uiTheme.indent)
                imgui.SetNextItemWidth(uiTheme.comboWidth())
                local currentStyle = prSettings.layout or 'ffxi'
                if imgui.BeginCombo('Style##style', currentStyle) then
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

                local currentDV = debugViewType or 'avatar'
                imgui.SetNextItemWidth(uiTheme.comboWidth())
                if imgui.BeginCombo('Preview##debugview', currentDV) then
                    for _, t in ipairs(DEBUG_TYPES) do
                        local selected = (t == currentDV)
                        if imgui.Selectable(t, selected) then
                            cb.onDebugView(t)
                        end
                        if selected then imgui.SetItemDefaultFocus() end
                    end
                    imgui.EndCombo()
                end
                uiTheme.helpMarker(
                    'Render fake pet data to preview the window without an active pet.\n' ..
                    'Active while the config is open; clears when you close it.'
                )
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()

                -- Options ----------------------------------------------
                uiTheme.header('Options')

                imgui.Indent(uiTheme.indent)
                local alwaysShow = { prSettings.alwaysShow == true }
                if imgui.Checkbox('Always show recasts', alwaysShow) then
                    cb.onAlwaysShow(alwaysShow[1])
                end
                uiTheme.helpMarker('Show ability cooldowns even without an active pet')

                local alignBottom = { prSettings.alignBottom == true }
                if imgui.Checkbox('Align bottom', alignBottom) then
                    cb.onAlignBottom(alignBottom[1])
                end
                uiTheme.helpMarker('Anchor point is bottom-left; window grows upward')

                local verbose = { prSettings.verbose ~= false }
                if imgui.Checkbox('Verbose', verbose) then
                    cb.onVerbose(verbose[1])
                end
                uiTheme.helpMarker('Print confirmation messages when running commands like /pr reload.')

                local lockPosition = { prSettings.lockPosition == true }
                if imgui.Checkbox('Lock position', lockPosition) then
                    cb.onLockPosition(lockPosition[1])
                end
                uiTheme.helpMarker('Disable drag-to-move so the window cannot be accidentally repositioned.')

                local customScaleOn = { (prSettings.scale or 0) > 0 }
                if imgui.Checkbox('Custom scale', customScaleOn) then
                    if customScaleOn[1] then cb.onScale(1.0) else cb.onScale(0) end
                    cb.onSave()
                end
                uiTheme.helpMarker('Override the automatic scale (based on resolution) with a manual multiplier.')

                if customScaleOn[1] then
                    imgui.Indent(uiTheme.subIndent)
                    local scaleVal = { prSettings.scale > 0 and prSettings.scale or 1.0 }
                    imgui.SetNextItemWidth(uiTheme.comboWidth())
                    if imgui.SliderFloat('##scaleslider', scaleVal, 0.25, 2.5, 'Scale: %.2f',
                        ImGuiSliderFlags_AlwaysClamp) then
                        cb.onScale(scaleVal[1])
                    end
                    if imgui.IsItemDeactivatedAfterEdit() then
                        cb.onSave()
                    end
                    imgui.Unindent(uiTheme.subIndent)
                end
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()

                imgui.Separator()
                imgui.Spacing()

                if uiTheme.centeredButton('Reload##reloadbtn', 'primary') then
                    cb.onReload()
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(
                        'Reload layout and settings from disk.\n' ..
                        'Use this to apply changes made to layout files.'
                    )
                end

                imgui.Spacing()

                if uiTheme.centeredButton('Reset position##resetbtn', 'ghost') then
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
                uiTheme.header(
                    'General Elements',
                    'Choose which shared display elements are visible in the pet window.'
                )

                imgui.Indent(uiTheme.indent)
                local showMp = { prSettings.showMpBar ~= false }
                if imgui.Checkbox('MP bar', showMp) then
                    cb.onShowMpBar(showMp[1])
                end
                uiTheme.helpMarker('Show the pet MP bar.')

                local showTp = { prSettings.showTpBar ~= false }
                if imgui.Checkbox('TP bar', showTp) then
                    cb.onShowTpBar(showTp[1])
                end
                uiTheme.helpMarker('Show the pet TP bar.')

                local showTargetBar = { prSettings.showTargetBar ~= false }
                if imgui.Checkbox('Target bar', showTargetBar) then
                    cb.onShowTargetBar(showTargetBar[1])
                end
                uiTheme.helpMarker('Show the pet target bar.')

                local showRecasts = { prSettings.showRecasts ~= false }
                if imgui.Checkbox('Recast rows', showRecasts) then
                    cb.onShowRecasts(showRecasts[1])
                end
                uiTheme.helpMarker('Show the pet ability recast rows.')

                local showManeuvers = { prSettings.showManeuvers ~= false }
                if imgui.Checkbox('Maneuver column', showManeuvers) then
                    cb.onShowManeuvers(showManeuvers[1])
                end
                uiTheme.helpMarker('Show the PUP maneuver and overload column. Automaton only.')

                local hideStatusWhenEmpty = { prSettings.hideStatusWhenEmpty ~= false }
                if imgui.Checkbox('Hide status when empty', hideStatusWhenEmpty) then
                    cb.onHideStatusWhenEmpty(hideStatusWhenEmpty[1])
                end
                uiTheme.helpMarker('Hide status effect icons when pet has no active effects.')
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()

                -- Recasts -----------------------------------------------
                uiTheme.header(
                    'Recasts',
                    'Choose which pet job recast abilities are visible in the pet window.'
                )

                local RECAST_TYPES = {
                    { key = 'avatar',    label = 'Avatar (SMN)'    },
                    { key = 'wyvern',    label = 'Wyvern (DRG)'    },
                    { key = 'automaton', label = 'Automaton (PUP)' },
                    { key = 'jug',       label = 'Jug pet (BST)'   },
                    { key = 'charm',     label = 'Charm (BST)'     },
                }

                if not prSettings.recastVisible then prSettings.recastVisible = {} end

                imgui.Indent(uiTheme.indent)
                for _, typeEntry in ipairs(RECAST_TYPES) do
                    local petType  = typeEntry.key
                    local abilities = petAbilities.slots[petType] or {}
                    if #abilities > 0 then
                        if imgui.TreeNode(typeEntry.label) then
                            imgui.Indent(uiTheme.subIndent)
                            local typeVis = prSettings.recastVisible[petType] or {}
                            for _, slot in ipairs(abilities) do
                                local slotVis = { typeVis[tostring(slot.id)] ~= false }
                                if imgui.Checkbox(slot.displayName .. '##rc_' .. petType .. '_' .. slot.id, slotVis) then
                                    cb.onRecastVisible(petType, slot.id, slotVis[1])
                                end
                            end
                            -- Gate rows are read off the live head and frame, so the list is
                            -- empty until a 0x0044 has said what is fitted. Attachment
                            -- abilities are listed in their own section instead, which offers
                            -- all of them regardless of what is equipped.
                            if petType == 'automaton' then
                                for _, slot in ipairs(automatonIcd.slots()) do
                                    if not slot.isAttachment then
                                        local slotVis = { typeVis[tostring(slot.id)] ~= false }
                                        if imgui.Checkbox(slot.displayName .. '##rc_' .. petType .. '_' .. slot.id, slotVis) then
                                            cb.onRecastVisible(petType, slot.id, slotVis[1])
                                        end
                                    end
                                end
                            end
                            imgui.Unindent(uiTheme.subIndent)
                            imgui.TreePop()
                        end
                    end
                end
                imgui.Unindent(uiTheme.indent)

                imgui.EndTabItem()
            end

            -- ============================================================
            -- Automaton tab: PUP-only settings and the attachment recasts.
            -- ============================================================
            if imgui.BeginTabItem('Automaton') then
                currentTab = 'Automaton'

                -- General -----------------------------------------------
                uiTheme.header(
                    'General',
                    'Settings that apply to the PUP automaton only.'
                )

                imgui.Indent(uiTheme.indent)
                local showIcd = { prSettings.showAutomatonIcd ~= false }
                if imgui.Checkbox('Internal cooldowns', showIcd) then
                    cb.onShowAutomatonIcd(showIcd[1])
                end
                uiTheme.helpMarker(
                    'Show the automaton\'s own action gates: the magic cooldowns its head\n' ..
                    'sets, and the recasts of its attachment abilities.\n' ..
                    'Neither is in client memory, so both are timed from the automaton\'s\n' ..
                    'own actions, and read Ready until one has been seen.'
                )

                local currentHpDisplay = prSettings.automatonHpDisplay or 'value'
                imgui.SetNextItemWidth(uiTheme.comboWidth())
                if imgui.BeginCombo('HP readout##automatonhp', currentHpDisplay) then
                    for _, mode in ipairs(HP_DISPLAY_MODES) do
                        local selected = (mode == currentHpDisplay)
                        if imgui.Selectable(mode, selected) then
                            if mode ~= currentHpDisplay then cb.onAutomatonHpDisplay(mode) end
                        end
                        if selected then imgui.SetItemDefaultFocus() end
                    end
                    imgui.EndCombo()
                end
                uiTheme.helpMarker(
                    'Value shows the automaton\'s exact HP, which only PUP reports.\n' ..
                    'Percent shows HP percent instead, matching every other pet type.'
                )
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()

                -- Attachments -------------------------------------------
                uiTheme.header(
                    'Attachments',
                    'Recasts of the abilities attachments grant.\n' ..
                    'Every one is listed here whether or not it is fitted. A row reaches the\n' ..
                    'pet window only when the attachment is equipped AND ticked below, so\n' ..
                    'ticking one now decides what shows the next time it is on the automaton.'
                )

                -- Reached without the Display tab having been opened, so this cannot lean on
                -- the Recasts section having seeded recastVisible.
                local recastVisible = prSettings.recastVisible or {}
                local attachmentVis = recastVisible.automaton or {}
                imgui.Indent(uiTheme.indent)
                for _, slot in ipairs(automatonIcd.attachmentOptions()) do
                    local slotVis = { attachmentVis[tostring(slot.id)] ~= false }
                    if imgui.Checkbox(slot.displayName .. '##at_' .. slot.id, slotVis) then
                        cb.onRecastVisible('automaton', slot.id, slotVis[1])
                    end
                    -- Naming the ability explains nothing when it carries the attachment's
                    -- own name, so those four describe what it does instead.
                    uiTheme.helpMarker(slot.effect
                        or string.format('Casts %s.', slot.ability))
                end
                imgui.Unindent(uiTheme.indent)

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

    local n = uiTheme.push()
    local windowWidth = TAB_WIDTHS[currentTab] or 240
    if currentTab == 'Layout' and layoutEditor.isRegistered() and layoutEditor.getSuggestedWidth then
        windowWidth = layoutEditor.getSuggestedWidth()
    end
    windowWidth = math.max(windowWidth, minTabBarWidth())
    imgui.SetNextWindowSize({windowWidth, 0}, 1)  -- per-tab width; height=0 auto-fits content

    local visible = { true }
    local ok, err = true, nil
    if imgui.Begin('PetsReborn.' .. addon.version, visible, IMGUI_NO_RESIZE) then
        ok, err = pcall(drawBody)
    end
    imgui.End()
    uiTheme.pop(n)

    -- Window close button: also clears debug view if active
    if not visible[1] then
        if debugViewType then cb.onDebugView(nil) end
        open = false
    end
    if not ok then error(err, 0) end
end

return M
