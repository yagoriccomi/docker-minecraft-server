# Guardiao do Syncthing: mantem a replicacao do mapa SEMPRE no ar.
#
# Dois modos (ver lib-sync.ps1):
#   servico -> servico do Windows (opcao N do menu). O wrapper e a recuperacao do servico ja
#              religam em caso de queda; o guardiao cobre alguem PARAR o servico e remove
#              qualquer container 'syncthing' que reapareca (mesmo Device ID = conflito).
#              Nunca abre o Docker Desktop: e justamente o que este modo economiza.
#   docker  -> container do compose.sync.yaml. A politica 'restart: always' ja cobre queda e
#              reboot, mas nao cobre o container ser REMOVIDO nem o Docker Desktop fechado.
# So respeita um desligamento DELIBERADO, feito pela opcao S do menu (ou -Desligar), que deixa
# a marca logs\syncthing-desligado.flag.
#
# Uso:
#   ensure-sync.ps1            -> checagem (tarefa MinecraftP2P-SyncGuard, a cada 5 min)
#   ensure-sync.ps1 -Desligar  -> desliga DE PROPOSITO: cria a marca e para o Syncthing
#   ensure-sync.ps1 -Ligar     -> remove a marca e sobe o Syncthing
#   ensure-sync.ps1 -Instalar  -> registra a tarefa agendada do guardiao
param([switch]$Desligar, [switch]$Ligar, [switch]$Instalar)
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$root    = Split-Path $PSScriptRoot -Parent
$logDir  = Join-Path $root 'logs'
$flag    = Join-Path $logDir 'syncthing-desligado.flag'
$log     = Join-Path $logDir 'sync-guard.log'
$state   = Join-Path $logDir 'sync-guard.docker-launch'   # ultima vez que abrimos o Docker Desktop
$ddExe   = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# So registra quando FAZ algo (a tarefa roda a cada 5 min; nada de log a cada checagem).
function Log($m) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }

. (Join-Path $PSScriptRoot 'lib-sync.ps1')   # Get-SyncState / Start-Sync / Stop-Sync / Invoke-SyncDocker
$modo = Get-SyncMode

# Com o servidor rodando e o sync agendado, o watcher fica desligado e o mapa so vai a cada
# 30 min. Os LOGS do servidor (data\logs) nao precisam do mundo congelado: escaneia so essa
# subpasta para os outros PCs verem os logs quase ao vivo (opcao 6 deles).
function Send-ServerLogs {
    if ((Invoke-SyncDocker 'inspect -f {{.State.Status}} minecraft' 15).Out -ne 'running') { return }
    try {
        [xml]$cfg = Get-Content (Join-Path $root 'syncthing_config\config.xml')
        $hd = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
        $f  = Invoke-RestMethod 'http://localhost:8384/rest/config/folders/minecraft-data' -Headers $hd -TimeoutSec 10
        if (-not $f.fsWatcherEnabled) {
            Invoke-RestMethod 'http://localhost:8384/rest/db/scan?folder=minecraft-data&sub=logs' -Method Post -Headers $hd -TimeoutSec 60 | Out-Null
        }
    } catch { }
}

# ---------------- instalar a tarefa ----------------
if ($Instalar) {
    $vbs     = Join-Path $PSScriptRoot 'run-hidden.vbs'
    $action  = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}" ensure-sync.ps1' -f $vbs)
    # Um gatilho repetitivo basta: ele tambem dispara ate 5 min depois do login.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                   -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    $set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                   -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName 'MinecraftP2P-SyncGuard' -Action $action -Trigger $trigger -Settings $set -Force `
        -Description 'Minecraft P2P: mantem o Syncthing sempre no ar (a cada 5 min). So nao sobe se desligado de proposito pela opcao S do menu.' | Out-Null
    if (Get-ScheduledTask -TaskName 'MinecraftP2P-SyncGuard') {
        Write-Host "[OK] Guardiao 'MinecraftP2P-SyncGuard' agendado: confere o Syncthing a cada 5 min." -ForegroundColor Green
        exit 0
    }
    Write-Host '[ERRO] Nao foi possivel agendar o guardiao.' -ForegroundColor Red
    exit 1
}

# ---------------- desligar de proposito ----------------
if ($Desligar) {
    ("desligado de proposito em {0} por {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:USERNAME) | Set-Content $flag
    $r = Stop-Sync
    Log 'Syncthing DESLIGADO de proposito (opcao S). O guardiao nao vai religar ate a opcao S de novo.'
    if ($r.Code -eq 0) { Write-Host '[OK] Syncthing desligado. Ele so volta pela opcao S (ou ao Jogar, opcao 1).' -ForegroundColor Yellow; exit 0 }
    Write-Host "[AVISO] Marca criada, mas o stop falhou: $($r.Out)" -ForegroundColor Yellow; exit 1
}

# ---------------- religar ----------------
if ($Ligar) {
    $tinha = Test-Path $flag
    Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
    $r = Start-Sync
    if ($r.Code -eq 0) {
        if ($tinha) { Log 'Syncthing RELIGADO (marca de desligado removida).' }
        Write-Host '[OK] Syncthing no ar.' -ForegroundColor Green; exit 0
    }
    Log "ERRO ao religar o Syncthing: $($r.Out)"
    Write-Host "[ERRO] Nao subiu: $($r.Out)" -ForegroundColor Red; exit 1
}

# ---------------- checagem (tarefa agendada) ----------------
if (Test-Path $flag) { exit 0 }                       # desligado de proposito: respeita

if ($modo -eq 'servico') {
    # So fala com o Docker se ele ja estiver aberto (quem hospeda): nunca o abre.
    $dockerAberto = [bool](Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)
    if ($dockerAberto -and (Get-SyncContainerState)) {
        $r = Invoke-SyncDocker 'rm -f syncthing' 60
        Log "ERRO evitado: havia um container 'syncthing' junto com o servico (mesmo Device ID) - removido ($($r.Code))."
    }
    $antes = Get-SyncState
    if ($antes -eq 'running') { if ($dockerAberto) { Send-ServerLogs }; exit 0 }
    $r = Start-Sync
    if ($r.Code -eq 0) { Log "Servico do Syncthing estava '$antes' - religado pelo guardiao."; exit 0 }
    Log "ERRO: servico do Syncthing '$antes' e nao subiu: $($r.Out)"
    exit 1
}

# Docker Desktop fechado? Abre (no maximo 1 tentativa a cada 20 min, para nao insistir
# se ele estiver com defeito). O engine demora: o proximo ciclo sobe o Syncthing.
if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
    $ultima = [datetime]::MinValue
    if (Test-Path $state) { try { $ultima = [datetime]((Get-Content $state -Raw).Trim()) } catch { } }
    if (((Get-Date) - $ultima).TotalMinutes -ge 20 -and (Test-Path $ddExe)) {
        Start-Process $ddExe
        (Get-Date).ToString('o') | Set-Content $state
        Log 'Docker Desktop estava FECHADO - aberto pelo guardiao; o Syncthing sobe no proximo ciclo.'
    }
    exit 0
}

# Docker aberto mas engine ainda subindo (ou com defeito): nao mexe, tenta no proximo ciclo.
if ((Invoke-SyncDocker 'info --format {{.ServerVersion}}' 20).Code -ne 0) { exit 0 }

$antes = Get-SyncContainerState
if (-not $antes) { $antes = 'ausente' }
if ($antes -eq 'running') { Send-ServerLogs; exit 0 }  # tudo certo: nao registra nada

$r = Start-Sync
if ($r.Code -eq 0 -and (Get-SyncState) -eq 'running') {
    Log "Syncthing estava '$antes' - religado pelo guardiao."
    exit 0
}
Log "ERRO: Syncthing '$antes' e nao subiu: $($r.Out)"
exit 1
