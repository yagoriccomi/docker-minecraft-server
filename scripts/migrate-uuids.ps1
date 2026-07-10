# Migra dados de jogadores de UUID ONLINE (v4) para OFFLINE (v3).
# Chamado por import-world.ps1. Portavel e sem dependencia de Python.
# UUID offline do Minecraft = UUID v3 do MD5 de "OfflinePlayer:"+nick.
param(
    [Parameter(Mandatory)][string]$UserCache,   # usercache.json com os nicks
    [Parameter(Mandatory)][string]$WorldDir     # pasta 'world' de destino
)
$ErrorActionPreference = 'Stop'

function Get-OfflineUuid([string]$name) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $b = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("OfflinePlayer:$name"))
    $b[6] = ($b[6] -band 0x0F) -bor 0x30   # versao 3
    $b[8] = ($b[8] -band 0x3F) -bor 0x80   # variante RFC 4122
    $hex = -join ($b | ForEach-Object { $_.ToString('x2') })
    return ('{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0,8), $hex.Substring(8,4), `
            $hex.Substring(12,4), $hex.Substring(16,4), $hex.Substring(20,12))
}

Write-Host ''
Write-Host '=== Migracao de UUID online -> offline ===' -ForegroundColor Cyan

$cache = Get-Content $UserCache -Raw | ConvertFrom-Json
$dirs  = @('playerdata', 'stats', 'advancements')

$pdDir = Join-Path $WorldDir 'playerdata'
$existing = @()
if (Test-Path $pdDir) {
    $existing = Get-ChildItem $pdDir -File | ForEach-Object {
        [IO.Path]::GetFileNameWithoutExtension($_.Name).ToLower()
    }
}

# Monta o plano: nicks cujo UUID no cache e online (v4) e que possuem arquivo
$plan = @()
foreach ($e in $cache) {
    if (-not $e.name -or -not $e.uuid) { continue }
    $cu  = $e.uuid.ToLower()
    $off = (Get-OfflineUuid $e.name).ToLower()
    if ($cu -eq $off) { continue }                 # ja esta offline
    if ($cu.Substring(14,1) -ne '4') { continue }  # nao e UUID online (v4)
    if ($existing -contains $cu) {
        $plan += [pscustomobject]@{ Name = $e.name; Old = $cu; New = $off }
    }
}

if ($plan.Count -eq 0) {
    Write-Host 'Nenhum jogador com UUID online encontrado. Nada a migrar (os dados ja estao corretos).' -ForegroundColor Yellow
    return
}

Write-Host 'Jogadores a migrar:'
$plan | ForEach-Object { Write-Host ("  {0}: {1} -> {2}" -f $_.Name, $_.Old, $_.New) }

$moved = 0
foreach ($p in $plan) {
    foreach ($d in $dirs) {
        $dir = Join-Path $WorldDir $d
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem $dir -File | Where-Object { $_.Name.ToLower().StartsWith($p.Old) } | ForEach-Object {
            $newName = $p.New + $_.Name.Substring($p.Old.Length)
            $dst = Join-Path $dir $newName
            if (Test-Path $dst) { Remove-Item $dst -Force }   # sobrescreve o "novo" vazio
            Rename-Item -LiteralPath $_.FullName -NewName $newName -Force
            $moved++
        }
    }
}
Write-Host ("[OK] $moved arquivo(s) de jogador migrados para UUID offline.") -ForegroundColor Green
