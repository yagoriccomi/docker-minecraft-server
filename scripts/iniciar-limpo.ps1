# Limpa conflitos do Syncthing e sobe os conteineres (Minecraft + Syncthing).
# Usado tanto localmente quanto remotamente (via SSH pelo menu-remoto.bat).
$ErrorActionPreference = 'SilentlyContinue'
$root = 'D:\Server-Minecraft'

Write-Host 'Limpando arquivos de conflito do Syncthing (.sync-conflict-*)...'
Get-ChildItem -LiteralPath "$root\data" -Recurse -Filter '*.sync-conflict-*' -File |
    Remove-Item -Force

Write-Host 'Subindo os conteineres (Minecraft + Syncthing)...'
docker compose -f "$root\compose.yaml" up -d

Write-Host ''
Write-Host 'Servidor iniciado! Minecraft: porta 25565 | Syncthing: porta 8384'
