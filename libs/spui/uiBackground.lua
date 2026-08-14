-- libs/spui/uiBackground.lua
-- Generic 3-slice background component (top cap, stretchable mid, bottom cap).
-- Extends uiContainer: the three images are proper children in the spui tree.
-- Visibility, position, and scale all cascade automatically through the tree.
--
-- Usage:
--   local bg = uiBackground.new(layout.background, engine)
--   bg.posX = 0; bg.posY = 0
--   parentContainer:addChild(bg)
--   bg:createPrimitives()
--   bg:hide(VIS_TOKEN)   -- hides all three slices together
--
-- setHeight(totalH): resizes the mid section and repositions the bottom cap.
-- layout.background must have: imgTop, imgMid, imgBottom each with pos and size fields.

local classes     = require('libs/spui/classes')
local uiContainer = require('libs/spui/uiContainer')
local uiImage     = require('libs/spui/uiImage')

local uiBackground = classes.class(uiContainer)

-- @param bgLayout  the background sub-table from the layout (imgTop/imgMid/imgBottom)
-- @param engine    sprite engine instance from sprites.newEngine()
function uiBackground:init(bgLayout, engine)
    if self.super:init(bgLayout) then
        self.topH    = bgLayout.imgTop.size[2]
        self.bottomH = bgLayout.imgBottom.size[2]
        self.midW    = bgLayout.imgMid.size[1]

        local imgTop = uiImage.new(bgLayout.imgTop, engine)
        imgTop.posX  = bgLayout.imgTop.pos[1]
        imgTop.posY  = bgLayout.imgTop.pos[2]
        self:addChild(imgTop)

        local imgMid = uiImage.new(bgLayout.imgMid, engine)
        imgMid.posX  = bgLayout.imgMid.pos[1]
        imgMid.posY  = bgLayout.imgMid.pos[2]
        self:addChild(imgMid)

        local imgBottom = uiImage.new(bgLayout.imgBottom, engine)
        imgBottom.posX  = bgLayout.imgBottom.pos[1]
        imgBottom.posY  = bgLayout.imgBottom.pos[2]
        self:addChild(imgBottom)

        self.imgTop    = imgTop
        self.imgMid    = imgMid
        self.imgBottom = imgBottom
    end
end

-- Override createPrimitives to drain VIS_INIT synchronously.
-- uiImage:setPath sets initFrames=2, requiring update() calls before the sprite shows.
-- By draining here we make uiBackground behave like uiText: no per-frame update() needed.
function uiBackground:createPrimitives()
    self.super:createPrimitives()
    for _ = 1, 3 do
        if self.imgTop    then self.imgTop:update()    end
        if self.imgMid    then self.imgMid:update()    end
        if self.imgBottom then self.imgBottom:update() end
    end
end

-- Resize the mid section and reposition the bottom cap.
-- totalH is in layout-space pixels (1440p baseline), matching the layout file units.
-- The parent root must have the correct absolutePos set before calling this.
function uiBackground:setHeight(totalH)
    if not self.imgMid or not self.isEnabled then return end
    local midH = math.max(1, totalH - self.topH - self.bottomH)
    self.imgMid:size(self.midW, midH)             -- size() triggers layoutElement() internally
    self.imgBottom.posY = totalH - self.bottomH
    self.imgBottom:layoutElement()
end

return uiBackground
