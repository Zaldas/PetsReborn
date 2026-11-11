-- layouts/xiv.lua
-- XIV-style layout for PetsReborn: the ffxi layout with XIV background, bar and pip art.
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
        hp = {
            bar = {
                imgBg  = { path = 'layouts/assets/xiv/BarBG.png', color = '#FFFFFFFF' },
                imgBar = { path = 'layouts/assets/xiv/Bar.png',   color = '#FFFFFFFF' },
                imgFg  = { path = 'layouts/assets/xiv/BarFG.png', color = '#FFFFFFFF' },
            },
        },
    },

    petFrame = {
        background = {
            imgTop    = { path = 'layouts/assets/xiv/BgTop.png' },
            imgMid    = { path = 'layouts/assets/xiv/BgMid.png' },
            imgBottom = { path = 'layouts/assets/xiv/BgBottom.png' },
        },

        -- Frames keep a neutral tint; the fill colour lives on imgBar alone.
        hp = {
            bar = {
                imgBg  = { path = 'layouts/assets/xiv/BarBG.png', color = '#F0FFFFFF' },
                imgBar = { path = 'layouts/assets/xiv/Bar.png',   color = '#FFE3E8' },
                imgFg  = { path = 'layouts/assets/xiv/BarFG.png', color = '#F0FFFFFF' },
            },
        },
        mp = {
            bar = {
                imgBg  = { path = 'layouts/assets/xiv/BarBG.png', color = '#F0FFFFFF' },
                imgBar = { path = 'layouts/assets/xiv/Bar.png',   color = '#FFEE99' },
                imgFg  = { path = 'layouts/assets/xiv/BarFG.png', color = '#F0FFFFFF' },
            },
        },
        tp = {
            bar = {
                imgBg  = { path = 'layouts/assets/xiv/BarBG.png', color = '#F0FFFFFF' },
                imgBar = { path = 'layouts/assets/xiv/Bar.png',   color = '#DFF3FF' },
                imgFg  = { path = 'layouts/assets/xiv/BarFG.png', color = '#F0FFFFFF' },
            },
        },

        recast = {
            charges = {
                pip = {
                    path   = 'layouts/assets/xiv/pip.png',
                    size   = {20, 20},
                    pos    = {110, 0},
                    offset = {14, 0},
                },
            },
        },

        -- The pip set stays under assets/ffxi/pips/: it is untextured geometry, with no
        -- XIV-specific variant.
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
