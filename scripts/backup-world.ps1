# Backup .zip do mapa (data\world) com o mundo congelado (save-off + save-all flush) durante a copia.
# Pode rodar com o servidor ligado: quem esta jogando nao percebe nada.
#   -Daily      : backup automatico (tarefa MinecraftP2P-Backup, todo dia as 22:00). Gera
#                 backups\world_diario_AAAAMMDD_HHmmss.zip e mantem so os -Keep mais recentes.
#   sem -Daily  : backup manual (opcao 8 do menu) -> backups\world_backup_AAAAMMDD_HHmmss.zip,
#                 que NUNCA e apagado automaticamente.
param(
    [switch]$Daily,
    [int]$Keep = 3     # quantos backups diarios manter
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\backup.log'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$world   = Join-Path $root 'data\world'
$backups = Join-Path $root 'backups'
$tipo    = if ($Daily) { 'diario' } else { 'manual' }
$prefixo = if ($Daily) { 'world_diario_' } else { 'world_backup_' }

if (-not (Test-Path (Join-Path $world 'level.dat'))) {
    Write-Log "backup $tipo ERRO | mundo nao encontrado em $world (sem level.dat)." 'Red'
    exit 1
}
if (-not (Test-Path $backups)) { New-Item -ItemType Directory -Path $backups | Out-Null }

# O .zip fica perto do tamanho do mundo (os arquivos de regiao ja sao comprimidos).
$tamanho = (Get-ChildItem -LiteralPath $world -Recurse -File | Measure-Object Length -Sum).Sum
$livre   = (New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($backups))).AvailableFreeSpace
if ($livre -lt $tamanho + 500MB) {
    Write-Log ('backup {0} ERRO | espaco insuficiente: livre {1:N1} GB, necessario ~{2:N1} GB.' -f $tipo, ($livre / 1GB), (($tamanho + 500MB) / 1GB)) 'Red'
    exit 1
}

if (-not (Enter-WorldLock -TimeoutMin 30)) {
    Write-Log "backup $tipo ERRO | outro sync/backup do mapa rodando ha mais de 30 min." 'Red'
    exit 1
}
$codigo  = 0
$parcial = $null
try {
    # Restos de um backup interrompido (a trava garante que nao ha outro em andamento).
    Get-ChildItem -LiteralPath $backups -Filter '*.partial' -File | Remove-Item -Force

    $destino = Join-Path $backups ($prefixo + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.zip')
    $parcial = "$destino.partial"
    Write-Host 'Congelando o mundo e compactando o mapa, aguarde (alguns minutos)...'
    $inicio    = Get-Date
    $congelado = Suspend-WorldSaves

    # session.lock fica travado pelo servidor e nao faz parte do mapa.
    $base     = (Get-Item -LiteralPath $world).FullName.TrimEnd('\') + '\'
    $arquivos = @(Get-ChildItem -LiteralPath $world -Recurse -File | Where-Object { $_.Name -ne 'session.lock' })
    $zip = [System.IO.Compression.ZipFile]::Open($parcial, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $arquivos) {
            $entrada = $zip.CreateEntry($f.FullName.Substring($base.Length).Replace('\', '/'), [System.IO.Compression.CompressionLevel]::Optimal)
            $entrada.LastWriteTime = $f.LastWriteTime
            # FileShare ReadWrite: consegue ler os arquivos que o servidor mantem abertos.
            $origem = [System.IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite, Delete')
            try {
                $saida = $entrada.Open()
                try { $origem.CopyTo($saida) } finally { $saida.Dispose() }
            } finally { $origem.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }
    Resume-WorldSaves   # descongela ja; conferir e apagar os antigos nao precisa do mundo parado
    $duracao = ((Get-Date) - $inicio).TotalSeconds

    $conferir = [System.IO.Compression.ZipFile]::OpenRead($parcial)
    try { $gravados = $conferir.Entries.Count } finally { $conferir.Dispose() }
    if ($gravados -ne $arquivos.Count) { throw "zip incompleto: $gravados de $($arquivos.Count) arquivos" }
    Move-Item -LiteralPath $parcial -Destination $destino
    $parcial = $null

    $msg = 'backup {0} OK | {1} ({2:N2} GB, {3} arquivos) | {4}' -f $tipo, (Split-Path $destino -Leaf), ((Get-Item -LiteralPath $destino).Length / 1GB), $arquivos.Count,
           $(if ($congelado) { 'mundo congelado por {0:N0}s' -f $duracao } else { 'Minecraft parado' })

    # Retencao: so os backups diarios; os manuais e os de importacao nunca sao apagados.
    if ($Daily) {
        $antigos = @(Get-ChildItem -LiteralPath $backups -Filter 'world_diario_*.zip' -File |
                     Where-Object { $_.Name -match '^world_diario_\d{8}_\d{6}\.zip$' } |
                     Sort-Object Name -Descending | Select-Object -Skip $Keep)
        foreach ($a in $antigos) { Remove-Item -LiteralPath $a.FullName -Force }
        $msg += " | mantendo os $Keep mais recentes"
        if ($antigos.Count) { $msg += ' | apagados: ' + (($antigos | ForEach-Object { $_.Name }) -join ', ') }
    }
    Write-Log $msg 'Green'
} catch {
    $codigo = 1
    Write-Log ("backup $tipo ERRO | " + $_.Exception.Message) 'Red'
} finally {
    try { Resume-WorldSaves }
    catch { $codigo = 1; Write-Log ("backup $tipo ERRO | falha ao descongelar o mundo (save-on): " + $_.Exception.Message) 'Red' }
    if ($parcial -and (Test-Path -LiteralPath $parcial)) { Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue }
    Exit-WorldLock
}
exit $codigo
