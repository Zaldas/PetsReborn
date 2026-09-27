-- Copied byte-identical across addons; keep it free of addon-specific code.
local imgui = require('imgui')

local M = {}

M.accent = { 0.36, 0.66, 1.00 }

M.indent    = 6
M.subIndent = 10

local function rgba(c, a)
    return { c[1], c[2], c[3], a }
end

local function availWidth()
    local avail = imgui.GetContentRegionAvail()
    return type(avail) == 'table' and avail[1] or avail
end

M.palette = {
    { ImGuiCol_WindowBg,             { 0.055, 0.065, 0.100, 0.94 } },
    { ImGuiCol_ChildBg,              { 0.000, 0.000, 0.000, 0.00 } },
    { ImGuiCol_PopupBg,              { 0.075, 0.085, 0.130, 0.97 } },
    { ImGuiCol_Border,               { 0.36,  0.48,  0.72,  0.40 } },
    { ImGuiCol_BorderShadow,         { 0.00,  0.00,  0.00,  0.00 } },
    { ImGuiCol_TitleBg,              { 0.080, 0.095, 0.150, 1.00 } },
    { ImGuiCol_TitleBgActive,        { 0.115, 0.145, 0.230, 1.00 } },
    { ImGuiCol_TitleBgCollapsed,     { 0.080, 0.095, 0.150, 0.80 } },
    { ImGuiCol_Text,                 { 0.92,  0.94,  0.97,  1.00 } },
    { ImGuiCol_TextDisabled,         { 0.52,  0.57,  0.68,  1.00 } },
    { ImGuiCol_FrameBg,              { 0.125, 0.150, 0.225, 0.92 } },
    { ImGuiCol_FrameBgHovered,       { 0.180, 0.225, 0.340, 1.00 } },
    { ImGuiCol_FrameBgActive,        { 0.225, 0.290, 0.440, 1.00 } },
    { ImGuiCol_Button,               { 0.200, 0.300, 0.500, 0.90 } },
    { ImGuiCol_ButtonHovered,        { 0.300, 0.460, 0.740, 1.00 } },
    { ImGuiCol_ButtonActive,         { 0.380, 0.580, 0.900, 1.00 } },
    { ImGuiCol_CheckMark,            { 0.45,  0.82,  1.00,  1.00 } },
    { ImGuiCol_Header,               { 0.240, 0.380, 0.620, 0.80 } },
    { ImGuiCol_HeaderHovered,        { 0.300, 0.460, 0.740, 0.90 } },
    { ImGuiCol_HeaderActive,         { 0.380, 0.580, 0.900, 1.00 } },
    { ImGuiCol_Tab,                  { 0.110, 0.135, 0.205, 1.00 } },
    { ImGuiCol_TabHovered,           { 0.300, 0.460, 0.740, 1.00 } },
    { ImGuiCol_TabSelected,          { 0.220, 0.350, 0.600, 1.00 } },
    { ImGuiCol_TabSelectedOverline,  rgba(M.accent, 1.00) },
    { ImGuiCol_TabDimmed,            { 0.090, 0.110, 0.170, 1.00 } },
    { ImGuiCol_TabDimmedSelected,    { 0.170, 0.260, 0.440, 1.00 } },
    { ImGuiCol_Separator,            { 0.36,  0.48,  0.72,  0.35 } },
    { ImGuiCol_ScrollbarBg,          { 0.055, 0.065, 0.100, 0.60 } },
    { ImGuiCol_ScrollbarGrab,        { 0.240, 0.320, 0.480, 0.80 } },
    { ImGuiCol_ScrollbarGrabHovered, { 0.300, 0.460, 0.740, 1.00 } },
    { ImGuiCol_ScrollbarGrabActive,  { 0.380, 0.580, 0.900, 1.00 } },
    { ImGuiCol_SliderGrab,           { 0.36,  0.66,  1.00,  1.00 } },
    { ImGuiCol_SliderGrabActive,     { 0.55,  0.80,  1.00,  1.00 } },
    { ImGuiCol_ResizeGrip,           { 0.240, 0.320, 0.480, 0.80 } },
    { ImGuiCol_ResizeGripHovered,    { 0.300, 0.460, 0.740, 1.00 } },
    { ImGuiCol_ResizeGripActive,     { 0.380, 0.580, 0.900, 1.00 } },
}

M.styleVars = {
    { ImGuiStyleVar_WindowRounding,    8.0 },
    { ImGuiStyleVar_WindowBorderSize,  1.0 },
    { ImGuiStyleVar_FrameBorderSize,   1.0 },
    { ImGuiStyleVar_FrameRounding,     4.0 },
    { ImGuiStyleVar_PopupRounding,     6.0 },
    { ImGuiStyleVar_GrabRounding,      4.0 },
    { ImGuiStyleVar_ScrollbarRounding, 6.0 },
    { ImGuiStyleVar_ScrollbarSize,    10.0 },
    { ImGuiStyleVar_TabRounding,       5.0 },
    { ImGuiStyleVar_WindowPadding,    { 10.0, 8.0 } },
    { ImGuiStyleVar_FramePadding,     {  6.0, 3.0 } },
    { ImGuiStyleVar_ItemSpacing,      {  8.0, 5.0 } },
}

-- Callers must pop even when their body throws: the ImGui context is shared by every addon.
function M.push()
    local colors = 0
    for _, entry in ipairs(M.palette) do
        imgui.PushStyleColor(entry[1], entry[2])
        colors = colors + 1
    end
    local vars = 0
    for _, entry in ipairs(M.styleVars) do
        imgui.PushStyleVar(entry[1], entry[2])
        vars = vars + 1
    end
    return { colors = colors, vars = vars }
end

function M.pop(n)
    if n.vars > 0 then imgui.PopStyleVar(n.vars) end
    if n.colors > 0 then imgui.PopStyleColor(n.colors) end
end

function M.tooltipBegin()
    imgui.PushStyleColor(ImGuiCol_Border, rgba(M.accent, 0.9))
    imgui.PushStyleColor(ImGuiCol_PopupBg, { 0.055, 0.065, 0.105, 0.985 })
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1.5)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 10.0, 8.0 })
    imgui.BeginTooltip()
end

function M.tooltipEnd()
    imgui.EndTooltip()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(2)
end

function M.helpMarker(text)
    imgui.SameLine()
    imgui.TextDisabled('(?)')
    if imgui.IsItemHovered() then
        M.tooltipBegin()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 30)
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        M.tooltipEnd()
    end
end

function M.header(text, helpText)
    local drawlist = imgui.GetWindowDrawList()
    local avail    = imgui.GetContentRegionAvail()
    local availW   = type(avail) == 'table' and avail[1] or avail
    local x, y     = imgui.GetCursorScreenPos()
    local h        = imgui.GetTextLineHeightWithSpacing() + 4

    local bandL = imgui.GetColorU32(rgba(M.accent, 0.38))
    local bandR = imgui.GetColorU32(rgba(M.accent, 0.0))
    drawlist:AddRectFilledMultiColor({ x, y }, { x + availW * 0.85, y + h }, bandL, bandR, bandR, bandL)
    drawlist:AddRectFilled({ x, y }, { x + 3, y + h }, imgui.GetColorU32(rgba(M.accent, 1.0)))
    drawlist:AddLine({ x, y + h }, { x + availW, y + h }, imgui.GetColorU32(rgba(M.accent, 0.45)), 1.0)

    imgui.SetCursorScreenPos({ x + 9, y + math.floor((h - imgui.GetTextLineHeight()) * 0.5) })
    imgui.TextColored({ 1.0, 1.0, 1.0, 1.0 }, text)
    if type(helpText) == 'string' then
        M.helpMarker(helpText)
    end

    imgui.SetCursorScreenPos({ x, y + h + 3 })
    imgui.Spacing()
end

function M.comboWidth()
    return math.floor(availWidth() * 0.65)
end

function M.button(label, width, kind)
    local colors = 3
    if kind == 'primary' then
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.24, 0.42, 0.78, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.30, 0.52, 0.92, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.20, 0.34, 0.66, 1.00 })
    elseif kind == 'active' then
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.70, 0.45, 0.05, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.80, 0.55, 0.10, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.55, 0.35, 0.03, 1.00 })
    elseif kind == 'danger' then
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.55, 0.20, 0.20, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.70, 0.28, 0.28, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.40, 0.15, 0.15, 1.00 })
    else
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.00, 0.00, 0.00, 0.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 1.00, 1.00, 1.00, 0.12 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 1.00, 1.00, 1.00, 0.20 })
        imgui.PushStyleColor(ImGuiCol_Border,        rgba(M.accent, 0.55))
        colors = 4
    end
    local clicked = imgui.Button(label, { width, 0 })
    imgui.PopStyleColor(colors)
    return clicked
end

-- Centers on the full content width; call it outside any Indent.
function M.centeredButton(label, kind)
    local availW = availWidth()
    local btnW   = math.floor(availW * 0.80)
    imgui.SetCursorPosX(imgui.GetCursorPosX() + math.floor((availW - btnW) * 0.5))
    return M.button(label, btnW, kind)
end

return M
