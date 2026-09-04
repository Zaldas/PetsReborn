--[[
    spui/uiText.lua
    Wraps gdifonts.include font object as a uiElement.
    Font rendering is handled automatically by gdifonts' own d3d_present callback.
]]

local classes   = require('libs/spui/classes')
local uiElement = require('libs/spui/uiElement')
local utils     = require('libs/spui/utils')

local gdi = require('libs/gdifonts/include')

local uiText = classes.class(uiElement)
local private = {}

-- Alignment constants matching gdifonts
local ALIGN_LEFT   = 0
local ALIGN_CENTER = 1
local ALIGN_RIGHT  = 2

local ALIGN_MAP = { left = ALIGN_LEFT, none = ALIGN_LEFT, center = ALIGN_CENTER, right = ALIGN_RIGHT }

local function resolveAlign(layout)
    if layout and layout.align then
        return ALIGN_MAP[layout.align] or ALIGN_LEFT
    elseif layout and layout.alignRight then
        return ALIGN_RIGHT   -- backwards compat
    end
    return ALIGN_LEFT
end

-- FontFlags bitmask: bold=1, italic=2, underline=4, strikeout=8
-- bold defaults true to preserve existing behaviour for all layouts that don't specify it.
local function resolveFontFlags(layout)
    local bold      = layout and layout.bold or false
    local italic    = layout and layout.italic    or false
    local underline = layout and layout.underline or false
    local strikeout = layout and layout.strikeout or false
    return (bold and 1 or 0) + (italic and 2 or 0) + (underline and 4 or 0) + (strikeout and 8 or 0)
end

-- Gradient style: number passthrough or named string (matches gdifonts Gradient enum).
local GRADIENT_MAP = {
    none                   = 0,
    leftToRight            = 1,
    topLeftToBottomRight   = 2,
    topToBottom            = 3,
    topRightToBottomLeft   = 4,
    rightToLeft            = 5,
    bottomRightToTopLeft   = 6,
    bottomToTop            = 7,
    bottomLeftToTopRight   = 8,
}

local function resolveGradientStyle(layout)
    if not layout or layout.gradientStyle == nil then return 0 end
    if type(layout.gradientStyle) == 'number' then return layout.gradientStyle end
    return GRADIENT_MAP[layout.gradientStyle] or 0
end

local function toGdiColor(c)
    -- gdifonts uses 0xAARRGGBB format
    return tonumber(string.format('%02x%02x%02x%02x', c.a, c.r, c.g, c.b), 16)
end

function uiText:init(layout)
    if self.super:init(layout) then
        private[self] = {}
        private[self].text          = ''
        private[self].fontFamily    = (layout and layout.font) or 'Arial'
        private[self].fontSize      = (layout and layout.size) or 12
        private[self].align         = resolveAlign(layout)
        private[self].strokeWidth   = (layout and layout.strokeWidth) or 2
        private[self].fontFlags     = resolveFontFlags(layout)
        private[self].gradientStyle = resolveGradientStyle(layout)
        private[self].opacity       = (layout and layout.opacity) or 1.0

        local c = layout and layout.color and utils:colorFromHex(layout.color)
        private[self].color = c or { r = 255, g = 255, b = 255, a = 255 }

        -- :color() mutates the color table in place, so baseColor is a copy.
        local base = private[self].color
        private[self].baseColor = { r = base.r, g = base.g, b = base.b, a = base.a }

        local s = layout and layout.stroke and utils:colorFromHex(layout.stroke)
        private[self].stroke = s or { r = 0, g = 0, b = 0, a = 200 }

        local g = layout and layout.gradientColor and utils:colorFromHex(layout.gradientColor)
        private[self].gradientColor = g and toGdiColor(g) or 0x00000000
    end
end

function uiText:createPrimitives()
    if not self.isEnabled or self.isCreated then return end

    local c = private[self].color
    local s = private[self].stroke
    local settings = {
        font_family     = private[self].fontFamily,
        font_height     = private[self].fontSize,
        font_color      = toGdiColor(c),
        font_flags      = private[self].fontFlags,
        outline_color   = toGdiColor(s),
        outline_width   = private[self].strokeWidth or 2,
        font_alignment  = private[self].align,
        opacity         = private[self].opacity,
        gradient_color  = private[self].gradientColor,
        gradient_style  = private[self].gradientStyle,
        position_x      = 0,
        position_y      = 0,
        visible         = false,
        text            = '',
    }
    self.fontObj = gdi:create_object(settings, false)

    self.super:createPrimitives()
end

function uiText:applyLayout()
    if not self.isEnabled or not self.isCreated or not self.fontObj then return end

    self.fontObj:set_position_x(self.absolutePos.x)
    self.fontObj:set_position_y(self.absolutePos.y)
    self.fontObj:set_visible(self.absoluteVisibility)
    self.fontObj:set_font_height(private[self].fontSize * self.absoluteScale.y)
end

function uiText:update(text)
    if not self.isEnabled then return end

    if text ~= nil and private[self].text ~= text then
        private[self].text = text
        if self.isCreated and self.fontObj then
            self.fontObj:set_text(text or '')
        end
    end
end

-- The layout's declared color. Returned by reference; callers must not mutate it.
function uiText:baseColor()
    if not private[self] then return nil end
    return private[self].baseColor
end

-- Sets text color from a color table {r,g,b,a} or individual r,g,b values
function uiText:color(r, g, b)
    if not self.isEnabled then return end

    local a = nil
    if type(r) == 'table' and r.r and r.g and r.b then
        a = r.a or private[self].color.a; b = r.b; g = r.g; r = r.r
    end
    if not r then return end

    if private[self].color.r ~= r or private[self].color.g ~= g or private[self].color.b ~= b then
        private[self].color.r = r
        private[self].color.g = g
        private[self].color.b = b
        if self.isCreated and self.fontObj then
            self.fontObj:set_font_color(toGdiColor(private[self].color))
        end
    end

    if a then self:alpha(a) end
end

function uiText:alpha(a)
    if not self.isEnabled or not a then return end

    if private[self].color.a ~= a then
        private[self].color.a = a
        if self.isCreated and self.fontObj then
            self.fontObj:set_font_color(toGdiColor(private[self].color))
        end
    end
end

function uiText:opacity(v)
    if not self.isEnabled or not v then return end

    if private[self].opacity ~= v then
        private[self].opacity = v
        if self.isCreated and self.fontObj then
            self.fontObj:set_opacity(v)
        end
    end
end

function uiText:dispose()
    if not self.isEnabled then return end

    if self.isCreated and self.fontObj then
        gdi:destroy_object(self.fontObj)
        self.fontObj = nil
    end
    private[self] = nil

    self.super:dispose()
end

return uiText
