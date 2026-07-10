# Importa um mundo externo para data/world (com backup automatico do atual)
# e, opcionalmente, migra os dados de jogadores de UUID online para offline.
# Portavel: a raiz do projeto e a pasta-pai deste script.
param(
    [string]$Source   # opcional; se vazio, e solicitado interativamente
)
$ErrorActionPreference = 'Stop'
$root      = Split-Path $PSScriptRoot -Parent
$dataWorld = Join-Path $root 'data\world'
$backups   = Join-Path $root 'backups'

Write-Host '=== IMPORTAR MAPA E DADOS DE JOGADORES ===' -ForegroundColor Cyan
Write-Host ''

# 1) Origem
if (-not $Source) {
    Write-Host 'Informe a pasta do mundo a importar (a que contem o level.dat).'
    Write-Host 'Ex.: C:\Users\voce\AppData\Roaming\.minecraft\saves\MeuMundo'
    $Source = Read-Host 'Caminho de origem'
}
$Source = $Source.Trim().Trim('"')
if (-not (Test-Path (Join-Path $Source 'level.dat'))) {
    Write-Host "[ERRO] Nao encontrei 'level.dat' em: $Source" -ForegroundColor Red
    Write-Host 'Isso nao parece uma pasta de mundo valida. Importacao abortada.' -ForegroundColor Red
    exit 1
}

# 2) Confirmacao
Write-Host ''
Write-Host "Origem : $Source"
Write-Host "Destino: $dataWorld  (o mundo atual sera SUBSTITUIDO)" -ForegroundColor Yellow
$ok = Read-Host 'Confirmar importacao? (S/N)'
if ($ok -notmatch '^[sS]') { Write-Host 'Cancelado pelo usuario.'; exit 1 }

# 3) Backup do mundo atual (se existir)
if (Test-Path $dataWorld) {
    if (-not (Test-Path $backups)) { New-Item -ItemType Directory -Path $backups | Out-Null }
    $ts  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip = Join-Path $backups "world_antes_import_$ts.zip"
    Write-Host "Fazendo backup do mundo atual em: $zip"
    Compress-Archive -Path (Join-Path $dataWorld '*') -DestinationPath $zip -Force
    Remove-Item $dataWorld -Recurse -Force
}

# 4) Copia do mundo
Write-Host 'Copiando o mundo (pode levar alguns minutos)...'
Copy-Item -Path $Source -Destination $dataWorld -Recurse -Force
$srcCount = (Get-ChildItem $Source -Recurse -File).Count
$dstCount = (Get-ChildItem $dataWorld -Recurse -File).Count
if ($srcCount -eq $dstCount) {
    Write-Host ("[OK] Mundo importado: $dstCount arquivos (integridade conferida).") -ForegroundColor Green
} else {
    Write-Host ("[AVISO] Contagem diferente: origem=$srcCount destino=$dstCount.") -ForegroundColor Yellow
}

# 5) Migracao de UUID online -> offline (opcional)
Write-Host ''
$doUuid = Read-Host 'Migrar dados dos jogadores de UUID online para offline? (necessario se ONLINE_MODE=FALSE) (S/N)'
if ($doUuid -match '^[sS]') {
    # Fonte dos nicks: usercache.json costuma ficar 2 niveis acima de saves\world (na raiz .minecraft)
    $instRoot  = Split-Path (Split-Path $Source -Parent) -Parent
    $userCache = Join-Path $instRoot 'usercache.json'
    if (-not (Test-Path $userCache)) {
        Write-Host "usercache.json nao encontrado automaticamente em: $instRoot"
        $userCache = (Read-Host 'Cole o caminho do usercache.json (ou ENTER para pular)').Trim().Trim('"')
    }
    if ($userCache -and (Test-Path $userCache)) {
        & (Join-Path $PSScriptRoot 'migrate-uuids.ps1') -UserCache $userCache -WorldDir $dataWorld
    } else {
        Write-Host '[AVISO] Sem usercache.json: migracao de UUID pulada.' -ForegroundColor Yellow
        Write-Host '        (sem os nicks nao e possivel calcular o UUID offline dos jogadores).'
    }
}

Write-Host ''
Write-Host 'Importacao concluida! Inicie o servidor pela opcao [1] do menu.' -ForegroundColor Green
