-- PetsReborn: Mob status durations
--
-- Tracks status effects that land ON the pet — both self-buffs the pet applies
-- to itself and debuffs mobs apply to the pet. Does NOT include target-bar data
-- (effects on the enemy target).
--
-- selfBuffs: keyed by STATUS EFFECT ID (buff ID)
--   Used when the pet is both actor and target (pet self-buff path).
--   Durations sourced from LSB-server mobskill scripts.
--
-- skillDebuffs: keyed by MOB SKILL ID (0x028 action packet Param field)
--   Used by statustracker.lua for type 7/11 mob actions targeting the pet.
--   These IDs overlap with player spell IDs in the 280-700 range —
--   MUST NOT be added to spellDurations.lua.

local selfBuffs = {

    -- ── 2-Hour abilities ───────────────────────────────────────────────────
    [44]  = 45,   -- Mighty Strikes  (WAR 2hr)
    [46]  = 45,   -- Hundred Fists   (MNK 2hr)
    [47]  = 60,   -- Manafont        (BLM 2hr)
    [48]  = 60,   -- Chainspell      (RDM 2hr)
    [49]  = 30,   -- Perfect Dodge   (THF 2hr)
    [50]  = 30,   -- Invincible      (PLD 2hr)
    [51]  = 30,   -- Blood Weapon    (DRK 2hr)
    [52]  = 180,  -- Soul Voice      (BRD 2hr)
    [54]  = 30,   -- Meikyo Shisui   (SAM 2hr)
    [55]  = 30,   -- Astral Flow     (SMN 2hr)
    [126] = 30,   -- Spirit Surge    (DRG 2hr)
    [163] = 45,   -- Azure Lore      (BLU 2hr)  [azure_lore.lua: 45]
    [283] = 30,   -- Perfect Defense (special boss ability; e.g. Absolute Virtue)

    -- ── Offensive self-buffs ───────────────────────────────────────────────
    [45]  = { default=60, [1377]=5, [580]=180 },    -- Boost  [quake_stomp 1746/1899: 60 (default); fluorescence 1377: 5; fantod 580: 180]
    [56]  = 180,  -- Berserk         [berserk/rage: 120, berserk_bomb_big/boiling_blood: 180 — max]
    [57]  = 180,  -- Defender        [mob defensive stance: 180]
    [61]  = { default=60, [1331]=300 },             -- Counterstance  [bionic_boost 359/orcish 2201: 60 (default); counterstance 1331: 300]
    [62]  = 180,  -- Sentinel        [mob tankstance; some HNM abilities: 180]
    [68]  = 180,  -- Warcry          [berserk_doll: 120, crimson_howl/howl/rinpyotosha/berserk_volker: 180 (mode)]

    -- ── Defensive self-buffs ──────────────────────────────────────────────
    [36]  = 180,  -- Blink           [aerial_armor/zephyr_mantle: 180, dukkeripen/heavy_armature: 120 — max]
    [37]  = 300,  -- Stoneskin       [diamondhide/metallic_body/magma_hoplon/shiko: 300 (mode), earthen_ward/frozen_mist/hydro_wave: 180]
    [39]  = 180,  -- Aquaveil        [hydro_wave/water_veil: 180]
    [40]  = 300,  -- Protect         [crystal_shield/mix_guard_drink/royal_savior: 300 (mode), crystaline_cocoon/heavy_armature: 120/180]
    [41]  = 180,  -- Shell           [bubble_armor/bubble_curtain/unblessed_armor: 180 (mode)]
    [66]  = 300,  -- Copy Image      [occultation: 300] — Utsusemi shadow copies
    [116] = 120,  -- Phalanx         [noctoshield: 120]

    -- ── Damage absorb shields ─────────────────────────────────────────────
    [150] = 30,   -- Physical Shield [transmogrification: 30 (most common NM), energy_screen: 60, psychoanima: 10]
    [151] = 60,   -- Arrow Shield    [airy_shield: 60]
    [152] = { default=60, [471]=30, [522]=45, [1806]=300, [1505]=0 },
                  -- Magic Shield  [mind_wall 471: 30; spectral_barrier 522: 45 (midpoint 30-60); arcane_stomp 1806: 300; bastion_of_twilight 1505: 0 (permanent→skip); rest: 60 (default)]
    [153] = 180,  -- Damage Spikes   [damage_spikes mob ability: 180]
    [437] = 30,   -- Mana Wall       [mana_wall mob ability (certain HNMs/avatars): 30]

    -- ── Spikes ────────────────────────────────────────────────────────────
    [34]  = 180,  -- Blaze Spikes    [flame_armor/heat_barrier/magma_hoplon: 180]
    [35]  = 180,  -- Ice Spikes      [frost_armor: 180, reactor_cool: 120 — max]
    [38]  = { default=180, [1239]=60, [1537]=60 },  -- Shock Spikes  [reactive_armor/shield/lightning_armor: 180; discharger(Omega) 1239/1537: 60]
    [173] = 180,  -- Dread Spikes    [Barbaric_Weapon Whirl_of_Rage: 180 (Xarcabard/WOTG NM)]
    [573] = 180,  -- Deluge Spikes   [water elemental/aquan mobs: 180]
    [605] = 180,  -- Gale Spikes     [wind elemental/amorph mobs: 180]
    [606] = 180,  -- Clod Spikes     [earth elemental/arcana mobs: 180]

    -- ── En-spells (elemental weapon coat) ─────────────────────────────────
    [94]  = 30,   -- Enfire          [fire_blade: 30; heat_barrier outlier: 300]
    [95]  = 30,   -- Enblizzard      [frost_blade: 30]
    [96]  = 30,   -- Enaero          [wind_blade_kam: 30]
    [97]  = 30,   -- Enstone         [earth_blade: 30]
    [98]  = 30,   -- Enthunder       [lightning_blade: 30]
    [99]  = 30,   -- Enwater         [water_blade: 30]
    [288] = 30,   -- Endark          [dark_blade/dark_weapon: 30]
    [274] = 30,   -- Enlight         [light_weapon: 30]

    -- ── Regen / Refresh / Regain ──────────────────────────────────────────
    [42]  = 120,  -- Regen    [rapid_molt: 30, mix_life_water: 60, photosynthesis: 120, healing_stomp: 180, regeneration: 300 — no mode, 120 midpoint]
    [43]  = 198,  -- Refresh  [battery_charge: 198]
    [170] = 60,   -- Regain   [summer_breeze: 60]

    -- ── Magic power boosts ─────────────────────────────────────────────────
    [190] = 300,  -- Magic Atk Boost [frog_cheer/memento_mori: 300 (mode); amplification: 120; Immortal_mind: 180; mix_elemental_power: 60]
    [191] = 60,   -- Magic Def Boost [mix_dragon_shield/saline_coat: 60 (mode); barrier_tusk: 90; amplification: 120; Immortal_mind: 180]

    -- ── Haste ──────────────────────────────────────────────────────────────
    [33]  = 180,  -- Haste    [boiling_blood/erratic_flutter/heavy_armature/refueling: 180 (mode)]

    -- ── Stat boosts ────────────────────────────────────────────────────────
    [80]  = 180,  -- STR Boost  [mob stat-up abilities: 180]
    [81]  = 180,  -- DEX Boost
    [82]  = 180,  -- VIT Boost
    [83]  = 180,  -- AGI Boost
    [84]  = 180,  -- INT Boost
    [85]  = 180,  -- MND Boost
    [86]  = 180,  -- CHR Boost

    -- ── Evasion / Accuracy / Defense boosts ───────────────────────────────
    [90]  = 180,  -- Accuracy Boost   [mob acc-up: 180]
    [91]  = 180,  -- Attack Boost     [mob atk-up: 180]
    [92]  = { default=180, [784]=15, [454]=30, [815]=60, [496]=60, [373]=60, [1734]=60, [1924]=60, [793]=120 },
                  -- Evasion Boost  [sigh 784: 15; water_shield 454: 30; wind_wall 815/rabid_dance 496/secretion 373/warm-up 1734+1924: 60; sand_veil 793: 120; material_fend/mirage/hard_membrane/rhino_guard/feather_barrier: 180 (default)]
    [93]  = { default=180, [391]=60, [1351]=60, [445]=60, [453]=60 },
                  -- Defense Boost  [aura_of_persistence 391/molluscous_mutation 1351/scissor_guard 445/water_wall 453: 60; rest: 180 (default)]

    -- ── NM / Boss-specific ────────────────────────────────────────────────
    [127] = 300,  -- Costume         [some NMs disguise as another mob type: 300]
    [169] = 120,  -- Potency         [potency boost used by certain caster NMs: 120]
    [432] = 30,   -- Multi Strikes   [multi-hit buff from certain NMs: 30]
    [436] = 30,   -- Perfect Counter  [counter-stance variant on certain mobs: 30]
    [460] = 60,   -- Blood Rage      [certain DRK-type HNMs: 60]
    [461] = 60,   -- Impetus         [MNK-type HNMs: 60]
    [500] = 30,   -- Overkill        [rare boss buff granting massive damage bonus: 30]
}

-- Resolve self-buff duration. Pass abilityId for exact per-skill lookup (event-driven path);
-- omit or pass nil for modal fallback (mob2h polling path, statusId only).
-- Returns: >0 = duration in seconds, 0 = known permanent (skip tracking), nil = not in selfBuffs.
local function getSelfBuffDuration(statusId, abilityId)
    local entry = selfBuffs[statusId]
    if entry == nil then return nil end
    if type(entry) == 'table' then
        return (abilityId and entry[abilityId]) or entry.default
    end
    return entry
end

return {
    selfBuffs           = selfBuffs,
    getSelfBuffDuration = getSelfBuffDuration,

    skillDebuffs = {

        -- ── Ahriman (Dynamis Vanguard Eye) ────────────────────────────────────
        [551] = 10,   -- Mind Break     → MAX_MP_DOWN (145)     fixed 10s [mind_break.lua]
        [552] = 45,   -- Binding Wave   → BIND (11)             TP-scaled 30-60s; midpoint 45
        [557] = 30,   -- Level 5 Petrify → PETRIFICATION (7)    TP-scaled 15-60s; use low end (often resisted)
        [438] = 120,  -- Hex Eye        → PARALYSIS (4)         TP-scaled 0-120s; max [hex_eye.lua]

        -- ── Dhalmel ───────────────────────────────────────────────────────────
        [284] = 60,   -- Cold Stare      → SILENCE (6)           fixed 60s [cold_stare.lua] (Troglodyte Dhalmel)

        -- ── Imp ───────────────────────────────────────────────────────────────
        [1709] = 60,  -- Abrasive Tantara  → AMNESIA (16)        fixed 60s [abrasive_tantara.lua] (Tracker Imp)
        [1710] = 30,  -- Deafening Tantara → SILENCE (6)         fixed 30s [deafening_tantara.lua] (Tracker Imp)

        -- ── Goblin (Salvage) ──────────────────────────────────────────────────
        [1115] = 30,  -- Torpid Glare   → SLEEP_I (2)           fixed 30s [torpid_glare.lua]  (Goblin Replica)

        -- ── Doll / Golem (Abyssea) ────────────────────────────────────────────
        [541]  = 420, -- Gravity Field  → SLOW (13)             random 240-420s; max [gravity_field.lua]

        -- ── Kindred (Dynamis K. Paladin / K. Thief / K. Monk) ─────────────────
        [531] = 60,   -- Silence Seal   → SILENCE (6)           fixed 60s [silence_seal.lua]
        [563] = 240,  -- Demonic Howl   → SLOW (13)             fixed 240s per demonic_howl.lua

        -- ── Icon Prototype (Dynamis-Tavnazia / Xarcabard) ─────────────────────
        [1117] = 300, -- Lead Breath    → WEIGHT (12)           fixed 300s [lead_breath.lua]

        -- ── Diabolos (Dreams / Dynamis) ───────────────────────────────────────
        [558] = 30,   -- Nightmare      → SLEEP_I (2)           random 20-30s; max [nightmare.lua]

        -- ── Coeurl ────────────────────────────────────────────────────────────
        [653]  = 60,  -- Chaotic Eye    → SILENCE (6)           fixed 60s [chaotic_eye.lua]

        -- ── Manticore (Valley of Sorrows) ─────────────────────────────────────
        [801]  = 60,  -- Riddle         → MAX_MP_DOWN (145)     fixed 60s [riddle.lua]

        -- ── Aw'euvhi (ToAU) ───────────────────────────────────────────────────
        [1450] = 120, -- Viscid Nectar  → SLOW (13)             fixed 120s [viscid_nectar.lua]
        [1452] = 60,  -- Axial Bloom    → BIND (11)             random 30-60s; max [axial_bloom.lua]

        -- ── Proto-Omega (Apollyon) ────────────────────────────────────────────
        [1538] = 180, -- Ion Efflux     → PARALYSIS (4)         fixed 180s [ion_efflux.lua]

        -- ── Highwind / Notorious (ToAU) ───────────────────────────────────────
        [1721] = 20,  -- Obfuscate      → FLASH (156)           random 15-20s; max [obfuscate.lua]

        -- ── Lamia (ToAU) ──────────────────────────────────────────────────────
        [1759] = 60,  -- Hypnotic Sway  → AMNESIA (16)          TP-scaled 30-60s; max [hypnotic_sway.lua]
        [1756] = 120, -- Dukkeripen     → PARALYSIS (4)         fixed 120s [dukkeripen_para.lua] (Lamia Scouter)

        -- ── Antlion ───────────────────────────────────────────────────────────
        [275] = 180,  -- Sand Blast     → BLINDNESS (5)         fixed 180s [sand_blast.lua]
        [276] = 60,   -- Sand Pit       → BIND (11)             fixed 60s [sand_pit.lua]
        [277] = 120,  -- Venom Spray    → POISON (3)            fixed 120s [venom_spray.lua]

        -- ── Notorious Antlion (Attohwa) ───────────────────────────────────────
        [1841] = 60,  -- Silence Gas    → SILENCE (6)           random 15-60s; max [silence_gas.lua]
        [1843] = 120, -- Venom Spray    → POISON (3)            fixed 120s [venom_spray.lua]

        -- ── Notorious Taurus (ToAU) ───────────────────────────────────────────
        [1882] = 180, -- Frightful Roar → DEFENSE_DOWN (149)    fixed 180s [frightful_roar.lua]

        -- ── Diremite / Diamond (Sea Monk) ─────────────────────────────────────
        [1908] = 30,  -- Nightmare      → SLEEP_I (2)           random 20-30s; max [nightmare.lua]
        [1919] = 60,  -- Daydream       → CHARM_I (14)          60s [unimplemented in LSB SQL; observed in-game]

        -- ── Hpemde (Al'Taieu Sea) ─────────────────────────────────────────────
        [1366] = 5,   -- Temporal Shift → STUN (10)             fixed 5s [temporal_shift.lua]
        [1369] = 120, -- Ichor Stream   → POISON (3)            fixed 120s [ichor_stream.lua]

        -- ── Yovra (Al'Taieu Sea) ──────────────────────────────────────────────
        [1375] = 60,  -- Asthenic Fog   → DROWN (133)           fixed 60s [asthenic_fog.lua]
        [1376] = 25,  -- Luminous Drape → CHARM_I (14)          random 5-25s; max [luminous_drape.lua]
        [1377] = 5,   -- Fluorescence   → BOOST (45)            fixed 5s [fluorescence.lua]  (mob self-buff; packet lists nearby players as targets)

        -- ── Sea Hound (Al'Taieu Sea) ──────────────────────────────────────────
        [467] = 360,  -- Rot Gas        → DISEASE (8)           fixed 360s [rot_gas.lua]

        -- ── Ul'xzomit (Al'Taieu Sea) ──────────────────────────────────────────
        [1350] = 60,  -- Ink Cloud      → BLINDNESS (5)         random 30-60s; max [ink_cloud.lua]

        -- ── Bugard ────────────────────────────────────────────────────────────
        [343]  = 300, -- Spoil           → STR_DOWN (136)        fixed 300s [spoil.lua]
        [1862] = 300, -- Spoil (N. Bugard) → STR_DOWN (136)      fixed 300s [spoil.lua; client name: Spoil]

        -- ── Fly / Gnat (Batallia / Valkurm / Sacrarium) ───────────────────────
        [750]  = 90,  -- Stygian Flatus   → PARALYSIS (4)        fixed 90s [stygian_flatus.lua]

        -- ── Gnat / Bee (Sacrarium / Al'Taieu area) ────────────────────────────
        -- Murk applies whichever lands first (SLOW or WEIGHT); both durations needed.
        [1232] = { [13]=90, [12]=120 },
                      -- Murk: SLOW(13)=90s, WEIGHT(12)=120s [murk.lua]

        -- ── Fomor / Dancing Weapon ────────────────────────────────────────────
        [244]  = 60,  -- Dancing Chains  → DROWN (133)           fixed 60s [dancing_chains.lua]
        [252]  = 60,  -- Dancing Chains (alt) → DROWN (133)      same script, alternate skill entry

        -- ── Bat (Gusgen / Maze / Eastern Altepa) ──────────────────────────────
        [339]  = 180, -- Hi-Freq Field  → EVASION_DOWN (148)    fixed 180s [hi-freq_field.lua]
        [1155] = 180, -- Subsonics      → DEFENSE_DOWN (149)    fixed 180s [subsonics.lua]

        -- ── Lizard (East Ronfaure / Rolanberry / Sanctuary of Zi'Tah) ──────────
        [370]  = 60,  -- Baleful Gaze   → PETRIFICATION (7)     fixed 60s [baleful_gaze_lizard.lua]

        -- ── Goobbue (Jugner / Batallia / Uleguerand) ──────────────────────────
        [586]  = 180, -- Blank Gaze     → PARALYSIS (4)         fixed 180s [blank_gaze.lua]

        -- ── Bomb / Snoll (Ranguemont / Fei'Yin / Uleguerand) ─────────────────
        [1646] = 60,  -- Cold Wave      → FROST (129)           fixed 60s [cold_wave.lua]

        -- ── Wolf / Hound (Batallia / Xarcabard / Uleguerand) ─────────────────
        [465]  = 60,  -- Howling        → PARALYSIS (4)         fixed 60s [howling.lua]

        -- ── NM / Boss specific ────────────────────────────────────────────────
        [957]  = 45,  -- Absolute Terror → TERROR (28)          random 15-45s; max [absolute_terror.lua]

        -- ── Promathia (CoP Final Boss) ────────────────────────────────────────
        [1506] = 75,  -- Winds of Oblivion  → AMNESIA (16)      fixed 75s [winds_of_oblivion.lua]
        [1507] = 75,  -- Seal of Quiescence → MUTE (29)         fixed 75s [seal_of_quiescence.lua]

        -- ── Moblin (Movalpolos) ───────────────────────────────────────────────
        [1082] = 120, -- Smokebomb      → BLINDNESS (5)         fixed 120s [smokebomb.lua]

        -- ── Dragon (variant / Einherjar) ──────────────────────────────────────
        [651] = 30,   -- Lodesong       → WEIGHT (12)           fixed 30s [lodesong.lua]

    },

}
