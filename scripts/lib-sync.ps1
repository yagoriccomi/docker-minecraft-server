# Estado do Syncthing deste PC, nos DOIS modos em que ele pode rodar:
#   'servico' -> servico do Windows MinecraftP2P-Syncthing (instalado pela opcao [N]); nao
#                precisa do Docker, entao o Docker Desktop so abre no PC que hospeda.
#   'docker'  -> container 'syncthing' do compose.sync.yaml (PCs ainda nao migrados).
# O servico, se existir, SEMPRE manda: os dois juntos teriam o mesmo Device ID.
# Uso (dot-source):  . (Join-Path $PSScriptRoot 'lib-sync.ps1')

$script:SyncServiceName = 'MinecraftP2P-Syncthing'
$script:SyncCompose     = Join-Path (Split-Path $PSScriptRoot -Parent) 'compose.sync.yaml'

function Get-SyncService { Get-Service -Name $script:SyncServiceName -ErrorAction SilentlyContinue }

function Get-SyncMode { if (Get-SyncService) { 'servico' } else { 'docker' } }

# docker com limite de tempo: com o Docker Desktop fechado ou travado, nada fica preso.
function Invoke-SyncDocker([string]$Arguments, [int]$TimeoutSec = 30) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'docker', $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return @{ Code = -2; Out = 'docker nao encontrado' } }
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch { }; return @{ Code = -1; Out = "sem resposta em ${TimeoutSec}s" } }
    return @{ Code = $p.ExitCode; Out = ($o.Result + ' ' + $e.Result).Trim() }
}

# Estado do container 'syncthing' ('running', 'exited', ...) ou '' se nao existe / Docker fechado.
function Get-SyncContainerState {
    $r = Invoke-SyncDocker 'inspect -f {{.State.Status}} syncthing' 15
    if ($r.Code -eq 0) { return $r.Out }
    return ''
}

# 'running', 'stopped' ou 'ausente' (nem servico nem container).
function Get-SyncState {
    $svc = Get-SyncService
    if ($svc) { if ($svc.Status -eq 'Running') { return 'running' } else { return 'stopped' } }
    $c = Get-SyncContainerState
    if ($c -eq 'running') { return 'running' }
    if ($c) { return 'stopped' }
    return 'ausente'
}

# Liga o Syncthing no modo deste PC. Retorna @{ Code; Out } (Code 0 = ok).
function Start-Sync {
    $svc = Get-SyncService
    if (-not $svc) { return Invoke-SyncDocker ('compose -f "{0}" up -d' -f $script:SyncCompose) 300 }
    try {
        Start-Service -Name $script:SyncServiceName -ErrorAction Stop
        (Get-SyncService).WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
        return @{ Code = 0; Out = '' }
    } catch { return @{ Code = 1; Out = $_.Exception.Message } }
}

# Desliga o Syncthing no modo deste PC (stop, nao remove). Retorna @{ Code; Out }.
function Stop-Sync {
    $svc = Get-SyncService
    if (-not $svc) { return Invoke-SyncDocker ('compose -f "{0}" stop' -f $script:SyncCompose) 90 }
    try {
        Stop-Service -Name $script:SyncServiceName -ErrorAction Stop
        return @{ Code = 0; Out = '' }
    } catch { return @{ Code = 1; Out = $_.Exception.Message } }
}
