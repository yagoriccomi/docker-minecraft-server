# Funcoes comuns ao sync (sync-world.ps1), ao backup (backup-world.ps1) e ao agendamento
# (install-tasks.ps1). Uso (dot-source):  . (Join-Path $PSScriptRoot 'common.ps1')
#
# "Congelar" o mundo = save-off + save-all flush: o Minecraft grava tudo no disco e para de
# escrever nos arquivos do mundo enquanto o sync/backup le a pasta. O servidor continua no ar
# normalmente para quem esta jogando; so as gravacoes em disco esperam ate o save-on.
# Se o servidor for parado nesse meio tempo, o proprio 'stop' do Minecraft salva tudo.

# Garante que o docker seja encontrado mesmo dentro de tarefas agendadas.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$root     = Split-Path $PSScriptRoot -Parent
$mcName   = 'minecraft'
$folderId = 'minecraft-data'
$script:savesOff  = $false
$script:worldLock = $null

# Escreve na tela e no log definido em $script:LogFile (falha no log nunca derruba o script).
function Write-Log([string]$Message, [string]$Color = 'Gray') {
    Write-Host $Message -ForegroundColor $Color
    try {
        $dir = Split-Path $script:LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        Add-Content -Path $script:LogFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    } catch { }
}

# Roda o docker com limite de tempo: um Docker travado nunca prende o script (nem o mundo congelado).
function Invoke-Docker([string]$Arguments, [int]$TimeoutSec = 60) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'docker'
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $p   = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        return @{ Code = -1; Out = ''; Err = "sem resposta em ${TimeoutSec}s" }
    }
    return @{ Code = $p.ExitCode; Out = $out.Result.Trim(); Err = $err.Result.Trim() }
}

# Estado do container ('running', 'exited', ...) ou '' se ele nao existe / Docker parado.
function Get-ContainerState([string]$Name) {
    try { $r = Invoke-Docker "inspect -f {{.State.Status}} $Name" } catch { return '' }
    if ($r.Code -ne 0) { return '' }
    return $r.Out
}

# Comando no console do servidor via RCON (erro = excecao).
function Invoke-Rcon([string]$Command, [int]$TimeoutSec = 30) {
    $r = Invoke-Docker "exec $mcName rcon-cli $Command" $TimeoutSec
    if ($r.Code -ne 0) { throw ("RCON '{0}' falhou: {1} {2}" -f $Command, $r.Err, $r.Out) }
    return $r.Out
}

# Trava entre sync e backup: os dois congelam o mundo, entao um espera o outro terminar.
# E um arquivo aberto com acesso exclusivo; o Windows solta a trava sozinho se o processo morrer.
function Enter-WorldLock([int]$TimeoutMin) {
    $path = Join-Path $root 'logs\world.lock'
    if (-not (Test-Path (Split-Path $path))) { New-Item -ItemType Directory -Path (Split-Path $path) | Out-Null }
    $limite = (Get-Date).AddMinutes($TimeoutMin)
    $avisou = $false
    while ($true) {
        try {
            $script:worldLock = [System.IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
            return $true
        } catch [System.IO.IOException] {
            if ((Get-Date) -ge $limite) { return $false }
            if (-not $avisou) { Write-Host 'Aguardando outro sync/backup do mapa terminar...' -ForegroundColor Yellow; $avisou = $true }
            Start-Sleep -Seconds 5
        }
    }
}

function Exit-WorldLock {
    if ($script:worldLock) { $script:worldLock.Dispose(); $script:worldLock = $null }
}

# Congela o mundo se o Minecraft estiver rodando. Retorna $true se congelou.
function Suspend-WorldSaves {
    if ((Get-ContainerState $mcName) -ne 'running') { return $false }
    $script:savesOff = $true   # marca antes: se o save-off chegar ao servidor mas a resposta falhar, o save-on ainda roda
    Invoke-Rcon 'save-off' | Out-Null
    Invoke-Rcon 'save-all flush' 300 | Out-Null
    Start-Sleep -Seconds 3     # folga para as ultimas escritas do container chegarem ao disco do Windows
    return $true
}

# Descongela o mundo (save-on). Chamar SEMPRE num finally: o mundo nunca pode ficar congelado.
function Resume-WorldSaves {
    if (-not $script:savesOff) { return }
    for ($i = 1; $i -le 3; $i++) {
        if ((Get-ContainerState $mcName) -ne 'running') { $script:savesOff = $false; return }   # parado: o stop ja salvou
        try { Invoke-Rcon 'save-on' | Out-Null; $script:savesOff = $false; return }
        catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds 5 }
    }
}

# --- Syncthing (API REST local, mesma usada pelo status.ps1) ---
function Connect-Syncthing {
    $cfgPath = Join-Path $root 'syncthing_config\config.xml'
    if (-not (Test-Path $cfgPath)) { throw "config do Syncthing nao encontrada ($cfgPath)" }
    [xml]$cfg = Get-Content $cfgPath
    $script:stHeaders = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
}

function Invoke-Syncthing([string]$Path, [string]$Method = 'Get', $Body = $null, [int]$TimeoutSec = 15) {
    $req = @{ Uri = 'http://localhost:8384/rest' + $Path; Method = $Method; Headers = $script:stHeaders; TimeoutSec = $TimeoutSec }
    if ($Body) { $req.Body = $Body | ConvertTo-Json -Compress; $req.ContentType = 'application/json' }
    Invoke-RestMethod @req
}

# Watcher ligado  = Syncthing envia cada gravacao na hora (padrao do Syncthing).
# Watcher desligado + rescan 0 = so o sync-world.ps1 escaneia a pasta (mundo congelado).
function Set-FolderWatcher([bool]$Enabled) {
    $body = if ($Enabled) { @{ fsWatcherEnabled = $true; rescanIntervalS = 3600 } }
            else          { @{ fsWatcherEnabled = $false; rescanIntervalS = 0 } }
    Invoke-Syncthing "/config/folders/$folderId" 'Patch' $body | Out-Null
}
