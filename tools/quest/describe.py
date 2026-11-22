#!/usr/bin/env python3
"""Describe a .questphase or .scene (WolvenKit CR2W-JSON) as readable text.

Resolves WolvenKit handle references (HandleId / HandleRefId), walks nested phase graphs and prints each node
with its id, type, sub-type, compact parameters, and the nodes its output sockets lead to.

  describe.py file.questphase.json [--full] [--node ID]
"""
import json, sys

def load(path):
    d = json.load(open(path, encoding='utf-8'))
    handles = {}
    def index(o):
        if isinstance(o, dict):
            if 'HandleId' in o and 'Data' in o:
                handles[o['HandleId']] = o
            for v in o.values(): index(v)
        elif isinstance(o, list):
            for v in o: index(v)
    index(d)
    return d, handles

def deref(o, handles):
    if isinstance(o, dict) and 'HandleRefId' in o:
        return handles.get(o['HandleRefId'], {})
    return o

def strip(o, handles, depth=0):
    """Compact view of parameters: drop sockets/graphs, resolve handles, flatten NodeRef/CName values."""
    o = deref(o, handles)
    if isinstance(o, dict):
        if set(o.keys()) >= {'$type', '$value'} and o.get('$storage') in ('string', 'uint64'):
            return o['$value']
        if 'HandleId' in o and 'Data' in o:
            return strip(o['Data'], handles, depth)
        out = {}
        for k, v in o.items():
            if k in ('sockets', 'phaseGraph', 'graph', 'HandleId', 'connections'): continue
            if k == '$type' and depth > 0: out[k] = v; continue
            sv = strip(v, handles, depth + 1)
            if sv in (None, '', [], {}, 0, 'None') and k != 'id': continue
            out[k] = sv
        return out
    if isinstance(o, list):
        return [strip(v, handles, depth + 1) for v in o]
    return o

def nm(v):
    return v.get('$value', '?') if isinstance(v, dict) else v

def node_sub(nd):
    t = nd.get('type')
    if isinstance(t, dict):
        t = t.get('Data', t)
        if isinstance(t, dict): return t.get('$type', '')
    return ''

def describe(nodes, handles, indent=0, full=False):
    sock_owner = {}
    for n in nodes:
        n2 = deref(n, handles); nd = n2.get('Data', n2)
        for s in nd.get('sockets', []):
            s2 = deref(s, handles)
            hid = s2.get('HandleId') if 'HandleId' in s2 else s.get('HandleRefId')
            sd = s2.get('Data', s2)
            sock_owner[hid] = (nd.get('id'), nm(sd.get('name', '?')))
    pad = '  ' * indent
    for n in nodes:
        n2 = deref(n, handles); nd = n2.get('Data', n2)
        t = nd['$type'].replace('NodeDefinition', '').replace('quest', '')
        sub = node_sub(nd).replace('quest', '').replace('_NodeType', '')
        params = strip({k: v for k, v in nd.items() if k not in ('id', '$type')}, handles)
        ps = json.dumps(params, ensure_ascii=False)
        if not full and len(ps) > 400: ps = ps[:400] + '…'
        outs = []
        for s in nd.get('sockets', []):
            s2 = deref(s, handles); sd = s2.get('Data', s2)
            for c in sd.get('connections', []):
                cd = deref(c, handles).get('Data', {})
                dst = cd.get('destination', {})
                hid = dst.get('HandleRefId') or dst.get('HandleId')
                if hid in sock_owner and sock_owner[hid][0] != nd.get('id'):
                    outs.append(f"{nm(sd.get('name'))}→{sock_owner[hid][0]}.{sock_owner[hid][1]}")
        print(f"{pad}[{nd.get('id')}] {t}{(' / ' + sub) if sub else ''}  {ps}")
        if outs: print(f"{pad}     → {', '.join(outs)}")
        pg = nd.get('phaseGraph')
        if pg:
            g = deref(pg, handles).get('Data', {})
            if g.get('nodes'):
                print(f"{pad}  {{ inline phase, {len(g['nodes'])} nodes")
                describe(g['nodes'], handles, indent + 2, full)
                print(f"{pad}  }}")

def main():
    path = sys.argv[1]; full = '--full' in sys.argv
    d, handles = load(path)
    root = d['Data']['RootChunk']
    if 'graph' in root:
        g = deref(root['graph'], handles).get('Data', {})
        describe(g.get('nodes', []), handles, 0, full)
    elif 'sceneGraph' in root:
        g = deref(root['sceneGraph'], handles).get('Data', {})
        describe(g.get('graph', []), handles, 0, full)

if __name__ == '__main__':
    main()
