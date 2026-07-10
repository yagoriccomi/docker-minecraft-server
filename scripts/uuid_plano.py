"""Verificacao do algoritmo offline + plano de migracao preciso (somente leitura)."""
import json, hashlib, uuid, os

DATA = r"D:\Server-Minecraft\data"
WORLD = os.path.join(DATA, "world")
ORIG = r"D:\Games\MultiMC\instances\1.211\.minecraft"

def offline_uuid(name):
    md5 = hashlib.md5(("OfflinePlayer:" + name).encode("utf-8")).digest()
    b = bytearray(md5); b[6]=(b[6]&0x0F)|0x30; b[8]=(b[8]&0x3F)|0x80
    return str(uuid.UUID(bytes=bytes(b)))

def ver(u):
    try: return uuid.UUID(u).version
    except: return -1

pd = {f[:-4].lower() for f in os.listdir(os.path.join(WORLD,'playerdata')) if f.endswith('.dat') and '.dat_old' not in f}

with open(os.path.join(ORIG,'usercache.json'),encoding='utf-8') as f:
    cache = json.load(f)

print("=== Verificacao: nick -> offline calculado vs uuid no cache MultiMC ===")
print(f"{'NICK':<18} {'UUID NO CACHE':<38} {'OFFLINE CALCULADO':<38} situacao")
print("-"*120)
migrar = []
for e in cache:
    name, cu = e['name'], e['uuid'].lower()
    off = offline_uuid(name)
    if cu == off:
        sit = "JA OFFLINE (ok, nao migrar)"
    elif ver(cu)==4:
        old_has = cu in pd; new_has = off in pd
        sit = f"ONLINE->precisa migrar | old_file={old_has} new_file={new_has}"
        if old_has:
            migrar.append((name, cu, off))
    else:
        sit = f"cache v{ver(cu)} != offline (?)"
    print(f"{name:<18} {cu:<38} {off:<38} {sit}")

print("\n=== UUIDs em playerdata SEM nick conhecido ===")
known = {e['uuid'].lower() for e in cache} | {offline_uuid(e['name']) for e in cache}
for u in sorted(pd):
    if u not in known:
        print(f"  {u}  v{ver(u)}  -> {'ONLINE sem nick (NAO da p/ migrar)' if ver(u)==4 else 'offline (provavelmente ja ok)' if ver(u)==3 else 'tipo incomum'}")

print("\n=== PLANO DE MIGRACAO (somente o que tem arquivo antigo) ===")
if migrar:
    for name, old, new in migrar:
        print(f"  {name}: {old}  ->  {new}")
else:
    print("  (nenhuma migracao automatica segura identificada)")
