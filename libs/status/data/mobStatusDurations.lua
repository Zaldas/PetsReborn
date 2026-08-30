-- PetsReborn: Mob status durations
--
-- Tracks status effects that land ON the pet — both self-buffs the pet applies
-- to itself and debuffs mobs apply to the pet. Does NOT include target-bar data
-- (effects on the enemy target).
--
-- selfBuffs: keyed by STATUS EFFECT ID (buff ID)
--   Used when the pet is both actor and target (pet self-buff path).
--   Durations sourced from LSB-server mobskill scripts.
--   Where scripts vary per-mob, the modal (most common) value is used.
--   Where duration is tied, the maximum is used so the bar doesn't expire early.
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
    -- Transmogrification (mob ability) → Physical Shield [150]
    -- Mana Screen / Mana Wall (mob ability) → Magic Shield [152]
    -- Airy Shield (mob ability) → Arrow Shield [151]
    [150] = { default=30, [1522]=60 },
                  -- Physical Shield  [transmogrification 487: 30 (default); energy_screen 1522: 60; psychoanima: 10 (uncommon, accept default underestimate)]
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
    -- All standard blade WS variants use 30s. heat_barrier.lua is an outlier at 300s for Enfire.
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
    [93]  = { default=180, [391]=60, [1351]=60, [445]=60, [453]=60, [1270]=300 },
                  -- Defense Boost  [aura_of_persistence 391/molluscous_mutation 1351/scissor_guard 445/water_wall 453: 60; particle_shield 1270: 300; rest: 180 (default)]

    -- ── NM / Boss-specific ────────────────────────────────────────────────
    -- These tend to appear on notorious monsters and HNMs.
    [127] = 300,  -- Costume         [some NMs disguise as another mob type: 300]
    [169] = 120,  -- Potency         [potency boost used by certain caster NMs: 120]
    [432] = 30,   -- Multi Strikes   [multi-hit buff from certain NMs: 30]
    [436] = 30,   -- Perfect Counter  [counter-stance variant on certain mobs: 30]
    [460] = 60,   -- Blood Rage      [certain DRK-type HNMs: 60]
    [461] = 60,   -- Impetus         [MNK-type HNMs: 60]
    [500] = 30,   -- Overkill        [rare boss buff granting massive damage bonus: 30]

    -- ── Player-applied debuffs (appear on target mob via mob2h scan) ───────────
    -- These durations are approximations (player-cast debuffs vary by tier/gear).
    -- selfBuffs acts as fallback: only used when statustracker has no action-packet time.
    -- Source: LSB enfeebling_spell.lua / enfeebling_song.lua / spell scripts.
    -- Always use max tier — wore-off packet handles early removal.
    [3]   = 150,  -- Poison      [Poison I=90s, II=120s, III=150s — use max]
    [4]   = 120,  -- Paralysis   [Paralyze / Paralyze II: 120s each]
    [5]   = 180,  -- Blindness   [Blind / Blind II: 180s each]
    [12]  = 180,  -- Weight      [Gravity=120s, Gravity II=180s — use max]
    [13]  = 180,  -- Slow        [Slow / Slow II: 180s each]
    [128] = 90,   -- Burn        [elemental DoT debuff: 90s]
    [134] = 120,  -- Dia         [Dia=60s, Dia II=120s — use max]
    [135] = 120,  -- Bio         [Bio=60s, Bio II=120s — use max]
    [156] = 12,   -- Flash       [PLD Flash spell: 12s]
    [192] = 160,  -- Requiem     [Foe Requiem I=64s … VII=160s — use max]
    [194] = 180,  -- Elegy       [Battlefield Elegy=120s, Carnage Elegy=180s — use max]
    [217] = 90,   -- Threnody    [Threnody I=60s, II=90s — use max]
    [576] = 30,   -- Doubt       [THF Bully (JP merit): 30s per thief.lua]
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

-- Mob skills that use xi.msg.basic.NONE as their action-packet message and return 0 as
-- the Param, so the standard statusOnMes path cannot detect them.  Keyed by mob skill ID;
-- value is the statusId the skill applies to self.  Duration comes from selfBuffs[statusId]
-- via getSelfBuffDuration().  Only add skills where actor == target (self-only effects).
--
-- Sources:
--   LSB  scripts/actions/mobskills/<name>.lua  (setMsg(NONE) + return 0 pattern)
local selfBuffSkillMap = {
    -- Skills that use xi.msg.basic.NONE + return 0 (no usable message or Param in the action packet).
    -- Pattern: xi.mobskills.mobBuffMove(mob, effect, ...) + skill:setMsg(NONE) + return 0
    [487] = 150,  -- Transmogrification (Mammett / automaton-type) → PHYSICAL_SHIELD (150)  [transmogrification.lua]
    [471] = 152,  -- Mind Wall          (Mammett staff form)        → MAGIC_SHIELD   (152)  [mind_wall.lua]
}

return {
    selfBuffs           = selfBuffs,
    getSelfBuffDuration = getSelfBuffDuration,
    selfBuffSkillMap    = selfBuffSkillMap,

    skillDebuffs = {

        -- ── Ahriman (Dynamis Vanguard Eye) ────────────────────────────────────
        [492] = 120,  -- Abyss Blast     → BLINDNESS (5)         fixed 120s [abyss_blast.lua]
        [491] = 120,  -- Call of the Grave → INT_DOWN (140)      fixed 120s [call_of_the_grave.lua]
        [534] = 90,   -- Kartstrahl      → SLEEP_I (2)           random 30-90s; max [kartstrahl.lua]
        [550] = 90,   -- Hypnosis        → SLEEP_I (2)           TP-scaled 45-90s; max [hypnosis.lua]
        [551] = 10,   -- Mind Break      → MAX_MP_DOWN (145)     fixed 10s [mind_break.lua]
        [552] = 45,   -- Binding Wave    → BIND (11)             TP-scaled 30-60s; midpoint 45
        [557] = 30,   -- Level 5 Petrify → PETRIFICATION (7)     TP-scaled 15-60s; use low end (often resisted)

        -- ── Antlion ────────────────────────────────────────────────────────────
        [275] = 180,  -- Sand Blast      → BLINDNESS (5)         fixed 180s [sand_blast.lua]
        [276] = 60,   -- Sand Pit        → BIND (11)             fixed 60s [sand_pit.lua]
        [277] = 120,  -- Venom Spray     → POISON (3)            fixed 120s [venom_spray.lua]

        -- ── Bat ───────────────────────────────────────────────────────────────
        [339] = 180,  -- hi-freq_field   → EVASION_DOWN (148)    fixed 180s [hi-freq_field.lua]
        [372] = 180,  -- Infrasonics     → EVASION_DOWN (148)    fixed 180s [infrasonics.lua]
        [392] = 180,  -- Ultrasonics     → EVASION_DOWN (148)    fixed 180s [ultrasonics.lua]
        [1155] = 180, -- subsonics       → DEFENSE_DOWN (149)    fixed 180s [subsonics.lua]

        -- ── Ahriman (additional) ─────────────────────────────────────────────
        [438] = 120,  -- hex_eye         → PARALYSIS (4)         TP-scaled 0-120s; max [hex_eye.lua]

        -- ── Beetle ────────────────────────────────────────────────────────────
        [434] = 30,   -- Soporific       → SLEEP_I (2)           fixed 30s [soporific.lua]
        [435] = 60,   -- Palsy Pollen    → PARALYSIS (4)         fixed 60s [palsy_pollen.lua]

        -- ── Bomb ──────────────────────────────────────────────────────────────
        [258] = 120,  -- Dust Cloud      → BLINDNESS (5)         fixed 120s [dust_cloud.lua]

        -- ── Buffalo ───────────────────────────────────────────────────────────
        [497] = 60,   -- Lowing          → PLAGUE (31)           fixed 60s [lowing.lua]

        -- ── Bugard ────────────────────────────────────────────────────────────
        [343]  = 300, -- Spoil           → STR_DOWN (136)        fixed 300s [spoil.lua]
        [1862] = 300, -- Spoil (N. Bugard) → STR_DOWN (136)      fixed 300s [spoil.lua; client name: Spoil]
        [386]  = 180, -- Awful Eye       → STR_DOWN (136)        fixed 180s [awful_eye.lua; gaze]
        [387]  = 6,   -- Heavy Bellow    → STUN (10)             fixed 6s [heavy_bellow.lua]

        -- ── Cockatrice ────────────────────────────────────────────────────────
        [269] = 120,  -- Petribreath     → PETRIFICATION (7)     fixed 120s [petribreath.lua]
        [480] = 60,   -- Petrifactive Breath → PETRIFICATION (7) fixed 60s [petrifactive_breath.lua]

        -- ── Lizard ────────────────────────────────────────────────────────────
        [370] = 60,   -- baleful_gaze_lizard → PETRIFICATION (7) fixed 60s [baleful_gaze_lizard.lua]

        -- ── Crab ──────────────────────────────────────────────────────────────
        [280] = 180,  -- Sonic Wave      → DEFENSE_DOWN (149)    fixed 180s [sonic_wave.lua]
        [376] = 180,  -- Foul Breath     → DISEASE (8)           fixed 180s [foul_breath.lua]
        [442] = 180,  -- Bubble Shower   → STR_DOWN (136)        fixed 180s [bubble_shower.lua]

        -- ── Crawler ───────────────────────────────────────────────────────────
        [344] = 540,  -- Sticky Thread   → SLOW (13)             random 300-540s; max [sticky_thread.lua]
        [345] = 60,   -- Poison Breath   → POISON (3)            fixed 60s [poison_breath_crawler.lua]
        [364] = 120,  -- Filamented Hold → SLOW (13)             fixed 120s [filamented_hold.lua]
        [686] = 30,   -- Slumber Powder  → SLEEP_I (2)           fixed 30s [slumber_powder.lua]

        -- ── Dhalmel ───────────────────────────────────────────────────────────
        [462] = 120,  -- Maelstrom       → STR_DOWN (136)        fixed 120s [maelstrom.lua]
        [284] = 60,   -- Cold Stare      → SILENCE (6)           fixed 60s [cold_stare.lua] (Troglodyte Dhalmel)

        -- ── Dragon ────────────────────────────────────────────────────────────
        [349] = 60,   -- Cold Breath     → BIND (11)             fixed 60s [cold_breath.lua]
        [377] = 180,  -- Frost Breath    → PARALYSIS (4)         fixed 180s [frost_breath.lua]
        [643] = 180,  -- Poison Breath   → POISON (3)            random 120-180s; max [poison_breath_dragon.lua]
        [651] = 30,   -- Lodesong        → WEIGHT (12)           fixed 30s [lodesong.lua]  (Enhanced Dragon / Einherjar variant)

        -- ── Eyeball / Hecteyes ────────────────────────────────────────────────
        [479] = 120,  -- Horror Cloud    → SLOW (13)             fixed 120s [horror_cloud.lua]

        -- ── Funguar ───────────────────────────────────────────────────────────
        [309] = 180,  -- Spore           → PARALYSIS (4)         fixed 180s [spore.lua]
        [310] = 60,   -- Queasyshroom    → POISON (3)            fixed 60s [queasyshroom.lua]
        [311] = 180,  -- Numbshroom      → PARALYSIS (4)         fixed 180s [numbshroom.lua]
        [312] = 720,  -- Shakeshroom     → DISEASE (8)           fixed 720s [shakeshroom.lua]
        [315] = 90,   -- Dark Spore      → BLINDNESS (5)         fixed 90s [dark_spore.lua]

        -- ── Goobbue ───────────────────────────────────────────────────────────
        [586] = 180,  -- blank_gaze      → PARALYSIS (4)         fixed 180s [blank_gaze.lua]

        -- ── Goblin ────────────────────────────────────────────────────────────
        [314] = 60,   -- Silence Gas     → SILENCE (6)           random 15-60s; max [silence_gas.lua]
        [1115] = 30,  -- Torpid Glare    → SLEEP_I (2)          fixed 30s [torpid_glare.lua]  (Goblin Replica, Salvage)

        -- ── Kindred (Dynamis) ─────────────────────────────────────────────────
        [531] = 60,   -- Silence Seal    → SILENCE (6)           fixed 60s [silence_seal.lua]
        [563] = 240,  -- Demonic Howl    → SLOW (13)             fixed 240s [demonic_howl.lua]
        [647] = 420,  -- Chaos Blade     → CURSE_I (9)           fixed 420s [chaos_blade.lua]

        -- ── Icon Prototype (Dynamis-Tavnazia / Xarcabard) ─────────────────────
        [1117] = 300, -- Lead Breath     → WEIGHT (12)           fixed 300s [lead_breath.lua]

        -- ── Diabolos (Dreams / Dynamis) ───────────────────────────────────────
        [558] = 30,   -- Nightmare       → SLEEP_I (2)           random 20-30s; max [nightmare.lua]

        -- ── Leech ─────────────────────────────────────────────────────────────
        [436] = 180,  -- Gloeosuccus     → SLOW (13)             fixed 180s [gloeosuccus.lua]

        -- ── Mandragora ────────────────────────────────────────────────────────
        [301] = 60,   -- Dream Flower    → SLEEP_I (2)           random 15-60s; max [dream_flower.lua]
        [687] = 90,   -- Sprout Smack    → SLOW (13)             fixed 90s [sprout_smack.lua]

        -- ── Mindflayer ────────────────────────────────────────────────────────
        [369] = 30,   -- Brain Crush     → SILENCE (6)           fixed 30s [brain_crush.lua]
        [423] = 120,  -- Brain Drain     → INT_DOWN (140)        fixed 120s [brain_drain.lua]
        [524] = 300,  -- Mind Drain      → MND_DOWN (141)        fixed 300s [mind_drain.lua]

        -- ── Morbol ────────────────────────────────────────────────────────────
        -- Bad Breath randomly applies several debuffs in one action; all have 60s duration.
        [319] = 60,   -- Bad Breath      → multi (SLOW/BLIND/WEIGHT/BIND/PARA/POISON/BIO, all 60s)
        [727] = 60,   -- Bad Breath (alt)→ multi (same script, variant mob)
        [320] = 60,   -- Sweet Breath    → SLEEP_I (2)           random 15-60s; max [sweet_breath.lua]
        [728] = 60,   -- Sweet Breath (alt) → SLEEP_I (2)        same script, variant mob

        -- ── Pugil ─────────────────────────────────────────────────────────────
        [458] = 120,  -- Ink Jet         → BLINDNESS (5)         fixed 120s [ink_jet.lua]

        -- ── Sabotender ────────────────────────────────────────────────────────
        [329] = 60,   -- Pinecone Bomb   → SLEEP_I (2)           fixed 60s [pinecone_bomb.lua]

        -- ── Sahagin ───────────────────────────────────────────────────────────
        [796] = 120,  -- Jamming Wave    → SILENCE (6)           fixed 120s [jamming_wave.lua]

        -- ── Scorpion / King Vinegarroon ────────────────────────────────────────
        [722] = 60,   -- Venom Storm     → POISON (3)            fixed 60s [venom_storm.lua]

        -- ── Sheep ─────────────────────────────────────────────────────────────
        [264] = 45,   -- Sheep Song      → SLEEP_I (2)           fixed 45s [sheep_song.lua]

        -- ── Shadow Dragon / Wreaker / Agonizer ────────────────────────────────
        -- Shadow Spread applies 3 effects; action.Param carries whichever landed first.
        -- Table keyed by statusId since a single cast can report any of the three.
        [1252] = { [9]=180, [2]=120, [5]=180 },
                      -- Shadow Spread: CURSE_I (9)=180s, SLEEP_I (2)=120s (Wreaker/Agonizer pool),
                      --               BLINDNESS (5)=180s  [shadow_spread.lua]

        -- ── Spider / Bark Tarantula ────────────────────────────────────────────
        [351] = 60,   -- Poison Sting    → POISON (3)            fixed 60s [poison_sting.lua]
        [812] = 90,   -- Spider Web      → SLOW (13)             fixed 90s [spider_web.lua]

        -- ── Tiger / Raptor ────────────────────────────────────────────────────
        [270] = 120,  -- Roar            → PARALYSIS (4)         fixed 120s [roar.lua]

        -- ── Toad ──────────────────────────────────────────────────────────────
        [425] = 180,  -- Gastric Bomb    → ATTACK_DOWN (147)     fixed 180s [gastric_bomb.lua]

        -- ── Treant ────────────────────────────────────────────────────────────
        [328] = 45,   -- Drill Branch    → BLINDNESS (5)         fixed 45s [drill_branch.lua]
        [332] = 60,   -- Entangle        → BIND (11)             fixed 60s [entangle.lua]

        -- ── Undead ────────────────────────────────────────────────────────────
        [474] = 300,  -- Fear Touch      → SLOW (13)             fixed 300s [fear_touch.lua]
        [475] = 90,   -- Terror Touch    → ATTACK_DOWN (147)     fixed 90s [terror_touch.lua]
        [476] = 2280, -- Curse           → CURSE_I (9)           fixed 2280s (NM-only) [curse.lua]
        [490] = 660,  -- Undead Mold     → DISEASE (8)           fixed 660s [undead_mold.lua]
        [783] = 45,   -- Words of Bane   → CURSE_I (9)           fixed 45s [words_of_bane.lua]

        -- ── Corse ─────────────────────────────────────────────────────────────────
        [533] = 60,   -- Danse Macabre   → CHARM_I (14)          fixed 60s [danse_macabre.lua]

        -- ── Various beasts ────────────────────────────────────────────────────
        [393] = 180,  -- Sonic Boom      → ATTACK_DOWN (147)     TP-based max [sonic_boom.lua]
        [410] = 180,  -- Sound Blast     → INT_DOWN (140)        fixed 180s [sound_blast.lua]
        [488] = 180,  -- Acid Breath     → STR_DOWN (136)        fixed 180s [acid_breath.lua]
        [489] = 180,  -- Stinking Gas    → VIT_DOWN (138)        fixed 180s [stinking_gas.lua]
        [501] = 180,  -- Frightful Roar  → DEFENSE_DOWN (149)    fixed 180s [frightful_roar.lua]

        -- ── Ignidrake (ToAU) ──────────────────────────────────────────────────
        [817] = 60,   -- Dread Shriek    → PARALYSIS (4)         random 30-60s; max [dread_shriek.lua]

        -- ── Fly / Mourioche ───────────────────────────────────────────────────
        [306] = 180,  -- Scream          → MND_DOWN (141)        fixed 180s [scream.lua]

        -- ── Wyrm ──────────────────────────────────────────────────────────────
        [1304] = 120, -- Bai Wing        → SLOW (13)             fixed 120s [bai_wing.lua]

        -- ── Dice abilities (COR-type / Qiqirn mobs) ───────────────────────────
        [1100] = 300, -- Dice Curse      → CURSE_I (9)           fixed 300s [dice_curse.lua]
        [1103] = 60,  -- Dice Poison     → POISON (3)            fixed 60s [dice_poison.lua]
        [1104] = 180, -- Dice Disease    → DISEASE (8)           fixed 180s [dice_disease.lua]
        [1106] = { [13]=120, [2]=30 },
                      -- Dice Slow: SLOW(13)=120s, SLEEP_I(2)=30s [dice_slow.lua]

        -- ── Snoll / Bomb (Campaign) ──────────────────────────────────────────
        [1646] = 60,  -- cold_wave       → FROST (129)           fixed 60s [cold_wave.lua]

        -- ── Wolf / Hound ──────────────────────────────────────────────────────
        [465] = 60,   -- howling         → PARALYSIS (4)         fixed 60s [howling.lua]

        -- ── NM / Boss specific ─────────────────────────────────────────────────
        [957]  = 45,  -- absolute_terror → TERROR (28)           random 15-45s; max [absolute_terror.lua]  (Fafnir/Nidhogg)
        [1067] = 30,  -- Doom            → DOOM (15)             fixed 30s [doom.lua]
        [1073] = 30,  -- Doom (alt)      → DOOM (15)             same script, alternate skill entry
        [1360] = 30,  -- Apocalyptic Ray → DOOM (15)             fixed 30s [apocalyptic_ray.lua]

        -- ── Jailer of xxx (CoP Sea Gods) ──────────────────────────────────────
        [1491] = 30,  -- Chains of Apathy    → TERROR (28)       fixed 30s [chains_of_apathy.lua]
        [1492] = 30,  -- Chains of Arrogance → TERROR (28)       fixed 30s [chains_of_arrogance.lua]
        [1493] = 30,  -- Chains of Cowardice → TERROR (28)       fixed 30s [chains_of_cowardice.lua]
        [1494] = 30,  -- Chains of Rage      → TERROR (28)       fixed 30s [chains_of_rage.lua]
        [1495] = 30,  -- Chains of Envy      → TERROR (28)       fixed 30s [chains_of_envy.lua]

        -- ── Promathia (CoP Final Boss) ────────────────────────────────────────
        [1506] = 75,  -- Winds of Oblivion  → AMNESIA (16)       fixed 75s [winds_of_oblivion.lua]
        [1507] = 75,  -- Seal of Quiescence → MUTE (29)          fixed 75s [seal_of_quiescence.lua]

        -- ── Hpemde (Al'Taieu Sea) ─────────────────────────────────────────────
        [1366] = 5,   -- Temporal Shift  → STUN (10)             fixed 5s [temporal_shift.lua]
        [1369] = 120, -- Ichor Stream    → POISON (3)            fixed 120s [ichor_stream.lua]

        -- ── Yovra (Al'Taieu Sea) ──────────────────────────────────────────────
        [1375] = 60,  -- Asthenic Fog    → DROWN (133)           fixed 60s [asthenic_fog.lua]
        [1376] = 25,  -- Luminous Drape  → CHARM_I (14)          random 5-25s; max [luminous_drape.lua]
        [1377] = 5,   -- Fluorescence    → BOOST (45)            fixed 5s [fluorescence.lua]  (mob self-buff; packet lists nearby players as targets)

        -- ── Sea Hound (Al'Taieu Sea) ──────────────────────────────────────────
        [467] = 360,  -- Rot Gas         → DISEASE (8)           fixed 360s [rot_gas.lua]

        -- ── Ul'xzomit (Al'Taieu Sea) ──────────────────────────────────────────
        [1350] = 60,  -- Ink Cloud       → BLINDNESS (5)         random 30-60s; max [ink_cloud.lua]

        -- ── Undead (Bane / long Curse) ────────────────────────────────────────
        [1339] = 600, -- Bane            → BANE (30)             fixed 600s [bane.lua]

        -- ── Hecteyes ──────────────────────────────────────────────────────────
        [484]  = 420, -- Black Cloud     → BLINDNESS (5)         fixed 420s [black_cloud.lua]

        -- ── Orc (Battle Dance) ────────────────────────────────────────────────
        [609]  = 180, -- Battle Dance    → DEX_DOWN (137)        fixed 180s [battle_dance.lua]

        -- ── Peiste ────────────────────────────────────────────────────────────
        -- Abominable Belch applies three debuffs; durations are TP-scaled (max values used).
        [1978] = { [31]=45, [6]=60, [4]=60 },
                      -- Abominable Belch: PLAGUE(31)=45s max, SILENCE(6)=60s max, PARALYSIS(4)=60s max

        -- ── Ahriman / Bat (multi-effect gaze) ─────────────────────────────────
        [1220] = { [6]=60, [5]=90 },
                      -- Auroral Drape: SILENCE(6)=60s, BLINDNESS(5)=90s [auroral_drape.lua]

        -- ── Puk ───────────────────────────────────────────────────────────────
        [2189] = { [6]=60, [5]=60 },
                      -- Aeolian Void: SILENCE(6)=60s, BLINDNESS(5)=60s [aeolian_void.lua]

        -- ── Weeper / Seether (Al'Taieu Sea) ───────────────────────────────────
        [587]  = 90,  -- Antiphase       → SILENCE (6)           fixed 90s [antiphase.lua]
        [3357] = 90,  -- Antiphase (alt) → SILENCE (6)           fixed 90s [antiphase.lua]

        -- ── Zdei / Ghrah (Luminian) ───────────────────────────────────────────
        [1528] = { [5]=120, [156]=20, [6]=60 },
                      -- Floodlight: BLINDNESS(5)=120s, FLASH(156)=20s, SILENCE(6)=60s
        [1441] = 15,  -- Actinic Burst   → FLASH (156)           fixed 15s [actinic_burst.lua]

        -- ── Khimaira ──────────────────────────────────────────────────────────
        [1269] = { [13]=120, [194]=120 },
                      -- Chemical Bomb: SLOW(13)=120s, ELEGY(194)=120s [chemical_bomb.lua]

        -- ── Imp ───────────────────────────────────────────────────────────────
        [2118] = { [146]=60, [147]=60, [149]=60 },
                      -- Bilgestorm: ACCURACY_DOWN(146)=60s, ATTACK_DOWN(147)=60s, DEFENSE_DOWN(149)=60s
        [1709] = 60,  -- Abrasive Tantara  → AMNESIA (16)        fixed 60s [abrasive_tantara.lua] (Tracker Imp)
        [1710] = 30,  -- Deafening Tantara → SILENCE (6)         fixed 30s [deafening_tantara.lua] (Tracker Imp)

        -- ── Qiqirn ────────────────────────────────────────────────────────────
        [1730] = { [149]=120, [167]=120 },
                      -- Deadeye: DEFENSE_DOWN(149)=120s, MAGIC_DEF_DOWN(167)=120s

        -- ── Aquan / Sea Monk ──────────────────────────────────────────────────
        [2629] = { [167]=60, [149]=60 },
                      -- Benthic Typhoon: MAGIC_DEF_DOWN(167)=60s, DEFENSE_DOWN(149)=60s

        -- ── Slug / Crawler variant ────────────────────────────────────────────
        [2185] = { [147]=120, [149]=120 },
                      -- Corrosive Ooze: ATTACK_DOWN(147)=120s, DEFENSE_DOWN(149)=120s

        -- ── Fly / Wamoura ─────────────────────────────────────────────────────
        [1745] = { [149]=30, [167]=30 },
                      -- Enervation: DEFENSE_DOWN(149)=30s, MAGIC_DEF_DOWN(167)=30s [enervation.lua]
        [1898] = { [149]=30, [167]=30 },
                      -- Enervation (alt): same script, alternate skill entry

        -- ── Poroggo / Doomed ──────────────────────────────────────────────────
        [2562] = 120, -- Acrid Stream    → MAGIC_DEF_DOWN (167)  fixed 120s [acrid_stream.lua]

        -- ── Limule (Abyssea) ──────────────────────────────────────────────────
        [1822] = 120, -- Boiling Point   → MAGIC_DEF_DOWN (167)  fixed 120s [boiling_point.lua]

        -- ── Gargouille ────────────────────────────────────────────────────────
        [2422] = 60,  -- Dark Mist       → WEIGHT (12)           fixed 60s [dark_mist.lua]

        -- ── Wivre ─────────────────────────────────────────────────────────────
        [1832] = 60,  -- Barofield       → WEIGHT (12)           fixed 60s [barofield.lua]

        -- ── Rampart (Besieged) ────────────────────────────────────────────────
        [2033] = 30,  -- Choke Chain     → BIND (11)             fixed 30s [choke_chain.lua]

        -- ── Cockatrice (additional) ───────────────────────────────────────────
        [652]  = 60,  -- Blaster         → PARALYSIS (4)         fixed 60s [blaster.lua]

        -- ── Sheep / Ram ───────────────────────────────────────────────────────
        [1837] = 90,  -- Feeble Bleat    → PARALYSIS (4)         fixed 90s [feeble_bleat.lua]

        -- ── Capacitor / Cluster ───────────────────────────────────────────────
        [2056] = 180, -- Discharge       → PARALYSIS (4)         fixed 180s [discharge.lua]
        [2028] = 60,  -- Fulmination     → PARALYSIS (4)         fixed 60s (stun 4s skipped) [fulmination.lua]

        -- ── Troll (Demoralizing Roar) ─────────────────────────────────────────
        [2101] = 90,  -- Demoralizing Roar → ATTACK_DOWN (147)   TP-based max [demoralizing_roar.lua]

        -- ── Crawler / Leech (additional POISON) ───────────────────────────────
        [811]  = 120, -- Acid Spray      → POISON (3)            fixed 120s [acid_spray.lua]
        [415]  = 120, -- Acid Mist       → ATTACK_DOWN (147)     fixed 120s [acid_mist.lua]

        -- ── Uragnite ──────────────────────────────────────────────────────────
        [504]  = 90,  -- Gas Shell       → POISON (3)            random 30-90s; max [gas_shell.lua]
        [1571] = 90,  -- Gas Shell (alt) → POISON (3)            same script, alternate skill entry

        -- ── Aern / plant variant ──────────────────────────────────────────────
        [1385] = 60,  -- Biotic Boomerang → PLAGUE (31)          random 30-60s; max [biotic_boomerang.lua]

        -- ── Wyrm / Wyvern (additional SLEEP) ─────────────────────────────────
        [1309] = 60,  -- Cyclone Wing    → SLEEP_I (2)           fixed 60s [cyclone_wing.lua]

        -- ── Mandragora / Sabotender (additional) ─────────────────────────────
        [2166] = 30,  -- Floral Bouquet  → SLEEP_I (2)           fixed 30s [floral_bouquet.lua]

        -- ── Dice (additional) ─────────────────────────────────────────────────
        [1105] = 30,  -- Dice Sleep      → SLEEP_I (2)           fixed 30s [dice_sleep.lua]

        -- ── Fomor / Dancing Weapon ────────────────────────────────────────────
        [244]  = 60,  -- Dancing Chains  → DROWN (133)           fixed 60s [dancing_chains.lua]
        [252]  = 60,  -- Dancing Chains (alt) → DROWN (133)      same script, alternate skill entry

        -- ── Coeurl ────────────────────────────────────────────────────────────
        [653]  = 60,  -- Chaotic Eye     → SILENCE (6)           fixed 60s [chaotic_eye.lua]

        -- ── Manticore (Valley of Sorrows) ─────────────────────────────────────
        [801]  = 60,  -- Riddle          → MAX_MP_DOWN (145)     fixed 60s [riddle.lua]

        -- ── Aw'euvhi (ToAU) ───────────────────────────────────────────────────
        [1448] = { [5]=30, [6]=30 },
                      -- Efflorescent Foetor: BLINDNESS(5)=random 10-30s; max, SILENCE(6)=random 10-30s; max [efflorescent_foetor.lua]
        [1450] = 120, -- Viscid Nectar   → SLOW (13)             fixed 120s [viscid_nectar.lua]
        [1452] = 60,  -- Axial Bloom     → BIND (11)             random 30-60s; max [axial_bloom.lua]

        -- ── Lamia (ToAU) ──────────────────────────────────────────────────────
        [1759] = 60,  -- Hypnotic Sway   → AMNESIA (16)          TP-scaled 30-60s; max [hypnotic_sway.lua]
        [1756] = 120, -- Dukkeripen      → PARALYSIS (4)         fixed 120s [dukkeripen_para.lua] (Lamia Scouter)

        -- ── Omega (Sea Lions' Den) ────────────────────────────────────────────
        -- pile_pitch (1235) / hyper_pulse (1237): apply BIND via mobStatusEffectMove without setMsg
        --   → no ability sub-action generated; BIND shows via party status memory only (no timer)
        [1240] = 180, -- Ion Efflux      → PARALYSIS (4)         fixed 180s [ion_efflux.lua]  (same script as 1538)
        [1241] = 30,  -- Rear Lasers     → PETRIFICATION (7)     fixed 30s  [rear_lasers.lua]

        -- ── Proto-Omega (Apollyon) ────────────────────────────────────────────
        -- pile_pitch (1533) / hyper_pulse (1535): same BIND issue as Omega variants above
        [1538] = 180, -- Ion Efflux      → PARALYSIS (4)         fixed 180s [ion_efflux.lua]
        [1539] = 30,  -- Rear Lasers     → PETRIFICATION (7)     fixed 30s  [rear_lasers.lua]

        -- ── Highwind / Notorious (ToAU) ───────────────────────────────────────
        [1721] = 20,  -- Obfuscate       → FLASH (156)           random 15-20s; max [obfuscate.lua]

        -- ── Notorious Antlion (Attohwa) ───────────────────────────────────────
        [1841] = 60,  -- Silence Gas     → SILENCE (6)           random 15-60s; max [silence_gas.lua]
        [1843] = 120, -- Venom Spray     → POISON (3)            fixed 120s [venom_spray.lua]

        -- ── Notorious Taurus (ToAU) ───────────────────────────────────────────
        [1882] = 180, -- Frightful Roar  → DEFENSE_DOWN (149)    fixed 180s [frightful_roar.lua]

        -- ── Diremite / Diamond (Sea Monk) ─────────────────────────────────────
        [1908] = 30,  -- Nightmare       → SLEEP_I (2)           random 20-30s; max [nightmare.lua]
        [1919] = 60,  -- Daydream        → CHARM_I (14)          60s [unimplemented in LSB SQL; observed in-game]

        -- ── Mimic / Box (Dynamis / ToAU) ──────────────────────────────────────
        -- death_trap tries Stun then Poison; action packet reports whichever lands first.
        [588] = { [10]=15, [3]=300 },
                      -- Death Trap: STUN(10)=random 10-15s; max, POISON(3)=fixed 300s [death_trap.lua]

        -- ── Praetorian Guard (ToAU / Aht Urhgan) ─────────────────────────────
        [792] = 90,   -- Sandstorm       → BLINDNESS (5)         fixed 90s [sandstorm.lua]

        -- ── Ultima / Proto-Ultima (Temenos / Sea Lions' Den) ─────────────────
        -- nuclear_waste: uses target:addStatusEffectEx + setMsg(NONE) + return statusId
        --   → NONE message path in statustracker.lua handles this via skillDebuffs-none code path
        -- wire_cutter (1259), antimatter (1260), equalizer (1261): damage only
        -- armor_buster (1521): WEIGHT via mobPhysicalStatusEffectMove → AdditionalEffect → additionalEffectDurations[12]=45 ✓
        -- energy_screen (1522): PHYSICAL_SHIELD via mobBuffMove w/ normal message → selfBuffs[150][1522]=60 ✓
        -- mana_screen (1523): MAGIC_SHIELD via mobBuffMove w/ normal message → selfBuffs[152].default=60 ✓
        -- particle_shield (1270): DEFENSE_BOOST via mobBuffMove w/ normal message → selfBuffs[93][1270]=300 ✓
        -- chemical_bomb (1269): already in skillDebuffs above ✓
        [1268] = 60,  -- Nuclear Waste   → ELEMENTALRES_DOWN (802) fixed 60s [nuclear_waste.lua]

        -- ── Doll / Golem (Abyssea) ────────────────────────────────────────────
        [541]  = 420, -- Gravity Field   → SLOW (13)             random 240-420s; max [gravity_field.lua]

        -- ── Moblin (ToAU / Halvung) ───────────────────────────────────────────
        [1082] = 120, -- smokebomb       → BLINDNESS (5)         fixed 120s [smokebomb.lua]
        [1086] = 120, -- Paralysis Shower → PARALYSIS (4)        fixed 120s [paralysis_shower.lua]

        -- ── Fly / Gnat (Batallia / Valkurm / Sacrarium) ───────────────────────
        [750]  = 90,  -- Stygian Flatus   → PARALYSIS (4)        fixed 90s [stygian_flatus.lua]

        -- ── Gnat / Bee (Sacrarium / Al'Taieu area) ────────────────────────────
        -- Murk applies whichever lands first (SLOW or WEIGHT); both durations needed.
        [1232] = { [13]=90, [12]=120 },
                      -- Murk: SLOW(13)=90s, WEIGHT(12)=120s [murk.lua]

        -- ── Worm ──────────────────────────────────────────────────────────────
        [429]  = 90,  -- Sound Vacuum    → SILENCE (6)           fixed 90s [sound_vacuum_worm.lua]

        -- ── Hippogryph ────────────────────────────────────────────────────────
        [577]  = 10,  -- Jettatura       → TERROR (28)           fixed 10s [jettatura.lua]

        -- ── Basilisk / Dragon (gaze petrify) ──────────────────────────────────
        [648]  = 420, -- Petro Eyes      → PETRIFICATION (7)     fixed 420s [petro_eyes.lua]

        -- ── Charm (generic mob skill) ─────────────────────────────────────────
        [710]  = 180, -- Charm           → CHARM_I (14)          fixed 180s (30s for Osschaart) [charm.lua]

        -- ── Medusa ────────────────────────────────────────────────────────────
        [1814] = 180, -- Gorgon Dance    → PETRIFICATION (7)     random 60-180s; max [gorgon_dance.lua]

        -- ── Hydra ─────────────────────────────────────────────────────────────
        [1836] = { [9]=420, [3]=60 },
                      -- Nerve Gas: CURSE_I(9)=420s, POISON(3)=60s [nerve_gas.lua]

    },

}
