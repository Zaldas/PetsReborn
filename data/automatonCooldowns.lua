-- data/automatonCooldowns.lua
-- The automaton's internal cooldowns: the magic gates the controller enforces between casts,
-- and the recasts the attachment abilities apply to themselves.
--
-- Magic is a two level gate: a global one advanced by any cast, plus a per-category floor.
-- Individual spells carry no recast of their own, so a spell is gated only by its category.
--
-- Every gate is filtered behind the automaton's 3s decision tick, so a countdown here can
-- expire up to 3s before the automaton acts on it.
--
-- Trap: the magic gates are set by FRAME while their values come from HEAD. A magic head on a
-- Sharpshot or Valoredge frame never calls setMagicCooldowns, and the automaton then casts
-- nothing at all.
--
-- A nil category means the head has no such gate. Zero would mean instant; these are off.

local M = {}

-- frameItemId - 0x2000, which is the raw byte the 0x0044 packet carries.
M.FRAME_HARLEQUIN  = 0x20
M.FRAME_VALOREDGE  = 0x21
M.FRAME_SHARPSHOT  = 0x22
M.FRAME_STORMWAKER = 0x23

-- setMagicCooldowns is reached from these two frames only.
M.magicFrames = {
    [M.FRAME_HARLEQUIN]  = true,
    [M.FRAME_STORMWAKER] = true,
}

-- Keyed by headItemId - 0x2000, the raw byte the 0x0044 packet carries. A full transcription of
-- setMagicCooldowns, enhance included, so it can be diffed against LSB; M.display decides which
-- of these become rows.
--
-- Horizon measurements, 2026-08-25, from ~200 logged intervals:
--   Stormwaker magic      12.8, LSB 8   (57 intervals, 12.58-12.80)
--   Spiritreaver magic    12.8, LSB 8   (10 intervals, 12.81)
--   Spiritreaver elemental  35, LSB 30  (5 samples, 35.01-35.31)
-- Everything else is LSB's and unverified. Both measured heads are LSB 8, so a head LSB puts at
-- 10 measuring 12.8 would mean the gate is not per-head at all -- this table's shape would be
-- wrong, not just its numbers.
M.categories = {
    -- Harlequin
    [1] = { magic = 10, enfeeble = 12, heal = 12 },
    -- Valoredge
    [2] = { magic = 10, heal = 20 },
    -- Sharpshot
    [3] = { magic = 10, enfeeble = 12, heal = 20 },
    -- Stormwaker. elemental is bounded at >= 36.35 by priority starvation rather than measured:
    -- enfeeble outranks it on this head unless Ice is up.
    [4] = { magic = 12.8, enfeeble = 10, heal = 20, elemental = 25, enhance = 25 },
    -- Soulsoother
    [5] = { magic = 8, enfeeble = 10, heal = 10, status = 10, enhance = 25 },
    -- Spiritreaver
    [6] = { magic = 12.8, enfeeble = 10, elemental = 35, enhance = 35 },
}

M.CATEGORY_LABELS = {
    magic     = 'Latency',
    heal      = 'Heal',
    enfeeble  = 'Enfeeble',
    status    = 'Status',
    elemental = 'Elemental',
    enhance   = 'Enhance',
}

-- The rows each head shows, in the order TrySpellcast tries them with no maneuvers up and a
-- healthy target. A maneuver promotes a category past the ones above it, which this order does
-- not track. Latency leads throughout: it is the global gate and floors everything below it.
--
-- Enhance only casts a buff that is missing, so it idles at ready once the automaton is buffed.
-- It is last on Stormwaker but ahead of enfeeble on Soulsoother and Spiritreaver, so this is a
-- per-head order rather than one list with enhance appended.
--
-- Spiritreaver reaches enhance and enfeeble only with a Dark Maneuver up, enfeeble also below
-- 75% HP or MP, so on the no-maneuver baseline this head casts elementals alone. Both are
-- listed because the gates are real and do run.
--
-- A category a head has no gate for is simply absent here, and buildSlots drops any that slips
-- in without a duration -- so a head that cannot do something never produces the row, whatever
-- the settings say. Heal is on every head but Spiritreaver; enhance only on the last three.
M.display = {
    [1] = { 'magic', 'enfeeble', 'heal' },                            -- Harlequin
    [2] = { 'magic', 'heal' },                                        -- Valoredge
    [3] = { 'magic', 'enfeeble', 'heal' },                            -- Sharpshot
    [4] = { 'magic', 'enfeeble', 'heal', 'elemental', 'enhance' },    -- Stormwaker, the RDM head
    [5] = { 'magic', 'status', 'heal', 'enhance', 'enfeeble' },       -- Soulsoother, the WHM head
    [6] = { 'magic', 'elemental', 'enhance', 'enfeeble' },            -- Spiritreaver, the BLM head
}

-- Which gate a cast advances, on top of the global one. A spell absent here is not gated by
-- any category the automaton owns and is ignored.
M.spellCategory = {
    -- Cure I-VI
    [1] = 'heal', [2] = 'heal', [3] = 'heal',
    [4] = 'heal', [5] = 'heal', [6] = 'heal',

    -- The -na line and Erase, reached through FindNaSpell.
    [14] = 'status',  -- Poisona
    [15] = 'status',  -- Paralyna
    [16] = 'status',  -- Blindna
    [17] = 'status',  -- Silena
    [18] = 'status',  -- Stona
    [19] = 'status',  -- Viruna
    [20] = 'status',  -- Cursna
    [143] = 'status', -- Erase

    [23] = 'enfeeble',  -- Dia
    [24] = 'enfeeble',  -- Dia II
    [56] = 'enfeeble',  -- Slow
    [58] = 'enfeeble',  -- Paralyze
    [59] = 'enfeeble',  -- Silence
    [220] = 'enfeeble', -- Poison
    [221] = 'enfeeble', -- Poison II
    [230] = 'enfeeble', -- Bio
    [231] = 'enfeeble', -- Bio II
    [245] = 'enfeeble', -- Drain
    [247] = 'enfeeble', -- Aspir
    [248] = 'enfeeble', -- Aspir II
    [254] = 'enfeeble', -- Blind
    [260] = 'enfeeble', -- Dispel
    [270] = 'enfeeble', -- Absorb-INT
    [286] = 'enfeeble', -- Addle

    -- Protect I-V, Shell I-V
    [43] = 'enhance', [44] = 'enhance', [45] = 'enhance',
    [46] = 'enhance', [47] = 'enhance',
    [48] = 'enhance', [49] = 'enhance', [50] = 'enhance',
    [51] = 'enhance', [52] = 'enhance',
    [54] = 'enhance',  -- Stoneskin
    [57] = 'enhance',  -- Haste
    [106] = 'enhance', -- Phalanx
    [108] = 'enhance', -- Regen
    [110] = 'enhance', -- Regen II
    [111] = 'enhance', -- Regen III
    [129] = 'enhance', -- Protectra V
    [134] = 'enhance', -- Shellra V
    [277] = 'enhance', -- Dread Spikes
    [477] = 'enhance', -- Regen IV
    [511] = 'enhance', -- Haste II

    -- Fire, Blizzard, Aero, Stone, Thunder, Water, tiers I-V.
    -- TryElemental picks the tier from target HP and its own MP, so all five are reachable.
    [144] = 'elemental', [145] = 'elemental', [146] = 'elemental',
    [147] = 'elemental', [148] = 'elemental',
    [149] = 'elemental', [150] = 'elemental', [151] = 'elemental',
    [152] = 'elemental', [153] = 'elemental',
    [154] = 'elemental', [155] = 'elemental', [156] = 'elemental',
    [157] = 'elemental', [158] = 'elemental',
    [159] = 'elemental', [160] = 'elemental', [161] = 'elemental',
    [162] = 'elemental', [163] = 'elemental',
    [164] = 'elemental', [165] = 'elemental', [166] = 'elemental',
    [167] = 'elemental', [168] = 'elemental',
    [169] = 'elemental', [170] = 'elemental', [171] = 'elemental',
    [172] = 'elemental', [173] = 'elemental',
}

M.ATTACHMENT_ITEM_BASE = 0x2100

-- Attachment array length in the 0x0044 packet, and so the most attachment rows an automaton
-- can produce.
M.ATTACHMENT_SLOTS = 12

-- Attachment item id -> the ability it grants. Attachments encode as item =
-- ATTACHMENT_ITEM_BASE plus the byte in the 0x0044 attachment array (puppetutils.cpp:295).
--
-- Tiers sharing one ability share its recast and collapse to one row. skillId is what the
-- 0x0028 mob skill carries and what the timer is keyed on.
--
-- name is the attachment and is what rows display; label is the ability it casts, kept because
-- a bare skillId says nothing about what the row is timing.
--
-- effect is set only where the ability carries the attachment's own name, so naming it explains
-- nothing. Values are LSB's, from scripts/actions/abilities/pets/automaton/.
--
-- Every cooldown here is LSB's and unverified on Horizon.
M.attachmentAbilities = {
    [8449] = { skillId = 1945, name = 'Strobe',             label = 'Provoke',        cooldown =  30 },
    [8454] = { skillId = 2031, name = 'Reactive Shield',    label = 'Blaze Spikes',   cooldown =  60 },
    [8456] = { skillId = 2745, name = 'Heat Capacitor',     label = 'Heat Capacitor', cooldown =  90,
               effect = 'Grants 400 TP per Fire Maneuver up, and adds Fire burden for each.' },
    [8457] = { skillId = 1945, name = 'Strobe II',          label = 'Provoke',        cooldown =  30 },
    [8461] = { skillId = 2745, name = 'Heat Capacitor II',  label = 'Heat Capacitor', cooldown =  90 },
    [8519] = { skillId = 2132, name = 'Replicator',         label = 'Copy Image',     cooldown =  60 },
    [8520] = { skillId = 2746, name = 'Barrage Turbine',    label = 'Barrage',        cooldown = 180 },
    [8545] = { skillId = 1946, name = 'Shock Absorber',     label = 'Stoneskin',      cooldown = 180 },
    [8553] = { skillId = 1946, name = 'Shock Absorber II',  label = 'Stoneskin',      cooldown = 180 },
    [8557] = { skillId = 1946, name = 'Shock Absorber III', label = 'Stoneskin',      cooldown = 180 },
    [8642] = { skillId = 1947, name = 'Flashbulb',          label = 'Flash',          cooldown =  45 },
    [8645] = { skillId = 2021, name = 'Eraser',             label = 'Erase',          cooldown =  30 },
    [8674] = { skillId = 1948, name = 'Mana Converter',     label = 'Mana Converter', cooldown = 180,
               effect = 'Halves the automaton\'s HP and gives it back as Refresh over 30s.' },
    [8678] = { skillId = 2068, name = 'Economizer',         label = 'Economizer',     cooldown = 180,
               effect = 'Restores 20 percent of max MP per Dark Maneuver up, and adds Dark burden.\n' ..
                        'Waits until MP is below 30 percent, rising 10 per maneuver.' },
    [8680] = { skillId = 2747, name = 'Disruptor',          label = 'Dispel',         cooldown =  60 },
    [8682] = { skillId = 3485, name = 'Regulator',          label = 'Regulator',      cooldown =  60,
               effect = 'Absorbs one beneficial effect from the target.' },
}

return M
