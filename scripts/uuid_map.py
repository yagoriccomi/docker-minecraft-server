"""
Fase 1 - Mapeamento de UUIDs (somente leitura, NAO altera nada).
Le data/usercache.json, calcula o UUID offline de cada nick e cruza com os
arquivos existentes em world/playerdata para identificar quem precisa migrar.
"""
import json, hashlib, uuid, os

DATA = r"D:\Server-Minecraft\data"
WORLD = os.path.join(DATA, "world")


def offline_uuid(name: str) -> str:
    """UUID v3 do MD5 de 'OfflinePlayer:'+nick (algoritmo do Minecraft)."""
    md5 = hashlib.md5(("OfflinePlayer:" + name).encode("utf-8")).digest()
    b = bytearray(md5)
    b[6] = (b[6] & 0x0F) | 0x30  # versao 3
    b[8] = (b[8] & 0x3F) | 0x80  # variante RFC 4122
    return str(uuid.UUID(bytes=bytes(b)))


def ver(u: str) -> int:
    try:
        return uuid.UUID(u).version
    except Exception:
        return -1


# --- ler usercache ---
with open(os.path.join(DATA, "usercache.json"), encoding="utf-8") as f:
    cache = json.load(f)

# nick -> conjunto de uuids vistos no cache
seen = {}
for e in cache:
    seen.setdefault(e["name"], set()).add(e["uuid"].lower())

# --- arquivos existentes por pasta ---
def ids_in(sub):
    d = os.path.join(WORLD, sub)
    out = set()
    if os.path.isdir(d):
        for fn in os.listdir(d):
            if fn.endswith(".dat") or fn.endswith(".json"):
                out.add(os.path.splitext(fn)[0].lower())
    return out

pd = ids_in("playerdata")
stt = ids_in("stats")
adv = ids_in("advancements")

print(f"usercache: {len(cache)} entradas | nicks unicos: {len(seen)}")
print(f"arquivos playerdata={len(pd)} stats={len(stt)} advancements={len(adv)}\n")

rows = []
for name in sorted(seen):
    new = offline_uuid(name)
    # uuid antigo = o do cache que NAO eh o offline e que tem arquivo playerdata
    candidates = [u for u in seen[name] if u != new]
    old = None
    for c in candidates:
        if c in pd:
            old = c
            break
    if old is None and candidates:
        old = sorted(candidates)[0]  # melhor palpite mesmo sem arquivo
    rows.append((name, old, new))

# tabela
print(f"{'NICK':<18} {'UUID ANTIGO (online)':<38} {'UUID OFFLINE NOVO':<38} {'arq?'}")
print("-" * 110)
for name, old, new in rows:
    flags = []
    if old:
        if old in pd: flags.append("pd")
        if old in stt: flags.append("st")
        if old in adv: flags.append("adv")
    has = "+".join(flags) if flags else "(sem arq antigo)"
    novo_existe = "NEW-ja-existe" if new in pd else ""
    print(f"{name:<18} {str(old):<38} {new:<38} {has} {novo_existe}")

print("\nLegenda: pd=playerdata, st=stats, adv=advancements | "
      "v(antigo)=", {r[0]: ver(r[1]) for r in rows if r[1]})
