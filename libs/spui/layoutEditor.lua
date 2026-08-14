local imgui = require('imgui')
local spuiUtils = require('libs/spui/utils')

local M = {}

local SKIP_KEYS = {
    bind = true,
    sliceBorder = true,
    anchor = true,
    zOrder = true,
    _meta = true,
}

local HIGHLIGHT_COLOR = { 0.6, 0.9, 1.0, 1.0 }
local EMPTY_TABLE = {}
local BASE_INPUT_START_X = 160
local LABEL_GAP = 8

local reg = nil
local cachedBase = nil
local cachedWidth = nil
local draftNumbers = {}
local draftCoords = {}
local draftStrings = {}
local draftColors = {}

local function splitKeypath(path)
    local parts = {}
    for segment in string.gmatch(path, '[^.]+') do
        parts[#parts + 1] = segment
    end
    return parts
end

local function getByKeypath(t, path)
    if type(t) ~= 'table' or type(path) ~= 'string' or path == '' then
        return nil
    end

    local node = t
    local parts = splitKeypath(path)
    for i = 1, #parts do
        if type(node) ~= 'table' then
            return nil
        end
        local key = tonumber(parts[i]) or parts[i]
        node = node[key]
        if node == nil then
            return nil
        end
    end

    return node
end

local function setByKeypath(t, path, value)
    if type(t) ~= 'table' or type(path) ~= 'string' or path == '' then
        return
    end

    local node = t
    local parts = splitKeypath(path)
    for i = 1, #parts - 1 do
        local key = tonumber(parts[i]) or parts[i]
        if type(node[key]) ~= 'table' then
            return
        end
        node = node[key]
    end

    local leaf = tonumber(parts[#parts]) or parts[#parts]
    node[leaf] = value
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t or EMPTY_TABLE) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function isColorString(value)
    return type(value) == 'string'
        and (value:match('^#%x%x%x%x%x%x%x%x$') ~= nil or value:match('^#%x%x%x%x%x%x$') ~= nil)
end

local function isCoordArray(value)
    if type(value) ~= 'table' or value[1] == nil then
        return false
    end

    local len = #value
    if len < 2 or len > 4 then
        return false
    end

    for key, entry in pairs(value) do
        if type(entry) ~= 'number' or type(key) ~= 'number' then
            return false
        end
    end

    return true
end

local function inferType(key, value)
    if value == nil or type(value) == 'function' or SKIP_KEYS[key] then
        return 'skip'
    end

    local valueType = type(value)
    if valueType == 'boolean' then
        return 'bool'
    end
    if valueType == 'number' then
        return 'number'
    end
    if isColorString(value) then
        return 'color'
    end
    if valueType == 'string' then
        return 'string'
    end
    if valueType ~= 'table' then
        return 'skip'
    end
    if isCoordArray(value) then
        return 'coord'
    end
    if type(value[1]) == 'table' then
        return 'skip'
    end
    return 'node'
end

local function partitionNodeKeys(t)
    local propertyKeys = {}
    local nodeKeys = {}
    local keys = sortedKeys(t)

    for i = 1, #keys do
        local key = keys[i]
        local tag = inferType(tostring(key), t[key])
        if tag ~= 'skip' then
            if tag == 'node' then
                nodeKeys[#nodeKeys + 1] = key
            else
                propertyKeys[#propertyKeys + 1] = key
            end
        end
    end

    return propertyKeys, nodeKeys
end

local function colorToFloats(hexStr)
    local rgba = spuiUtils:colorFromHex(hexStr)
    if not rgba then
        return { 1.0, 1.0, 1.0, 1.0 }
    end

    return {
        (rgba.r or 255) / 255.0,
        (rgba.g or 255) / 255.0,
        (rgba.b or 255) / 255.0,
        (rgba.a or 255) / 255.0,
    }
end

local function floatsToHex(floats)
    local r = math.max(0, math.min(255, math.floor((floats[1] or 0) * 255 + 0.5)))
    local g = math.max(0, math.min(255, math.floor((floats[2] or 0) * 255 + 0.5)))
    local b = math.max(0, math.min(255, math.floor((floats[3] or 0) * 255 + 0.5)))
    local a = math.max(0, math.min(255, math.floor((floats[4] or 1) * 255 + 0.5)))
    return string.format('#%02X%02X%02X%02X', r, g, b, a)
end

local function valuesEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= 'table' then
        return a == b
    end

    for key, value in pairs(a) do
        if not valuesEqual(value, b[key]) then
            return false
        end
    end
    for key, value in pairs(b) do
        if not valuesEqual(value, a[key]) then
            return false
        end
    end
    return true
end

local function currentOverrides()
    if not reg or not reg.getOverrides then
        return EMPTY_TABLE
    end
    return reg.getOverrides() or EMPTY_TABLE
end

local function getInputStartX()
    return BASE_INPUT_START_X
end

local function drawLabel(text, isOverridden)
    local rowStartX = imgui.GetCursorPosX()
    local inputStartX = getInputStartX()
    local textWidth = imgui.CalcTextSize(text)
    local labelX = inputStartX - LABEL_GAP - textWidth
    if labelX < rowStartX then
        labelX = rowStartX
    end
    imgui.SetCursorPosX(labelX)

    if isOverridden then
        imgui.PushStyleColor(ImGuiCol_Text, HIGHLIGHT_COLOR)
        imgui.Text(text)
        imgui.PopStyleColor(1)
    else
        imgui.Text(text)
    end

    imgui.SameLine(inputStartX)
end

local function commitOverride(path, value)
    if not reg then
        return
    end

    local baseValue = getByKeypath(cachedBase, path)
    if valuesEqual(baseValue, value) then
        reg.deleteOverride(path)
    else
        reg.setOverride(path, value)
    end

    draftNumbers[path] = nil
    draftCoords[path] = nil
    draftStrings[path] = nil
    draftColors[path] = nil
end

local function deleteDraft(path)
    draftNumbers[path] = nil
    draftCoords[path] = nil
    draftStrings[path] = nil
    draftColors[path] = nil
end

local function hasCoordOverride(path, value)
    local overrides = currentOverrides()
    for i = 1, #value do
        if overrides[path .. '.' .. i] ~= nil then
            return true
        end
    end
    return false
end

local function drawNumberWidget(path, key, value)
    local draft = draftNumbers[path]
    if draft == nil then
        draft = { value }
        draftNumbers[path] = draft
    end

    local isOverridden = currentOverrides()[path] ~= nil
    drawLabel(key, isOverridden)
    imgui.SetNextItemWidth(78)
    imgui.DragFloat('##' .. path, draft, 0.5, 0, 0, '%.1f')
    if imgui.IsItemDeactivatedAfterEdit() then
        commitOverride(path, draft[1])
    elseif not imgui.IsItemActive() and value ~= draft[1] and currentOverrides()[path] == nil then
        draft[1] = value
    end
    imgui.SameLine()
    if imgui.SmallButton('Reset##' .. path) then
        reg.deleteOverride(path)
        deleteDraft(path)
    end
end

local function drawBoolWidget(path, key, value)
    local boolValue = { value == true }
    local isOverridden = currentOverrides()[path] ~= nil
    drawLabel(key, isOverridden)
    if imgui.Checkbox('##' .. path, boolValue) then
        commitOverride(path, boolValue[1])
    end
    imgui.SameLine()
    if imgui.SmallButton('Reset##' .. path) then
        reg.deleteOverride(path)
    end
end

local function drawStringWidget(path, key, value)
    local draft = draftStrings[path]
    if draft == nil then
        draft = { tostring(value or '') }
        draftStrings[path] = draft
    end

    local isOverridden = currentOverrides()[path] ~= nil
    drawLabel(key, isOverridden)
    imgui.SetNextItemWidth(120)
    imgui.InputText('##' .. path, draft, 128)
    if imgui.IsItemDeactivatedAfterEdit() then
        commitOverride(path, draft[1])
    elseif not imgui.IsItemActive() and draft[1] ~= tostring(value or '') and currentOverrides()[path] == nil then
        draft[1] = tostring(value or '')
    end
    imgui.SameLine()
    if imgui.SmallButton('Reset##' .. path) then
        reg.deleteOverride(path)
        deleteDraft(path)
    end
end

local function drawColorWidget(path, key, value)
    local draft = draftColors[path]
    if draft == nil then
        draft = colorToFloats(value)
        draftColors[path] = draft
    end

    local isOverridden = currentOverrides()[path] ~= nil
    drawLabel(key, isOverridden)
    if imgui.ColorEdit4('##' .. path, draft, bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs)) then
        draftColors[path] = draft
    end
    if imgui.IsItemDeactivatedAfterEdit() then
        commitOverride(path, floatsToHex(draft))
    elseif not imgui.IsItemActive() and currentOverrides()[path] == nil and not valuesEqual(draft, colorToFloats(value)) then
        draftColors[path] = colorToFloats(value)
        draft = draftColors[path]
    end
    imgui.SameLine()
    imgui.Text(floatsToHex(draft))
    imgui.SameLine()
    if imgui.SmallButton('Reset##' .. path) then
        reg.deleteOverride(path)
        deleteDraft(path)
    end
end

local function drawCoordWidget(path, key, value)
    local draft = draftCoords[path]
    if draft == nil then
        draft = {}
        for i = 1, #value do
            draft[i] = value[i]
        end
        draftCoords[path] = draft
    end

    local isOverridden = hasCoordOverride(path, value)
    drawLabel(key, isOverridden)

    for i = 1, #value do
        if i > 1 then
            imgui.SameLine()
        end
        imgui.SetNextItemWidth(52)
        local label = (i == 1 and 'X' or i == 2 and 'Y' or i == 3 and 'Z' or 'W') .. '##' .. path .. '.' .. i
        local component = { draft[i] }
        if imgui.DragFloat(label, component, 1.0, 0, 0, '%.1f') then
            draft[i] = component[1]
        end
        if imgui.IsItemDeactivatedAfterEdit() then
            commitOverride(path .. '.' .. i, draft[i])
            draftCoords[path] = nil
            return
        end
    end

    if not isOverridden then
        for i = 1, #draft do
            draft[i] = value[i]
        end
    end

    imgui.SameLine()
    if imgui.SmallButton('Reset##' .. path) then
        for i = 1, #value do
            reg.deleteOverride(path .. '.' .. i)
        end
        deleteDraft(path)
    end
end

local function drawNode(path, key, value, depth)
    local tag = inferType(key, value)
    if tag == 'skip' then
        return
    end

    if tag == 'node' then
        if imgui.TreeNode(key) then
            local propertyKeys, nodeKeys = partitionNodeKeys(value)
            for i = 1, #propertyKeys do
                local childKey = propertyKeys[i]
                local childPath = (path == '' and tostring(childKey)) or (path .. '.' .. tostring(childKey))
                drawNode(childPath, tostring(childKey), value[childKey], depth + 1)
            end
            for i = 1, #nodeKeys do
                local childKey = nodeKeys[i]
                local childPath = (path == '' and tostring(childKey)) or (path .. '.' .. tostring(childKey))
                drawNode(childPath, tostring(childKey), value[childKey], depth + 1)
            end
            imgui.TreePop()
        end
        return
    end

    if tag == 'coord' then
        drawCoordWidget(path, key, value)
    elseif tag == 'color' then
        drawColorWidget(path, key, value)
    elseif tag == 'number' then
        drawNumberWidget(path, key, value)
    elseif tag == 'string' then
        drawStringWidget(path, key, value)
    elseif tag == 'bool' then
        drawBoolWidget(path, key, value)
    end
end

local function measureNodeWidth(key, value, depth)
    local tag = inferType(key, value)
    if tag == 'skip' then
        return 0
    end

    local labelWidth = 120 + (depth * 18)
    if tag == 'node' then
        local widest = labelWidth
        local propertyKeys, nodeKeys = partitionNodeKeys(value)
        for i = 1, #propertyKeys do
            local childKey = propertyKeys[i]
            local childWidth = measureNodeWidth(tostring(childKey), value[childKey], depth + 1)
            if childWidth > widest then
                widest = childWidth
            end
        end
        for i = 1, #nodeKeys do
            local childKey = nodeKeys[i]
            local childWidth = measureNodeWidth(tostring(childKey), value[childKey], depth + 1)
            if childWidth > widest then
                widest = childWidth
            end
        end
        return widest
    end

    if tag == 'coord' then
        return labelWidth + 230
    end
    if tag == 'color' then
        return labelWidth + 270
    end
    if tag == 'string' then
        return labelWidth + 190
    end
    if tag == 'number' or tag == 'bool' then
        return labelWidth + 150
    end

    return labelWidth + 140
end

function M.register(opts)
    reg = opts
    cachedBase = opts.getBase and opts.getBase() or nil
    cachedWidth = nil
    draftNumbers = {}
    draftCoords = {}
    draftStrings = {}
    draftColors = {}
end

function M.isRegistered()
    return reg ~= nil
end

function M.applyOverrides(layout, overrides)
    if type(layout) ~= 'table' or type(overrides) ~= 'table' then
        return layout
    end

    cachedWidth = nil
    for path, value in pairs(overrides) do
        setByKeypath(layout, path, value)
    end
    return layout
end

function M.draw()
    if not reg then
        imgui.TextDisabled('Layout editor not initialized.')
        return
    end

    local overrides = currentOverrides()
    local hasOverrides = next(overrides) ~= nil
    if imgui.Button('Reset All Overrides') and hasOverrides then
        reg.clearOverrides()
        draftNumbers = {}
        draftCoords = {}
        draftStrings = {}
        draftColors = {}
    end

    if not hasOverrides then
        imgui.SameLine()
        imgui.TextDisabled('No active overrides for this style.')
    end

    imgui.Separator()

    local layout = reg.getLayout and reg.getLayout()
    if type(layout) ~= 'table' then
        imgui.TextDisabled('No layout loaded.')
        return
    end

    local keys = sortedKeys(layout)
    for i = 1, #keys do
        local key = keys[i]
        drawNode(tostring(key), tostring(key), layout[key], 0)
    end
end

function M.getSuggestedWidth()
    if cachedWidth then return cachedWidth end

    if not reg or not reg.getLayout then
        return 320
    end

    local layout = reg.getLayout()
    if type(layout) ~= 'table' then
        return 320
    end

    local widest = 320
    local keys = sortedKeys(layout)
    for i = 1, #keys do
        local key = keys[i]
        local width = measureNodeWidth(tostring(key), layout[key], 0)
        if width > widest then
            widest = width
        end
    end

    widest = widest + 36
    if widest < 320 then widest = 320
    elseif widest > 560 then widest = 560
    end

    cachedWidth = widest
    return cachedWidth
end

return M
