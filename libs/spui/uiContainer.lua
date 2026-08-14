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
local uiElement = require('libs/spui/uiElement')
local utils = require('libs/spui/utils')

local uiContainer = classes.class(uiElement)

-- @param layout optional: layout table defining this UI element
-- @return true if the UI element is enabled
function uiContainer:init(layout)
    self.super:init(layout)

    self.children = {}
    self._anyChildAnimating = false

    return self.isEnabled
end

-- disposes and removes all children
function uiContainer:dispose()
    if not self.isEnabled then return end

    self:clearChildren(true)

    self.super:dispose()
end

-- adds a child UI element
-- @param child UI element derived from uiElement
-- @return the added child element
function uiContainer:addChild(child)
    if not self.isEnabled then return end

    if not child:instanceOf(uiElement) then
        utils:print('Failed to add UI child. Class must derive from uiElement!', 4)
        return nil
    end

    table.insert(self.children, child)
    child.parent = self

    child:layoutElement()
    if self.isCreated then
        child:createPrimitives()
    end

    return child
end

-- removes a child UI element
-- @param child UI element that has been added using addChild() before
function uiContainer:removeChild(child)
    if not self.isEnabled then return end

    local found = false
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            found = true
            break
        end
    end

    if not found then return end

    child.parent = nil
    child:layoutElement()
end

-- removes all child UI elements
-- @param dispose when true, children are also disposed
function uiContainer:clearChildren(dispose)
    if not self.isEnabled then return end

    for _, child in ipairs(self.children) do
        child.parent = nil

        if dispose then
            child:dispose()
        else
            child:layoutElement()
        end
    end

    self.children = {}
end

-- creates the windower primitives of all child UI elements in their z-order
function uiContainer:createPrimitives()
    if not self.isEnabled then return end

    -- sort children by z-order ascending
    table.sort(self.children, function(a, b) return a.zOrder < b.zOrder end)

    for _, child in ipairs(self.children) do
        child:createPrimitives()
    end

    self.super:createPrimitives()
end

-- calculates the element's and its children's absolute position and scale based on its parent
function uiContainer:layoutElement()
    if not self.isEnabled then return end

    self.super:layoutElement()

    for _, child in ipairs(self.children) do
        child:layoutElement()
    end
end

function uiContainer:update()
    if not self.isEnabled then return end

    self.super:update()

    self._anyChildAnimating = false
    for _, child in ipairs(self.children) do
        child:update()
        if child._isAnimating or child._anyChildAnimating then
            self._anyChildAnimating = true
        end
    end
end

return uiContainer
