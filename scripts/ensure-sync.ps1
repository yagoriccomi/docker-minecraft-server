# Guardiao do Syncthing: mantem a replicacao do mapa SEMPRE no ar.
#
# A politica 'restart: always' do compose ja cobre queda do processo e reboot, mas nao cobre
# o container ser REMOVIDO (ex.: um 'docker compose down') nem o Docker Desktop fechado.
# Este script cobre os dois. So respeita um desligamento DELIBERADO, feito pela opcao S do
# menu (ou -Desligar), que deixa a marca logs\syncthing-desligado.flag.
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
$compose = Join-Path $root 'compose.sync.yaml'
$logDir  = Join-Path $root 'logs'
$flag    = Join-Path $logDir 'syncthing-desligado.flag'
$log     = Join-Path $logDir 'sync-guard.log'
$state   = Join-Path $logDir 'sync-guard.docker-launch'   # ultima vez que abrimos o Docker Desktop
$ddExe   = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# So registra quando FAZ algo (a tarefa roda a cada 5 min; nada de log a cada checagem).
function Log($m) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }

# docker com limite de tempo: um engine travado NUNCA prende o guardiao.
function Docker([string]$a, [int]$sec = 30) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'docker', $a
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return @{ Code = -2; Out = 'docker nao encontrado' } }
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($sec * 1000)) { try { $p.Kill() } catch { }; return @{ Code = -1; Out = "sem resposta em ${sec}s" } }
    return @{ Code = $p.ExitCode; Out = ($o.Result + ' ' + $e.Result).Trim() }
}
function Sync-State { $r = Docker 'inspect -f {{.State.Status}} syncthing' 15; if ($r.Code -eq 0) { return $r.Out } else { return 'ausente' } }
function Sync-Up    { return Docker ('compose -f "{0}" up -d' -f $compose) 300 }

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
    $r = Docker ('compose -f "{0}" stop' -f $compose) 90
    Log 'Syncthing DESLIGADO de proposito (opcao S). O guardiao nao vai religar ate a opcao S de novo.'
    if ($r.Code -eq 0) { Write-Host '[OK] Syncthing desligado. Ele so volta pela opcao S (ou ao Jogar, opcao 1).' -ForegroundColor Yellow; exit 0 }
    Write-Host "[AVISO] Marca criada, mas o stop falhou: $($r.Out)" -ForegroundColor Yellow; exit 1
}

# ---------------- religar ----------------
if ($Ligar) {
    $tinha = Test-Path $flag
    Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue
    $r = Sync-Up
    if ($r.Code -eq 0) {
        if ($tinha) { Log 'Syncthing RELIGADO (marca de desligado removida).' }
        Write-Host '[OK] Syncthing no ar.' -ForegroundColor Green; exit 0
    }
    Log "ERRO ao religar o Syncthing: $($r.Out)"
    Write-Host "[ERRO] Nao subiu: $($r.Out)" -ForegroundColor Red; exit 1
}

# ---------------- checagem (tarefa agendada) ----------------
if (Test-Path $flag) { exit 0 }                       # desligado de proposito: respeita

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
if ((Docker 'info --format {{.ServerVersion}}' 20).Code -ne 0) { exit 0 }

$antes = Sync-State
if ($antes -eq 'running') { exit 0 }                  # tudo certo: nao faz nada

$r = Sync-Up
if ($r.Code -eq 0 -and (Sync-State) -eq 'running') {
    Log "Syncthing estava '$antes' - religado pelo guardiao."
    exit 0
}
Log "ERRO: Syncthing '$antes' e nao subiu: $($r.Out)"
exit 1
