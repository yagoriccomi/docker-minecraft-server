# Compacta o mapa em um .zip com data/hora. Usado local e remotamente.
$ErrorActionPreference = 'Stop'
$root = 'D:\Server-Minecraft'

if (-not (Test-Path "$root\backups")) {
    New-Item -ItemType Directory -Path "$root\backups" | Out-Null
}
$ts  = Get-Date -Format 'yyyyMMdd_HHmmss'
$dst = "$root\backups\world_backup_$ts.zip"
Compress-Archive -Path "$root\data\world\*" -DestinationPath $dst -Force
Write-Host "Backup criado em: $dst"
