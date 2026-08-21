-- layouts/ffxi.lua
-- FFXI-style layout for PetsReborn.
-- Positions/sizes: D3D menu pixels, authored at ~768p internal (half of 1440p screen).
--
-- ANCHOR SYSTEM
-- anchor = 'elementName'        -- offset from that element's registered position
-- anchor = {'a', 'b', ...}     -- tries each in order; first registered wins
-- nil anchor: offset from window origin

return {
    targetFrame = {
        anchor = 'window.bottom',
        pos    = {0, 3},   -- offset from the anchor; y clears the pet frame's bottom edge
        height = 44,
        background = {
            imgTop = {
                path        = 'layouts/assets/ffxi/BgTop.png',
                size        = {190, 6},
                pos         = {0, 0},
                color       = '#FFFFFFBB',
                zOrder      = 0,
                sliceBorder = {60, 60, 0, 0},
            },
            imgMid = {
                path   = 'layouts/assets/ffxi/BgMid.png',
                size   = {190, 32},
                pos    = {0, 6},
                color  = '#FFFFFFBB',
                zOrder = 0,
            },
            imgBottom = {
                path        = 'layouts/assets/ffxi/BgBottom.png',
                size        = {190, 6},
                pos         = {0, 38},
                color       = '#FFFFFFBB',
                zOrder      = 0,
                sliceBorder = {60, 60, 0, 0},
            },
        },
        name = {
            pos = {9, 6},
            txt = {
                font        = 'Segoe UI',
                size        = 14,
                bold        = true,
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 2,
                pos         = {0, 0},
                zOrder      = 6,
                bind = {
                    value       = 'target.name',
                    visible    = 'target.active',
                    visibleAnd = 'ui.showTargetBar',
                },
            },
        },
        distance = {
            pos = {170, 38},
            txt = {
                font        = 'Grammara',
                size        = 12,
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 1,
                align       = 'right',
                pos         = {0, 0},
                zOrder      = 6,
                bind = {
                    value       = 'target.dist',
                    visible    = 'target.active',
                    visibleAnd = 'ui.showTargetBar',
                },
            },
        },
        hp = {
            pos = {5, 15},
            thresholds = {
                { below = 0.25, color = '#FC8182FF' },
                { below = 0.50, color = '#F3F37CFF' },
                { below = 0.75, color = '#F8BA80FF' },
            },
            bar = {
                pos       = {0, 0},
                zOrder    = 1,
                animSpeed = 0.2,
                imgBg  = { path = 'layouts/assets/ffxi/BarBG.png', size = {159,8},  pos = {3,2},  color = '#FF9597FF', sliceBorder = {60, 60, 6, 6},   zOrder = 1 },
                imgBar = { path = 'layouts/assets/ffxi/Bar.png',   size = {157,8},  pos = {4,2},  color = '#FF9597FF', zOrder = 2 },
                imgFg  = { path = 'layouts/assets/ffxi/BarFG.png', size = {165,14}, pos = {0,0},  color = '#FF9597FF', sliceBorder = {60, 60, 13, 13}, zOrder = 3 },
                bind = {
                    value      = 'target.hppNorm',
                    color      = 'threshold',
                    visible    = 'target.active',
                    visibleAnd = 'ui.showTargetBar',
                },
            },
            txt = {
                font        = 'Grammara',
                size        = 10,
                align       = 'right',
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 2,
                pos         = {157, 7},
                zOrder      = 6,
                bind = {
                    value         = 'target.hppPct',
                    color        = 'threshold',
                    colorValue   = 'target.hppNorm',
                    defaultColor = '#F0FFFFFF',
                    visible      = 'target.active',
                    visibleAnd   = 'ui.showTargetBar',
                },
            },
        },
    },

    petFrame = {
        baseWidth     = 185,
        marginBottom = 8,
        background = {
            imgTop = {
                path        = 'layouts/assets/ffxi/BgTop.png',
                size        = {190, 6},
                pos         = {0, 0},
                color       = '#FFFFFFDD',
                zOrder      = 0,
                sliceBorder = {60, 60, 0, 0},  -- texture pixels; not scaled
            },
            imgMid = {
                path   = 'layouts/assets/ffxi/BgMid.png',
                size   = {190, 18},  -- height grows based on content
                pos    = {0, 6},
                color  = '#FFFFFFDD',
                zOrder = 0,
            },
            imgBottom = {
                path        = 'layouts/assets/ffxi/BgBottom.png',
                size        = {190, 6},
                pos         = {0, 24},
                color       = '#FFFFFFDD',
                zOrder      = 0,
                sliceBorder = {60, 60, 0, 0},  -- texture pixels; not scaled
            },
        },

        name = {
            pos = {8, 12},
            marginBottom = 6,
            txt = {
                font        = 'Grammara',
                size        = 13,
                bold        = true,
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 2,
                pos         = {0, 0},
                zOrder      = 6,
                bind = {
                    value    = 'pet.name',
                    visible = 'pet.active',
                },
            },
        },

        distance = {
            pos = {170, -5},
            txt = {
                font        = 'Grammara',
                size        = 12,
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 1,
                align       = 'right',
                pos         = {0, 0},
                zOrder      = 6,
                bind = {
                    value    = 'pet.dist',
                    visible = 'pet.active',
                },
            },
        },

        -- anchor='name.y': downstream elements collapse to name origin when HP is hidden
        hp = {
            anchor = 'name.bottom',
            pos    = {0, 0},
            bind   = { visible = 'pet.active' },
            thresholds = {
                { below = 0.25, color = '#FC8182FF' },  -- <25%
                { below = 0.50, color = '#F3F37CFF' },  -- <50%
                { below = 0.75, color = '#F8BA80FF' },  -- <75%
            },
            bar = {
                pos       = {0, 0},
                zOrder    = 1,
                animSpeed = 0.2,
                imgBg  = { path = 'layouts/assets/ffxi/BarBG.png', size = {104,8},  pos = {3,2},  color = '#FF9597FF', sliceBorder = {60, 60, 6, 6},   zOrder = 1 },
                imgBar = { path = 'layouts/assets/ffxi/Bar.png',   size = {102,8},  pos = {4,2},  color = '#FF9597FF', zOrder = 2 },
                imgFg  = { path = 'layouts/assets/ffxi/BarFG.png', size = {110,14}, pos = {0,0},  color = '#FF9597FF', sliceBorder = {60, 60, 13, 13}, zOrder = 3 },
                bind = {
                    value      = 'pet.hppNorm',
                    color      = 'threshold',
                    visible    = 'pet.active',
                },
            },
            txt = {
                font        = 'Grammara',
                size        = 10,
                align       = 'right',
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 1,
                pos         = {105, -1},
                zOrder      = 6,
                bind = {
                    value         = 'pet.hpText',
                    color        = 'threshold',
                    colorValue   = 'pet.hppNorm',
                    defaultColor = '#F0FFFFFF',
                    visible      = 'pet.active',
                },
            },
        },

        -- avatar and automaton only; anchor falls back to name.y when mp absent
        mp = {
            anchor = {'hp', 'name.y'},
            pos    = {20, 10},
            bind   = { visible = 'pet.mppActive' },
            bar = {
                pos       = {0, 0},
                zOrder    = 1,
                animSpeed = 0.2,
                imgBg  = { path = 'layouts/assets/ffxi/BarBG.png', size = {104,8},  pos = {3,2},  color = '#FFFF9CFF', sliceBorder = {60, 60, 6, 6},   zOrder = 1 },
                imgBar = { path = 'layouts/assets/ffxi/Bar.png',   size = {102,8},  pos = {4,2},  color = '#FFFF9CFF', zOrder = 2 },
                imgFg  = { path = 'layouts/assets/ffxi/BarFG.png', size = {110,14}, pos = {0,0},  color = '#FFFF9CFF', sliceBorder = {60, 60, 13, 13}, zOrder = 3 },
                bind = {
                    value      = 'pet.mppNorm',
                    visible    = 'pet.mppActive',
                    visibleAnd = 'ui.showMpBar',
                },
            },
            txt = {
                font        = 'Grammara',
                size        = 10,
                align       = 'right',
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 1,
                pos         = {105, -1},
                zOrder      = 6,
                bind = {
                    value       = 'pet.mpText',
                    visible    = 'pet.mppActive',
                    visibleAnd = 'ui.showMpBar',
                },
            },
        },

        -- anchor resolves to mp (avatar/automaton) or hp (others)
        tp = {
            anchor = {'mp', 'hp', 'name.y'},
            pos    = {20, 10},
            bind   = { visible = 'pet.active' },
            bar = {
                pos       = {0, 0},
                zOrder    = 1,
                animSpeed = 0.2,
                imgBg  = { path = 'layouts/assets/ffxi/BarBG.png', size = {104,8},  pos = {3,2},  color = '#8EB4F9FF', sliceBorder = {60, 60, 6, 6},   zOrder = 1 },
                imgBar = { path = 'layouts/assets/ffxi/Bar.png',   size = {102,8},  pos = {4,2},  color = '#8EB4F9FF', zOrder = 2 },
                imgFg  = { path = 'layouts/assets/ffxi/BarFG.png', size = {110,14}, pos = {0,0},  color = '#8EB4F9FF', sliceBorder = {60, 60, 13, 13}, zOrder = 3 },
                bind = {
                    value      = 'pet.tpNorm',
                    visible    = 'pet.active',
                    visibleAnd = 'ui.showTpBar',
                },
                tpFullColor = '#50B4FAFF',
            },
            txt = {
                font        = 'Grammara',
                size        = 10,
                align       = 'right',
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 1,
                pos         = {105, -1},
                zOrder      = 6,
                bind = {
                    value       = 'pet.tpStr',
                    visible    = 'pet.active',
                    visibleAnd = 'ui.showTpBar',
                },
            },
        },

        -- 2hr/familiar countdown: BST familiar, SMN astral flow, DRG spirit surge, PUP overdrive.
        -- Also shows BST charm/jug duration when no 2hr is active.
        petTimer = {
            pos    = {15, -5},
            txt    = {
                font        = 'Grammara',
                size        = 12,
                color       = '#F0FFFFFF',
                stroke      = '#062D54C8',
                strokeWidth = 2,
                pos         = {0, 0},
                zOrder      = 6,
                bind = {
                    value    = 'pet.timer',
                    visible = 'pet.timerActive',
                },
            },
        },

        statusEffects = {
            anchor       = {'name.y'},
            maxIcons     = 10,
            iconSize     = 18,    -- layout pixels (1440p baseline)
            iconGap      = 2,
            pos          = { 140, 2 },
            marginBottom = 14,    -- includes timer label height
            bind = {
                visible    = 'pet.active',
                visibleAnd = 'pet.statusActive',
            },
            timer = {
                font        = 'Segoe UI',
                size        = 9,
                color       = '#FFFFFFFF',
                stroke      = '#000000C8',
                strokeWidth = 1,
                pos         = {0, 20},
            },
        },

        recast = {
            bind = {
                visible = 'ui.showRecasts',
            },
            anchor                = {'tp.y', 'mp.y', 'hp.y', 'name.y'},
            rowHeight             = 18,
            firstRowPos           = {0, 18},
            alwaysShowFirstRowPos = {0, 8},  -- alwaysShow: offset from window origin
            txt = {
                font        = 'Segoe UI',
                size        = 13,
                bold        = true,
                color       = '#C8C8C8FF',
                stroke      = '#062D5480',
                strokeWidth = 1,
                pos         = {60, 0},
                zOrder      = 6,
            },
            timer = {
                font        = 'Grammara',
                size        = 11,
                color       = '#F0FFFFFF',
                stroke      = '#062D5480',
                strokeWidth = 1,
                align       = 'right',
                pos         = {55, 5},
                zOrder      = 6,
                thresholds  = {
                    { below = 0.01, color = '#66FF66FF' },  -- ready
                    { below = 0.30, color = '#FFBB44FF' },  -- nearly ready
                },
            },
            labelOverrides = {
                ['Stay'] = { text = 'Healing' },
            },
            charges = {
                --[[
                txt = {
                    font        = 'Grammara',
                    size        = 9,
                    color       = '#A0C8FFFF',
                    stroke      = '#062D5480',
                    strokeWidth = 1,
                    align       = 'right',
                    pos         = {175, 2},
                    zOrder      = 6,
                },
                ]]
                pip = {
                    path       = 'layouts/assets/ffxi/Pip.png',
                    size       = {11, 11},
                    pos        = {110, 5},
                    offset     = {10, 0},
                    color      = '#A0C8FFFF',
                    colorEmpty = '#282848FF',
                    zOrder     = 5,
                },
            },
        },

        -- PUP maneuver column: 8 fixed element rows plus a shared-recast row, hanging off the
        -- LEFT edge of the frame. firstRowPos[1] is negative and the column renders outside
        -- the frame's own 190-wide background; the frame is not widened to cover it.
        --
        -- Row model, per element -- every pip the same size, filled in pipOffsets order:
        --              o
        --      38%   (o)   [frame        count 1 = (o) alone, 2 = + upper, 3 = all three
        --              o
        -- Pip 1 holds a fixed X and Y on every row, so the eight of them line up vertically.
        --
        -- Coordinate contract: origin O = resolved anchor + firstRowPos, which is row 1's
        -- origin; all row-local X below is relative to it.
        --   row origin of row i     -> O + (0, (i-1) * rowHeight)
        --   row i pip k             -> row i + pipOffsets[k]
        --   row i percentage        -> pctAlign-ed at row i + pipOffsets[1] + pctOffset
        --   shared recast text      -> O + recastTxt.pos
        --
        -- The `background` sub-table (imgTop/imgMid/imgBottom, same shape as
        -- petFrame.background) paints a panel behind the pip rows only; the recast row floats
        -- above it unpainted, as petTimer does over the frame's own background.
        --
        -- Sprites are white-scale: uiImage tints multiplicatively, so a coloured source can
        -- never reach the element hue.
        maneuvers = {
            bind = {
                visible    = 'pet.active',
                visibleAnd = 'ui.showManeuvers',
            },
            anchor      = {'name.y'},
            -- columnWidth sets the column's extent and the drag hit-rect. It does NOT set the
            -- panel width -- that is authored separately in background.imgTop/imgMid/imgBottom
            -- -- and it never resizes the frame background. It has to cover the widest string
            -- the column can produce ('~230%' at txt size 11).
            columnWidth = 72,
            -- firstRowPos[1] is the column's origin: pips, percentages, the recast row and the
            -- panel all derive from it, so it moves the whole column as a unit. -23 leaves a
            -- 3px gap between the panel's right edge and the frame.
            -- firstRowPos[2] lands the recast row (row 1's origin + recastTxt.pos[2]) on
            -- petTimer's line, so the two floating countdowns share a baseline across the
            -- frame's left edge.
            firstRowPos = {-23, 5},
            -- rowHeight is sized for legibility: eight size-11 percentages each need a
            -- readable band. Geometric floor is 14 -- the nearest pair is row i-1's pip 1
            -- against row i's upper pip, offset (-8, rowHeight - 8), and diamonds clear each
            -- other at |dx| + |dy| >= 14 (see pipOffsets).
            rowHeight   = 20,

            -- Panel behind the pip rows, from horizontally mirrored copies of the frame's own
            -- background art so the gradient fades away from the frame. Same 6px caps, same
            -- tint and zOrder as petFrame.background.
            --
            -- background.pos moves the whole panel; the three img pos values are offsets
            -- INSIDE it, as in petFrame.background. pos[1] = -panelWidth - firstRowPos[1]
            -- right-edges the panel on the column's own origin; changing an img width or
            -- firstRowPos[1] means re-deriving it.
            --
            -- The panel is narrower than columnWidth, and spui does not scissor text to it, so
            -- a percentage wider than the panel renders over the game world rather than clip.
            --
            -- No sliceBorder here, unlike petFrame.background's {60, 60, 0, 0}: border values
            -- are texture pixels scaled by destH/textureH (libs/spui/sprites.lua), so 60 + 60
            -- would reach 72px of border in a 64-wide element, collapsing the texture middle
            -- to zero and splitting the panel into two mismatched gradients.
            background = {
                pos = {-39, 0},
                imgTop = {
                    path   = 'layouts/assets/ffxi/BgTopMirror.png',
                    size   = {59, 6},
                    pos    = {0, 0},
                    color  = '#FFFFFFDD',
                    zOrder = 0,
                },
                imgMid = {
                    path   = 'layouts/assets/ffxi/BgMidMirror.png',
                    size   = {59, 18},  -- height grows to the pip rows' span
                    pos    = {0, 6},
                    color  = '#FFFFFFDD',
                    zOrder = 0,
                },
                imgBottom = {
                    path   = 'layouts/assets/ffxi/BgBottomMirror.png',
                    size   = {59, 6},
                    pos    = {0, 24},
                    color  = '#FFFFFFDD',
                    zOrder = 0,
                },
            },

            iconSize    = {16, 16},    -- {w, h} of every pip; feeds uiImage size directly
            iconZOrder  = 5,

            -- Pip N's {x, y} from the row origin, drawn in this order as the count climbs.
            -- maxPips is how many a row may draw; it is NOT the game's maneuver cap --
            -- data/maneuvers.lua MAX_ACTIVE states what the game permits, this states what the
            -- column has room for, and the two may differ.
            -- The art constrains the spacing: the -16 sprites are 16px boxes holding a diamond
            -- whose INK spans only 14px (1px pad on every side), so two pips touch without
            -- overlapping at |dx| + |dy| = 14. That is the hard floor -- anything tighter
            -- merges two filled same-coloured diamonds into one blob. Replacement art with a
            -- different ink span moves the limit.
            maxPips     = 3,
            pipOffsets  = {
                { 0,  0},   -- 1: main pip, the only one drawn at count 0 (as an outline)
                {-8, -8},   -- 2: upper left
                {-8,  8},   -- 3: lower left
            },

            -- Expiry warning. Once an element's soonest maneuver is at or below `threshold`
            -- seconds, that element's LAST-drawn pip -- the one that instance takes with it --
            -- pulses its alpha down to `alphaFloor` and back once every `period` seconds. Only
            -- that pip pulses; the rest of the row and the percentage hold full alpha.
            -- alphaFloor is a 0..1 MULTIPLIER on the element colour's own alpha, not a hex
            -- alpha, so a translucent palette dims proportionally instead of being overwritten.
            -- Omitting this whole sub-table turns the warning off; period must be positive.
            blink = {
                threshold  = 15,   -- seconds remaining at which the pulse starts
                alphaFloor = 0.3,  -- dimmest point of the cycle, as a fraction of authored alpha
                period     = 1,    -- seconds for one full 100% -> 30% -> 100% cycle
            },

            -- The -16 sources render 1:1 at uiScale 1.0 (1440p), so the 1px stroke stays
            -- crisp. At 4K (uiScale 1.5) they upscale; the -32 set is a path edit away.
            -- iconActive also draws pips 2+. The circle sprites in this directory are
            -- unreferenced by this layout.
            iconActive   = 'layouts/assets/ffxi/pips/diamondFill-16.png',  -- >=1 maneuver up, and every pip past 1
            iconResidual = 'layouts/assets/ffxi/pips/diamondLine-16.png',  -- 0 maneuvers up: outline, still element-coloured

            -- Diamond tint, indexed 1..8 in data/maneuvers.lua order: fire ice wind earth
            -- thunder water light dark. Applied in BOTH pip states and to every pip.
            elementColors = {
                '#F0603FFF',  -- 1 fire
                '#A6DCEEFF',  -- 2 ice
                '#6FD49AFF',  -- 3 wind
                '#D0A44FFF',  -- 4 earth
                '#BD8BF0FF',  -- 5 thunder
                '#5FA4EFFF',  -- 6 water
                '#F7EFC2FF',  -- 7 light
                '#8A72C4FF',  -- 8 dark
            },

            -- Percentage colour is by RISK, not by element. Keyed on pet.maneuver[N].norm,
            -- which is pct/100 clamped to 0..1, so `below = 0.40` is exactly "under 40%
            -- chance". There is no settings key for this ramp.
            -- The amber band is a final catch-all entry, not a `default` key:
            -- `thresholds.default` is a valid Utils.resolveThreshold input but makes this a
            -- mixed array/dictionary table, which selene rejects.
            thresholds = {
                { below = 0.40, color = '#F0E6C8FF' },  -- parchment: below the warn point
                { below = 1.01, color = '#FFAE32FF' },  -- amber: at or above it (norm is clamped 0..1)
            },

            -- Percentage placement, measured from PIP 1, not from the row origin: pairing
            -- {0, 0} with pctAlign 'center' centres the number on the main diamond.
            -- [1] clears pip 1, whose box starts at 0; re-authoring pipOffsets wider means
            -- re-deriving it from the new leftmost X.
            -- [2] = 0: no vertical adjustment; the line sits on pip 1's own top edge.
            -- pctAlign owns the alignment for this element, so txt.align is not read.
            -- gdifonts aligns AT the anchor and never clips, so nothing here is a clip rect:
            -- a three-digit value ('230%') simply runs further left. Overload chance
            -- reaches ~230 -- the server clamps at 255 -- which is what columnWidth is
            -- sized for.
            pctOffset = {-7, 0},
            pctAlign  = 'right',

            -- string.format pattern taking the integer chance. A pattern string.format
            -- rejects falls back to this value; it is validated once at create, never on
            -- the render path.
            pctFormat = '%d%%',

            -- Font only: position comes from pctOffset and alignment from pctAlign, so this
            -- block carries neither pos nor align.
            txt = {
                font        = 'Segoe UI',
                bold          = true,
                size        = 11,
                color       = '#F0FFFFFF',
                stroke      = '#062D5480',
                strokeWidth = 1,
                zOrder      = 6,
            },
            -- Shared recast row. pos[1] right-edges the timer flush with the pip column's
            -- right edge, clear of the panel's left edge. The row sits above the pips, sharing
            -- petFrame.petTimer's line.
            -- pos[2] also sets the column's top edge, so it is what the frame reserves height
            -- from -- keep it tight to the text.
            -- overloadColor replaces color while Overload is active, when the row counts down
            -- Overload instead of the maneuver recast. Matches overload.txt.color so the two
            -- read as one state.
            recastTxt = {
                font          = 'Grammara',
                size          = 12,
                color         = '#F0FFFFFF',   -- matches recast.timer, the ability-timer colour
                overloadColor = '#FF6B54FF',
                readyLabel    = 'Mnvr',
                stroke        = '#1A0508F0',
                strokeWidth   = 2,
                align         = 'right',
                pos           = {15, -22},
                zOrder        = 6,
            },
        },

        -- 2hr/familiar ability name label: shown below the window when a timer is active.
        special = {
            --anchor = 'window.bottom',
            pos    = {0, 0},
            txt    = {
                font          = 'Penumbra Serif Std',
                size          = 20,
                bold          = true,
                color         = '#F8F8FFFF',
                stroke        = '#2D3A80FF',
                strokeWidth   = 2,
                align         = 'center',
                gradientStyle = 'topToBottom',
                gradientColor = '#00072DFF',
                pos           = {90, -30},
                zOrder        = 6,
                bind = {
                    value    = 'pet.specialName',
                    visible = 'pet.specialActive',
                },
            },
        },

        -- PUP Overload banner. A sibling of special, which is a single mutually-exclusive
        -- slot (Astral Flow / Spirit Surge / Overdrive / Familiar / charm / jug); Overload
        -- stays readable concurrently with Overdrive.
        --
        -- Two positions, one authored plus one offset:
        --   pos + txt.pos is the 2h slot and MUST stay equal to special's pos + txt.pos,
        --     where Overload renders with no 2h text showing. Both elements have a nil
        --     anchor and resolve from the same base, so moving special without moving this
        --     makes the two silently drift apart.
        --   raisedOffset is added on top only while pet.specialActive, lifting Overload one
        --     line clear so the two stack instead of overlapping. Optional: absent means
        --     Overload never leaves the 2h slot. It moves the text only -- section extras
        --     (img/bg) are positioned once at create time and never repositioned, so an
        --     authored overload.bg would stay behind in the 2h slot.
        --
        -- Label only. The countdown lives in the maneuver strip's shared recast row, which
        -- shows pet.overloadTimer while Overload is up.
        -- No pet.active term in the bind: Overload outlives the automaton, and data.lua
        -- zeroes overloadOn off-PUP so this can never fire for a non-PUP.
        overload = {
            pos          = {0, 0},
            raisedOffset = {0, -22},
            txt    = {
                font          = 'Penumbra Serif Std',
                size          = 20,
                bold          = true,
                color         = '#FF5A4BFF',
                stroke        = '#3A0505FF',
                strokeWidth   = 2,
                align         = 'center',
                gradientStyle = 'topToBottom',
                gradientColor = '#5A0000FF',
                pos           = {90, -30},  -- keep equal to special.txt.pos
                zOrder        = 6,
                bind = {
                    value    = 'pet.overloadLabel',
                    visible = 'pet.overloadActive',
                },
            },
        },
    },
}
