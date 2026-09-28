# Agenda (ou remove) as tarefas automaticas do mapa no Agendador de Tarefas do Windows:
#   MinecraftP2P-Sync   : a cada 30 min (minutos :15 e :45) -> sync-world.ps1
#   MinecraftP2P-Backup : todo dia as 22:00                 -> backup-world.ps1 -Daily (mantem 3)
# Rodam escondidas (sem janela) pelo lancador run-hidden.vbs. Resultados em logs\sync.log e
# logs\backup.log, e nas opcoes 2 (status) e D (detector) do menu.
# Uso: install-tasks.ps1          -> cria/atualiza as tarefas
#      install-tasks.ps1 -Remove  -> remove as tarefas e devolve o Syncthing ao modo automatico
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$vbs = Join-Path $PSScriptRoot 'run-hidden.vbs'

# A antiga MinecraftP2P-AutoSave (so fazia save-all flush) foi substituida pelo sync, que ja salva o mundo.
$remover = @('MinecraftP2P-AutoSave')
if ($Remove) { $remover += 'MinecraftP2P-Sync', 'MinecraftP2P-Backup' }
foreach ($t in $remover) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
        Write-Host "[OK] Tarefa '$t' removida." -ForegroundColor Green
    }
}

if ($Remove) {
    # Sem o sync agendado ninguem mais escanearia a pasta: o watcher do Syncthing precisa voltar.
    try {
        Connect-Syncthing
        Set-FolderWatcher $true
        Write-Host '[OK] Syncthing de volta ao modo automatico (watcher ligado).' -ForegroundColor Green
    } catch {
        Write-Host ('[AVISO] Nao foi possivel religar o watcher do Syncthing: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host '        Religue no painel (opcao 8): pasta Minecraft Data > Editar > Avancado >' -ForegroundColor Yellow
        Write-Host '        marque "Watch for Changes" e ponha o rescan em 3600 s.' -ForegroundColor Yellow
    }
    return
}

$config = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# Sync a cada 30 min nos minutos :15 e :45, longe do backup das 22:00.
$agora  = Get-Date
$inicio = $agora.Date.AddHours($agora.Hour).AddMinutes(15)
while ($inicio -le $agora) { $inicio = $inicio.AddMinutes(30) }
Register-ScheduledTask -TaskName 'MinecraftP2P-Sync' -Force `
    -Action   (New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}" sync-world.ps1' -f $vbs)) `
    -Trigger  (New-ScheduledTaskTrigger -Once -At $inicio -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)) `
    -Settings $config `
    -Description 'Minecraft P2P: congela o mundo, sincroniza o mapa pelo Syncthing e descongela. A cada 30 min, sem janela.' | Out-Null
Write-Host ("[OK] 'MinecraftP2P-Sync' agendada: a cada 30 min (proxima as {0:HH:mm})." -f $inicio) -ForegroundColor Green

Register-ScheduledTask -TaskName 'MinecraftP2P-Backup' -Force `
    -Action   (New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}" backup-world.ps1 -Daily' -f $vbs)) `
    -Trigger  (New-ScheduledTaskTrigger -Daily -At '22:00') `
    -Settings $config `
    -Description 'Minecraft P2P: backup .zip diario do mapa as 22:00, mantendo os 3 mais recentes. Sem janela.' | Out-Null
Write-Host "[OK] 'MinecraftP2P-Backup' agendada: todo dia as 22:00 (mantem os 3 mais recentes em backups\)." -ForegroundColor Green
