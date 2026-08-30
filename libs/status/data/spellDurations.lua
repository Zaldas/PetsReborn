-- PetsReborn: Spell durations (player and mob casters)
-- Maps spell ID → base duration in seconds.
-- Covers both buff spells (Protect, Shell, Haste, etc.) and debuff/enfeebling spells.
-- Source: LSB-server scripts/globals/spells/enhancing_spell.lua,
--         enhancing_ninjutsu.lua, enhancing_song.lua, enfeebling_spell.lua,
--         and individual spell scripts.
--
-- Duration = 0 means the effect is not time-based (shadow count, luopan-tied) — no timer shown.
-- Song durations are the no-instrument/no-JA base (120s); actual in-game values are
-- typically 240-288s with Troubadour. Timer will be conservative but functional.

return {

    -- ── Enfeebling / debuff spells ─────────────────────────────────────────
    -- Source: LSB enfeebling_spell.lua / enfeebling_song.lua
    -- Durations are base values (no instrument, JA, or merit bonuses).

    -- WHM / BLM enfeebling
    [58]  = 120, [80]  = 120, [356] = 120,  -- Paralyze / Paralyze II / Paralyga
    [56]  = 180, [79]  = 180, [357] = 180,  -- Slow / Slow II / Slowga
    [216] = 120, [217] = 180, [366] = 120,  -- Gravity / Gravity II / Graviga
    [254] = 180, [276] = 180, [361] = 180,  -- Blind / Blind II / Blindga
    [59]  = 120, [359] = 120,               -- Silence / Silencega
    [253] = 60,  [273] = 60,  [363] = 60,  -- Sleep / Sleepga / (legacy ID)
    [259] = 90,  [274] = 90,  [364] = 90,  -- Sleep II / Sleepga II / Sleepga III
    [258] = 60,  [362] = 60,               -- Bind / Bindga
    [252] = 5,                             -- Stun
    [98]  = 90,                            -- Repose (WHM sleep, applies Sleep I effect)
    [112] = 12,                            -- Flash (very short enmity/blind effect)
    [255] = 30, [365] = 30,               -- Break / Breakga (Petrification, 30s)
    [256] = 60,                            -- Virus (Plague/Disease, 60s)
    [220] = 90,  [221] = 120, [222] = 150, -- Poison / Poison II / Poison III
    [225] = 90,  [226] = 120, [227] = 150, -- Poisonga / Poisonga II / Poisonga III

    -- Elemental DoTs (base 90s; 120s with max Elemental Debuff Duration merits)
    [235] = 120, [236] = 120, [237] = 120, -- Burn / Frost / Choke
    [238] = 120, [239] = 120, [240] = 120, -- Rasp / Shock / Drown

    -- RDM / SCH enfeebling
    [841] = 120, [842] = 120, [882] = 120, -- Distract / II / III (Evasion Down)
    [843] = 120, [844] = 120, [883] = 120, -- Frazzle / II / III (Magic Eva Down)
    [286] = 180, [884] = 180,             -- Addle / Addle II (Magic Atk Down)

    -- Ninjutsu debuffs
    [341] = 180, [342] = 300, [343] = 420, -- Jubaku: Ichi / Ni / San (Paralyze)
    [344] = 180, [345] = 300, [346] = 420, -- Hojo:   Ichi / Ni / San (Slow)
    [347] = 180, [348] = 300, [349] = 420, -- Kurayami: Ichi / Ni / San (Blind)
    [350] = 60,  [351] = 120, [352] = 360, -- Dokumori: Ichi / Ni / San (Poison)
    [319] = 120,                           -- Aisha: Ichi (Attack Down)
    [508] = 180,                           -- Yurin: Ichi (Inhibit TP)

    -- Scholar Helix spells (base 30s + level bonus; 90s max at cap)
    [278] = 90,  [279] = 90,  [280] = 90,  [281] = 90,
    [282] = 90,  [283] = 90,  [284] = 90,  [285] = 90,  -- Helix I-VIII
    [885] = 90,  [886] = 90,  [887] = 90,  [888] = 90,
    [889] = 90,  [890] = 90,  [891] = 90,  [892] = 90,  -- Helix I-VIII (tier 2)

    -- Bard debuff songs (base no-instrument duration)
    -- Troubadour, Mad Minstrel, and instruments extend these significantly.
    [368] = 64,  [369] = 80,  [370] = 96,  [371] = 112,
    [372] = 128, [373] = 144, [374] = 160,             -- Foe Requiem I-VII
    [454] = 60,  [455] = 60,  [456] = 60,  [457] = 60,
    [458] = 60,  [459] = 60,  [460] = 60,  [461] = 60,  -- Threnody I-VIII
    [871] = 90,  [872] = 90,  [873] = 90,  [874] = 90,
    [875] = 90,  [876] = 90,  [877] = 90,  [878] = 90,  -- Threnody II I-VIII
    [421] = 120, [422] = 180, [423] = 240, -- Battlefield / Carnage / Massacre Elegy  (423 trust-only; LSB unimplemented, extrapolated)
    [376] = 30,  [463] = 30,              -- Horde Lullaby / Foe Lullaby
    [377] = 60,  [471] = 60,              -- Horde Lullaby II / Foe Lullaby II
    [472] = 120,                          -- Pining Nocturne
    [466] = 30,                           -- Maiden's Virelai → Charm (14); gear-boosted only, no song-duration bonus

    -- ── Haste ─────────────────────────────────────────────────────────────
    [57]  = 180,  -- Haste
    [511] = 180,  -- Haste II
    [358] = 180,  -- Hastega

    -- ── Protect / Protectra ───────────────────────────────────────────────
    [43]  = 1800, -- Protect
    [44]  = 1800, -- Protect II
    [45]  = 1800, -- Protect III
    [46]  = 1800, -- Protect IV
    [47]  = 1800, -- Protect V
    [125] = 1800, -- Protectra
    [126] = 1800, -- Protectra II
    [127] = 1800, -- Protectra III
    [128] = 1800, -- Protectra IV
    [129] = 1800, -- Protectra V

    -- ── Shell / Shellra ───────────────────────────────────────────────────
    [48]  = 1800, -- Shell
    [49]  = 1800, -- Shell II
    [50]  = 1800, -- Shell III
    [51]  = 1800, -- Shell IV
    [52]  = 1800, -- Shell V
    [130] = 1800, -- Shellra
    [131] = 1800, -- Shellra II
    [132] = 1800, -- Shellra III
    [133] = 1800, -- Shellra IV
    [134] = 1800, -- Shellra V

    -- ── Regen ─────────────────────────────────────────────────────────────
    [108] = 75,   -- Regen
    [110] = 60,   -- Regen II
    [111] = 60,   -- Regen III
    [477] = 60,   -- Regen IV
    [504] = 60,   -- Regen V

    -- ── Refresh ───────────────────────────────────────────────────────────
    [109] = 150,  -- Refresh
    [473] = 150,  -- Refresh II
    [894] = 150,  -- Refresh III

    -- ── Stoneskin / Blink / Aquaveil ──────────────────────────────────────
    [54]  = 300,  -- Stoneskin
    [53]  = 300,  -- Blink
    [55]  = 600,  -- Aquaveil

    -- ── Phalanx ───────────────────────────────────────────────────────────
    [106] = 180,  -- Phalanx
    [107] = 240,  -- Phalanx II

    -- ── Reraise ───────────────────────────────────────────────────────────
    [135] = 3600, -- Reraise
    [141] = 3600, -- Reraise II
    [142] = 3600, -- Reraise III
    [848] = 3600, -- Reraise IV

    -- ── Bar-element (single target) ───────────────────────────────────────
    [60]  = 480,  -- Barfire
    [61]  = 480,  -- Barblizzard
    [62]  = 480,  -- Baraero
    [63]  = 480,  -- Barstone
    [64]  = 480,  -- Barthunder
    [65]  = 480,  -- Barwater
    [66]  = 480,  -- Barfira
    [67]  = 480,  -- Barblizzara
    [68]  = 480,  -- Baraera
    [69]  = 480,  -- Barstonra
    [70]  = 480,  -- Barthundra
    [71]  = 480,  -- Barwatera

    -- ── Bar-status ────────────────────────────────────────────────────────
    [72]  = 480,  -- Barsleep
    [73]  = 480,  -- Barpoison
    [74]  = 480,  -- Barparalyze
    [75]  = 480,  -- Barblind
    [76]  = 480,  -- Barsilence
    [77]  = 480,  -- Barpetrify
    [78]  = 480,  -- Barvirus
    [84]  = 480,  -- Baramnesia
    [85]  = 480,  -- Baramnesra
    [86]  = 480,  -- Barsleepra
    [87]  = 480,  -- Barpoisonra
    [88]  = 480,  -- Barparalyzra
    [89]  = 480,  -- Barblindra
    [90]  = 480,  -- Barsilencera
    [91]  = 480,  -- Barpetra
    [92]  = 480,  -- Barvira

    -- ── Invisible / Sneak / Deodorize ─────────────────────────────────────
    -- Base 420s; server adds up to 120s random jitter. Using floor value.
    [136] = 420,  -- Invisible
    [137] = 420,  -- Sneak
    [138] = 420,  -- Deodorize

    -- ── En-spells ─────────────────────────────────────────────────────────
    [100] = 180,  -- Enfire
    [101] = 180,  -- Enblizzard
    [102] = 180,  -- Enaero
    [103] = 180,  -- Enstone
    [104] = 180,  -- Enthunder
    [105] = 180,  -- Enwater
    [312] = 180,  -- Enfire II
    [313] = 180,  -- Enblizzard II
    [314] = 180,  -- Enaero II
    [315] = 180,  -- Enstone II
    [316] = 180,  -- Enthunder II
    [317] = 180,  -- Enwater II
    [310] = 180,  -- Enlight
    [311] = 180,  -- Endark

    -- ── Spikes ────────────────────────────────────────────────────────────
    [249] = 180,  -- Blaze Spikes
    [250] = 180,  -- Ice Spikes
    [251] = 180,  -- Shock Spikes
    [277] = 180,  -- Dread Spikes

    -- ── Storm spells ──────────────────────────────────────────────────────
    [99]  = 180,  -- Sandstorm
    [113] = 180,  -- Rainstorm
    [114] = 180,  -- Windstorm
    [115] = 180,  -- Firestorm
    [116] = 180,  -- Hailstorm
    [117] = 180,  -- Thunderstorm
    [118] = 180,  -- Voidstorm
    [119] = 180,  -- Aurorastorm

    -- ── Boost/Gain-stat ───────────────────────────────────────────────────
    [479] = 300,  -- Boost-STR
    [480] = 300,  -- Boost-DEX
    [481] = 300,  -- Boost-VIT
    [482] = 300,  -- Boost-AGI
    [483] = 300,  -- Boost-INT
    [484] = 300,  -- Boost-MND
    [485] = 300,  -- Boost-CHR
    [486] = 300,  -- Gain-STR
    [487] = 300,  -- Gain-DEX
    [488] = 300,  -- Gain-VIT
    [489] = 300,  -- Gain-AGI
    [490] = 300,  -- Gain-INT
    [491] = 300,  -- Gain-MND
    [492] = 300,  -- Gain-CHR

    -- ── Other white magic buffs ───────────────────────────────────────────
    [96]  = 180,  -- Auspice
    [97]  = 60,   -- Reprisal
    [476] = 300,  -- Crusade
    [478] = 90,   -- Embrava
    [493] = 180,  -- Temper
    [895] = 180,  -- Temper II
    [845] = 180,  -- Flurry
    [846] = 180,  -- Flurry II
    [840] = 30,   -- Foil

    -- ── Ninjutsu buffs ────────────────────────────────────────────────────
    -- Utsusemi: shadow count based, not time based — skip timer
    [338] = 0,    -- Utsusemi: Ichi
    [339] = 0,    -- Utsusemi: Ni
    [340] = 0,    -- Utsusemi: San
    [353] = 420,  -- Tonko: Ichi (Invisible)
    [354] = 600,  -- Tonko: Ni (Invisible)
    [318] = 420,  -- Monomi: Ichi (Sneak)
    [505] = 300,  -- Gekka: Ichi
    [509] = 180,  -- Kakka: Ichi
    [507] = 180,  -- Myoshu: Ichi
    [510] = 60,   -- Migawari: Ichi
    [506] = 300,  -- Yain: Ichi

    -- ── Bard songs (120s base, no instrument/Troubadour) ──────────────────
    [386] = 120,  -- Mage's Ballad
    [387] = 120,  -- Mage's Ballad II
    [388] = 120,  -- Mage's Ballad III
    [378] = 120,  -- Army's Paeon
    [379] = 120,  -- Army's Paeon II
    [380] = 120,  -- Army's Paeon III
    [381] = 120,  -- Army's Paeon IV
    [382] = 120,  -- Army's Paeon V
    [383] = 120,  -- Army's Paeon VI
    [389] = 120,  -- Knight's Minne
    [390] = 120,  -- Knight's Minne II
    [391] = 120,  -- Knight's Minne III
    [392] = 120,  -- Knight's Minne IV
    [393] = 120,  -- Knight's Minne V
    [394] = 120,  -- Valor Minuet
    [395] = 120,  -- Valor Minuet II
    [396] = 120,  -- Valor Minuet III
    [397] = 120,  -- Valor Minuet IV
    [398] = 120,  -- Valor Minuet V
    [399] = 120,  -- Sword Madrigal
    [400] = 120,  -- Blade Madrigal
    [401] = 120,  -- Hunter's Prelude
    [402] = 120,  -- Archer's Prelude
    [403] = 120,  -- Sheepfoe Mambo
    [404] = 120,  -- Dragonfoe Mambo
    [419] = 120,  -- Advancing March
    [420] = 120,  -- Victory March
    [438] = 120,  -- Fire Carol
    [439] = 120,  -- Ice Carol
    [440] = 120,  -- Wind Carol
    [441] = 120,  -- Earth Carol
    [442] = 120,  -- Lightning Carol
    [443] = 120,  -- Water Carol
    [444] = 120,  -- Light Carol
    [445] = 120,  -- Dark Carol
    [424] = 120,  -- Sinewy Etude
    [425] = 120,  -- Dextrous Etude
    [426] = 120,  -- Vivacious Etude
    [427] = 120,  -- Quick Etude
    [428] = 120,  -- Learned Etude
    [429] = 120,  -- Spirited Etude
    [430] = 120,  -- Enchanting Etude
    [431] = 120,  -- Herculean Etude
    [432] = 120,  -- Uncanny Etude
    [433] = 120,  -- Vital Etude
    [434] = 120,  -- Swift Etude
    [435] = 120,  -- Sage Etude
    [436] = 120,  -- Logical Etude
    [437] = 120,  -- Bewitching Etude
    [405] = 120,  -- Fowl Aubade
    [412] = 120,  -- Gold Capriccio
    [415] = 120,  -- Goblin Gavotte
    [409] = 120,  -- Scops Operetta
    [410] = 120,  -- Puppet's Operetta
    [406] = 120,  -- Herb Pastoral
    [408] = 120,  -- Shining Fantasia
    [414] = 120,  -- Warding Round
    [464] = 120,  -- Goddess's Hymnus
    [470] = 120,  -- Sentinel's Scherzo
    [465] = 120,  -- Chocobo Mazurka
    [467] = 120,  -- Raptor Mazurka
    [468] = 120,  -- Foe Sirvente
    [469] = 120,  -- Adventurer's Dirge

    -- ── Geomancy (GEO job — not on HorizonXI era server, commented out) ──────
    -- Trust GEOs (e.g. T. Sovereign) do use Indi-spells; uncomment as seen in logs.
    -- [768] = 180,  -- Indi-Regen
    -- [770] = 180,  -- Indi-Refresh
    -- [771] = 180,  -- Indi-Haste
    -- [772] = 180,  -- Indi-STR
    -- [773] = 180,  -- Indi-DEX
    -- [774] = 180,  -- Indi-VIT
    -- [775] = 180,  -- Indi-AGI
    -- [776] = 180,  -- Indi-INT
    -- [777] = 180,  -- Indi-MND
    -- [778] = 180,  -- Indi-CHR
    -- [779] = 180,  -- Indi-Fury
    -- [780] = 180,  -- Indi-Barrier
    -- [781] = 180,  -- Indi-Acumen
    -- [782] = 180,  -- Indi-Fend
    -- [783] = 180,  -- Indi-Precision
    [784] = 180,  -- Indi-Voidance  (Trust GEO confirmed in logs; base 180s per geomancer.lua)
    -- [785] = 180,  -- Indi-Focus
    -- [786] = 180,  -- Indi-Attunement
    -- [798] = 0,    -- Geo-Regen
    -- [799] = 0,    -- Geo-Refresh
    -- [800] = 0,    -- Geo-Haste
    -- [801] = 0,    -- Geo-STR
    -- [802] = 0,    -- Geo-DEX
    -- [803] = 0,    -- Geo-VIT
    -- [804] = 0,    -- Geo-AGI
    -- [805] = 0,    -- Geo-INT
    -- [806] = 0,    -- Geo-MND
    -- [807] = 0,    -- Geo-CHR
    -- [808] = 0,    -- Geo-Fury
    -- [809] = 0,    -- Geo-Barrier
    -- [810] = 0,    -- Geo-Acumen
    -- [811] = 0,    -- Geo-Fend
    -- [812] = 0,    -- Geo-Precision
    -- [813] = 0,    -- Geo-Voidance
    -- [814] = 0,    -- Geo-Focus
    -- [815] = 0,    -- Geo-Attunement
    -- [816] = 0,    -- Geo-Wilt
    -- [817] = 0,    -- Geo-Frailty
    -- [818] = 0,    -- Geo-Fade
    -- [819] = 0,    -- Geo-Malaise
    -- [820] = 0,    -- Geo-Slip
    -- [821] = 0,    -- Geo-Torpor
    -- [822] = 0,    -- Geo-Vex
    -- [823] = 0,    -- Geo-Languor
    -- [824] = 0,    -- Geo-Slow
    -- [825] = 0,    -- Geo-Paralysis
    -- [826] = 0,    -- Geo-Gravity

    -- ── Monster abilities and pet blood pacts ─────────────────────────────
    -- Action types 7 (MobSkill), 11, and 13 (Pet) are not type-6 JAs, so they
    -- fall through to this table. IDs are network packet ability IDs.
    -- 2hr IDs sourced from LSB scripts/enum/job_special_ability.lua (xi.jsa.*).

    -- NM/mob 2-hour self-buffs (type 11 actions).
    -- These IDs are shared by ALL mobs using the job_special mixin — not mob-specific.
    -- Maat/Prishe/variant IDs for the same 2hr are grouped alongside the primary.
    [688] = 45,   -- MIGHTY_STRIKES         (statusId=44)
    [1008] = 45,  -- MIGHTY_STRIKES_MAAT
    [690] = 45,   -- HUNDRED_FISTS          (statusId=46)
    [1009] = 45,  -- HUNDRED_FISTS_MAAT
    [1485] = 45,  -- HUNDRED_FISTS_PRISHE
    [691] = 60,   -- MANAFONT               (statusId=47)
    [1011] = 60,  -- MANAFONT_MAAT
    [692] = 60,   -- CHAINSPELL             (statusId=48)
    [1012] = 60,  -- CHAINSPELL_MAAT
    [693] = 30,   -- PERFECT_DODGE          (statusId=49)
    [1013] = 30,  -- PERFECT_DODGE_MAAT
    [694] = 30,   -- INVINCIBLE             (statusId=50)
    [1014] = 30,  -- INVINCIBLE_MAAT
    [695] = 30,   -- BLOOD_WEAPON           (statusId=51)
    [1015] = 30,  -- BLOOD_WEAPON_MAAT
    [2249] = 30,  -- BLOOD_WEAPON_IXDRK
    [696] = 180,  -- SOUL_VOICE             (statusId=52)
    [1018] = 180, -- SOUL_VOICE_MAAT
    [730] = 30,   -- MEIKYO_SHISUI          (statusId=54)
    [1020] = 30,  -- MEIKYO_SHISUI_MAAT
    [734] = 30,   -- ASTRAL_FLOW            (statusId=55)
    [1023] = 30,  -- ASTRAL_FLOW_MAAT
    [1933] = 45,  -- AZURE_LORE             (statusId=163)

    -- ── Monster skills (type 7) — debuffs on players only ─────────────────────
    -- Mob SELF-buffs are handled by mob2h memory tracking (mobStatusDurations.lua).
    -- Only debuffs that land on party members need entries here.
    -- IDs = mob_skills.sql mob_skill_id.
    [805]  = 180, -- head_butt_turtle: ACCURACY_DOWN          (Adamantoise/KA, LSB: 120-180s random; use max)
    [957]  = 45,  -- absolute_terror: TERROR single target    (Fafnir/Nidhogg, LSB: 15-45s random; use max)
    [1220] = 60,  -- auroral_drape:  SILENCE on targets       (Weeper, LSB: 60s)
    [1238] = 60,  -- target_analysis: STAT_DOWN on targets    (Proto-Omega, LSB: 60s each)
    [1268] = 60,  -- nuclear_waste:  ELEMENTALRES_DOWN        (Ultima, LSB: 60s)
    [1269] = 120, -- chemical_bomb:  ELEGY+SLOW               (Ultima, LSB: 120s each)
    [1285] = 45,  -- absolute_terror: TERROR single target    (Tiamat, LSB: 15-45s random; use max)
    [1295] = 45,  -- absolute_terror: TERROR single target    (Vrtra, LSB: 15-45s random; use max)
    [1305] = 18,  -- absolute_terror: TERROR AoE              (Vrtra, LSB: 10-18s random; use max)
    [1315] = 45,  -- absolute_terror: TERROR single target    (Jormungand, LSB: 15-45s random; use max)
    [1521] = 45,  -- armor_buster:   WEIGHT on targets        (Ultima, LSB: 45s)
    [1536] = 60,  -- target_analysis: STAT_DOWN on targets    (Omega, LSB: 60s each)
    [1548] = 45,  -- absolute_terror: TERROR                  (Bahamut, LSB: 15-45s random; use max)

    -- ── Blood Pacts (type 13 Pet actions) ────────────────────────────────────
    -- Durations from LSB scripts/actions/abilities/pets/*.lua
    -- Skill-based formula: duration = base + clamp(summoning_skill - 300, 0, 200)
    -- At era 75 cap (~275 skill), bonusTime = 0 — base duration is accurate for most players.

    -- Carbuncle
    [514] = 180,  -- Shining Ruby:    SHINING_RUBY to party  (LSB: 180 + skill bonus)
    [515] = 90,   -- Glittering Ruby: stat boost to party    (LSB: 90s fixed)

    -- Titan
    [564] = 900,  -- Earthen Ward:    STONESKIN to party     (LSB: 900s fixed)

    -- Garuda
    [596] = 900,  -- Aerial Armor:    BLINK to party         (LSB: 900s fixed)
    [548] = 60,   -- Crimson Howl:    WARCRY to party        (LSB: base 60s)
    [595] = 180,  -- Hastega:         HASTE to party         (LSB: base 180s)
    [602] = 180,  -- Hastega II:      HASTE to party         (LSB: base 180s)

    -- Shiva
    [610] = 180,  -- Frost Armor:     ICE_SPIKES to party    (LSB: base 180s)

    -- Ramuh
    [628] = 180,  -- Lightning Armor: SHOCK_SPIKES to party  (LSB: base 180s)
    [626] = 120,  -- Rolling Thunder: ENTHUNDER to party     (LSB: base 120s)

    -- Fenrir
    [532] = 180,  -- Ecliptic Growl:  all stat boosts        (LSB: base 180s)
    [533] = 180,  -- Ecliptic Howl:   ACC+EVA boost          (LSB: base 180s)
    [660] = 180,  -- Noctoshield:     PHALANX to party       (LSB: base 180s)

    -- Diabolos
    [661] = 180,  -- Dream Shroud:    MAB+MDB to party       (LSB: base 180s)

    -- Leviathan
    [579] = 180,  -- Spring Water:    REFRESH to party       (observed in logs, statusId=43)
    [586] = 180,  -- Soothing Current: CURING_CONDUIT        (LSB: 180s fixed)

    -- Phoenix
    [526] = 3600, -- Reraise II:      RERAISE to party       (LSB: 3600s = 1 hour)

    -- Alexander (Perfect Defense — self-only, ~30-45s at era skill cap)
    [671] = 45,   -- Perfect Defense: PERFECT_DEFENSE        (LSB: 30 + skill/20)

    -- ── Blood Pact debuffs on enemies ─────────────────────────────────────────
    [513] = 60,   -- Poison Nails:    POISON     (LSB: 60s)
    [522] = 90,   -- Mewing Lullaby:  SLEEP_I    (LSB: 90s * resist)
    [523] = 30,   -- Eerie Eye:       SILENCE+AMNESIA (LSB: 30s * resist)
    [528] = 30,   -- Moonlit Charge:  BLINDNESS  (LSB: 30s)
    [529] = 90,   -- Crescent Fang:   PARALYSIS  (LSB: 90s)
    [530] = 180,  -- Lunar Cry:       ACC_DOWN+EVA_DOWN (LSB: 180s)
    [567] = 3,    -- Geocrush:        STUN       (LSB: 3s)
    [578] = 120,  -- Tail Whip:       WEIGHT     (LSB: 120s * resist)
    [580] = 180,  -- Slowga:          SLOW       (LSB: 180s + mod, cap 350)
    [585] = 60,   -- Tidal Roar:      ATTACK_DOWN (LSB: 60s)
    [611] = 90,   -- Sleepga:         SLEEP_I    (LSB: 90s * resist)
    [627] = 60,   -- Thunderspark:    PARALYSIS  (LSB: 60s)
    [657] = 120,  -- Somnolence:      WEIGHT     (LSB: 120s * resist)
    [658] = 90,   -- Nightmare:       SLEEP_I+BIO (LSB: 90s * resist)
}
