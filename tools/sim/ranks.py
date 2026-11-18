import math
# Contractor tiers: stars -> (fee per job, work points per job)
TIERS={1:(500,600),2:(1500,2000),3:(4000,6000),4:(10000,16000),5:(25000,45000)}
FIT={'◎':1.5,'○':1.0,'△':0.6,'×':0.3}
K=[0.30,0.50,0.80,1.20]          # points to next rank, as a share of purchase price (D->C, C->B, B->A, A->S)
MULT=[1.0,1.25,1.5,1.8,2.2]
OCC={0:0.66,1:0.92,2:1.0,3:1.0,4:1.0}   # Watson (safety 2) settled occupancy by rank, from the tenant sim
JOBS=3
props=[("Kabuki Waterfront",3499,3,110,False),("Harbor Safehouse",5150,6,109,False),("Capitan Caliente",6350,1,650,True),
       ("Bradbury & Boreas",9275,4,160,False),("Kabuki Shop Booth",10000,1,850,True),("City Center 16-unit (draft)",160000,16,400,False)]
def weekly(units,rent,rank,commercial):
    occ=1.0 if commercial else OCC[rank]   # shop: occupied nearly always
    return units*rent*MULT[rank]*occ
print(f"{'property':30} {'contractor':12} {'weeks to S':>10} {'cost to S':>10} {'rent D->S /wk':>16} {'payback wks':>11}")
for name,price,units,rent,com in props:
    for stars,fit in ((1,'○'),(2,'○'),(3,'◎'),(5,'◎')):
        fee,work=TIERS[stars]; pts=work*FIT[fit]
        need=sum(price*k for k in K); jobs=math.ceil(need/pts); weeks=math.ceil(jobs/JOBS)
        cost=jobs*fee; gain=weekly(units,rent,4,com)-weekly(units,rent,0,com)
        print(f"{name:30} {str(stars)+'★ '+fit:12} {weeks:10} {cost:10,} {round(weekly(units,rent,0,com)):>7,}->{round(weekly(units,rent,4,com)):<7,} {cost/gain:11.1f}")

print("\n--- with cap: a job raises at most one rank; points past the next rank are lost ---")
def run(price,pts,fee):
    rank=0; bar=0; jobs=0; weeks=0
    while rank<4:
        weeks+=1
        for _ in range(JOBS):
            if rank>=4: break
            jobs+=1; bar+=pts; need=price*K[rank]
            if bar>=need: rank+=1; bar=0
    return weeks,jobs*fee
print(f"{'property':30} {'contractor':12} {'weeks to S':>10} {'cost to S':>10} {'payback wks':>11}")
for name,price,units,rent,com in props:
    for stars,fit in ((1,'○'),(2,'○'),(3,'◎'),(5,'◎')):
        fee,work=TIERS[stars]; w,c=run(price,work*FIT[fit],fee)
        gain=weekly(units,rent,4,com)-weekly(units,rent,0,com)
        print(f"{name:30} {str(stars)+'★ '+fit:12} {w:10} {c:10,} {c/gain:11.1f}")
