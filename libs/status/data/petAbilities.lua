-- Pet abilities: automaton and BST jug pet abilities, which arrive as action type 11
-- [battle_entity.cpp:2915-2926].  Three sub-tables, all keyed by ability ID (action.Param):
--
--   durations  ability ID → seconds.  The status ID rides in ability.Param, so only the
--              duration is needed here.
--
--   hitData    ability ID → { statusId, duration }.  Applied server-side via
--              mobStatusEffectMove() with no result message — the 0x028 action carries only
--              the damage message, so both the status ID and the duration must be supplied.
--              Same value shape as mobSkillSilentDebuffs.
--
--   names      ability ID → display name, covering the damage-only abilities too so audit
--              logs can label every pet ability.
--
-- Every hitData entry, Flashbulb's duration and every BST jug duration are applied through
-- mobStatusEffectMove(), which scales them by the resist rate (>= 0.25), so those values are
-- pre-resist maxima.
--
-- Avatar abilities arrive as action type 13: see bloodPactDebuffs and wardBuffDurations.
--
-- Durations are base-LSB values, pending HorizonXI verification.

return {
    -- ── Messaged abilities (status ID in ability.Param) ───────────────────────
    durations = {
        -- ── PUP automatons ────────────────────────────────────────────────────
        [1946] = 180,  -- Shock Absorber  → Stoneskin (37),      180s  [shock_absorber.lua]
        [1947] = 12,   -- Flashbulb       → Flash (156),          12s  [flashbulb.lua]
        [1948] = 30,   -- Mana Converter  → Refresh (43),         30s  [mana_converter.lua]
        [2031] = 60,   -- Reactive Shield → Blaze Spikes (34),    60s  [reactive_shield.lua]
        [2132] = 300,  -- Replicator      → Copy Image (66),     300s  [replicator.lua]
        [2939] = 45,   -- Mighty Strikes  → Mighty Strikes (44),  45s  [mighty_strikes_automaton.lua]
        [2940] = 30,   -- Invincible      → Invincible (50),      30s  [invincible_automaton.lua]
        [2942] = 60,   -- Chainspell      → Chainspell (48),      60s  [chainspell_automaton.lua]
        [2944] = 60,   -- Manafont        → Manafont (47),        60s  [manafont_automaton.lua]

        -- ── BST jug pets ──────────────────────────────────────────────────────
        [3844] = 60,   -- Dream Flower    → Sleep (2),           random 15-60s; max  [dream_flower.lua]
        [3860] = 45,   -- Sheep Song      → Sleep (2),            45s  [sheep_song.lua]
        [3883] = 60,   -- Sand Pit        → Bind (11),            60s  [sand_pit.lua]
        [3886] = 30,   -- Soporific       → Sleep (2),            30s  [soporific.lua]
        [3890] = 5,    -- Numbing Noise   → Stun (10),             5s  [numbing_noise.lua]
    },

    -- ── Silent abilities (no result message; hit-confirmed only) ──────────────
    hitData = {
        -- ── PUP automatons ────────────────────────────────────────────────────
        [1944] = { statusId = 10,  duration = 6  },  -- Shield Bash     → Stun (10),           6s  [shield_bash.lua]
        -- Shield Bash — Hammermill's Slow is absent: neither the attachment nor the master's
        -- Earth Maneuver count is visible from the packet.
        [2066] = { statusId = 10,  duration = 4  },  -- Daze            → Stun (10),           4s  [daze.lua]
        [2067] = { statusId = 148, duration = 30 },  -- Knockout        → Evasion Down (148), 30s  [knockout.lua]
        [2299] = { statusId = 10,  duration = 4  },  -- Bone Crusher    → Stun (10),           4s  [bone_crusher.lua]
        -- Real duration is 60 + 3 × TP/100: 90s is the 1000 TP minimum, 120s at 3000 TP.
        [2744] = { statusId = 149, duration = 90 },  -- Armor Shatterer → Defense Down (149), 90s  [armor_shatterer.lua]

        -- ── BST jug pets ──────────────────────────────────────────────────────
        [3851] = { statusId = 10,  duration = 4  },  -- Tail Blow       → Stun (10),           4s  [tail_blow.lua]
        [3873] = { statusId = 6,   duration = 60 },  -- Silence Gas     → Silence (6),       random 15-60s; max  [silence_gas.lua]
    },

    -- ── Display names (damage-only abilities included) ────────────────────────
    names = {
        -- ── PUP automatons ────────────────────────────────────────────────────
        [1940] = 'Chimera Ripper',
        [1941] = 'String Clipper',
        [1942] = 'Arcuballista',
        [1943] = 'Slapstick',
        [1944] = 'Shield Bash',
        [1945] = 'Provoke',
        [1946] = 'Shock Absorber',
        [1947] = 'Flashbulb',
        [1948] = 'Mana Converter',
        [1949] = 'Ranged Attack',
        [2021] = 'Eraser',
        [2031] = 'Reactive Shield',
        [2065] = 'Cannibal Blade',
        [2066] = 'Daze',
        [2067] = 'Knockout',
        [2068] = 'Economizer',
        [2132] = 'Replicator',
        [2299] = 'Bone Crusher',
        [2300] = 'Armor Piercer',
        [2301] = 'Magic Mortar',
        [2743] = 'String Shredder',
        [2744] = 'Armor Shatterer',
        [2745] = 'Heat Capacitor',
        [2746] = 'Barrage Turbine',
        [2747] = 'Disruptor',
        [2939] = 'Mighty Strikes',
        [2940] = 'Invincible',
        [2941] = 'Eagle Eye Shot',
        [2942] = 'Chainspell',
        [2943] = 'Benediction',
        [2944] = 'Manafont',
        [3485] = 'Regulator',

        -- ── BST jug pets ──────────────────────────────────────────────────────
        [3844] = 'Dream Flower',
        [3851] = 'Tail Blow',
        [3860] = 'Sheep Song',
        [3873] = 'Silence Gas',
        [3883] = 'Sand Pit',
        [3886] = 'Soporific',
        [3890] = 'Numbing Noise',
    },
}
