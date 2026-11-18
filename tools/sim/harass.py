import random, statistics as st
ARR={0:.4,1:.7,2:1.2,3:2.5}; LV={0:.06,1:.045,2:.03,3:.02,4:.01}; SA=0.85; SL=1.25  # Santo Domingo, safety 2
def run(units,start,rank,p,weeks=52,trials=3000):
    rng=random.Random(2); occs=[]; events=[]
    for _ in range(trials):
        occ=start; h=[]; ev=0
        for w in range(weeks):
            occ-=sum(rng.random()<LV[rank]*SL for _ in range(occ))
            if occ>0 and rng.random()<p: occ-=1; ev+=1      # lease broken by Finger's people
            if rank==4: occ=units
            else:
                lam=ARR[rank]*SA; n=int(lam)+(rng.random()<lam-int(lam)); occ+=min(n,units-occ)
            h.append(occ)
        occs.append(st.mean(h[13:])/units); events.append(ev/weeks)
    return st.mean(occs)*100, st.mean(events)
print("6-unit Santo Domingo building, starts at 3 tenants; avg occupancy weeks 14-52, lease-broken texts per week")
for rank in (0,1,2):
    row=[f"{'DCBAS'[rank]}:"]
    for p in (0,0.10,0.20,0.30):
        o,e=run(6,3,rank,p); row.append(f"p={p:.2f} {o:4.0f}% ({e:.2f}/wk)")
    print("  ".join(row))
