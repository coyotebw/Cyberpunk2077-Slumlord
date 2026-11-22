#!/usr/bin/env python3
"""Conversation Overtime's motel scene as the game's own quest files (design doc 4.9, 13).

Writes WolvenKit raw JSON under wolvenkit/source/raw/slumlord and the loose files it needs:
  quest/slumlord_motel.questphase        root phase, started once per save by ArchiveXL (quest.phases), loops forever
  quest/scenes/slumlord_co_standoff.scene Finger's pitch and V's answers, then "Waste 'em!"
  quest/scenes/slumlord_co_truce.scene    the truce after the goons are down
  world/sectors/slumlord_motel.streamingsector  AI spots, communities, trigger area, crowd null area, scene marker
  world/slumlord.streamingblock          (descriptor added)
  localization/en-us/subtitles/*.json    the scene lines' subtitles and their map
  localization/en-us.json                onscreen "Quentin Finger" (Finger's record's display name)
  mod/r6/audioware/Slumlord/slumlord.yml  dialogs: each scene line's audio, keyed by its string id
  mod/r6/scripts/Slumlord/MotelLines.reds line lengths for the game's voice-over length table (Codeware)
  mod/r6/tweaks/Slumlord/slumlord_finger.yaml  Character.slumlord_quentin_finger (TweakXL)
Then: cp77tools convert d on the JSON, copy the CR2W files to wolvenkit/source/archive, pack (README "Build").

Slumlord talks to the phase through facts:
  slumlord_co_ready      script -> quest  1 while V should meet Finger now (stage 3 and night)
  slumlord_co_scene      quest -> script  1 while the encounter is up (script clears bystanders, spawns the bike)
  slumlord_co_fight      quest -> script  1 fighting, 2 goons down (script switches objectives)
  slumlord_co_motel_won  quest -> script  1 after the truce (script runs SlumlordFinger.Win)
  slumlord_co_abort      script -> quest  1 ends the encounter now (debug, or the quest left the motel stage)
"""
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qgraph import (H, CN, NR, TDB, RES, V3, V4, ENT, Graph, write, c_fact, c_and, c_or, c_trigger,  # noqa: E402
                    c_player_combat, c_attacked, c_spawned, c_killed, c_near, c_delay)

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "wolvenkit/source/raw/slumlord"
MOD = ROOT / "mod"

QUEST_PATH = r"slumlord\quest\slumlord_motel.questphase"
SCENE_STANDOFF = r"slumlord\quest\scenes\slumlord_co_standoff.scene"
SCENE_TRUCE = r"slumlord\quest\scenes\slumlord_co_truce.scene"
SECTOR_PATH = r"slumlord\world\sectors\slumlord_motel.streamingsector"
SUBS_PATH = r"slumlord\localization\en-us\subtitles\slumlord_subtitles.json"
SUBMAP_PATH = r"slumlord\localization\en-us\subtitles\slumlord_subtitle_map.json"

BASE = "$/slumlord/motel/#"
COM_FINGER = BASE + "slumlord_co_com_finger"
COM_GOONS = BASE + "slumlord_co_com_goons"
TR_AREA = BASE + "slumlord_co_tr_area"
NULL_AREA = BASE + "slumlord_co_crowd_null"
SM = BASE + "slumlord_co_sm"

FINGER_RECORD = "Character.slumlord_quentin_finger"   # TweakXL clone of the stand-in below, named "Quentin Finger"
FINGER_BASE = "Character.sixthstreet_prepers3_shotgun3_carnage_ma_rare"
GOONS = [("goon_1", "Character.sixthstreet_hooligan_ranged1_saratoga_wa"),
         ("goon_2", "Character.sixthstreet_hooligan_ranged1_nova_wa"),
         ("goon_3", "Character.sixthstreet_prepers3_shotgun3_carnage_ma_rare")]

WS_ARMS = r"base\workspots\main_characters\ripperdoc\ground\ripperdoc__stand_ground_arms_crossed__talk__01.workspot"
WS_STAND = r"base\workspots\common\ground\generic__stand_ground_arms_crossed__stand_around__02.workspot"
WS_SMOKE = r"base\workspots\common\ground\generic__stand_ground_cigarette__smoke__01.workspot"

# Spots captured in game 2026-11-19/20 (CET "Capture spot", motel_* names). Yaw = facing, degrees.
FINGER_SPOT = (-1082.31, -1525.95, 25.78, -42.8)
GOON_SPOT = (-1074.25, -1527.08, 25.78, 1.4)
HIDE_SPOT = (-1098.00, -1537.78, 25.76, -42.8)
LEAVE_SPOT = (-1057.27, -1498.45, 25.75, 43.4)     # the motel entrance, facing out
GOON_SPACING = 1.3

TALK_METERS = 10.0
TRUCE_METERS = 12.0
AREA_HALF = 140.0          # activation/leave square around Finger's spot
NULL_HALF = 45.0           # crowd-free square during the encounter

# Scene lines: key, speaker ("finger" or "v"), text, seconds (female, male), audio (one file, or (female, male)).
STANDOFF = [
    ("slumlord_co_standoff_01", "finger", "Well, look who showed. Pretty ride, huh? Be a shame if somethin' happened to it.", (6.43, 6.43), "slumlord_finger_motel_01"),
    ("slumlord_co_standoff_02", "v", "Not actually mine.", (1.56, 1.56), ("slumlord_v_motel_01_f", "slumlord_v_motel_01_m")),
    ("slumlord_co_standoff_03", "finger", "Uh-huh. Here's the deal: you sign over Santo to me, and you ride outta here on your pretty little bike.", (6.75, 6.75), "slumlord_finger_motel_02"),
    ("slumlord_co_standoff_04", "v", "I'm serious.", (1.11, 1.10), ("slumlord_v_motel_02_f", "slumlord_v_motel_02_m")),
    ("slumlord_co_standoff_05", "finger", "Don't play dumb with me! My boys lifted it right outta your— ...Whose bike IS this?", (6.51, 6.51), "slumlord_finger_motel_03"),
    ("slumlord_co_standoff_06", "finger", "Fuck it. Waste 'em!", (1.71, 1.71), "slumlord_finger_motel_04"),
]
TRUCE = [
    ("slumlord_co_truce_01", "finger", "Okay, okay! Truce, truce!", (2.14, 2.14), "slumlord_finger_truce_01"),
    ("slumlord_co_truce_02", "finger", "Look, these boys, what's left of 'em, they're good muscle. They're yours. Just let me walk.", (6.01, 6.01), "slumlord_finger_truce_02"),
    ("slumlord_co_truce_03", "v", "Deal.", (0.70, 0.63), ("slumlord_v_truce_01_f", "slumlord_v_truce_01_m")),
    ("slumlord_co_truce_04", "finger", "Pleasure doin' business, Mr. Landlord.", (3.76, 3.76), "slumlord_finger_truce_03"),
]
GAP = 0.45   # seconds between lines


def fnv1a64(s):
    h = 0xcbf29ce484222325
    for c in s.encode():
        h ^= c
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def node_id(ref):
    """Global node id of a NodeRef: FNV-1a 64 of the path with the '#' removed (checked against vanilla)."""
    return fnv1a64(ref.replace("#", ""))


def ruid(key):
    """String id of a scene line (subtitle, Audioware dialog, line length): stable, below 2^63."""
    return fnv1a64("slumlord:" + key) & 0x7FFFFFFFFFFFFFFF


def quat(yaw):
    h = math.radians(yaw) / 2
    return {"$type": "Quaternion", "i": 0, "j": 0, "k": math.sin(h), "r": math.cos(h)}


def goon_spots():
    x, y, z, yaw = GOON_SPOT
    rad = math.radians(yaw)
    right = (math.cos(rad), math.sin(rad))    # across the way they face (forward = (-sin, cos))
    return [(x + right[0] * GOON_SPACING * (i - 1), y + right[1] * GOON_SPACING * (i - 1), z, yaw) for i in range(3)]


# ---------------------------------------------------------------- world sector

def setup_info(ref, pos, yaw=0.0, scale=(1, 1, 1), distance=200.0, flags="FLAG_AllowForceStreamIn, FLAG_Quest", idx=0):
    x, y, z = pos
    return {"$type": "worldCompiledNodeInstanceSetupInfo", "dataGroup": "Base",
            "externalInplaceResourceHash": RES(None, "Default"),
            "globalNodeId": {"$type": "worldGlobalNodeID", "hash": str(node_id(ref) if ref else 0)},
            "instanceIndex": 4294967295, "nodeFlags": flags, "nodeIdx": str(idx),
            "patchedNode": NR(None), "preboostStreamingRefPoint": V3(x, y, z),
            "proxyMeshId": {"$type": "worldGlobalNodeID", "hash": "0"}, "scale": V3(*scale),
            "secondaryRefPointDistance": 3.40282347e+38, "secondaryRefPointPosition": V3(0, 0, 0),
            "streamingDistance": distance, "streamingPriority": "1", "streamingRefPoint": V3(x, y, z),
            "todvisMask": "0",
            "transform": {"$type": "Transform", "orientation": quat(yaw), "position": V4(x, y, z)}}


def outline(hx, hy, z0, height):
    """AreaShapeOutline: four corners in local meters; the packed buffer is what the game reads."""
    import base64
    import struct
    pts = [(-hx, -hy, z0), (hx, -hy, z0), (hx, hy, z0), (-hx, hy, z0)]
    buf = struct.pack("<i", 4) + b"".join(struct.pack("<4f", x, y, z, 1.0) for x, y, z in pts) + struct.pack("<f", height)
    return H({"$type": "AreaShapeOutline", "buffer": base64.b64encode(buf).decode(), "height": height,
              "points": [V3(x, y, z) for x, y, z in pts]})


def ai_spot(name, workspot):
    return {"$type": "worldAISpotNode", "crowdBlacklist": {"$type": "redTagList", "tags": []},
            "crowdWhitelist": {"$type": "redTagList", "tags": []}, "debugName": CN("{" + name + "}"),
            "disableBumps": 0, "isHostOnly": 0, "isVisibleInGame": 1, "isWorkspotInfinite": 1, "isWorkspotStatic": 0,
            "lookAtTarget": NR(None), "markings": [], "proxyScale": None, "sourcePrefabHash": "0",
            "spot": H({"$type": "AIActionSpot", "ActorBodytypeE3": "Undefined", "clippingSpaceOrientation": 180,
                       "clippingSpaceRange": 120, "enabledWhenMasterOccupied": 0, "masterNodeRef": NR(None),
                       "resource": RES(workspot), "snapToGround": 1, "useClippingSpace": 0}),
            "spotDef": None, "tag": "None", "tagExt": "None", "useCrowdBlacklist": 0, "useCrowdWhitelist": 0}


def fixed(v):
    return {"$type": "FixedPoint", "Bits": int(round(v * 131072))}


SPOTS = {}   # name -> (x, y, z, yaw, workspot)


def build_sector():
    SPOTS.clear()
    SPOTS["slumlord_co_ws_finger"] = (*FINGER_SPOT, WS_ARMS)
    SPOTS["slumlord_co_ws_hide"] = (*HIDE_SPOT, WS_STAND)
    SPOTS["slumlord_co_ws_leave"] = (*LEAVE_SPOT, WS_STAND)
    for i, (x, y, z, yaw) in enumerate(goon_spots()):
        SPOTS[f"slumlord_co_ws_goon_{i + 1}"] = (x, y, z, yaw, WS_SMOKE if i != 1 else WS_STAND)

    nodes, data, refs = [], [], []

    def add(node, ref, pos, yaw=0.0, scale=(1, 1, 1), distance=200.0):
        idx = len(nodes)
        nodes.append(H(node))
        data.append(setup_info(ref, pos, yaw, scale, distance, idx=idx))
        if ref:
            refs.append(NR(ref))

    for name, (x, y, z, yaw, ws) in SPOTS.items():
        add(ai_spot(name, ws), BASE + name, (x, y, z), yaw)

    fx, fy, fz, fyaw = FINGER_SPOT
    add({"$type": "worldStaticMarkerNode", "data": H({"$type": "scnSceneMarker", "markers": [], "workspotMarkers": []}),
         "debugName": CN("{slumlord_co_sm}"), "isEnabled": 1, "isHostOnly": 0, "isVisibleInGame": 1,
         "proxyScale": None, "sourcePrefabHash": "0", "tag": "None", "tagExt": "None",
         "tags": {"$type": "redTagList", "tags": []}}, SM, (fx, fy, fz), fyaw)
    add({"$type": "worldTriggerAreaNode", "color": {"$type": "Color", "Alpha": 128, "Blue": 160, "Green": 160, "Red": 255},
         "debugName": CN("{slumlord_co_tr_area}"), "isHostOnly": 0, "isVisibleInGame": 1,
         "notifiers": [H({"$type": "questTriggerNotifier_Quest", "excludeChannels": 0, "includeChannels": "TC_Default",
                          "isEnabled": 1})],
         "outline": outline(AREA_HALF, AREA_HALF, 0.0, 60.0), "proxyScale": None, "sourcePrefabHash": "0",
         "tag": "None", "tagExt": "None"}, TR_AREA, (fx, fy, fz - 15.0), 0.0, distance=AREA_HALF * 3)
    cx, cy = (fx + GOON_SPOT[0]) / 2, (fy + GOON_SPOT[1]) / 2
    add({"$type": "worldCrowdNullAreaNode", "color": {"$type": "Color", "Alpha": 128, "Blue": 32, "Green": 32, "Red": 32},
         "debugName": CN("{slumlord_co_crowd_null}"), "IsForBlockade": 0, "isHostOnly": 0, "isVisibleInGame": 1,
         "outline": outline(NULL_HALF, NULL_HALF, -5.0, 25.0), "permanentlyEnabledByDefault": 0, "proxyScale": None,
         "sourcePrefabHash": "0", "tag": "None", "tagExt": "None"}, NULL_AREA, (cx, cy, fz), 0.0, distance=NULL_HALF * 6)

    # Communities: Finger (three phases: standoff, hide, leave) and the goons (standoff).
    finger_entries = [("finger", FINGER_RECORD, {"standoff": "slumlord_co_ws_finger", "hide": "slumlord_co_ws_hide",
                                                 "leave": "slumlord_co_ws_leave"})]
    goon_entries = [(name, rec, {"standoff": f"slumlord_co_ws_{name}"}) for name, rec in GOONS]

    def template(entries):
        out = []
        for name, rec, phases in entries:
            out.append(H({"$type": "communitySpawnEntry", "characterRecordId": TDB(rec), "entryName": CN(name),
                          "initializers": [], "spawnInView": "default__true_",
                          "phases": [H({"$type": "communitySpawnPhase", "alwaysSpawned": "default__false_",
                                        "appearances": [], "phaseName": CN(ph), "prefetchAppearance": 0,
                                        "timePeriods": [{"$type": "communityPhaseTimePeriod", "categories": [],
                                                         "hour": "Day", "isSequence": 0, "markings": [], "quantity": 1,
                                                         "spotNodeRefs": [NR(BASE + spot)]}]})
                                     for ph, spot in phases.items()]}))
        return H({"$type": "communityCommunityTemplateData", "crowdEntries": [], "entries": out,
                  "spawnSetReference": CN("None")})

    def registry_item(ref, entries):
        return {"$type": "worldCommunityRegistryItem", "communityAreaType": "Regular",
                "communityId": {"$type": "gameCommunityID", "entityId": {"$type": "entEntityID", "hash": str(node_id(ref))}},
                "entriesInitialState": [{"$type": "worldCommunityEntryInitialState", "entryActiveOnStart": 0,
                                         "entryName": CN(name), "initialPhaseName": CN(next(iter(phases)))}
                                        for name, _, phases in entries],
                "template": template(entries)}

    def area_node(ref, entries, debug):
        return {"$type": "worldCompiledCommunityAreaNode",
                "area": H({"$type": "communityArea", "entriesData": [
                    {"$type": "communityCommunityEntrySpotsData", "entryName": CN(name), "phasesData": [
                        {"$type": "communityCommunityEntryPhaseSpotsData", "entryPhaseName": CN(ph), "timePeriodsData": [
                            {"$type": "communityCommunityEntryPhaseTimePeriodData", "isSequence": 0,
                             "periodName": CN("Day"),
                             "spotNodeIds": [{"$type": "worldGlobalNodeID", "hash": str(node_id(BASE + spot))}]}]}
                        for ph, spot in phases.items()]}
                    for name, _, phases in entries]}),
                "debugName": CN(debug), "isHostOnly": 0, "isVisibleInGame": 1, "proxyScale": None,
                "sourceObjectId": {"$type": "entEntityID", "hash": str(node_id(ref))}, "sourcePrefabHash": "0",
                "tag": "None", "tagExt": "None"}

    add({"$type": "worldCommunityRegistryNode",
         "communitiesData": [registry_item(COM_FINGER, finger_entries), registry_item(COM_GOONS, goon_entries)],
         "crowdCreationRegistry": None, "debugName": CN("slumlord_co_registry"), "isHostOnly": 0, "isVisibleInGame": 1,
         "proxyScale": None, "representsCrowd": 0, "sourcePrefabHash": "0",
         "spawnSetNameToCommunityID": {"$type": "gameCommunitySpawnSetNameToID", "entries": []},
         "tag": "None", "tagExt": "None",
         "workspotsPersistentData": [{"$type": "AISpotPersistentData",
                                      "globalNodeId": {"$type": "worldGlobalNodeID", "hash": str(node_id(BASE + n))},
                                      "isEnabled": 1, "worldPosition": {"$type": "WorldPosition", "x": fixed(x),
                                                                        "y": fixed(y), "z": fixed(z)}, "yaw": yaw}
                                     for n, (x, y, z, yaw, _) in SPOTS.items()]},
        None, (fx, fy, fz), distance=1000.0)
    add(area_node(COM_FINGER, finger_entries, "slumlord_co_com_finger"), COM_FINGER, (fx, fy, fz), distance=1000.0)
    add(area_node(COM_GOONS, goon_entries, "slumlord_co_com_goons"), COM_GOONS, (fx, fy, fz), distance=1000.0)

    sector = {"$type": "worldStreamingSector", "category": "AlwaysLoaded", "cookingPlatform": "PLATFORM_PC",
              "externInplaceResource": RES(None), "level": 1, "localInplaceResource": [],
              "nodeData": {"BufferId": "0", "Flags": 7471104,
                           "Type": "WolvenKit.RED4.Archive.Buffer.worldNodeDataBuffer, WolvenKit.RED4, Version=10.0.0.0, Culture=neutral, PublicKeyToken=null",
                           "Data": data},
              "nodeRefs": refs, "nodes": nodes, "persistentNodeIndex": 0,
              "persistentNodes": [dict(d) for d in data], "variantIndices": [0], "variantNodes": [], "version": 68}
    write(RAW / "world/sectors/slumlord_motel.streamingsector.json", sector)


def update_block():
    p = RAW / "world/slumlord.streamingblock.json"
    doc = json.loads(p.read_text(encoding="utf-8"))
    descs = doc["Data"]["RootChunk"]["descriptors"]
    if not any(d["data"]["DepotPath"]["$value"] == SECTOR_PATH for d in descs):
        d = json.loads(json.dumps(descs[0]))
        d["data"]["DepotPath"]["$value"] = SECTOR_PATH
        descs.append(d)
        p.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")


# ---------------------------------------------------------------- scenes

def actor_finger():
    return {"$type": "scnActorDef", "acquisitionPlan": "community", "actorId": {"$type": "scnActorId", "id": 0},
            "actorName": "finger", "animSets": [], "bodyCinematicAnimSets": [],
            "communityParams": {"$type": "scnCommunityParams", "entryName": CN("finger"), "forceMaxVisibility": 0,
                                "reference": NR(COM_FINGER)},
            "cyberwareAnimSets": [], "cyberwareCinematicAnimSets": [], "deformationAnimSets": [], "dynamicAnimSets": [],
            "facialAnimSets": [], "facialCinematicAnimSets": [],
            "lipsyncAnimSet": {"$type": "scnLipsyncAnimSetSRRefId", "id": 4294967295},
            "specAppearance": CN("default"), "specCharacterRecordId": TDB(None),
            "voicetagId": {"$type": "scnVoicetagId", "id": "0"}}


def actor_v(actor_id):
    return {"$type": "scnPlayerActorDef", "acquisitionPlan": "findInContext",
            "actorId": {"$type": "scnActorId", "id": actor_id}, "animSets": [], "bodyCinematicAnimSets": [],
            "cyberwareAnimSets": [], "cyberwareCinematicAnimSets": [], "deformationAnimSets": [], "dynamicAnimSets": [],
            "facialAnimSets": [], "facialCinematicAnimSets": [],
            "findActorInContextParams": {"$type": "scnFindEntityInContextParams", "contextActorName": CN("None"),
                                         "contextualName": "Player", "forceMaxVisibility": 0,
                                         "specRecordId": TDB("Character.Player_Puppet_Base"),
                                         "voiceVagId": {"$type": "scnVoicetagId", "id": "0"}},
            "findNetworkPlayerParams": {"$type": "scnFindNetworkPlayerParams", "networkId": 0},
            "lipsyncAnimSet": {"$type": "scnLipsyncAnimSetSRRefId", "id": 4294967295}, "playerName": "V",
            "specAppearance": CN("default"), "specCharacterRecordId": TDB("Character.Player_Puppet_Base"),
            "specTemplate": CN("(None)"), "voicetagId": {"$type": "scnVoicetagId", "id": "1103967280742240864"}}


def out_socket(name, ordinal, dests):
    return {"$type": "scnOutputSocket", "destinations": [
        {"$type": "scnInputSocketId", "isockStamp": {"$type": "scnInputSocketStamp", "name": 0, "ordinal": o},
         "nodeId": {"$type": "scnNodeId", "id": n}} for n, o in dests],
        "stamp": {"$type": "scnOutputSocketStamp", "name": name, "ordinal": ordinal}}


def build_scene(path_json, lines, interrupt):
    """start(1) -> section(3) with the lines -> end(2). With interrupt: start -> quest pause (V attacks or is in
    combat) -> end too, so the talk stops the moment V opens fire."""
    FINGER, V = 0, 1
    events, store, vd, vp = [], [], [], []
    t = 0.0
    for i, (key, who, text, secs, _audio) in enumerate(lines):
        rid = ruid(key)
        dur = max(secs)
        item = i * 256
        speaker, addressee = (FINGER, V) if who == "finger" else (V, FINGER)
        events.append(H({"$type": "scnDialogLineEvent",
                         "additionalSpeakers": {"$type": "scnAdditionalSpeakers", "executionTag": 0, "role": "Full", "speakers": []},
                         "duration": int(round(dur * 1000)), "executionTagFlags": 0,
                         "id": {"$type": "scnSceneEventId", "id": "18446744073709551615"}, "scalingData": None,
                         "screenplayLineId": {"$type": "scnscreenplayItemId", "id": item},
                         "startTime": int(round(t * 1000)), "type": "0", "visualStyle": "regular",
                         "voParams": {"$type": "scnDialogLineVoParams", "alwaysUseBrainGender": 0,
                                      "customVoEvent": CN("None"), "disableHeadMovement": 0,
                                      "ignoreSpeakerIncapacitation": 0, "isHolocallSpeaker": 0,
                                      "voContext": "Vo_Context_Quest", "voExpression": "Vo_Expression_Spoken"}}))
        store.append({"$type": "scnscreenplayDialogLine", "addressee": {"$type": "scnActorId", "id": addressee},
                      "femaleLipsyncAnimationName": CN("None"), "itemId": {"$type": "scnscreenplayItemId", "id": item},
                      "locstringId": {"$type": "scnlocLocstringId", "ruid": str(rid)},
                      "maleLipsyncAnimationName": CN("None"), "speaker": {"$type": "scnActorId", "id": speaker},
                      "usage": {"$type": "scnscreenplayLineUsage", "playerGenderMask": {"$type": "scnGenderMask", "mask": 3}}})
        vd.append({"$type": "scnlocLocStoreEmbeddedVariantDescriptorEntry", "localeId": "db_db",
                   "locstringId": {"$type": "scnlocLocstringId", "ruid": str(rid)},
                   "signature": {"$type": "scnlocSignature", "val": "3"},
                   "variantId": {"$type": "scnlocVariantId", "ruid": str(rid + 4)}, "vpeIndex": i})
        vp.append({"$type": "scnlocLocStoreEmbeddedVariantPayloadEntry", "content": text,
                   "variantId": {"$type": "scnlocVariantId", "ruid": str(rid + 4)}})
        t += dur + GAP
    behaviors = [{"$type": "scnSectionInternalsActorBehavior", "actorId": {"$type": "scnActorId", "id": a},
                  "behaviorMode": "OnlyIfAlive"} for a in (FINGER, V)]
    start_dests = [(3, 0)] + ([(4, 1)] if interrupt else [])
    graph = [
        H({"$type": "scnStartNode", "ffStrategy": "automatic", "nodeId": {"$type": "scnNodeId", "id": 1},
           "outputSockets": [out_socket(0, 0, start_dests)]}),
        H({"$type": "scnEndNode", "ffStrategy": "automatic", "nodeId": {"$type": "scnNodeId", "id": 2},
           "outputSockets": [out_socket(0, 0, [])], "type": "Terminating"}),
        H({"$type": "scnSectionNode", "actorBehaviors": behaviors, "events": events, "ffStrategy": "automatic",
           "isFocusClue": 0, "nodeId": {"$type": "scnNodeId", "id": 3},
           "outputSockets": [out_socket(0, 0, [(2, 0)]), out_socket(1, 0, [])],
           "sectionDuration": {"$type": "scnSceneTime", "stu": int(round((t + 0.3) * 1000))}}),
    ]
    if interrupt:
        cond = c_or(c_attacked(COM_GOONS), c_attacked(COM_FINGER), c_player_combat())
        graph.append(H({"$type": "scnQuestNode", "ffStrategy": "automatic",
                        "isockMappings": [CN("Cancel"), CN("In")], "nodeId": {"$type": "scnNodeId", "id": 4},
                        "osockMappings": [CN("Out")], "outputSockets": [out_socket(0, 0, [(2, 0)])],
                        "questNode": H({"$type": "questPauseConditionNodeDefinition", "condition": cond, "id": 4,
                                        "sockets": [H({"$type": "questSocketDefinition", "connections": [], "name": CN(n), "type": k})
                                                    for n, k in (("Cancel", "CutDestination"), ("In", "Input"), ("Out", "Output"))]})}))
    def perf(actor):
        return {"$type": "scnPerformerId", "id": actor * 256 + 1}
    scene = {
        "$type": "scnSceneResource", "cookingPlatform": "PLATFORM_PC",
        "actors": [actor_finger()], "playerActors": [actor_v(V)],
        "debugSymbols": {"$type": "scnDebugSymbols", "performersDebugSymbols": [
            {"$type": "scnPerformerSymbol", "editorPerformerId": "0", "entityRef": ENT(COM_FINGER, ["finger"]), "performerId": perf(FINGER)},
            {"$type": "scnPerformerSymbol", "editorPerformerId": "0", "entityRef": ENT(player=True), "performerId": perf(V)}],
            "sceneEventsDebugSymbols": [], "sceneNodesDebugSymbols": [], "workspotsDebugSymbols": []},
        "effectDefinitions": [], "effectInstances": [],
        "entryPoints": [{"$type": "scnEntryPoint", "name": CN("start"), "nodeId": {"$type": "scnNodeId", "id": 1}}],
        "executionTagEntries": [], "executionTags": [],
        "exitPoints": [{"$type": "scnExitPoint", "name": CN("end"), "nodeId": {"$type": "scnNodeId", "id": 2}}],
        "interruptionScenarios": [{"$type": "scnInterruptionScenario", "enabled": 1, "forcePlayReturnLine": 0,
                                   "id": {"$type": "scnInterruptionScenarioId", "id": 0},
                                   "interruptConditions": [H({"$type": "scnCheckSpeakersDistanceInterruptCondition",
                                                              "params": {"$type": "scnCheckSpeakersDistanceInterruptConditionParams",
                                                                         "comparisonType": "Greater", "distance": 20}})],
                                   "interruptionSpammingSafeguard": 0, "name": CN("Default"),
                                   "playingLinesBehavior": "Default", "playInterruptLine": 0,
                                   "postInterruptSignalFactCondition": None, "postInterruptSignalTimeDelay": 0,
                                   "postReturnSignalFactCondition": None, "postReturnSignalTimeDelay": 0,
                                   "queueName": CN("None"),
                                   "returnConditions": [H({"$type": "scnCheckSpeakersDistanceReturnCondition",
                                                           "params": {"$type": "scnCheckSpeakersDistanceReturnConditionParams",
                                                                      "comparisonType": "Less", "distance": 15}})],
                                   "talkOnReturn": 1}],
        "localMarkers": [],
        "locStore": {"$type": "scnlocLocStoreEmbedded", "vdEntries": vd, "vpEntries": vp},
        "notablePoints": [], "props": [], "referencePoints": [],
        "resouresReferences": {"$type": "scnSRRefCollection"}, "ridResources": [],
        "sceneCategoryTag": "minorQuests",
        "sceneGraph": H({"$type": "scnSceneGraph", "endNodes": [], "graph": graph, "startNodes": []}),
        "screenplayStore": {"$type": "scnscreenplayStore", "lines": store, "options": []},
        "version": 5, "voInfo": [], "workspotInstances": [], "workspots": []}
    write(RAW / path_json, scene)


# ---------------------------------------------------------------- quest phase

def spawn_node(g, actions):
    """actions: (action, community, entry or None, phase or None)"""
    return g.node("questSpawnManagerNodeDefinition", {"actions": [
        {"$type": "questSpawnManagerNodeActionEntry",
         "type": H({"$type": "questCommunityTemplate_NodeType", "action": a,
                    "communityEntryName": CN(e or "None"), "communityEntryPhaseName": CN(p or "None"),
                    "spawnerReference": NR(c)})} for a, c, e, p in actions]})


def char_param(g, subtype):
    return g.node("questCharacterManagerNodeDefinition",
                  {"type": H({"$type": "questCharacterManagerParameters_NodeType", "subtype": H(subtype)})})


def attitude(g, community, names, group):
    return char_param(g, {"$type": "questCharacterManagerParameters_SetAttitudeGroupForPuppet", "groupName": CN(group),
                          "isPlayer": 0, "puppetRef": ENT(community, names)})


def reaction(g, community, names, preset):
    return char_param(g, {"$type": "questCharacterManagerParameters_SetReactionPreset",
                          "puppetRef": ENT(community, names),
                          "recordSelector": H({"$type": "questReactionPresetRecordSelector",
                                               "civilianRecordID": TDB(preset), "corpoRecordID": TDB(preset),
                                               "gangerRecordID": TDB(preset), "isCivilian": 0, "isCorpo": 0,
                                               "isGanger": 1, "isMechanical": 0, "isPolice": 0,
                                               "mechanicalRecordID": TDB(None), "noReactionRecordID": TDB(None),
                                               "policeRecordID": TDB(None)})})


def mortality(g, community, names, state):
    return char_param(g, {"$type": "questCharacterManagerParameters_SetMortality", "isPlayer": 0,
                          "puppetRef": ENT(community, names), "resetToDefault": 0, "source": CN("None"),
                          "state": state})


def kill(g, community, name):
    return g.node("questCharacterManagerNodeDefinition", {"type": H({
        "$type": "questCharacterManagerCombat_NodeType",
        "subtype": H({"$type": "questCharacterManagerCombat_Kill",
                      "puppetRef": ENT(community, [name])})})})


def attack_v(g, community, name):
    return g.node("questCombatNodeDefinition", {
        "entityReference": ENT(community, [name]), "function": CN("questCombatNodeParams_ShootAt"),
        "params": H({"$type": "AIInjectCombatThreatCommandParams", "dontForceHostileAttitude": 0, "duration": 0,
                     "isPersistent": 1, "targetNodeRef": NR(None), "targetPuppetRef": ENT(player=True)})},
        outputs=("Success",))


def null_area(g, on):
    return g.node("questCrowdManagerNodeDefinition", {"type": H({
        "$type": "questCrowdManagerNodeType_EnableNullArea", "areaReference": NR(NULL_AREA), "enable": 1 if on else 0})})


def build_phase():
    goons = [n for n, _ in GOONS]
    # ---- the encounter, inside an inline phase: leaving it through either output ends everything in it
    e = Graph()
    e_in = e.input()
    started = e.chain(e_in, e.set_fact("slumlord_co_scene", 1), e.set_fact("slumlord_co_fight", 0),
                      null_area(e, True),
                      spawn_node(e, [("Activate", COM_FINGER, "finger", "standoff")] +
                                 [("Activate", COM_GOONS, n, "standoff") for n in goons]),
                      e.pause(c_and(c_spawned(COM_FINGER, ["finger"]), c_spawned(COM_GOONS, (), count=len(goons)))),
                      attitude(e, COM_GOONS, (), "friendly"), attitude(e, COM_FINGER, ["finger"], "friendly"),
                      reaction(e, COM_GOONS, (), "ReactionPresets.NoReaction"),
                      reaction(e, COM_FINGER, ["finger"], "ReactionPresets.NoReaction"),
                      mortality(e, COM_FINGER, ["finger"], "Invulnerable"))
    early = e.pause(c_or(c_attacked(COM_GOONS), c_attacked(COM_FINGER), c_player_combat()))
    talk = e.pause(c_and(c_near(COM_FINGER, ["finger"], TALK_METERS), c_fact("slumlord_co_fight", "Equal", 0)))
    e.link(started, "Out", early, "In")
    e.link(started, "Out", talk, "In")
    standoff = e.scene(SCENE_STANDOFF, SM, ("start",), ("end",))
    e.link(talk, "Out", standoff, "start")
    # Both routes can arrive (V opens fire mid-talk: the scene ends and the early check fires too); only the
    # first one starts the fight, since it sets slumlord_co_fight before the second is checked.
    fight = e.hub(2)
    e.link(early, "Out", fight, "In1")
    e.link(standoff, "end", fight, "In2")
    first = e.branch(c_fact("slumlord_co_fight", "Equal", 0))
    e.link(fight, "Out1", first, "In")
    fighting = e.set_fact("slumlord_co_fight", 1)
    e.link(first, "True", fighting, "In")
    hostile = e.chain(fighting, attitude(e, COM_GOONS, (), "hostile"),
                      reaction(e, COM_GOONS, (), "ReactionPresets.Ganger_Aggressive"))
    for n in goons:
        e.link(hostile, "Out", attack_v(e, COM_GOONS, n), "In")
    e.link(hostile, "Out", spawn_node(e, [("Activate", COM_FINGER, "finger", "hide")]), "In")
    down = e.pause(c_killed(COM_GOONS, (), count=len(goons)))
    e.link(hostile, "Out", down, "In")
    for n in goons:
        e.link(down, "Out", kill(e, COM_GOONS, n), "In")
    after = e.chain(down, e.set_fact("slumlord_co_fight", 2), e.pause(c_player_combat(inverted=True)),
                    reaction(e, COM_FINGER, ["finger"], "ReactionPresets.NoReaction"),
                    spawn_node(e, [("Activate", COM_FINGER, "finger", "standoff")]),
                    e.pause(c_near(COM_FINGER, ["finger"], TRUCE_METERS)))
    truce = e.scene(SCENE_TRUCE, SM, ("start",), ("end",))
    e.link(after, "Out", truce, "start")
    won = e.set_fact("slumlord_co_motel_won", 1)
    e.link(truce, "end", won, "In")
    done = e.output("Out1")
    e.chain(won, spawn_node(e, [("Activate", COM_FINGER, "finger", "leave")]),
            e.pause(c_or(c_delay(40.0), c_trigger(TR_AREA, "IsOutside"))), done)
    abort = e.pause(c_or(c_and(c_trigger(TR_AREA, "IsOutside"), c_fact("slumlord_co_motel_won", "Equal", 0)),
                         c_fact("slumlord_co_abort", "GreaterOrEqual", 1)))
    e.link(e_in, "Out", abort, "In")
    e.link(abort, "Out", e.output("Out2"), "In")

    # ---- root: wait, run the encounter, clean up, wait again
    g = Graph()
    g_in = g.input()
    wait = g.pause(c_and(c_fact("slumlord_co_ready", "GreaterOrEqual", 1), c_trigger(TR_AREA, "IsInside")))
    g.link(g_in, "Out", wait, "In")
    enc = g.phase(e, inputs=("In1",), outputs=("Out1", "Out2"))
    g.link(wait, "Out", enc, "In1")
    hub = g.hub(2)
    g.link(enc, "Out1", hub, "In1")
    g.link(enc, "Out2", hub, "In2")
    first = null_area(g, False)
    g.link(hub, "Out1", first, "In")
    last = g.chain(first, spawn_node(g, [("Deactivate", COM_GOONS, None, None), ("Deactivate", COM_FINGER, None, None)]),
                   g.set_fact("slumlord_co_fight", 0), g.set_fact("slumlord_co_scene", 0),
                   g.set_fact("slumlord_co_abort", 0),
                   g.pause(c_delay(5.0)))
    g.link(last, "Out", wait, "In")
    write(RAW / "quest/slumlord_motel.questphase.json",
          {"$type": "questQuestPhaseResource", "cookingPlatform": "PLATFORM_PC", "graph": g.definition(),
           "inplacePhases": [], "phasePrefabs": []})


# ---------------------------------------------------------------- texts, audio, line lengths, record

def build_texts():
    entries = []
    for key, who, text, _secs, _audio in STANDOFF + TRUCE:
        entries.append({"$type": "localizationPersistenceSubtitleEntry", "femaleVariant": text, "maleVariant": "",
                        "stringId": str(ruid(key))})
    write(RAW / "localization/en-us/subtitles/slumlord_subtitles.json.json",
          {"$type": "JsonResource", "cookingPlatform": "PLATFORM_PC",
           "root": H({"$type": "localizationPersistenceSubtitleEntries", "entries": entries})})
    write(RAW / "localization/en-us/subtitles/slumlord_subtitle_map.json.json",
          {"$type": "JsonResource", "cookingPlatform": "PLATFORM_PC",
           "root": H({"$type": "localizationPersistenceSubtitleMap", "entries": [
               {"$type": "localizationPersistenceSubtitleMapEntry", "subtitleFile": RES(SUBS_PATH),
                "subtitleGroup": CN("quest")}]})})
    # Finger's display name for the subtitles' speaker
    p = RAW / "localization/en-us.json.json"
    doc = json.loads(p.read_text(encoding="utf-8"))
    on = doc["Data"]["RootChunk"]["root"]["Data"]["entries"]
    if not any(x["secondaryKey"] == "slumlord-finger-name" for x in on):
        on.append({"$type": "localizationPersistenceOnScreenEntry", "femaleVariant": "Quentin Finger", "maleVariant": "",
                   "primaryKey": "0", "secondaryKey": "slumlord-finger-name"})
        p.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")


def build_audio():
    p = MOD / "r6/audioware/Slumlord/slumlord.yml"
    text = p.read_text(encoding="utf-8")
    text = re.sub(r"\n# >>> scene dialogs \(tools/quest/make_motel.py\).*?# <<< scene dialogs\n", "\n", text, flags=re.S)
    out = ["# >>> scene dialogs (tools/quest/make_motel.py): the motel scenes' lines, keyed by their string id",
           "dialogs:"]
    for key, who, text_, _secs, audio in STANDOFF + TRUCE:
        out.append(f"  {ruid(key)}:   # {key}: {text_[:40]}")
        if isinstance(audio, tuple):
            out += ["    en-us:", f"      fem: ./vo/{audio[0]}.ogg", f"      male: ./vo/{audio[1]}.ogg"]
        else:
            out.append(f"    en-us: ./vo/{audio}.ogg")
    out.append("# <<< scene dialogs")
    p.write_text(text.rstrip("\n") + "\n\n" + "\n".join(out) + "\n", encoding="utf-8")


def build_lengths():
    lines = ["// Generated by tools/quest/make_motel.py: lengths of the motel scenes' lines for the game's voice-over",
             "// length table (the engine times subtitles and lines by it; ArchiveXL can't add to it). Same approach",
             "// as Audioware's scene-dialog example. Needs Codeware.",
             "module Slumlord", "",
             "public class SlumlordSceneLineLengths extends ScriptableService {",
             "  private cb func OnLoad() {",
             "    GameInstance.GetCallbackSystem().RegisterCallback(n\"Resource/PostLoad\", this, n\"OnPostLoad\")",
             "      .AddTarget(ResourceTarget.Path(r\"base\\\\localization\\\\en-us\\\\stringidvariantlengthsreport.json\"));",
             "  }", "",
             "  private cb func OnPostLoad(event: ref<ResourceEvent>) {",
             "    let resource = event.GetResource() as JsonResource;",
             "    let map = IsDefined(resource) ? resource.root as locVoiceoverLengthMap : null;",
             "    if !IsDefined(map) { return; }"]
    for key, who, text_, secs, _audio in STANDOFF + TRUCE:
        lines.append(f"    SlumlordSceneLineLengths.Add(map, {ruid(key)}ul, {secs[0]:.2f}, {secs[1]:.2f});   // {key}")
    lines += ["  }", "",
              "  private static func Add(map: ref<locVoiceoverLengthMap>, id: Uint64, female: Float, male: Float) -> Void {",
              "    let entry: locVoLengthEntry;",
              "    entry.stringId = HashToCRUID(id);",
              "    entry.femaleLength = female;",
              "    entry.maleLength = male;",
              "    ArrayPush(map.entries, entry);",
              "  }", "}", ""]
    (MOD / "r6/scripts/Slumlord/MotelLines.reds").write_text("\n".join(lines), encoding="utf-8")


def build_record():
    p = MOD / "r6/tweaks/Slumlord/slumlord_finger.yaml"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        "# Quentin Finger (design doc 4.9): the motel scene's community spawns this record. A stand-in body (a 6th Street\n"
        "# member) until his look is picked; the name shows over his subtitles. Generated by tools/quest/make_motel.py.\n"
        f"{FINGER_RECORD}:\n"
        f"  $base: {FINGER_BASE}\n"
        "  displayName: slumlord-finger-name\n"
        "  fullDisplayName: slumlord-finger-name\n", encoding="utf-8")


def main():
    build_sector()
    update_block()
    build_scene("quest/scenes/slumlord_co_standoff.scene.json", STANDOFF, interrupt=True)
    build_scene("quest/scenes/slumlord_co_truce.scene.json", TRUCE, interrupt=False)
    build_phase()
    build_texts()
    build_audio()
    build_lengths()
    build_record()
    for key, *_ in STANDOFF + TRUCE:
        print(f"{key}: {ruid(key)}")


if __name__ == "__main__":
    main()
