"""Shared parts for Slumlord's in-person encounters built as the game's own quest files (design doc 13).

An encounter is: a world sector (AI spots with workspots, communities on them, a trigger area, a crowd null area,
a scene marker), one root quest phase injected by ArchiveXL, and scenes. make_scenes.py describes each encounter
and builds its phase graph with the node helpers here; the shared outputs (subtitles, Audioware dialogs, line
lengths, TweakXL records, onscreen texts) are written once for all encounters.
"""
import base64
import json
import math
import re
import struct
from pathlib import Path

from qgraph import (H, CN, NR, TDB, RES, V3, V4, ENT, write, c_or, c_attacked, c_player_combat)

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "wolvenkit/source/raw/slumlord"
MOD = ROOT / "mod"

SUBS_PATH = r"slumlord\localization\en-us\subtitles\slumlord_subtitles.json"
GAP = 0.45   # seconds between scene lines


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


def fixed(v):
    return {"$type": "FixedPoint", "Bits": int(round(v * 131072))}


class Line:
    """A scene line. who: "npc" (the scene's NPC actor) or "v". text: one string, or (for female V, for male V).
    secs: (female V, male V) lengths. audio: one file stem, or (female, male) stems in r6/audioware/Slumlord/vo."""

    def __init__(self, key, who, text, secs, audio):
        self.key, self.who, self.text, self.secs, self.audio = key, who, text, secs, audio

    @property
    def id(self):
        return ruid(self.key)

    def texts(self):
        return self.text if isinstance(self.text, tuple) else (self.text, self.text)


class Encounter:
    def __init__(self, key, folder, sector_path, phase_path):
        self.key = key                      # fact prefix: slumlord_<key>_...
        self.base = f"$/slumlord/{folder}/#"
        self.sector_path = sector_path
        self.phase_path = phase_path
        self.spots = {}                     # name -> (x, y, z, yaw, workspot)
        self.communities = {}               # name -> [(entry, record, {phase: spot})]
        self.marker = None                  # (name, x, y, z, yaw)
        self.area = None                    # (name, x, y, z, half, height)
        self.null = None                    # (name, x, y, z, half)
        self.records = {}                   # TweakXL clones: record -> (base, display-name key or None)

    def ref(self, name):
        return self.base + name

    def fact(self, name):
        return f"slumlord_{self.key}_{name}"


# ---------------------------------------------------------------- world sector

def setup_info(ref, pos, yaw=0.0, distance=200.0, idx=0):
    x, y, z = pos
    return {"$type": "worldCompiledNodeInstanceSetupInfo", "dataGroup": "Base",
            "externalInplaceResourceHash": RES(None, "Default"),
            "globalNodeId": {"$type": "worldGlobalNodeID", "hash": str(node_id(ref) if ref else 0)},
            "instanceIndex": 4294967295, "nodeFlags": "FLAG_AllowForceStreamIn, FLAG_Quest", "nodeIdx": str(idx),
            "patchedNode": NR(None), "preboostStreamingRefPoint": V3(x, y, z),
            "proxyMeshId": {"$type": "worldGlobalNodeID", "hash": "0"}, "scale": V3(1, 1, 1),
            "secondaryRefPointDistance": 3.40282347e+38, "secondaryRefPointPosition": V3(0, 0, 0),
            "streamingDistance": distance, "streamingPriority": "1", "streamingRefPoint": V3(x, y, z),
            "todvisMask": "0",
            "transform": {"$type": "Transform", "orientation": quat(yaw), "position": V4(x, y, z)}}


def outline(hx, hy, z0, height):
    """AreaShapeOutline: four corners in local meters; the packed buffer is what the game reads."""
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


def build_sector(enc):
    nodes, data, refs = [], [], []

    def add(node, ref, pos, yaw=0.0, distance=200.0):
        idx = len(nodes)
        nodes.append(H(node))
        data.append(setup_info(ref, pos, yaw, distance, idx=idx))
        if ref:
            refs.append(NR(ref))

    for name, (x, y, z, yaw, ws) in enc.spots.items():
        add(ai_spot(name, ws), enc.ref(name), (x, y, z), yaw)

    name, mx, my, mz, myaw = enc.marker
    add({"$type": "worldStaticMarkerNode", "data": H({"$type": "scnSceneMarker", "markers": [], "workspotMarkers": []}),
         "debugName": CN("{" + name + "}"), "isEnabled": 1, "isHostOnly": 0, "isVisibleInGame": 1,
         "proxyScale": None, "sourcePrefabHash": "0", "tag": "None", "tagExt": "None",
         "tags": {"$type": "redTagList", "tags": []}}, enc.ref(name), (mx, my, mz), myaw)
    name, ax, ay, az, half, height = enc.area
    add({"$type": "worldTriggerAreaNode", "color": {"$type": "Color", "Alpha": 128, "Blue": 160, "Green": 160, "Red": 255},
         "debugName": CN("{" + name + "}"), "isHostOnly": 0, "isVisibleInGame": 1,
         "notifiers": [H({"$type": "questTriggerNotifier_Quest", "excludeChannels": 0, "includeChannels": "TC_Default",
                          "isEnabled": 1})],
         "outline": outline(half, half, 0.0, height), "proxyScale": None, "sourcePrefabHash": "0",
         "tag": "None", "tagExt": "None"}, enc.ref(name), (ax, ay, az), 0.0, distance=half * 3)
    name, nx, ny, nz, half = enc.null
    add({"$type": "worldCrowdNullAreaNode", "color": {"$type": "Color", "Alpha": 128, "Blue": 32, "Green": 32, "Red": 32},
         "debugName": CN("{" + name + "}"), "IsForBlockade": 0, "isHostOnly": 0, "isVisibleInGame": 1,
         "outline": outline(half, half, -5.0, 25.0), "permanentlyEnabledByDefault": 0, "proxyScale": None,
         "sourcePrefabHash": "0", "tag": "None", "tagExt": "None"}, enc.ref(name), (nx, ny, nz), 0.0, distance=half * 6)

    def template(entries):
        out = []
        for entry, rec, phases in entries:
            out.append(H({"$type": "communitySpawnEntry", "characterRecordId": TDB(rec), "entryName": CN(entry),
                          "initializers": [], "spawnInView": "default__true_",
                          "phases": [H({"$type": "communitySpawnPhase", "alwaysSpawned": "default__false_",
                                        "appearances": [], "phaseName": CN(ph), "prefetchAppearance": 0,
                                        "timePeriods": [{"$type": "communityPhaseTimePeriod", "categories": [],
                                                         "hour": "Day", "isSequence": 0, "markings": [], "quantity": 1,
                                                         "spotNodeRefs": [NR(enc.ref(spot))]}]})
                                     for ph, spot in phases.items()]}))
        return H({"$type": "communityCommunityTemplateData", "crowdEntries": [], "entries": out,
                  "spawnSetReference": CN("None")})

    def registry_item(ref, entries):
        return {"$type": "worldCommunityRegistryItem", "communityAreaType": "Regular",
                "communityId": {"$type": "gameCommunityID", "entityId": {"$type": "entEntityID", "hash": str(node_id(ref))}},
                "entriesInitialState": [{"$type": "worldCommunityEntryInitialState", "entryActiveOnStart": 0,
                                         "entryName": CN(entry), "initialPhaseName": CN(next(iter(phases)))}
                                        for entry, _, phases in entries],
                "template": template(entries)}

    def area_node(ref, entries, debug):
        return {"$type": "worldCompiledCommunityAreaNode",
                "area": H({"$type": "communityArea", "entriesData": [
                    {"$type": "communityCommunityEntrySpotsData", "entryName": CN(entry), "phasesData": [
                        {"$type": "communityCommunityEntryPhaseSpotsData", "entryPhaseName": CN(ph), "timePeriodsData": [
                            {"$type": "communityCommunityEntryPhaseTimePeriodData", "isSequence": 0,
                             "periodName": CN("Day"),
                             "spotNodeIds": [{"$type": "worldGlobalNodeID", "hash": str(node_id(enc.ref(spot)))}]}]}
                        for ph, spot in phases.items()]}
                    for entry, _, phases in entries]}),
                "debugName": CN(debug), "isHostOnly": 0, "isVisibleInGame": 1, "proxyScale": None,
                "sourceObjectId": {"$type": "entEntityID", "hash": str(node_id(ref))}, "sourcePrefabHash": "0",
                "tag": "None", "tagExt": "None"}

    add({"$type": "worldCommunityRegistryNode",
         "communitiesData": [registry_item(enc.ref(c), entries) for c, entries in enc.communities.items()],
         "crowdCreationRegistry": None, "debugName": CN(f"slumlord_{enc.key}_registry"), "isHostOnly": 0,
         "isVisibleInGame": 1, "proxyScale": None, "representsCrowd": 0, "sourcePrefabHash": "0",
         "spawnSetNameToCommunityID": {"$type": "gameCommunitySpawnSetNameToID", "entries": []},
         "tag": "None", "tagExt": "None",
         "workspotsPersistentData": [{"$type": "AISpotPersistentData",
                                      "globalNodeId": {"$type": "worldGlobalNodeID", "hash": str(node_id(enc.ref(n)))},
                                      "isEnabled": 1, "worldPosition": {"$type": "WorldPosition", "x": fixed(x),
                                                                        "y": fixed(y), "z": fixed(z)}, "yaw": yaw}
                                     for n, (x, y, z, yaw, _) in enc.spots.items()]},
        None, (mx, my, mz), distance=1000.0)
    for c, entries in enc.communities.items():
        add(area_node(enc.ref(c), entries, c), enc.ref(c), (mx, my, mz), distance=1000.0)

    sector = {"$type": "worldStreamingSector", "category": "AlwaysLoaded", "cookingPlatform": "PLATFORM_PC",
              "externInplaceResource": RES(None), "level": 1, "localInplaceResource": [],
              "nodeData": {"BufferId": "0", "Flags": 7471104,
                           "Type": "WolvenKit.RED4.Archive.Buffer.worldNodeDataBuffer, WolvenKit.RED4, Version=10.0.0.0, Culture=neutral, PublicKeyToken=null",
                           "Data": data},
              "nodeRefs": refs, "nodes": nodes, "persistentNodeIndex": 0,
              "persistentNodes": [dict(d) for d in data], "variantIndices": [0], "variantNodes": [], "version": 68}
    write(RAW / (enc.sector_path.replace("slumlord\\", "", 1).replace("\\", "/") + ".json"), sector)


def update_block(sector_paths):
    p = RAW / "world/slumlord.streamingblock.json"
    doc = json.loads(p.read_text(encoding="utf-8"))
    descs = doc["Data"]["RootChunk"]["descriptors"]
    changed = False
    for path in sector_paths:
        if not any(d["data"]["DepotPath"]["$value"] == path for d in descs):
            d = json.loads(json.dumps(descs[0]))
            d["data"]["DepotPath"]["$value"] = path
            descs.append(d)
            changed = True
    if changed:
        p.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")


# ---------------------------------------------------------------- scenes

def actor_npc(name, community, entry):
    return {"$type": "scnActorDef", "acquisitionPlan": "community", "actorId": {"$type": "scnActorId", "id": 0},
            "actorName": name, "animSets": [], "bodyCinematicAnimSets": [],
            "communityParams": {"$type": "scnCommunityParams", "entryName": CN(entry), "forceMaxVisibility": 0,
                                "reference": NR(community)},
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


def build_scene(depot_path, lines, npc, interrupt_on=None):
    """Scene: start(1) -> one section(3) with the lines -> end(2), exits "start"/"end". npc = (actor name,
    community ref, entry). interrupt_on = community refs: the talk also ends at once if V attacks any of their
    people or is in combat."""
    NPC, V = 0, 1
    events, store, vd, vp = [], [], [], []
    t = 0.0
    for i, line in enumerate(lines):
        rid = line.id
        dur = max(line.secs)
        item = i * 256
        speaker, addressee = (NPC, V) if line.who == "npc" else (V, NPC)
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
        vp.append({"$type": "scnlocLocStoreEmbeddedVariantPayloadEntry", "content": line.texts()[1],
                   "variantId": {"$type": "scnlocVariantId", "ruid": str(rid + 4)}})
        t += dur + GAP
    behaviors = [{"$type": "scnSectionInternalsActorBehavior", "actorId": {"$type": "scnActorId", "id": a},
                  "behaviorMode": "OnlyIfAlive"} for a in (NPC, V)]
    start_dests = [(3, 0)] + ([(4, 1)] if interrupt_on else [])
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
    if interrupt_on:
        cond = c_or(*[c_attacked(c) for c in interrupt_on], c_player_combat())
        graph.append(H({"$type": "scnQuestNode", "ffStrategy": "automatic",
                        "isockMappings": [CN("Cancel"), CN("In")], "nodeId": {"$type": "scnNodeId", "id": 4},
                        "osockMappings": [CN("Out")], "outputSockets": [out_socket(0, 0, [(2, 0)])],
                        "questNode": H({"$type": "questPauseConditionNodeDefinition", "condition": cond, "id": 4,
                                        "sockets": [H({"$type": "questSocketDefinition", "connections": [], "name": CN(n), "type": k})
                                                    for n, k in (("Cancel", "CutDestination"), ("In", "Input"), ("Out", "Output"))]})}))

    def perf(actor):
        return {"$type": "scnPerformerId", "id": actor * 256 + 1}
    name, community, entry = npc
    scene = {
        "$type": "scnSceneResource", "cookingPlatform": "PLATFORM_PC",
        "actors": [actor_npc(name, community, entry)], "playerActors": [actor_v(V)],
        "debugSymbols": {"$type": "scnDebugSymbols", "performersDebugSymbols": [
            {"$type": "scnPerformerSymbol", "editorPerformerId": "0", "entityRef": ENT(community, [entry]), "performerId": perf(NPC)},
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
    write(RAW / (depot_path.replace("slumlord\\", "", 1).replace("\\", "/") + ".json"), scene)


# ---------------------------------------------------------------- quest nodes

def spawn_node(g, actions):
    """actions: (action, community, entry or None, phase or None); action Activate or Deactivate."""
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
        "subtype": H({"$type": "questCharacterManagerCombat_Kill", "puppetRef": ENT(community, [name])})})})


def attack_v(g, community, name):
    return g.node("questCombatNodeDefinition", {
        "entityReference": ENT(community, [name]), "function": CN("questCombatNodeParams_ShootAt"),
        "params": H({"$type": "AIInjectCombatThreatCommandParams", "dontForceHostileAttitude": 0, "duration": 0,
                     "isPersistent": 1, "targetNodeRef": NR(None), "targetPuppetRef": ENT(player=True)})},
        outputs=("Success",))


def null_area(g, ref, on):
    return g.node("questCrowdManagerNodeDefinition", {"type": H({
        "$type": "questCrowdManagerNodeType_EnableNullArea", "areaReference": NR(ref), "enable": 1 if on else 0})})


def write_phase(enc, graph):
    write(RAW / (enc.phase_path.replace("slumlord\\", "", 1).replace("\\", "/") + ".json"),
          {"$type": "questQuestPhaseResource", "cookingPlatform": "PLATFORM_PC", "graph": graph.definition(),
           "inplacePhases": [], "phasePrefabs": []})


# ---------------------------------------------------------------- shared outputs

def build_texts(lines, onscreens):
    """Subtitles for every scene line, their map, and onscreen texts (key -> text) added to en-us.json."""
    entries = []
    for line in lines:
        fem, male = line.texts()
        entries.append({"$type": "localizationPersistenceSubtitleEntry", "femaleVariant": fem,
                        "maleVariant": male if male != fem else "", "stringId": str(line.id)})
    write(RAW / "localization/en-us/subtitles/slumlord_subtitles.json.json",
          {"$type": "JsonResource", "cookingPlatform": "PLATFORM_PC",
           "root": H({"$type": "localizationPersistenceSubtitleEntries", "entries": entries})})
    write(RAW / "localization/en-us/subtitles/slumlord_subtitle_map.json.json",
          {"$type": "JsonResource", "cookingPlatform": "PLATFORM_PC",
           "root": H({"$type": "localizationPersistenceSubtitleMap", "entries": [
               {"$type": "localizationPersistenceSubtitleMapEntry", "subtitleFile": RES(SUBS_PATH),
                "subtitleGroup": CN("quest")}]})})
    p = RAW / "localization/en-us.json.json"
    doc = json.loads(p.read_text(encoding="utf-8"))
    on = doc["Data"]["RootChunk"]["root"]["Data"]["entries"]
    changed = False
    for key, text in onscreens.items():
        if not any(x["secondaryKey"] == key for x in on):
            on.append({"$type": "localizationPersistenceOnScreenEntry", "femaleVariant": text, "maleVariant": "",
                       "primaryKey": "0", "secondaryKey": key})
            changed = True
    if changed:
        p.write_text(json.dumps(doc, indent=1, ensure_ascii=False), encoding="utf-8")


def build_audio(lines):
    p = MOD / "r6/audioware/Slumlord/slumlord.yml"
    text = p.read_text(encoding="utf-8")
    text = re.sub(r"\n*# >>> scene dialogs \(tools/quest/.*?# <<< scene dialogs\n", "\n", text, flags=re.S)
    out = ["# >>> scene dialogs (tools/quest/make_scenes.py): every scene line, keyed by its string id", "dialogs:"]
    for line in lines:
        out.append(f"  {line.id}:   # {line.key}: {line.texts()[1][:40]}")
        if isinstance(line.audio, tuple):
            out += ["    en-us:", f"      fem: ./vo/{line.audio[0]}.ogg", f"      male: ./vo/{line.audio[1]}.ogg"]
        else:
            out.append(f"    en-us: ./vo/{line.audio}.ogg")
    out.append("# <<< scene dialogs")
    p.write_text(text.rstrip("\n") + "\n\n" + "\n".join(out) + "\n", encoding="utf-8")


def build_lengths(lines):
    out = ["// Generated by tools/quest/make_scenes.py: lengths of the scene lines for the game's voice-over length",
           "// table (the engine times subtitles and lines by it; ArchiveXL can't add to it). Same approach as",
           "// Audioware's scene-dialog example. Needs Codeware.",
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
    for line in lines:
        out.append(f"    SlumlordSceneLineLengths.Add(map, {line.id}ul, {line.secs[0]:.2f}, {line.secs[1]:.2f});   // {line.key}")
    out += ["  }", "",
            "  private static func Add(map: ref<locVoiceoverLengthMap>, id: Uint64, female: Float, male: Float) -> Void {",
            "    let entry: locVoLengthEntry;",
            "    entry.stringId = HashToCRUID(id);",
            "    entry.femaleLength = female;",
            "    entry.maleLength = male;",
            "    ArrayPush(map.entries, entry);",
            "  }", "}", ""]
    (MOD / "r6/scripts/Slumlord/SceneLines.reds").write_text("\n".join(out), encoding="utf-8")


def build_records(records):
    """records: record -> (base record, display-name onscreen key or None)."""
    p = MOD / "r6/tweaks/Slumlord/slumlord_characters.yaml"
    p.parent.mkdir(parents=True, exist_ok=True)
    out = ["# The scene characters' records (design doc 13), generated by tools/quest/make_scenes.py. Clones of vanilla",
           "# records, so Slumlord can tell its own NPCs from vanilla ones near the scenes, and so a name can show over",
           "# a character's subtitles."]
    for rec, (base, name) in records.items():
        out += [f"{rec}:", f"  $base: {base}"]
        if name:
            out += [f"  displayName: {name}", f"  fullDisplayName: {name}"]
    p.write_text("\n".join(out) + "\n", encoding="utf-8")
