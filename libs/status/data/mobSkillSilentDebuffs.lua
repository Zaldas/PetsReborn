-- Mob skill silent debuffs: statuses a mob skill applies that never reach the client as a
-- status message, so neither the statusOnMes path nor the NONE-message path fires and
-- mobStatusDurations.skillDebuffs has nothing to key off.
--
-- Two independent causes:
--   1. LSB calls xi.mobskills.mobStatusEffectMove() without passing the result to
--      skill:setMsg() -- the 0x028 action carries only the damage message.
--   2. The packet has room for ONE status message per target, so a skill applying N statuses
--      has at least N-1 silent ones no matter what the script does. Observed directly:
--      enervation (1745/1898) only ever reports DEFENSE_DOWN, never MAGIC_DEF_DOWN;
--      death_trap (588) only STUN, never POISON; nerve_gas (1836) only CURSE_I, never POISON.
--
-- Multi-status skills list every status, including whichever one rides the message. That entry
-- is redundant, not wrong: applyStatusOn runs first and this table never overwrites a live
-- timer. Which status wins the message is server-side ordering we cannot predict per skill.
--
-- Applied only when ability.Param (damage) > 0 and no active timer exists. May produce false
-- timers when the status resisted independently of the damage -- mobStatusEffectMove rolls
-- resist server-side where the addon cannot observe it. In VanaVista a false timer stays
-- invisible: the icon list is read from memory and a timer never creates an icon. PetsReborn
-- draws the pet's icons from this tracker, so there a false timer is a visible icon.
--
-- Scope: every mob skill observed in play (unknownDurations.log, 2026-07-08 onward) whose LSB
-- script applies a status silently. skillDebuffs entries not yet observed are left alone --
-- base LSB and Horizon disagree about which skills call setMsg, so those need a live sample.
--
-- Durations are pre-resist: mobStatusEffectMove scales duration by the resist rate, so a
-- partially resisted status wears before the timer. math.randomInt(a, b) is taken at b;
-- calculateDuration(tp, min, max) is taken at its clamp ceiling, the min/max midpoint.
--
-- Pet ability IDs must NOT appear here. They share the mob-skill namespace and this table is
-- consulted before petAbilities.hitData, so an entry here shadows the tuned pet value --
-- shield_bash (1944) is the Valoredge frame's ability, not a mob skill.
--
-- Keyed by mob skill ID (action.Param for type 7/11). Value is one { statusId, duration }
-- record, or a list of them for multi-status skills.

return {
    -- Single silent status
    [291 ] = { statusId = 3,   duration = 60  },  -- Claw Storm           → POISON (3) [claw_storm.lua]
    [302 ] = { statusId = 138, duration = 120 },  -- Wild Oats            → VIT_DOWN (138) [wild_oats.lua]
    [305 ] = { statusId = 3,   duration = 90  },  -- Leaf Dagger          → POISON (3) [leaf_dagger.lua]
    [354 ] = { statusId = 3,   duration = 60  },  -- Wild Rage            → POISON (3) [wild_rage.lua]
    [355 ] = { statusId = 137, duration = 180 },  -- Earth Pounder        → DEX_DOWN (137) [earth_pounder.lua]
    [361 ] = { statusId = 10,  duration = 4   },  -- Earth Shock          → STUN (10) [earth_shock.lua]
    [369 ] = { statusId = 6,   duration = 30  },  -- Brain Crush          → SILENCE (6) [brain_crush.lua]
    [380 ] = { statusId = 10,  duration = 4   },  -- Scythe Tail          → STUN (10) [scythe_tail.lua]
    [385 ] = { statusId = 31,  duration = 60  },  -- Bone Crunch          → PLAGUE (31) [bone_crunch.lua]
    [407 ] = { statusId = 3,   duration = 60  },  -- Poison Pick          → POISON (3) [poison_pick.lua]
    [414 ] = { statusId = 10,  duration = 4   },  -- Suction              → STUN (10) [suction.lua]
    [426 ] = { statusId = 146, duration = 180 },  -- Sandspin             → ACCURACY_DOWN (146) [sandspin.lua]
    [427 ] = { statusId = 137, duration = 180 },  -- Tremors              → DEX_DOWN (137) [tremors.lua]
    [442 ] = { statusId = 136, duration = 180 },  -- Bubble Shower        → STR_DOWN (136) [bubble_shower.lua]
    [450 ] = { statusId = 136, duration = 180 },  -- Aqua Ball            → STR_DOWN (136) [aqua_ball.lua]
    [463 ] = { statusId = 138, duration = 120 },  -- Whirlwind            → VIT_DOWN (138) [whirlwind.lua]
    [477 ] = { statusId = 5,   duration = 300 },  -- Dark Sphere          → BLINDNESS (5) [dark_sphere.lua]
    [486 ] = { statusId = 10,  duration = 4   },  -- Whip Tongue          → STUN (10) [whip_tongue.lua]
    [498 ] = { statusId = 137, duration = 90  },  -- Triclip              → DEX_DOWN (137) [triclip.lua]
    [500 ] = { statusId = 3,   duration = 30  },  -- Mow                  → POISON (3) [mow.lua]
    [514 ] = { statusId = 10,  duration = 4   },  -- Whirl of Rage        → STUN (10) [whirl_of_rage.lua]
    [523 ] = { statusId = 12,  duration = 120 },  -- Mysterious Light     → WEIGHT (12) [mysterious_light.lua]
    [540 ] = { statusId = 10,  duration = 3   },  -- Tremorous Tread      → STUN (10) [tremorous_tread.lua]
    [560 ] = { statusId = 5,   duration = 120 },  -- Hecatomb Wave        → BLINDNESS (5), randomInt(60, 120) [hecatomb_wave.lua]
    [605 ] = { statusId = 10,  duration = 4   },  -- Aerial Wheel         → STUN (10) [aerial_wheel.lua]
    [607 ] = { statusId = 11,  duration = 60  },  -- Slam Dunk            → BIND (11) [slam_dunk.lua]
    [612 ] = { statusId = 10,  duration = 4   },  -- Head Butt (quadav)   → STUN (10) [head_butt_quadav.lua]
    [617 ] = { statusId = 3,   duration = 45  },  -- Feather Storm        → POISON (3) [feather_storm.lua]
    [618 ] = { statusId = 10,  duration = 4   },  -- Double Kick          → STUN (10) [double_kick.lua]
    [620 ] = { statusId = 10,  duration = 4   },  -- Sweep                → STUN (10) [sweep.lua]
    [629 ] = { statusId = 10,  duration = 14  },  -- Thunderbolt Behemoth → STUN (10), randomInt(8, 14) [thunderbolt_behemoth.lua]
    [630 ] = { statusId = 5,   duration = 120 },  -- Kick Out             → BLINDNESS (5) [kick_out.lua]
    [660 ] = { statusId = 3,   duration = 60  },  -- Venom                → POISON (3) [venom.lua]
    [676 ] = { statusId = 11,  duration = 180 },  -- Ice Break            → BIND (11), calculateDuration(skill:getTP(), 120, 240) [ice_break.lua]
    [677 ] = { statusId = 10,  duration = 20  },  -- Thunder Break        → STUN (10), randomInt(10, 20) [thunder_break.lua]
    [771 ] = { statusId = 136, duration = 120 },  -- Hydro Ball           → STR_DOWN (136) [hydro_ball.lua]
    [780 ] = { statusId = 10,  duration = 4   },  -- Spinning Fin         → STUN (10) [spinning_fin.lua]
    [786 ] = { statusId = 149, duration = 30  },  -- Lateral Slash        → DEFENSE_DOWN (149) [lateral_slash.lua]
    [787 ] = { statusId = 146, duration = 30  },  -- Vertical Slash       → ACCURACY_DOWN (146) [vertical_slash.lua]
    [789 ] = { statusId = 3,   duration = 60  },  -- Spikeball            → POISON (3) [spikeball.lua]
    [791 ] = { statusId = 12,  duration = 60  },  -- Magnetite Cloud      → WEIGHT (12) [magnetite_cloud.lua]
    [795 ] = { statusId = 7,   duration = 15  },  -- Sand Trap            → PETRIFICATION (7) [sand_trap.lua]
    [803 ] = { statusId = 130, duration = 90  },  -- Great Whirlwind      → CHOKE (130) [great_whirlwind.lua]
    [805 ] = { statusId = 146, duration = 180 },  -- Head Butt (turtle)   → ACCURACY_DOWN (146), randomInt(120, 180) [head_butt_turtle.lua]
    [806 ] = { statusId = 149, duration = 180 },  -- Tortoise Stomp       → DEFENSE_DOWN (149), randomInt(120, 180) [tortoise_stomp.lua]
    [818 ] = { statusId = 3,   duration = 120 },  -- Tail Crush           → POISON (3), POISON scales 30-120s with TP [tail_crush.lua]
    [885 ] = { statusId = 10,  duration = 12  },  -- Shock Strike         → STUN (10) [shock_strike.lua]
    [888 ] = { statusId = 4,   duration = 60  },  -- Thunderspark         → PARALYSIS (4) [thunderspark.lua]
    [891 ] = { statusId = 10,  duration = 10  },  -- Chaotic Strike       → STUN (10) [chaotic_strike.lua]
    [907 ] = { statusId = 3,   duration = 60  },  -- Poison Nails         → POISON (3) [poison_nails.lua]
    [931 ] = { statusId = 10,  duration = 4   },  -- Cross Reaver         → STUN (10) [cross_reaver.lua]
    [932 ] = { statusId = 2,   duration = 60  },  -- Havoc Spiral         → SLEEP_I (2), randomInt(30, 60) [havoc_spiral.lua]
    [933 ] = { statusId = 6,   duration = 60  },  -- Dominion Slash       → SILENCE (6) [dominion_slash.lua]
    [934 ] = { statusId = 10,  duration = 6   },  -- Shield Strike        → STUN (10) [shield_strike.lua]
    [937 ] = { statusId = 11,  duration = 30  },  -- Dragonfall           → BIND (11) [dragonfall.lua]
    [946 ] = { statusId = 5,   duration = 60  },  -- Tachi: Yukikaze      → BLINDNESS (5) [tachi_yukikaze.lua]
    [947 ] = { statusId = 6,   duration = 45  },  -- Tachi: Gekko         → SILENCE (6) [tachi_gekko.lua]
    [948 ] = { statusId = 4,   duration = 60  },  -- Tachi: Kasha         → PARALYSIS (4) [tachi_kasha.lua]
    [951 ] = { statusId = 5,   duration = 30  },  -- Hurricane Wing       → BLINDNESS (5) [hurricane_wing.lua]
    [1039] = { statusId = 5,   duration = 30  },  -- Hurricane Wing (alt) → BLINDNESS (5) [hurricane_wing.lua]
    [1081] = { statusId = 10,  duration = 4   },  -- Frypan               → STUN (10) [frypan.lua]
    [1110] = { statusId = 10,  duration = 4   },  -- Seismostomp          → STUN (10) [seismostomp.lua]
    [1263] = { statusId = 4,   duration = 120 },  -- Cryo Jet             → PARALYSIS (4) [cryo_jet.lua]
    [1264] = { statusId = 6,   duration = 30  },  -- Turbofan             → SILENCE (6) [turbofan.lua]
    [1347] = { statusId = 10,  duration = 4   },  -- Dual Strike          → STUN (10) [dual_strike.lua]
    [1349] = { statusId = 12,  duration = 45  },  -- Mantle Pierce        → WEIGHT (12), randomInt(15, 45) [mantle_pierce.lua]
    [1378] = { statusId = 13,  duration = 60  },  -- Wing Thrust          → SLOW (13), randomInt(30, 60) [wing_thrust.lua]
    [1379] = { statusId = 6,   duration = 120 },  -- Auroral Wind         → SILENCE (6) [auroral_wind.lua]
    [1383] = { statusId = 4,   duration = 60  },  -- Glacier Splitter     → PARALYSIS (4), randomInt(30, 60) [glacier_splitter.lua]
    [1384] = { statusId = 3,   duration = 180 },  -- Disseverment         → POISON (3) [disseverment.lua]
    [1386] = { statusId = 7,   duration = 60  },  -- Medusa Javelin       → PETRIFICATION (7), randomInt(30, 60) [medusa_javelin.lua]
    [1445] = { statusId = 10,  duration = 15  },  -- Damnation Dive       → STUN (10) [damnation_dive.lua]
    [1449] = { statusId = 2,   duration = 60  },  -- Stupor Spores        → SLEEP_I (2), randomInt(15, 60) [stupor_spores.lua]
    [1467] = { statusId = 3,   duration = 180 },  -- Decayed Filament     → POISON (3) [decayed_filament.lua]
    [1468] = { statusId = 31,  duration = 60  },  -- Reactor Overheat     → PLAGUE (31), randomInt(30, 60) [reactor_overheat.lua]
    [1469] = { statusId = 6,   duration = 60  },  -- Reactor Overload     → SILENCE (6), randomInt(15, 60) [reactor_overload.lua]
    [1521] = { statusId = 12,  duration = 45  },  -- Armor Buster         → WEIGHT (12) [armor_buster.lua]
    [1524] = { statusId = 28,  duration = 10  },  -- Dissipation          → TERROR (28) [dissipation.lua]
    [1527] = { statusId = 149, duration = 60  },  -- Laser Shower         → DEFENSE_DOWN (149) [laser_shower.lua]
    [1529] = { statusId = 11,  duration = 15  },  -- Hyper Pulse          → BIND (11) [hyper_pulse.lua]
    [1530] = { statusId = 4,   duration = 120 },  -- Stun Cannon          → PARALYSIS (4) [stun_cannon.lua]
    [1533] = { statusId = 11,  duration = 30  },  -- Pile Pitch           → BIND (11) [pile_pitch.lua]
    [1697] = { statusId = 13,  duration = 60  },  -- Seaspray             → SLOW (13), randomInt(30, 60) [seaspray.lua]
    [1714] = { statusId = 10,  duration = 4   },  -- Wing Slap            → STUN (10) [wing_slap.lua]
    [1743] = { statusId = 7,   duration = 45  },  -- Rock Smash           → PETRIFICATION (7) [rock_smash.lua]
    [1758] = { statusId = 10,  duration = 4   },  -- Tail Slap            → STUN (10) [tail_slap.lua]
    [1780] = { statusId = 10,  duration = 30  },  -- Leaping Cleave       → STUN (10), calculateDuration(skill:getTP(), 15, 45) [leaping_cleave.lua]
    [1802] = { statusId = 7,   duration = 60  },  -- Sledgehammer         → PETRIFICATION (7) [sledgehammer.lua]
    [1804] = { statusId = 16,  duration = 60  },  -- Haymaker             → AMNESIA (16) [haymaker.lua]
    [1810] = { statusId = 10,  duration = 4   },  -- Tail Slap (alt)      → STUN (10) [tail_slap.lua]
    [1812] = { statusId = 11,  duration = 60  },  -- Pinning Shot         → BIND (11) [pinning_shot.lua]
    [1813] = { statusId = 7,   duration = 120 },  -- Calcifying Deluge    → PETRIFICATION (7) [calcifying_deluge.lua]
    [1828] = { statusId = 31,  duration = 60  },  -- Pyric Blast          → PLAGUE (31) [pyric_blast.lua]
    [1830] = { statusId = 4,   duration = 60  },  -- Polar Blast          → PARALYSIS (4) [polar_blast.lua]
    [1832] = { statusId = 12,  duration = 60  },  -- Barofield            → WEIGHT (12) [barofield.lua]
    [1896] = { statusId = 7,   duration = 45  },  -- Rock Smash (alt)     → PETRIFICATION (7) [rock_smash.lua]
    [1954] = { statusId = 134, duration = 30  },  -- Erosion Dust         → DIA (134) [erosion_dust.lua]
    [1998] = { statusId = 3,   duration = 45  },  -- Hane Fubuki          → POISON (3) [hane_fubuki.lua]
    [3854] = { statusId = 6,   duration = 30  },  -- Brain Crush (alt)    → SILENCE (6) [brain_crush.lua]
    [3861] = { statusId = 136, duration = 180 },  -- Bubble Shower (alt)  → STR_DOWN (136) [bubble_shower.lua]

    -- Multi-status skills (every status listed; see header)
    [319 ] = { { statusId = 13, duration = 60 }, { statusId = 3, duration = 60 },
               { statusId = 6, duration = 60 }, { statusId = 4, duration = 60 },
               { statusId = 11, duration = 60 }, { statusId = 5, duration = 60 },
               { statusId = 12, duration = 60 } },
               -- Bad Breath → SLOW (13), POISON (3), SILENCE (6), PARALYSIS (4), BIND (11), BLINDNESS (5), WEIGHT (12) [bad_breath.lua]
    [579 ] = { { statusId = 4, duration = 30 }, { statusId = 6, duration = 30 } },
               -- Choke Breath → PARALYSIS (4), SILENCE (6) [choke_breath.lua]
    [588 ] = { { statusId = 10, duration = 15 }, { statusId = 3, duration = 300 } },
               -- Death Trap → STUN (10), POISON (3) [death_trap.lua]
    [727 ] = { { statusId = 13, duration = 60 }, { statusId = 3, duration = 60 },
               { statusId = 6, duration = 60 }, { statusId = 4, duration = 60 },
               { statusId = 11, duration = 60 }, { statusId = 5, duration = 60 },
               { statusId = 12, duration = 60 } },
               -- Bad Breath (alt) → SLOW (13), POISON (3), SILENCE (6), PARALYSIS (4), BIND (11), BLINDNESS (5), WEIGHT (12) [bad_breath.lua]
    [821 ] = { { statusId = 13, duration = 120 }, { statusId = 6, duration = 120 } },
               -- Radiant Breath → SLOW (13), SILENCE (6) [radiant_breath.lua]
    [1106] = { { statusId = 13, duration = 120 }, { statusId = 2, duration = 30 } },
               -- Dice Slow → SLOW (13), SLEEP_I (2) [dice_slow.lua]
    [1220] = { { statusId = 6, duration = 60 }, { statusId = 5, duration = 90 } },
               -- Auroral Drape → SILENCE (6), BLINDNESS (5) [auroral_drape.lua]
    [1232] = { { statusId = 13, duration = 90 }, { statusId = 12, duration = 120 } },
               -- Murk → SLOW (13), WEIGHT (12) [murk.lua]
    [1252] = { { statusId = 9, duration = 180 }, { statusId = 2, duration = 120 },
               { statusId = 5, duration = 180 } },
               -- Shadow Spread → CURSE_I (9), SLEEP_I (2), BLINDNESS (5); SLEEP_I is 60s or 120s by mob pool [shadow_spread.lua]
    [1269] = { { statusId = 194, duration = 120 }, { statusId = 13, duration = 120 } },
               -- Chemical Bomb → ELEGY (194), SLOW (13) [chemical_bomb.lua]
    [1380] = { { statusId = 149, duration = 60 }, { statusId = 10, duration = 4 } },
               -- Impact Stream → DEFENSE_DOWN (149), STUN (10) [impact_stream.lua]
    [1448] = { { statusId = 5, duration = 30 }, { statusId = 6, duration = 30 } },
               -- Efflorescent Foetor → BLINDNESS (5), SILENCE (6) [efflorescent_foetor.lua]
    [1528] = { { statusId = 5, duration = 120 }, { statusId = 156, duration = 20 },
               { statusId = 6, duration = 60 } },
               -- Floodlight → BLINDNESS (5), FLASH (156), SILENCE (6) [floodlight.lua]
    [1730] = { { statusId = 149, duration = 120 }, { statusId = 167, duration = 120 } },
               -- Deadeye → DEFENSE_DOWN (149), MAGIC_DEF_DOWN (167) [deadeye.lua]
    [1745] = { { statusId = 149, duration = 30 }, { statusId = 167, duration = 30 } },
               -- Enervation → DEFENSE_DOWN (149), MAGIC_DEF_DOWN (167) [enervation.lua]
    [1800] = { { statusId = 31, duration = 60 }, { statusId = 3, duration = 60 },
               { statusId = 13, duration = 120 } },
               -- Miasma → PLAGUE (31), POISON (3), SLOW (13) [miasma.lua]
    [1807] = { { statusId = 4, duration = 120 }, { statusId = 5, duration = 120 },
               { statusId = 3, duration = 120 }, { statusId = 31, duration = 120 },
               { statusId = 11, duration = 120 }, { statusId = 6, duration = 120 },
               { statusId = 13, duration = 120 } },
               -- Pleiades Ray → PARALYSIS (4), BLINDNESS (5), POISON (3), PLAGUE (31), BIND (11), SILENCE (6), SLOW (13) [pleiades_ray.lua]
    [1836] = { { statusId = 9, duration = 420 }, { statusId = 3, duration = 60 } },
               -- Nerve Gas → CURSE_I (9), POISON (3) [nerve_gas.lua]
    [1898] = { { statusId = 149, duration = 30 }, { statusId = 167, duration = 30 } },
               -- Enervation (alt) → DEFENSE_DOWN (149), MAGIC_DEF_DOWN (167) [enervation.lua]
    [1978] = { { statusId = 31, duration = 45 }, { statusId = 6, duration = 60 },
               { statusId = 4, duration = 60 } },
               -- Abominable Belch → PLAGUE (31), SILENCE (6), PARALYSIS (4) [abominable_belch.lua]
    [2028] = { { statusId = 4, duration = 60 }, { statusId = 10, duration = 10 } },
               -- Fulmination → PARALYSIS (4), STUN (10) [fulmination.lua]
    [2033] = { { statusId = 11, duration = 60 }, { statusId = 6, duration = 60 },
               { statusId = 16, duration = 60 } },
               -- Choke Chain → BIND (11), SILENCE (6), AMNESIA (16) [choke_chain.lua]
    [2118] = { { statusId = 146, duration = 60 }, { statusId = 147, duration = 60 },
               { statusId = 149, duration = 60 } },
               -- Bilgestorm → ACCURACY_DOWN (146), ATTACK_DOWN (147), DEFENSE_DOWN (149) [bilgestorm.lua]
    [2185] = { { statusId = 147, duration = 120 }, { statusId = 149, duration = 120 } },
               -- Corrosive Ooze → ATTACK_DOWN (147), DEFENSE_DOWN (149) [corrosive_ooze.lua]
    [2189] = { { statusId = 6, duration = 180 }, { statusId = 5, duration = 180 } },
               -- Aeolian Void → SILENCE (6), BLINDNESS (5) [aeolian_void.lua]
    [2629] = { { statusId = 167, duration = 60 }, { statusId = 149, duration = 60 } },
               -- Benthic Typhoon → MAGIC_DEF_DOWN (167), DEFENSE_DOWN (149) [benthic_typhoon.lua]
}
