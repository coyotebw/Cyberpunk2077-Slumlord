#!/usr/bin/env python3
"""Describe a .scene (WolvenKit CR2W-JSON): actors, entry/exit points, graph nodes with events, lines, choices."""
import json, sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
from describe import load, deref, strip

def v(x):
    return x.get('$value') if isinstance(x, dict) and '$value' in x else x

def main():
    path = sys.argv[1]; full = '--full' in sys.argv
    d, H = load(path); r = d['Data']['RootChunk']
    print('category', r.get('sceneCategoryTag'))
    for a in r['actors']:
        cp = a.get('communityParams', {})
        print('actor', a['actorId']['id'], a['actorName'], a['acquisitionPlan'], 'community', v(cp.get('reference')), v(cp.get('entryName')), 'spawner', json.dumps(strip(a.get('spawnerParams'), H))[:200], 'spawnSet', json.dumps(strip(a.get('spawnSetParams'), H))[:160])
    for a in r['playerActors']:
        print('player', a['actorId']['id'], a.get('playerName'), a['acquisitionPlan'], v(a.get('specCharacterRecordId')))
    print('entry', [(v(e['name']), e['nodeId']['id']) for e in r['entryPoints']])
    print('exit', [(v(e['name']), e['nodeId']['id']) for e in r['exitPoints']])
    lines = {l['itemId']['id']: l for l in r['screenplayStore']['lines']}
    opts = {o['itemId']['id']: o for o in r['screenplayStore']['options']}
    vp = {e['locstringId']['ruid'] if isinstance(e.get('locstringId'), dict) and 'ruid' in e['locstringId'] else None: e for e in r['locStore'].get('vpEntries', [])}
    g = deref(r['sceneGraph'], H)['Data']
    for n in g['graph']:
        nd = deref(n, H)['Data']; t = nd['$type']
        outs = []
        for i, s in enumerate(nd.get('outputSockets', [])):
            for dst in s.get('destinations', []):
                outs.append(f"{s['stamp']['name']}/{s['stamp']['ordinal']}→{dst['nodeId']['id']}.{dst['isockStamp']['name']}")
        extra = ''
        if t == 'scnSectionNode' or t == 'scnRewindableSectionNode':
            evs = []
            for e in nd.get('events', []):
                ed = deref(e, H)['Data']; et = ed['$type']
                s = f"{ed.get('startTime')}+{ed.get('duration')} {et}"
                if et == 'scnDialogLineEvent':
                    sid = ed['screenplayLineId']['id']; L = lines.get(sid, {})
                    s += f" line{sid} spk={L.get('speaker',{}).get('id')} to={L.get('addressee',{}).get('id')} loc={L.get('locstringId',{}).get('ruid')}"
                elif full:
                    s += ' ' + json.dumps(strip(ed, H))[:300]
                else:
                    s += ' perf=' + str(ed.get('performer', {}).get('id', ''))
                evs.append(s)
            extra = f" dur={nd.get('sectionDuration',{}).get('stu')} events:\n      " + '\n      '.join(evs)
        elif t == 'scnChoiceNode':
            ol = []
            for o in nd.get('options', []):
                sid = o['screenplayOptionId']['id']; O = opts.get(sid, {})
                ol.append(f"opt{sid} loc={O.get('locstringId',{}).get('ruid')} {o.get('type',{}).get('properties')} {json.dumps(strip(o, H))[:250] if full else ''}")
            extra = f" mode={json.dumps(strip(nd.get('displayNameOverride'),H))[:60]} {json.dumps(strip(nd.get('choiceFlags'), H))} options:\n      " + '\n      '.join(ol)
        elif t == 'scnQuestNode':
            extra = ' ' + json.dumps(strip(nd.get('questNode'), H))[:600]
        elif full:
            extra = ' ' + json.dumps(strip({k: x for k, x in nd.items() if k not in ('outputSockets', 'nodeId')}, H))[:600]
        print(f"[{nd['nodeId']['id']}] {t}{extra}")
        if outs: print('     → ' + ', '.join(outs))
    print('interruption scenarios', len(r.get('interruptionScenarios', [])))
    for s in r.get('interruptionScenarios', []):
        print('  ', json.dumps(strip(s, H))[:500])

main()
