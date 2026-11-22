"""Small builder for Cyberpunk 2077 quest and scene files as WolvenKit CR2W-JSON.

Write the files as plain Python dicts. Wrap an object in H(...) where the game format holds a handle (a pointer
that can be shared); the serializer gives every handle a HandleId on its first appearance and a HandleRefId after.
Fields left out are filled with defaults by WolvenKit when the JSON is converted (cp77tools convert d).

Quest graphs: Graph() collects nodes; node(kind, fields, inputs, outputs) makes a node with its sockets;
link(a, 'Out', b, 'In') connects them. Scenes: see Scene in make_motel.py.
"""
import json

WK_HEADER = {"WolvenKitVersion": "10.0.0-beta.1", "WKitJsonVersion": "0.0.9", "GameVersion": 2500,
             "ExportedDateTime": "2026-11-22T00:00:00Z", "DataType": "CR2W", "ArchiveFileName": ""}


class H:
    """A handle to obj (a dict). The same H instance, or the same obj, serializes once with HandleId."""
    __slots__ = ("obj",)

    def __init__(self, obj):
        self.obj = obj


def serialize(root):
    ids = {}

    def ser(o):
        if isinstance(o, H):
            key = id(o.obj)
            if key in ids:
                return {"HandleRefId": ids[key]}
            ids[key] = str(len(ids))
            return {"HandleId": ids[key], "Data": ser(o.obj)}
        if isinstance(o, dict):
            return {k: ser(v) for k, v in o.items()}
        if isinstance(o, list):
            return [ser(v) for v in o]
        return o

    return ser(root)


def cr2w(root_chunk, version=195):
    return {"Header": dict(WK_HEADER), "Data": {"Version": version, "BuildVersion": 0, "RootChunk": serialize(root_chunk)}}


def write(path, root_chunk):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cr2w(root_chunk), indent=1, ensure_ascii=False), encoding="utf-8")


# ---- value helpers

def CN(s):
    return {"$type": "CName", "$storage": "string", "$value": s}


def NR(s):
    if not s:
        return {"$type": "NodeRef", "$storage": "uint64", "$value": "0"}
    return {"$type": "NodeRef", "$storage": "string", "$value": s}


def TDB(s):
    if not s:
        return {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}
    return {"$type": "TweakDBID", "$storage": "string", "$value": s}


def RES(path, flags="Soft"):
    if not path:
        return {"DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"}, "Flags": flags}
    return {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": path}, "Flags": flags}


def V3(x, y, z):
    return {"$type": "Vector3", "X": x, "Y": y, "Z": z}


def V4(x, y, z, w=0):
    return {"$type": "Vector4", "W": w, "X": x, "Y": y, "Z": z}


def ENT(ref=None, names=(), player=False):
    """gameEntityReference: a community/spawner NodeRef (optionally with entry names), or V ("#player")."""
    return {"$type": "gameEntityReference", "dynamicEntityUniqueName": CN("None"),
            "names": [CN(n) for n in names], "reference": NR("#player" if player else ref),
            "sceneActorContextName": CN("None"), "slotName": CN("None"), "type": "EntityRef"}


def UREF_PLAYER():
    return H({"$type": "questUniversalRef", "entityReference": ENT(), "mainPlayerObject": 0, "refLocalPlayer": 1})


def UREF(ref, names=()):
    return H({"$type": "questUniversalRef", "entityReference": ENT(ref, names), "mainPlayerObject": 0,
              "refLocalPlayer": 0})


# ---- quest conditions

def c_fact(name, op, value=0):
    """op: Equal, NotEqual, Less, LessOrEqual, Greater, GreaterOrEqual"""
    return H({"$type": "questFactsDBCondition", "type": H({"$type": "questVarComparison_ConditionType",
              "comparisonType": op, "factName": name, "value": value})})


def c_and(*conds):
    return H({"$type": "questLogicalCondition", "conditions": list(conds), "operation": "AND"})


def c_or(*conds):
    return H({"$type": "questLogicalCondition", "conditions": list(conds), "operation": "OR"})


def c_trigger(area, kind="IsInside"):
    """kind: IsInside, IsOutside, Entered, Exited"""
    return H({"$type": "questTriggerCondition", "activatorRef": ENT(), "isPlayerActivator": 1,
              "triggerAreaRef": NR(area), "type": kind})


def c_player_combat(inverted=False):
    return H({"$type": "questCharacterCondition", "type": H({"$type": "questCharacterCombat_ConditionType",
              "inverted": 1 if inverted else 0})})


def c_attacked(community, names=()):
    """V attacks someone of the community (or the named entries)."""
    return H({"$type": "questCharacterCondition", "type": H({"$type": "questCharacterAttack_ConditionType",
              "attackerRef": ENT(player=True), "targetRef": ENT(community, names)})})


def c_spawned(community, names=(), count=1, op="GreaterOrEqual", entire=False):
    return H({"$type": "questCharacterCondition", "type": H({"$type": "questCharacterSpawned_ConditionType",
              "comparisonParams": H({"$type": "questComparisonParam", "comparisonType": op, "count": count,
                                     "entireCommunity": 1 if entire else 0}),
              "objectRef": ENT(community, names)})})


def c_killed(community, names=(), count=1, op="GreaterOrEqual", entire=False):
    """Killed, defeated or unconscious."""
    return H({"$type": "questCharacterCondition", "type": H({"$type": "questCharacterKilled_ConditionType",
              "comparisonParams": H({"$type": "questComparisonParam", "comparisonType": op, "count": count,
                                     "entireCommunity": 1 if entire else 0}),
              "defeated": 1, "killed": 1, "unconscious": 1, "objectRef": ENT(community, names)})})


def c_near(community, names, meters):
    """V within `meters` of the named community entry."""
    return H({"$type": "questDistanceCondition", "type": H({"$type": "questDistanceComparison_ConditionType",
              "comparisonType": "LessOrEqual",
              "distanceDefinition1": H({"$type": "questObjectDistance", "entityRef": UREF_PLAYER(),
                                        "nodeRef2": ENT(community, names)}),
              "distanceDefinition2": H({"$type": "questValueDistance", "distanceValue": meters})})})


def c_delay(seconds):
    s = int(seconds)
    return H({"$type": "questTimeCondition", "type": H({"$type": "questRealtimeDelay_ConditionType",
              "seconds": s, "miliseconds": int(round((seconds - s) * 1000))})})


# ---- quest graph

class Node:
    def __init__(self, graph, data, inputs, outputs):
        self.graph = graph
        self.data = data
        self.sockets = {}
        socks = [H({"$type": "questSocketDefinition", "connections": [], "name": CN("CutDestination"),
                    "type": "CutDestination"})]
        for name in inputs:
            s = H({"$type": "questSocketDefinition", "connections": [], "name": CN(name), "type": "Input"})
            self.sockets[name] = s
            socks.append(s)
        for name in outputs:
            s = H({"$type": "questSocketDefinition", "connections": [], "name": CN(name), "type": "Output"})
            self.sockets[name] = s
            socks.append(s)
        data["sockets"] = socks

    @property
    def id(self):
        return self.data["id"]


class Graph:
    def __init__(self, first_id=1):
        self.nodes = []
        self.next_id = first_id

    def node(self, kind, fields=None, inputs=("In",), outputs=("Out",)):
        data = {"$type": kind, "id": self.next_id}
        self.next_id += 1
        data.update(fields or {})
        n = Node(self, data, inputs, outputs)
        self.nodes.append(n)
        return n

    def definition(self):
        return H({"$type": "questGraphDefinition", "nodes": [H(n.data) for n in self.nodes]})

    # common nodes
    def input(self, name="In1"):
        return self.node("questInputNodeDefinition", {"socketName": CN(name)}, inputs=(), outputs=("Out",))

    def output(self, name="Out1", terminating=True):
        return self.node("questOutputNodeDefinition", {"socketName": CN(name),
                         "type": "Terminating" if terminating else "NonTerminating"}, inputs=("In",), outputs=())

    def pause(self, cond):
        return self.node("questPauseConditionNodeDefinition", {"condition": cond})

    def branch(self, cond):
        return self.node("questConditionNodeDefinition", {"condition": cond}, outputs=("True", "False"))

    def set_fact(self, name, value, exact=True):
        return self.node("questFactsDBManagerNodeDefinition", {"type": H({"$type": "questSetVar_NodeType",
                         "factName": name, "setExactValue": 1 if exact else 0, "value": value})})

    def hub(self, inputs=2):
        return self.node("questLogicalHubNodeDefinition", {"inputSocketCount": inputs, "outputSocketCount": 1},
                         inputs=[f"In{i + 1}" for i in range(inputs)], outputs=("Out1",))

    def xor(self, inputs=2):
        return self.node("questLogicalXorNodeDefinition", {"inputSocketCount": inputs, "outputSocketCount": 1},
                         inputs=[f"In{i + 1}" for i in range(inputs)], outputs=("Out1",))

    def and_(self, inputs=2):
        return self.node("questLogicalAndNodeDefinition", {"inputSocketCount": inputs, "outputSocketCount": 1},
                         inputs=[f"In{i + 1}" for i in range(inputs)], outputs=("Out1",))

    def phase(self, inner, inputs=("In1",), outputs=("Out1",)):
        """An inline phase holding the Graph `inner`."""
        return self.node("questPhaseNodeDefinition", {"phaseGraph": inner.definition(), "phaseInstancePrefabs": [],
                         "phaseResource": RES(None), "saveLock": 0, "unfreezingTriggerNodeRef": NR(None)},
                         inputs=inputs, outputs=outputs)

    def scene(self, path, marker, entries, exits):
        return self.node("questSceneNodeDefinition", {"interruptionOperations": [], "notAllowedToBeFrozen": 0,
                         "reapplyInterruptionOperationsAfterGameLoad": 0, "sceneFile": RES(path),
                         "sceneLocation": {"$type": "scnWorldMarker", "nodeRef": NR(marker), "tag": CN("None"),
                                           "type": "NodeRef"}},
                         inputs=entries, outputs=exits)

    def link(self, a, out, b, inp):
        src = a.sockets[out]
        dst = b.sockets[inp]
        conn = H({"$type": "graphGraphConnectionDefinition", "destination": dst, "source": src})
        src.obj["connections"].append(conn)
        dst.obj["connections"].append(conn)
        return b

    def chain(self, *nodes):
        """Link Out→In along a list of plain nodes."""
        for a, b in zip(nodes, nodes[1:]):
            self.link(a, "Out", b, "In")
        return nodes[-1]
