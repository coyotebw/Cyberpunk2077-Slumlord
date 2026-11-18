import zlib, statistics as st, sys
sys.path.insert(0,'/home/claude/sim')
def roll(pid, week, salt):
    s=f"slumlord.tenants.{pid}.{week}.{salt}".encode()
    x=zlib.crc32(s)
    x = x-2**32 if x>=2**31 else x   # Cast<Int32>
    return ((x % 10000)+10000)%10000/10000.0
# uniformity
vals=[roll(f"prop_{p}",w,s) for p in range(40) for w in range(200) for s in range(12)]
bins=[0]*10
for v in vals: bins[int(v*10)]+=1
print("deciles", [round(b/len(vals),3) for b in bins], "mean", round(st.mean(vals),4))
# per-property sequence correlation check: arrival roll (salt 1) across consecutive weeks
seq=[roll("wat_harbor_safehouse",w,1) for w in range(2000)]
c=st.correlation(seq[:-1],seq[1:]); print("lag-1 correlation", round(c,4))
# sim with crc rolls, Harbor Safehouse D, safety 2
ARR={0:.4,1:.7,2:1.2,3:2.5}; LV={0:.06,1:.045,2:.03,3:.02,4:.01}; SA={1:.7,2:.85,3:1,4:1.15,5:1.3}; SL={1:1.5,2:1.25,3:1,4:.8,5:.6}
def sim(pid,units,start,rank,safety,weeks=52):
    occ=start; full=None; hist=[]
    for w in range(1,weeks+1):
        out=sum(roll(pid,w,100+i)<LV[rank]*SL[safety] for i in range(occ)); occ-=out
        if rank==4: occ=units
        else:
            lam=ARR[rank]*SA[safety]; n=int(lam)+(roll(pid,w,1)<lam-int(lam)); occ+=min(n,units-occ)
        hist.append(occ)
        if full is None and occ==units: full=w
    return full, st.mean(hist[26:])/units
res=[sim(f"p{i}",6,1,0,2) for i in range(500)]
print("D, safety 2: median weeks to full", st.median([r[0] or 99 for r in res]), "avg occ", round(st.mean(r[1] for r in res)*100), "%")
