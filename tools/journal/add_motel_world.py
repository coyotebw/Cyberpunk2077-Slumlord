"""Conversation Overtime: Las Palapas world nodes and quest map pins.

Idempotent. Edits the WolvenKit raw JSON in place; then convert and pack (README "Build").
  - slumlord_markers.streamingsector: a quest marker at the motel entrance
    ($/slumlord/conversation_overtime/#slumlord_co_marker) and an AI spot running the arms-crossed
    workspot at Finger's spot ($/slumlord/conversation_overtime/#slumlord_co_spot_finger).
  - Journal: map pins slumlord_co_pin_wait / slumlord_co_pin_motel under the "Wait until night" and
    "Meet Finger" objectives, on that marker, with GPS (cloned from Million Dollar Baby's pin).
    Script-registered pins do not render (Fight.reds), so the pin has to be a journal pin on a world node.
  - Onscreen text slumlord-co-pin: "Las Palapas Motel".

Node data is WolvenKit's packed worldNodeData (144 bytes a node). The node's global id at bytes 88-95 is
FNV-1a 64 of its NodeRef with the '#' removed ("$/slumlord/final_cut/slumlord_fc_marker" matches).
"""
import base64
import copy
import json
import math
import struct
from pathlib import Path

from add_boss_quests import Handles, find

ROOT = Path(__file__).resolve().parents[2]
SECTOR = ROOT / "wolvenkit/source/raw/slumlord/world/sectors/slumlord_markers.streamingsector.json"
JOURNAL = ROOT / "wolvenkit/source/raw/slumlord/journal/slumlord.journal.json"
ONSCREENS = ROOT / "wolvenkit/source/raw/slumlord/localization/en-us.json.json"

BASE = "$/slumlord/conversation_overtime/#"
# name: (x, y, z, yaw, template node index: 0 marker, 5 arms-crossed AI spot), captured in game 2026-11-19
NODES = {
    "slumlord_co_marker": (-1057.27, -1498.45, 25.75, 133.4, 0),
    "slumlord_co_spot_finger": (-1082.31, -1525.95, 25.78, -42.8, 5),   # beside the bike (moved 2026-11-20)
}
PINS = {"slumlord_co_wait": "slumlord_co_pin_wait", "slumlord_co_motel": "slumlord_co_pin_motel"}
REC = 144


def fnv1a64(s):
    h = 0xcbf29ce484222325
    for c in s.encode():
        h ^= c
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def sector():
    doc = json.loads(SECTOR.read_text(encoding="utf-8"))
    root = doc["Data"]["RootChunk"]
    data = bytearray(base64.b64decode(root["nodeData"]["Bytes"]))
    refs = [r["$value"] for r in root["nodeRefs"]]
    assert len(data) == REC * len(refs) == REC * len(root["nodes"])
    h = Handles(doc)
    changed = False
    for name, (x, y, z, yaw, tpl) in NODES.items():
        ref = BASE + name
        if ref in refs:   # already there: move it if its position changed
            idx = refs.index(ref)
            rec = bytearray(data[idx * REC:(idx + 1) * REC])
            half = math.radians(yaw) / 2
            new = bytearray(rec)
            struct.pack_into("<3f", new, 0, x, y, z)
            struct.pack_into("<4f", new, 16, 0.0, 0.0, math.sin(half), math.cos(half))
            for off in (44, 56, 68):
                struct.pack_into("<3f", new, off, x, y, z)
            if new != rec:
                data[idx * REC:(idx + 1) * REC] = new
                changed = True
            continue
        index = len(refs)
        rec = bytearray(data[tpl * REC:(tpl + 1) * REC])
        half = math.radians(yaw) / 2
        struct.pack_into("<3f", rec, 0, x, y, z)                          # position
        struct.pack_into("<4f", rec, 16, 0.0, 0.0, math.sin(half), math.cos(half))  # orientation
        for off in (44, 56, 68):                                           # pivot, bounds min, bounds max
            struct.pack_into("<3f", rec, off, x, y, z)
        struct.pack_into("<Q", rec, 88, fnv1a64(ref.replace("#", "")))     # global node id
        struct.pack_into("<H", rec, 112, index)                            # node index
        data += rec
        node = copy.deepcopy(root["nodes"][tpl])
        node["HandleId"] = h.take()
        inner = node["Data"]
        label = "[Static Marker] " if tpl == 0 else "[AI Spot] "
        inner["debugName"]["$value"] = label + name
        for key in ("data", "spot"):
            if isinstance(inner.get(key), dict) and "HandleId" in inner[key]:
                inner[key]["HandleId"] = h.take()
        root["nodes"].append(node)
        root["nodeRefs"].append({"$type": "NodeRef", "$storage": "string", "$value": ref})
        refs.append(ref)
        changed = True
    if changed:
        root["nodeData"]["Bytes"] = base64.b64encode(bytes(data)).decode()
        SECTOR.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def journal():
    doc = json.loads(JOURNAL.read_text(encoding="utf-8"))
    h = Handles(doc)
    root = doc["Data"]["RootChunk"]["entry"]["Data"]
    minor = find(find(root["entries"], "quests")["Data"]["entries"], "minor_quest")["Data"]["entries"]
    fc_go = find(find(find(minor, "slumlord_final_cut")["Data"]["entries"], "slumlord_fc_phase")["Data"]["entries"], "slumlord_fc_go")
    template = find(fc_go["Data"]["entries"], "slumlord_fc_pin")
    phase = find(find(minor, "slumlord_conversation_overtime")["Data"]["entries"], "slumlord_co_phase")["Data"]
    changed = False
    for objective_id, pin_id in PINS.items():
        objective = find(phase["entries"], objective_id)["Data"]
        if find(objective["entries"], pin_id):
            continue
        pin = copy.deepcopy(template)
        text = json.dumps(pin)
        # fresh handles for every handle inside the clone
        import re
        for old in sorted(set(re.findall(r'"HandleId": "(\d+)"', text)), key=int):
            text = text.replace('"HandleId": "%s"' % old, '"HandleId": "@%s"' % h.take())
        text = text.replace('"HandleId": "@', '"HandleId": "')
        pin = json.loads(text)
        d = pin["Data"]
        d["id"] = pin_id
        d["mappinData"]["debugCaption"] = "slumlord-co-pin"
        d["mappinData"]["localizedCaption"]["value"] = "slumlord-co-pin"
        d["reference"]["reference"]["$value"] = BASE + "slumlord_co_marker"
        objective["entries"].append(pin)
        changed = True
    if changed:
        JOURNAL.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def onscreens():
    doc = json.loads(ONSCREENS.read_text(encoding="utf-8"))
    entries = doc["Data"]["RootChunk"]["root"]["Data"]["entries"]
    if any(e["secondaryKey"] == "slumlord-co-pin" for e in entries):
        return False
    entries.append({"$type": "localizationPersistenceOnScreenEntry", "femaleVariant": "Las Palapas Motel",
                    "maleVariant": "", "primaryKey": "0", "secondaryKey": "slumlord-co-pin"})
    ONSCREENS.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return True


if __name__ == "__main__":
    print("sector nodes added:", sector())
    print("journal pins added:", journal())
    print("onscreen text added:", onscreens())
