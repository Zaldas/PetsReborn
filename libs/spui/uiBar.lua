--[[
    Copyright © 2023, Tylas
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

        * Redistributions of source code must retain the above copyright
          notice, this list of conditions and the following disclaimer.
        * Redistributions in binary form must reproduce the above copyright
          notice, this list of conditions and the following disclaimer in the
          documentation and/or other materials provided with the distribution.
        * Neither the name of XivParty nor the
          names of its contributors may be used to endorse or promote products
          derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

local classes = require('libs/spui/classes')
local uiContainer = require('libs/spui/uiContainer')
local uiImage = require('libs/spui/uiImage')
local utils = require('libs/spui/utils')

local uiBar = classes.class(uiContainer)

-- @param layout layout table defining this bar element
-- @param engine sprite engine instance from sprites.newEngine()
-- @param value initial bar value 0..1
function uiBar:init(layout, engine, value)
    if self.super:init(layout) then
        self.layout = layout
        self.engine = engine

        if not value then value = 0 end
        self.value = value
        self.exactValue = value
        self.currentValue = nil

        self.animSpeed = (self.layout.animSpeed and self.layout.animSpeed > 0) and self.layout.animSpeed or 1

        self.imgBg = nil
        self.imgBar = nil
        self.imgFg = nil

        if layout.imgBg then
            self.imgBg = self:addChild(uiImage.new(layout.imgBg, engine))
        end
        if layout.imgBar then
            self.imgBar = self:addChild(uiImage.new(layout.imgBar, engine))
        end
        if layout.imgFg then
            self.imgFg = self:addChild(uiImage.new(layout.imgFg, engine))
        end

        self.sizeBar = layout.imgBar and utils:coord(layout.imgBar.size) or { x = 0, y = 0 }

        self.imgBgColor  = layout.imgBg  and utils:colorFromHex(layout.imgBg.color)  or nil
        self.imgBarColor = layout.imgBar and utils:colorFromHex(layout.imgBar.color) or nil
        self.imgFgColor  = layout.imgFg  and utils:colorFromHex(layout.imgFg.color)  or nil
    end
end

function uiBar:setValue(value)
    self.value = math.min(math.max(value, 0), 1)
end

-- sets the color of the bar image
-- @param color the color table (rgba) to set or nil to restore original color
function uiBar:setColor(color)
    if not self.isEnabled or not self.imgBar then return end

    if not color then color = self.imgBarColor end
    if color then
        self.imgBar:color(color)
    end
end

-- must be called every frame for a smooth animation
function uiBar:update()
    if not self.isEnabled then return end

    if self.currentValue ~= self.value then
        self.exactValue = self.exactValue + (self.value - self.exactValue) * self.animSpeed
        self.exactValue = math.min(math.max(self.exactValue, 0), 1)
        self.currentValue = utils:round(self.exactValue, 3)

        if self.imgBar then
            self.imgBar:size(self.sizeBar.x * self.currentValue, self.sizeBar.y)
        end
    end

    -- Signal to parent container whether this bar needs to keep running next frame.
    self._isAnimating = self.alwaysUpdate or (self.currentValue ~= self.value)

    self.super:update()
end

-- overrides the color of a named bar child element; nil restores the layout default color
-- valid names: 'imgBg', 'imgBar', 'imgFg'
function uiBar:setElementColor(name, color)
    if not self.isEnabled then return end
    if name == 'imgFg' and self.imgFg then
        self.imgFg:color(color or self.imgFgColor)
    elseif name == 'imgBg' and self.imgBg then
        self.imgBg:color(color or self.imgBgColor)
    elseif name == 'imgBar' and self.imgBar then
        self.imgBar:color(color or self.imgBarColor)
    end
end

function uiBar:opacity(o)
    if not self.isEnabled or not self.imgBar then return end

    self.imgBar:opacity(o)
end

return uiBar
