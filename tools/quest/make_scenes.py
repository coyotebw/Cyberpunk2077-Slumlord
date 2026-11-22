#!/usr/bin/env python3
"""Slumlord's in-person boss encounters as the game's own quest files (design doc 13).

  Conversation Overtime, Las Palapas Motel (Finger, design doc 4.9): slumlord\\quest\\slumlord_motel.questphase
  Million Dollar Baby, Harbor Safehouse (Oshima, design doc 4.8): slumlord\\quest\\slumlord_harbor.questphase

Each root phase is started once per save by ArchiveXL (quest.phases) and loops: wait for its "ready" fact and V in
its trigger area, run the encounter in an inline phase (leaving it ends everything inside), clean up, wait again.
Slumlord's scripts (Motel.reds, Fight.reds) talk to the phases through facts:
  slumlord_<key>_ready   script -> quest  1 while the encounter may start
  slumlord_<key>_scene   quest -> script  1 while the encounter is up
  slumlord_<key>_fight   quest -> script  1 fighting, 2 the gang is down
  slumlord_<key>_won     quest -> script  1 when won (the motel keeps its first name, slumlord_co_motel_won)
  slumlord_<key>_abort   script -> quest  1 ends the encounter now
  slumlord_fc_fled       quest -> script  1 when Oshima runs (the script does his Sandevistan sprint)

Writes WolvenKit raw JSON under wolvenkit/source/raw/slumlord (phases, scenes, sectors, subtitles, onscreens,
streaming block) and loose files: the Audioware dialogs block, SceneLines.reds, the TweakXL character records.
Build: tools/quest/build_scenes.sh.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qgraph import Graph, c_fact, c_and, c_or, c_trigger, c_player_combat, c_attacked, c_spawned, c_killed, c_near, c_delay  # noqa: E402
from encounter import (Encounter, Line, build_sector, update_block, build_scene, spawn_node, attitude, reaction,  # noqa: E402
                       mortality, kill, attack_v, null_area, write_phase, build_texts, build_audio, build_lengths,
                       build_records)

WS_ARMS = r"base\workspots\main_characters\ripperdoc\ground\ripperdoc__stand_ground_arms_crossed__talk__01.workspot"
WS_STAND = r"base\workspots\common\ground\generic__stand_ground_arms_crossed__stand_around__02.workspot"
WS_SMOKE = r"base\workspots\common\ground\generic__stand_ground_cigarette__smoke__01.workspot"
WS_KNOCK = r"base\workspots\common\door\generic__stand_door_lean_front__knock__01.workspot"
WS_WELD = r"base\workspots\construction_site\generic__kneel_welder__use__01.workspot"
WS_ARGUE = r"base\workspots\quest\side_quests\sq024\sq024_05_big_race\sq024__sampson__stand__argue__01.workspot"


# ================================================================ Conversation Overtime: the motel

def motel():
    e = Encounter("co", "motel", r"slumlord\world\sectors\slumlord_motel.streamingsector",
                  r"slumlord\quest\slumlord_motel.questphase")
    # Spots captured in game 2026-11-19/20 (CET "Capture spot", motel_* names). Yaw = facing, degrees.
    finger = (-1082.31, -1525.95, 25.78, -42.8)
    goon = (-1074.25, -1527.08, 25.78, 1.4)
    e.spots["slumlord_co_ws_finger"] = (*finger, WS_ARMS)
    e.spots["slumlord_co_ws_hide"] = (-1098.00, -1537.78, 25.76, -42.8, WS_STAND)
    e.spots["slumlord_co_ws_leave"] = (-1057.27, -1498.45, 25.75, 43.4, WS_STAND)   # the motel entrance
    rad = math.radians(goon[3])
    right = (math.cos(rad), math.sin(rad))     # across the way they face
    for i in range(3):
        off = 1.3 * (i - 1)
        e.spots[f"slumlord_co_ws_goon_{i + 1}"] = (goon[0] + right[0] * off, goon[1] + right[1] * off, goon[2], goon[3],
                                                   WS_STAND if i == 1 else WS_SMOKE)
    goons = [("goon_1", "Character.slumlord_co_goon_1", "Character.sixthstreet_hooligan_ranged1_saratoga_wa"),
             ("goon_2", "Character.slumlord_co_goon_2", "Character.sixthstreet_hooligan_ranged1_nova_wa"),
             ("goon_3", "Character.slumlord_co_goon_3", "Character.sixthstreet_prepers3_shotgun3_carnage_ma_rare")]
    e.records["Character.slumlord_quentin_finger"] = ("Character.sixthstreet_prepers3_shotgun3_carnage_ma_rare",
                                                      "slumlord-finger-name")
    for _, rec, base in goons:
        e.records[rec] = (base, None)
    e.communities["slumlord_co_com_finger"] = [("finger", "Character.slumlord_quentin_finger",
                                                {"standoff": "slumlord_co_ws_finger", "hide": "slumlord_co_ws_hide",
                                                 "leave": "slumlord_co_ws_leave"})]
    e.communities["slumlord_co_com_goons"] = [(n, rec, {"standoff": f"slumlord_co_ws_{n}"}) for n, rec, _ in goons]
    e.marker = ("slumlord_co_sm", *finger)
    e.area = ("slumlord_co_tr_area", finger[0], finger[1], finger[2] - 15.0, 140.0, 60.0)
    e.null = ("slumlord_co_crowd_null", (finger[0] + goon[0]) / 2, (finger[1] + goon[1]) / 2, finger[2], 45.0)
    e.onscreens = {"slumlord-finger-name": "Quentin Finger"}
    e.standoff = [
        Line("slumlord_co_standoff_01", "npc", "Well, look who showed. Pretty ride, huh? Be a shame if somethin' happened to it.", (6.43, 6.43), "slumlord_finger_motel_01"),
        Line("slumlord_co_standoff_02", "v", "Not actually mine.", (1.56, 1.56), ("slumlord_v_motel_01_f", "slumlord_v_motel_01_m")),
        Line("slumlord_co_standoff_03", "npc", "Uh-huh. Here's the deal: you sign over Santo to me, and you ride outta here on your pretty little bike.", (6.75, 6.75), "slumlord_finger_motel_02"),
        Line("slumlord_co_standoff_04", "v", "I'm serious.", (1.11, 1.10), ("slumlord_v_motel_02_f", "slumlord_v_motel_02_m")),
        Line("slumlord_co_standoff_05", "npc", "Don't play dumb with me! My boys lifted it right outta your— ...Whose bike IS this?", (6.51, 6.51), "slumlord_finger_motel_03"),
        Line("slumlord_co_standoff_06", "npc", "Fuck it. Waste 'em!", (1.71, 1.71), "slumlord_finger_motel_04"),
    ]
    e.truce = [
        Line("slumlord_co_truce_01", "npc", "Okay, okay! Truce, truce!", (2.14, 2.14), "slumlord_finger_truce_01"),
        Line("slumlord_co_truce_02", "npc", "Look, these boys, what's left of 'em, they're good muscle. They're yours. Just let me walk.", (6.01, 6.01), "slumlord_finger_truce_02"),
        Line("slumlord_co_truce_03", "v", "Deal.", (0.70, 0.63), ("slumlord_v_truce_01_f", "slumlord_v_truce_01_m")),
        Line("slumlord_co_truce_04", "npc", "Pleasure doin' business, Mr. Landlord.", (3.76, 3.76), "slumlord_finger_truce_03"),
    ]
    e.lines = e.standoff + e.truce
    return e


def motel_phase(enc):
    scene_standoff = r"slumlord\quest\scenes\slumlord_co_standoff.scene"
    scene_truce = r"slumlord\quest\scenes\slumlord_co_truce.scene"
    com_f, com_g = enc.ref("slumlord_co_com_finger"), enc.ref("slumlord_co_com_goons")
    area, null, sm = enc.ref("slumlord_co_tr_area"), enc.ref("slumlord_co_crowd_null"), enc.ref("slumlord_co_sm")
    goons = [n for n, _, _ in enc.communities["slumlord_co_com_goons"]]
    build_scene(scene_standoff, enc.standoff, ("finger", com_f, "finger"), interrupt_on=(com_g, com_f))
    build_scene(scene_truce, enc.truce, ("finger", com_f, "finger"))
    F = enc.fact
    won_fact = "slumlord_co_motel_won"

    e = Graph()
    e_in = e.input()
    started = e.chain(e_in, e.set_fact(F("scene"), 1), e.set_fact(F("fight"), 0), null_area(e, null, True),
                      spawn_node(e, [("Activate", com_f, "finger", "standoff")] +
                                 [("Activate", com_g, n, "standoff") for n in goons]),
                      e.pause(c_and(c_spawned(com_f, ["finger"]), c_spawned(com_g, (), count=len(goons)))),
                      attitude(e, com_g, (), "friendly"), attitude(e, com_f, ["finger"], "friendly"),
                      reaction(e, com_g, (), "ReactionPresets.NoReaction"),
                      reaction(e, com_f, ["finger"], "ReactionPresets.NoReaction"),
                      mortality(e, com_f, ["finger"], "Invulnerable"))
    early = e.pause(c_or(c_attacked(com_g), c_attacked(com_f), c_player_combat()))
    talk = e.pause(c_and(c_near(com_f, ["finger"], 10.0), c_fact(F("fight"), "Equal", 0)))
    e.link(started, "Out", early, "In")
    e.link(started, "Out", talk, "In")
    standoff = e.scene(scene_standoff, sm, ("start",), ("end",))
    e.link(talk, "Out", standoff, "start")
    # Both routes can arrive (V opens fire mid-talk: the scene ends and the early check fires too); only the
    # first one starts the fight, since it sets the fight fact before the second is checked.
    fight = e.hub(2)
    e.link(early, "Out", fight, "In1")
    e.link(standoff, "end", fight, "In2")
    first = e.branch(c_fact(F("fight"), "Equal", 0))
    e.link(fight, "Out1", first, "In")
    fighting = e.set_fact(F("fight"), 1)
    e.link(first, "True", fighting, "In")
    hostile = e.chain(fighting, attitude(e, com_g, (), "hostile"),
                      reaction(e, com_g, (), "ReactionPresets.Ganger_Aggressive"))
    for n in goons:
        e.link(hostile, "Out", attack_v(e, com_g, n), "In")
    e.link(hostile, "Out", spawn_node(e, [("Activate", com_f, "finger", "hide")]), "In")
    down = e.pause(c_killed(com_g, (), count=len(goons)))
    e.link(hostile, "Out", down, "In")
    for n in goons:
        e.link(down, "Out", kill(e, com_g, n), "In")
    after = e.chain(down, e.set_fact(F("fight"), 2), e.pause(c_player_combat(inverted=True)),
                    reaction(e, com_f, ["finger"], "ReactionPresets.NoReaction"),
                    spawn_node(e, [("Activate", com_f, "finger", "standoff")]),
                    e.pause(c_near(com_f, ["finger"], 12.0)))
    truce = e.scene(scene_truce, sm, ("start",), ("end",))
    e.link(after, "Out", truce, "start")
    won = e.set_fact(won_fact, 1)
    e.link(truce, "end", won, "In")
    e.chain(won, spawn_node(e, [("Activate", com_f, "finger", "leave")]),
            e.pause(c_or(c_delay(40.0), c_trigger(area, "IsOutside"))), e.output("Out1"))
    abort = e.pause(c_or(c_and(c_trigger(area, "IsOutside"), c_fact(won_fact, "Equal", 0)),
                         c_fact(F("abort"), "GreaterOrEqual", 1)))
    e.link(e_in, "Out", abort, "In")
    e.link(abort, "Out", e.output("Out2"), "In")
    write_phase(enc, root(enc, e, [com_g, com_f], extra_resets=()))


# ================================================================ Million Dollar Baby: the Harbor Safehouse

def harbor():
    e = Encounter("fc", "harbor", r"slumlord\world\sectors\slumlord_harbor.streamingsector",
                  r"slumlord\quest\slumlord_harbor.questphase")
    # Spots captured in game 2026-11-18 (Fight.reds SpotPos/SpotYaw): the gangers, then Oshima.
    door = (-2013.79, 2617.27, 18.13)           # wat_harbor_safehouse (Positions.reds)
    oshima = (-2014.41, 2612.43, 18.17, -15.5)
    gangers = [("knocker", (-2014.59, 2619.14, 18.36, 28.7), WS_KNOCK, "Character.maelstrom_grunt2_melee2_machete_ma"),
               ("welder", (-2012.98, 2619.79, 18.36, 100.9), WS_WELD, "Character.maelstrom_grunt1_ranged1_lexington_ma"),
               ("smoker", (-2014.85, 2613.56, 18.15, -106.2), WS_SMOKE, "Character.maelstrom_grunt2_ranged2_ajax_wa"),
               ("talker", (-2013.11, 2614.17, 18.15, 130.1), WS_ARGUE, "Character.maelstrom_grunt1_ranged1_copperhead_ma")]
    for name, pos, ws, base in gangers:
        e.spots[f"slumlord_fc_ws_{name}"] = (*pos, ws)
        e.records[f"Character.slumlord_fc_{name}"] = (base, None)
    e.spots["slumlord_fc_ws_oshima"] = (*oshima, WS_ARMS)
    e.communities["slumlord_fc_com_oshima"] = [("oshima", "Character.q005_hideyoshi_oshima",
                                                {"standoff": "slumlord_fc_ws_oshima"})]
    e.communities["slumlord_fc_com_gang"] = [(n, f"Character.slumlord_fc_{n}", {"standoff": f"slumlord_fc_ws_{n}"})
                                             for n, _, _, _ in gangers]
    e.marker = ("slumlord_fc_sm", *oshima)
    e.area = ("slumlord_fc_tr_area", door[0], door[1], door[2] - 15.0, 150.0, 60.0)
    e.null = ("slumlord_fc_crowd_null", door[0], door[1], door[2], 30.0)
    e.onscreens = {}
    e.talk = [
        Line("slumlord_fc_talk_01", "npc", "V. I told you we'd be seeing each other again.", (2.30, 2.30), "slumlord_oshima_fight_01"),
        Line("slumlord_fc_talk_02", "v", "What the fuck…?", (1.89, 1.85), ("slumlord_v_fight_01_f", "slumlord_v_fight_01_m")),
        Line("slumlord_fc_talk_03", "npc", "I need this place to film a scene for Death Stranding 12. Now get lost, you're ruining the shot.", (8.40, 8.40), "slumlord_oshima_fight_02"),
        Line("slumlord_fc_talk_04", "npc", ("Kill her!", "Kill him!"), (1.28, 1.28), "slumlord_oshima_fight_03"),
    ]
    e.flee = [
        Line("slumlord_fc_flee_01", "npc", "This isn't over, V!", (2.63, 2.63), "slumlord_oshima_flee_01"),
    ]
    e.lines = e.talk + e.flee
    return e


def harbor_phase(enc):
    scene_talk = r"slumlord\quest\scenes\slumlord_fc_talk.scene"
    scene_flee = r"slumlord\quest\scenes\slumlord_fc_flee.scene"
    com_o, com_g = enc.ref("slumlord_fc_com_oshima"), enc.ref("slumlord_fc_com_gang")
    area, null, sm = enc.ref("slumlord_fc_tr_area"), enc.ref("slumlord_fc_crowd_null"), enc.ref("slumlord_fc_sm")
    gang = [n for n, _, _ in enc.communities["slumlord_fc_com_gang"]]
    build_scene(scene_talk, enc.talk, ("oshima", com_o, "oshima"), interrupt_on=(com_g, com_o))
    build_scene(scene_flee, enc.flee, ("oshima", com_o, "oshima"))
    F = enc.fact

    e = Graph()
    e_in = e.input()
    # Clear first (the script removes the Maelstromers that idle at the door while scene=1 and fight=0), then spawn.
    started = e.chain(e_in, e.set_fact(F("scene"), 1), e.set_fact(F("fight"), 0), e.set_fact(F("fled"), 0),
                      null_area(e, null, True), e.pause(c_delay(2.0)),
                      spawn_node(e, [("Activate", com_o, "oshima", "standoff")] +
                                 [("Activate", com_g, n, "standoff") for n in gang]),
                      e.pause(c_and(c_spawned(com_o, ["oshima"]), c_spawned(com_g, (), count=len(gang)))),
                      attitude(e, com_g, (), "friendly"), attitude(e, com_o, ["oshima"], "friendly"),
                      reaction(e, com_g, (), "ReactionPresets.NoReaction"),
                      reaction(e, com_o, ["oshima"], "ReactionPresets.NoReaction"),
                      mortality(e, com_o, ["oshima"], "Invulnerable"))
    early = e.pause(c_or(c_attacked(com_g), c_attacked(com_o), c_player_combat()))
    talk = e.pause(c_and(c_near(com_o, ["oshima"], 12.0), c_fact(F("fight"), "Equal", 0)))
    e.link(started, "Out", early, "In")
    e.link(started, "Out", talk, "In")
    scene = e.scene(scene_talk, sm, ("start",), ("end",))
    e.link(talk, "Out", scene, "start")
    fight = e.hub(2)
    e.link(early, "Out", fight, "In1")
    e.link(scene, "end", fight, "In2")
    first = e.branch(c_fact(F("fight"), "Equal", 0))
    e.link(fight, "Out1", first, "In")
    fighting = e.set_fact(F("fight"), 1)
    e.link(first, "True", fighting, "In")
    hostile = e.chain(fighting, attitude(e, com_g, (), "hostile"),
                      reaction(e, com_g, (), "ReactionPresets.Ganger_Aggressive"))
    for n in gang:
        e.link(hostile, "Out", attack_v(e, com_g, n), "In")
    # Oshima dodges (script) until 16 s in or the first Maelstromer drops, then shouts and runs (script sprint),
    # and is gone 8 s later.
    run_when = e.pause(c_or(c_delay(16.0), c_killed(com_g, (), count=1)))
    e.link(hostile, "Out", run_when, "In")
    runs = e.chain(run_when, e.set_fact(F("fled"), 1))
    e.link(runs, "Out", e.scene(scene_flee, sm, ("start",), ("end",)), "start")
    e.chain(runs, e.pause(c_delay(8.0)), spawn_node(e, [("Deactivate", com_o, "oshima", None)]))
    down = e.pause(c_killed(com_g, (), count=len(gang)))
    e.link(hostile, "Out", down, "In")
    for n in gang:
        e.link(down, "Out", kill(e, com_g, n), "In")
    e.chain(down, e.set_fact(F("fight"), 2), e.set_fact(F("won"), 1),
            e.pause(c_or(c_delay(30.0), c_trigger(area, "IsOutside"))), e.output("Out1"))
    abort = e.pause(c_or(c_and(c_trigger(area, "IsOutside"), c_fact(F("won"), "Equal", 0)),
                         c_fact(F("abort"), "GreaterOrEqual", 1)))
    e.link(e_in, "Out", abort, "In")
    e.link(abort, "Out", e.output("Out2"), "In")
    write_phase(enc, root(enc, e, [com_g, com_o], extra_resets=(F("fled"),)))


# ================================================================ shared root

def root(enc, inner, communities, extra_resets):
    """Wait for the ready fact and V in the area, run `inner`, clean up whichever way it ended, wait again."""
    F = enc.fact
    g = Graph()
    g_in = g.input()
    wait = g.pause(c_and(c_fact(F("ready"), "GreaterOrEqual", 1), c_trigger(enc.ref(enc.area[0]), "IsInside")))
    g.link(g_in, "Out", wait, "In")
    enc_node = g.phase(inner, inputs=("In1",), outputs=("Out1", "Out2"))
    g.link(wait, "Out", enc_node, "In1")
    hub = g.hub(2)
    g.link(enc_node, "Out1", hub, "In1")
    g.link(enc_node, "Out2", hub, "In2")
    first = null_area(g, enc.ref(enc.null[0]), False)
    g.link(hub, "Out1", first, "In")
    resets = [g.set_fact(F("fight"), 0), g.set_fact(F("scene"), 0), g.set_fact(F("abort"), 0)]
    resets += [g.set_fact(f, 0) for f in extra_resets]
    last = g.chain(first, spawn_node(g, [("Deactivate", c, None, None) for c in communities]), *resets,
                   g.pause(c_delay(5.0)))
    g.link(last, "Out", wait, "In")
    return g


def main():
    encounters = [motel(), harbor()]
    for enc in encounters:
        build_sector(enc)
    update_block([enc.sector_path for enc in encounters])
    motel_phase(encounters[0])
    harbor_phase(encounters[1])
    lines = [line for enc in encounters for line in enc.lines]
    onscreens = {k: v for enc in encounters for k, v in enc.onscreens.items()}
    records = {k: v for enc in encounters for k, v in enc.records.items()}
    build_texts(lines, onscreens)
    build_audio(lines)
    build_lengths(lines)
    build_records(records)
    for line in lines:
        print(f"{line.key}: {line.id}")


if __name__ == "__main__":
    main()
