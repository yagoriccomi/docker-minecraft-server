"""
Fase 2 - Migracao YagoRsxx (online -> offline).
Faz backup das pastas afetadas FORA de data/ (para nao sincronizar) e renomeia
playerdata/stats/advancements do UUID antigo para o novo, sobrescrevendo.
"""
import os, shutil, time

DATA = r"D:\Server-Minecraft\data"
WORLD = os.path.join(DATA, "world")
ROOT = r"D:\Server-Minecraft"

OLD = "aaf8eea1-3e79-42a3-a999-0fdc75e2d704"
NEW = "69ec4329-7b90-39b2-b26b-36a89b2c6de3"
DIRS = ["playerdata", "stats", "advancements"]

# 1) backup (fora de data/, nao entra no Syncthing)
ts = time.strftime("%Y%m%d_%H%M%S")
bdir = os.path.join(ROOT, f"_uuid_backup_{ts}")
for d in DIRS:
    src = os.path.join(WORLD, d)
    if os.path.isdir(src):
        shutil.copytree(src, os.path.join(bdir, d))
print(f"[backup] pastas copiadas para: {bdir}\n")

# 2) migracao (rename old -> new, sobrescrevendo)
print(f"{'PASTA':<14} {'ARQUIVO ANTIGO':<46} -> {'ARQUIVO NOVO'}")
print("-" * 100)
moved = 0
for d in DIRS:
    sd = os.path.join(WORLD, d)
    if not os.path.isdir(sd):
        continue
    for fn in list(os.listdir(sd)):
        if fn.lower().startswith(OLD.lower()):
            newname = NEW + fn[len(OLD):]          # preserva extensao (.dat, .dat_old, .json)
            src = os.path.join(sd, fn)
            dst = os.path.join(sd, newname)
            if os.path.exists(dst):
                os.remove(dst)                      # sobrescreve o "novo" vazio
            os.rename(src, dst)
            moved += 1
            print(f"{d:<14} {fn:<46} -> {newname}")

print(f"\n[ok] {moved} arquivo(s) migrado(s) para o UUID offline de YagoRsxx.")

# 3) conferencia
print("\n=== Conferencia pos-migracao ===")
for d in DIRS:
    sd = os.path.join(WORLD, d)
    old_left = any(f.lower().startswith(OLD.lower()) for f in os.listdir(sd))
    new_ok = any(f.lower().startswith(NEW.lower()) for f in os.listdir(sd))
    size = 0
    for f in os.listdir(sd):
        if f.lower().startswith(NEW.lower()):
            size = os.path.getsize(os.path.join(sd, f))
            break
    print(f"  {d:<14} antigo_restante={old_left}  novo_presente={new_ok}  ({size} bytes)")
