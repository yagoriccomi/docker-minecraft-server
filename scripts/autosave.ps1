# Salvamento automatico do mundo (chamado pela tarefa agendada a cada 30 min).
# Se o Minecraft estiver rodando, forca 'save-all flush' para gravar tudo em disco,
# permitindo que o Syncthing propague a versao mais recente. Assim, num desligamento
# abrupto (queda de energia), perde-se no maximo ~30 min de progresso.
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$root   = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $root 'logs'
$log    = Join-Path $logDir 'autosave.log'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$state = docker inspect -f '{{.State.Status}}' minecraft 2>$null
if ($state -eq 'running') {
    docker exec minecraft rcon-cli save-all flush | Out-Null
    Add-Content $log ("[{0}] save-all flush OK" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
} else {
    Add-Content $log ("[{0}] minecraft nao esta rodando ({1}) - nada a salvar" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $state)
}
