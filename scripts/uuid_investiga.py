"""Investigacao (somente leitura): de onde tirar os nicks dos UUIDs online."""
import json, uuid, os, glob

DATA = r"D:\Server-Minecraft\data"
WORLD = os.path.join(DATA, "world")
ORIG = r"D:\Games\MultiMC\instances\1.211\.minecraft"

def ver(u):
    try: return uuid.UUID(u).version
    except: return -1

# 1) UUIDs em playerdata, com versao (4=online, 3=offline)
print("=== playerdata (uuid -> versao) ===")
pd = os.path.join(WORLD, "playerdata")
uuids = []
for fn in sorted(os.listdir(pd)):
    if fn.endswith(".dat") and ".dat_old" not in fn:
        u = fn[:-4]
        uuids.append(u)
        print(f"  {u}  v{ver(u)}  ({'ONLINE' if ver(u)==4 else 'offline' if ver(u)==3 else '?'})")
print(f"  total .dat: {len(uuids)}")

# 2) usercache atual (data/)
print("\n=== data/usercache.json ===")
with open(os.path.join(DATA,'usercache.json'),encoding='utf-8') as f:
    print(json.dumps(json.load(f), indent=1, ensure_ascii=False))

# 3) usercache ORIGINAL do MultiMC
print("\n=== MultiMC usercache.json (fonte de nicks?) ===")
p = os.path.join(ORIG,'usercache.json')
if os.path.isfile(p):
    with open(p,encoding='utf-8') as f:
        data = json.load(f)
    print(f"  {len(data)} entradas:")
    for e in data:
        print(f"   {e.get('name'):<18} {e.get('uuid')}  v{ver(e.get('uuid',''))}")
else:
    print("  NAO existe:", p)

# 4) outros caches de nome
print("\n=== outros arquivos de nome ===")
for cand in ["usernamecache.json", os.path.join(ORIG,'usernamecache.json')]:
    print(f"  {cand} -> {'existe' if os.path.isfile(cand) else 'nao'}")

# 5) logs que mapeiam nick->uuid
print("\n=== logs com 'UUID of player' ===")
found = {}
for base in [os.path.join(DATA,'logs'), os.path.join(ORIG,'logs')]:
    for lg in glob.glob(os.path.join(base,'*.log*')) if os.path.isdir(base) else []:
        try:
            import gzip
            op = gzip.open if lg.endswith('.gz') else open
            with op(lg,'rt',encoding='utf-8',errors='ignore') as f:
                for line in f:
                    if 'UUID of player' in line:
                        # ... UUID of player NICK is UUID
                        parts = line.strip().split('UUID of player',1)[1].split(' is ')
                        if len(parts)==2:
                            found[parts[0].strip()] = parts[1].strip()
        except Exception as ex:
            pass
if found:
    for n,u in found.items():
        print(f"   {n:<18} {u}  v{ver(u)}")
else:
    print("  nenhum mapeamento nick->uuid encontrado em logs")
