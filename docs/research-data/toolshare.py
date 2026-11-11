import json,sys,collections
f=sys.argv[1]
names={}; size=collections.Counter(); cnt=collections.Counter(); big=[]
tot_res=0; tot_user=0; tot_asst=0
def sz(c):
    if isinstance(c,str): return len(c.encode())
    if isinstance(c,list): return sum(sz(x.get("text",x) if isinstance(x,dict) else x) for x in c)
    return len(json.dumps(c).encode())
for line in open(f):
    try: o=json.loads(line)
    except: continue
    m=o.get("message")
    if not isinstance(m,dict): continue
    c=m.get("content")
    if isinstance(c,str):
        if m.get("role")=="user": tot_user+=len(c.encode())
        continue
    if not isinstance(c,list): continue
    for b in c:
        if not isinstance(b,dict): continue
        t=b.get("type")
        if t=="tool_use": names[b["id"]]=b.get("name")
        elif t=="tool_result":
            n=names.get(b.get("tool_use_id"),"?"); s=sz(b.get("content")); size[n]+=s; cnt[n]+=1; tot_res+=s
            big.append((s,n))
        elif t=="text":
            if m.get("role")=="assistant": tot_asst+=len(b.get("text","").encode())
            else: tot_user+=len(b.get("text","").encode())
print("tool_result bytes",tot_res,"assistant text",tot_asst,"user text",tot_user)
print("tool_result share of (result+assistant+user text): %.1f%%"%(100*tot_res/max(1,tot_res+tot_asst+tot_user)))
for n,s in size.most_common(8): print(n,cnt[n],s)
big.sort(reverse=True)
over16=[b for b in big if b[0]>16384]; over4=[b for b in big if b[0]>4096]
print("results >16KB:",len(over16),sum(b[0] for b in over16),"; >4KB:",len(over4),sum(b[0] for b in over4),"; total results",len(big))
