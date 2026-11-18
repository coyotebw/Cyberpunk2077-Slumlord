import random, statistics as st
RANKS="DCBAS"
ARRIVE={'D':0.40,'C':0.70,'B':1.20,'A':2.50,'S':None}   # tenants/week at safety 3; S = fill all vacancies
LEAVE ={'D':0.06,'C':0.045,'B':0.03,'A':0.02,'S':0.01} # chance per tenant per week at safety 3
SAFE_ARR={1:0.70,2:0.85,3:1.00,4:1.15,5:1.30}
SAFE_LEAVE={1:1.50,2:1.25,3:1.00,4:0.80,5:0.60}
def week(occ,units,r,s,rng):
    left=sum(rng.random()<LEAVE[r]*SAFE_LEAVE[s] for _ in range(occ)); occ-=left
    vac=units-occ
    if ARRIVE[r] is None: return units
    lam=ARRIVE[r]*SAFE_ARR[s]; n=int(lam)+(rng.random()<lam-int(lam))
    return occ+min(n,vac)
def run(units,start,r,s,weeks=52,trials=4000):
    rng=random.Random(1); fill=[]; ss=[]
    for _ in range(trials):
        occ=start; t=None; hist=[]
        for w in range(1,weeks+1):
            occ=week(occ,units,r,s,rng); hist.append(occ)
            if t is None and occ==units: t=w
        fill.append(t if t else 99); ss.append(st.mean(hist[26:]))
    return st.median(fill), st.mean(ss)/units
print("Harbor Safehouse case: 6 units, starts with 1 tenant")
print("rank safety | median weeks to full | avg occupancy (weeks 27-52)")
for r in RANKS:
    for s in (1,2,3,5):
        f,o=run(6,1,r,s); print(f"  {r}    {s}    | {f:5.1f} | {o*100:4.0f}%")
