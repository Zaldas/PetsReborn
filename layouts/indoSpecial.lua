-- layouts/indoSpecial.lua
-- Hybrid layout: XIV-style backgrounds with FFXI-style bars and fonts, and the status effect
-- strip below the recast rows instead of beside the name.
-- Lists only what differs from layouts/ffxi.lua, which documents every key. Positions/sizes:
-- layout pixels at a 1440p baseline, as in ffxi.lua.

return {
    extends = 'ffxi',

    targetFrame = {
        pos = {0, 0},   -- flush against the pet frame's bottom edge
        background = {
            imgTop    = { path = 'layouts/assets/xiv/BgTop.png' },
            imgMid    = { path = 'layouts/assets/xiv/BgMid.png' },
            imgBottom = { path = 'layouts/assets/xiv/BgBottom.png' },
        },
    },

    petFrame = {
        background = {
            imgTop    = { path = 'layouts/assets/xiv/BgTop.png' },
            imgMid    = { path = 'layouts/assets/xiv/BgMid.png' },
            imgBottom = { path = 'layouts/assets/xiv/BgBottom.png' },
        },

        -- Status effect strip below all recast rows. 'recast.bottom' resolves to the recast
        -- block's bottom edge; the chain falls back when no pet type has built one.
        statusEffects = {
            anchor       = {'recast.bottom', 'tp', 'mp', 'hp', 'name'},
            pos          = {10, 4},
            marginBottom = 4,
        },

        recast = {
            charges = {
                pip = {
                    pos = {110, 4},
                },
            },
        },

        -- The panel follows the frame's XIV background art; the pip set stays under
        -- assets/ffxi/pips/.
        maneuvers = {
            -- background.pos[1] = -panelWidth - firstRowPos[1] (-59 + 20 = -39) puts the
            -- panel's right edge flush on the frame's left edge.
            firstRowPos = {-20, 5},
            background = {
                pos       = {-39, 0},
                imgTop    = { path = 'layouts/assets/xiv/BgTopMirror.png' },
                imgMid    = { path = 'layouts/assets/xiv/BgMidMirror.png' },
                imgBottom = { path = 'layouts/assets/xiv/BgBottomMirror.png' },
            },
        },
    },
}
