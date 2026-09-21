# Sincroniza o mapa com os outros PCs de forma CONSISTENTE.
# Chamado pela tarefa agendada MinecraftP2P-Sync (a cada 30 min) e pela opcao 6 do menu.
#
# Com o servidor ligado 24/7 o Minecraft grava os arquivos do mundo o tempo todo. Se o
# Syncthing enviasse cada gravacao na hora, os outros PCs receberiam arquivos "a quente"
# (pela metade). Por isso, neste PC, o watcher do Syncthing fica DESLIGADO e a cada ciclo:
#   1. o mundo e congelado (save-off + save-all flush);
#   2. o Syncthing escaneia a pasta data (foto consistente do mapa);
#   3. o script espera os PCs conectados receberem tudo (no maximo -PeerTimeoutMin minutos);
#   4. o mundo e descongelado (save-on) - sempre, mesmo se algo falhar.
# Com o Minecraft parado nao ha o que congelar: so escaneia e espera os PCs conectados.
param(
    [int]$PeerTimeoutMin = 10   # maximo de minutos esperando os outros PCs (com o mundo congelado)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\sync.log'

# Espera a pasta terminar scans/sincronizacoes em andamento.
function Wait-FolderIdle([int]$TimeoutSec = 900) {
    $limite = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        $st = Invoke-Syncthing "/db/status?folder=$folderId"
        if ($st.state -eq 'idle') { return }
        if ($st.state -eq 'error') { throw "pasta $folderId com erro no Syncthing: $($st.error)" }
        if ((Get-Date) -ge $limite) { throw "pasta $folderId nao ficou ociosa em ${TimeoutSec}s (estado: $($st.state))" }
        Start-Sleep -Seconds 2
    }
}

# Espera os PCs conectados que compartilham a pasta ficarem em dia (ou estourar o tempo).
function Wait-Peers([int]$TimeoutMin) {
    $meuId = (Invoke-Syncthing '/system/status').myID
    $nomes = @{}
    foreach ($d in (Invoke-Syncthing '/config/devices')) { $nomes[$d.deviceID] = $d.name }
    $ids = @((Invoke-Syncthing "/config/folders/$folderId").devices | ForEach-Object { $_.deviceID } | Where-Object { $_ -ne $meuId })
    $limite = (Get-Date).AddMinutes($TimeoutMin)
    while ($true) {
        $conexoes = (Invoke-Syncthing '/system/connections').connections
        $emDia = @(); $faltando = @(); $offline = @()
        foreach ($id in $ids) {
            $nome = $nomes[$id]; if (-not $nome) { $nome = $id.Substring(0, 7) }
            $c = $conexoes.$id
            if (-not ($c -and $c.connected)) { $offline += $nome; continue }
            $comp = Invoke-Syncthing "/db/completion?folder=$folderId&device=$id"
            if ($comp.remoteState -eq 'notSharing' -or $comp.remoteState -eq 'paused') { $offline += "$nome (pasta pausada)"; continue }
            if ($comp.needBytes -eq 0 -and $comp.needItems -eq 0 -and $comp.needDeletes -eq 0) { $emDia += $nome }
            else { $faltando += ('{0} {1}% (faltam {2:N1} MB)' -f $nome, [math]::Floor($comp.completion), ($comp.needBytes / 1MB)) }
        }
        if ($faltando.Count -eq 0 -or (Get-Date) -ge $limite) {
            return [pscustomobject]@{ EmDia = $emDia; Faltando = $faltando; Offline = $offline }
        }
        Write-Host ('  Enviando... ' + ($faltando -join ' | '))
        Start-Sleep -Seconds 5
    }
}

if ((Get-ContainerState 'syncthing') -ne 'running') {
    Write-Log 'sync | Syncthing parado (ou Docker fechado) - nada a sincronizar agora.'
    exit 0
}

if (-not (Enter-WorldLock -TimeoutMin 15)) {
    Write-Log 'sync ERRO | outro sync/backup do mapa rodando ha mais de 15 min - ciclo pulado.' 'Red'
    exit 1
}
$codigo = 0
try {
    Connect-Syncthing
    $inicio    = Get-Date
    $congelado = Suspend-WorldSaves

    # Syncthing em "modo agendado": sem watcher e sem rescan periodico (so este script escaneia).
    # Feito com o mundo congelado porque a pasta reinicia e ja escaneia ao mudar a config.
    $pasta = Invoke-Syncthing "/config/folders/$folderId"
    if ($pasta.fsWatcherEnabled -or $pasta.rescanIntervalS -ne 0) {
        Set-FolderWatcher $false
        Write-Log 'sync | Syncthing ajustado: watcher desligado, a pasta so e escaneada por este script.'
        Start-Sleep -Seconds 5
    }

    # Scan com o mundo parado; a chamada so retorna quando o scan termina.
    for ($i = 1; ; $i++) {
        try { Invoke-Syncthing "/db/scan?folder=$folderId" 'Post' -TimeoutSec 900 | Out-Null; break }
        catch { if ($i -ge 3) { throw }; Start-Sleep -Seconds 10 }
    }
    Wait-FolderIdle

    $peers  = Wait-Peers $PeerTimeoutMin
    $partes = @()
    if ($congelado) { $partes += ('mundo congelado por {0:N0}s' -f ((Get-Date) - $inicio).TotalSeconds) }
    else            { $partes += 'Minecraft parado' }
    if ($peers.EmDia.Count)   { $partes += 'em dia: ' + ($peers.EmDia -join ', ') }
    if ($peers.Offline.Count) { $partes += 'offline: ' + ($peers.Offline -join ', ') }
    if ($peers.Faltando.Count) {
        $partes += "tempo esgotado ($PeerTimeoutMin min) com: " + ($peers.Faltando -join ', ') + ' - o resto segue em segundo plano'
        Write-Log ('sync AVISO | ' + ($partes -join ' | ')) 'Yellow'
    } else {
        Write-Log ('sync OK | ' + ($partes -join ' | ')) 'Green'
    }
} catch {
    $codigo = 1
    Write-Log ('sync ERRO | ' + $_.Exception.Message) 'Red'
} finally {
    try { Resume-WorldSaves }
    catch { $codigo = 1; Write-Log ('sync ERRO | falha ao descongelar o mundo (save-on): ' + $_.Exception.Message) 'Red' }
    Exit-WorldLock
}
exit $codigo
