"""Add the boss-quest entries decided 2026-11-18 to Slumlord's journal and onscreen texts.

Idempotent. Edits the WolvenKit raw JSON in place (see add_realty_contact.py for the convert/pack step):
  - Million Dollar Baby (quests/minor_quest/slumlord_final_cut): "Buy up Watson (n/5)" objectives
    slumlord_fc_buy_0..4 and an intro description slumlord_fc_desc_intro (the quest now starts after
    Oshima's call).
  - Conversation Overtime (quests/minor_quest/slumlord_conversation_overtime): phase slumlord_co_phase with "Buy up Santo Domingo
    (n/5)" objectives slumlord_co_buy_0..5, slumlord_co_wait, slumlord_co_motel, slumlord_co_goons, and
    descriptions slumlord_co_desc_intro / slumlord_co_desc_motel. The motel map pin is added once the
    Las Palapas marker exists in the world sector.
  - Slumlord Realty: message slumlord_realty_alert (lease-broken alerts; live text drawn by script).

The game reads objective counters from engine code that scripts cannot set, so "n/5" is five static
objectives; script activates the one matching the number of properties owned.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JOURNAL = ROOT / "wolvenkit/source/raw/slumlord/journal/slumlord.journal.json"
ONSCREENS = ROOT / "wolvenkit/source/raw/slumlord/localization/en-us.json.json"

TEXTS = {
    "slumlord-fc-desc-intro": "A braindance director called Hideyoshi Oshima wants you out of Watson. Buy up the district anyway.",
    "slumlord-co-title": "Conversation Overtime",
    "slumlord-co-desc-intro": "Quentin Finger, who owns the Las Palapas Motel, says Santo Domingo has one landlord: him. If you keep buying, he'll run you out of town. Buy up the district anyway.",
    "slumlord-co-desc-motel": "Finger says he stole something of yours. He wants you at the Las Palapas Motel tonight. Alone.",
    "slumlord-co-wait": "Wait until night",
    "slumlord-co-motel": "Meet Finger at the Las Palapas Motel",
    "slumlord-co-goons": "Deal with Finger's goons",
    "slumlord-realty-alert": "TENANT MOVED OUT - LEASE BROKEN!",
}
for n in range(6):
    TEXTS[f"slumlord-fc-buy-{n}"] = f"Buy up Watson ({n}/5)"
    TEXTS[f"slumlord-co-buy-{n}"] = f"Buy up Santo Domingo ({n}/5)"


class Handles:
    def __init__(self, doc):
        used = [int(x) for x in re.findall(r'"HandleId": "(\d+)"', json.dumps(doc))]
        self.next = max(used) + 1

    def take(self):
        h = self.next
        self.next += 1
        return str(h)


def loc(key):
    return {"unk1": "0", "value": key}


def nodes_ref(value="0"):
    return {"$type": "NodeRef", "$storage": "uint64", "$value": value}


def tdb0():
    return {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}


def objective(h, oid, key):
    return {"HandleId": h.take(), "Data": {
        "$type": "gameJournalQuestObjective", "counter": 0, "description": loc(key), "districtID": "",
        "entries": [], "id": oid, "itemID": tdb0(), "journalEntryOverrideDataList": [],
        "locationPrefabRef": nodes_ref(), "optional": 0}}


def description(h, did, key):
    return {"HandleId": h.take(), "Data": {"$type": "gameJournalQuestDescription", "description": loc(key), "id": did}}


def find(entries, eid):
    for e in entries:
        if e["Data"].get("id") == eid:
            return e
    return None


def main():
    doc = json.loads(JOURNAL.read_text(encoding="utf-8"))
    h = Handles(doc)
    root = doc["Data"]["RootChunk"]["entry"]["Data"]
    quests = find(root["entries"], "quests")["Data"]["entries"]
    minor = find(quests, "minor_quest")["Data"]["entries"]
    changed = False

    # Million Dollar Baby: buy objectives + intro description.
    mdb = find(minor, "slumlord_final_cut")["Data"]
    phase = find(mdb["entries"], "slumlord_fc_phase")["Data"]
    for n in range(6):
        if not find(phase["entries"], f"slumlord_fc_buy_{n}"):
            phase["entries"].append(objective(h, f"slumlord_fc_buy_{n}", f"slumlord-fc-buy-{n}"))
            changed = True
    if not find(mdb["entries"], "slumlord_fc_desc_intro"):
        mdb["entries"].append(description(h, "slumlord_fc_desc_intro", "slumlord-fc-desc-intro"))
        changed = True

    # Conversation Overtime.
    if not find(minor, "slumlord_conversation_overtime"):
        wb_phase_entries = [objective(h, f"slumlord_co_buy_{n}", f"slumlord-co-buy-{n}") for n in range(6)]
        wb_phase_entries += [objective(h, "slumlord_co_wait", "slumlord-co-wait"),
                             objective(h, "slumlord_co_motel", "slumlord-co-motel"),
                             objective(h, "slumlord_co_goons", "slumlord-co-goons")]
        wb_phase = {"HandleId": h.take(), "Data": {
            "$type": "gameJournalQuestPhase", "id": "slumlord_co_phase", "journalEntryOverrideDataList": [],
            "locationPrefabRef": nodes_ref(), "entries": wb_phase_entries}}
        quest = {"HandleId": h.take(), "Data": {
            "$type": "gameJournalQuest", "districtID": "Districts.SantoDomingo", "id": "slumlord_conversation_overtime",
            "journalEntryOverrideDataList": [], "recommendedLevelID": tdb0(), "title": loc("slumlord-co-title"),
            "type": "MinorQuest",
            "entries": [wb_phase,
                        description(h, "slumlord_co_desc_intro", "slumlord-co-desc-intro"),
                        description(h, "slumlord_co_desc_motel", "slumlord-co-desc-motel")]}}
        minor.append(quest)
        changed = True

    wb = find(minor, "slumlord_conversation_overtime")["Data"]
    wb_phase = find(wb["entries"], "slumlord_co_phase")["Data"]
    for n in range(6):
        if not find(wb_phase["entries"], f"slumlord_co_buy_{n}"):
            wb_phase["entries"].insert(n, objective(h, f"slumlord_co_buy_{n}", f"slumlord-co-buy-{n}"))
            changed = True

    # Slumlord Realty: lease-broken alert message.
    contacts = find(root["entries"], "contacts")["Data"]["entries"]
    realty = find(contacts, "slumlord_realty")
    if realty is None:
        raise SystemExit("Run add_realty_contact.py first.")
    thread = find(realty["Data"]["entries"], "slumlord_realty_reports")["Data"]
    if not find(thread["entries"], "slumlord_realty_alert"):
        thread["entries"].append({"HandleId": h.take(), "Data": {
            "$type": "gameJournalPhoneMessage", "attachment": None, "delay": 1, "id": "slumlord_realty_alert",
            "imageId": tdb0(), "isQuestImportant": 0, "journalEntryOverrideDataList": [], "sender": "NPC",
            "text": loc("slumlord-realty-alert")}})
        changed = True

    onscreens = json.loads(ONSCREENS.read_text(encoding="utf-8"))
    entries = onscreens["Data"]["RootChunk"]["root"]["Data"]["entries"]
    have = {e["secondaryKey"] for e in entries}
    added = 0
    for key, text in TEXTS.items():
        if key not in have:
            entries.append({"$type": "localizationPersistenceOnScreenEntry", "femaleVariant": text,
                            "maleVariant": "", "primaryKey": "0", "secondaryKey": key})
            added += 1

    if changed:
        JOURNAL.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if added:
        ONSCREENS.write_text(json.dumps(onscreens, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"journal changed: {changed}, texts added: {added}")


if __name__ == "__main__":
    main()
