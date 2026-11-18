"""Add the "Slumlord Realty" texter to Slumlord's journal and its texts to the onscreen file.

Idempotent: running it again changes nothing. Edits the WolvenKit raw JSON in place:
  wolvenkit/source/raw/slumlord/journal/slumlord.journal.json
  wolvenkit/source/raw/slumlord/localization/en-us.json.json
Then convert and pack:
  cp77tools convert d wolvenkit/source/raw/slumlord/journal wolvenkit/source/raw/slumlord/localization
  (move the .journal / .json CR2W outputs into wolvenkit/source/archive/slumlord/...)

The weekly tenant report is one message that Tenants.reds re-sends each rent day; its text
on screen is replaced by the live report (SlumlordTenantReport). The onscreen text below is
only the fallback, shown wherever the game draws the message without going through that hook.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JOURNAL = ROOT / "wolvenkit/source/raw/slumlord/journal/slumlord.journal.json"
ONSCREENS = ROOT / "wolvenkit/source/raw/slumlord/localization/en-us.json.json"

CONTACT_ID = "slumlord_realty"
THREAD_ID = "slumlord_realty_reports"
MESSAGE_ID = "slumlord_realty_report"

TEXTS = {
    "slumlord-realty-name": "Slumlord Realty",
    "slumlord-realty-thread": "Tenant reports",
    "slumlord-realty-report": "Your weekly tenant report is ready.",
}


def loc(key):
    return {"unk1": "0", "value": key}


def add_contact(doc):
    root = doc["Data"]["RootChunk"]["entry"]["Data"]
    contacts = next(e for e in root["entries"] if e["Data"]["id"] == "contacts")
    if any(c["Data"]["id"] == CONTACT_ID for c in contacts["Data"]["entries"]):
        return False
    used = [int(x) for x in re.findall(r'"HandleId": "(\d+)"', json.dumps(doc))]
    h = max(used) + 1
    message = {
        "HandleId": str(h),
        "Data": {
            "$type": "gameJournalPhoneMessage",
            "attachment": None,
            "delay": 1,
            "id": MESSAGE_ID,
            "imageId": {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"},
            "isQuestImportant": 0,
            "journalEntryOverrideDataList": [],
            "sender": "NPC",
            "text": loc("slumlord-realty-report"),
        },
    }
    thread = {
        "HandleId": str(h + 1),
        "Data": {
            "$type": "gameJournalPhoneConversation",
            "id": THREAD_ID,
            "journalEntryOverrideDataList": [],
            "title": loc("slumlord-realty-thread"),
            "entries": [message],
        },
    }
    contact = {
        "HandleId": str(h + 2),
        "Data": {
            "$type": "gameJournalContact",
            "avatarID": {"$type": "TweakDBID", "$storage": "string", "$value": "PhoneAvatars.Avatar_Unknown"},
            "id": CONTACT_ID,
            "isCallableDefault": 0,
            "journalEntryOverrideDataList": [],
            "name": loc("slumlord-realty-name"),
            "type": "Texter",
            "useFlatMessageLayout": 1,
            "entries": [thread],
        },
    }
    contacts["Data"]["entries"].append(contact)
    return True


def add_texts(doc):
    entries = doc["Data"]["RootChunk"]["root"]["Data"]["entries"]
    have = {e["secondaryKey"] for e in entries}
    added = 0
    for key, text in TEXTS.items():
        if key in have:
            continue
        entries.append({
            "$type": "localizationPersistenceOnScreenEntry",
            "femaleVariant": text,
            "maleVariant": "",
            "primaryKey": "0",
            "secondaryKey": key,
        })
        added += 1
    return added


def main():
    journal = json.loads(JOURNAL.read_text(encoding="utf-8"))
    onscreens = json.loads(ONSCREENS.read_text(encoding="utf-8"))
    contact_added = add_contact(journal)
    texts_added = add_texts(onscreens)
    if contact_added:
        JOURNAL.write_text(json.dumps(journal, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if texts_added:
        ONSCREENS.write_text(json.dumps(onscreens, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"contact added: {contact_added}, texts added: {texts_added}")


if __name__ == "__main__":
    sys.exit(main())
