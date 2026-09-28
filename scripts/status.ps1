# Status do ambiente Minecraft P2P (chamado pelo menu.bat opcao 3)
# Portavel: descobre a raiz do projeto a partir da propria localizacao do script.
$ErrorActionPreference = 'SilentlyContinue'
$root        = Split-Path $PSScriptRoot -Parent
$compose     = Join-Path $root 'compose.yaml'
$composeSync = Join-Path $root 'compose.sync.yaml'
$cfgPath     = Join-Path $root 'syncthing_config\config.xml'

Write-Host '=== CONTEINERES ===' -ForegroundColor Cyan
Write-Host '-- Stack do jogo (compose.yaml) --' -ForegroundColor DarkGray
docker compose -f $compose ps
Write-Host '-- Stack de replicacao (compose.sync.yaml) - deve estar SEMPRE no ar --' -ForegroundColor DarkGray
docker compose -f $composeSync ps

Write-Host ''
Write-Host '=== SAUDE DO MINECRAFT ===' -ForegroundColor Cyan
$state  = docker inspect -f '{{.State.Status}}' minecraft 2>$null
$health = docker inspect -f '{{.State.Health.Status}}' minecraft 2>$null
if ($state) { Write-Host ("Minecraft: $state ($health)") }
else { Write-Host 'Minecraft: container nao encontrado / parado' }

Write-Host ''
Write-Host '=== SYNCTHING ===' -ForegroundColor Cyan
if (Test-Path $cfgPath) {
    [xml]$cfg = Get-Content $cfgPath
    $hd = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
    try {
        $st = Invoke-RestMethod -Uri 'http://localhost:8384/rest/db/status?folder=minecraft-data' -Headers $hd -TimeoutSec 5
        $glob = [double]$st.globalBytes; $need = [double]$st.needBytes
        $pct = if ($glob -gt 0) { [math]::Round((($glob - $need) / $glob) * 100, 1) } else { 100 }
        Write-Host ("Pasta minecraft-data: estado=$($st.state) | $pct% sincronizado | arquivos=$($st.localFiles)")
        $conn = Invoke-RestMethod -Uri 'http://localhost:8384/rest/system/connections' -Headers $hd -TimeoutSec 5
        $devs = @($conn.connections.PSObject.Properties | Where-Object { $_.Value.connected })
        Write-Host ("Dispositivos conectados: " + $devs.Count)
        foreach ($d in $devs) {
            $nome = ($cfg.configuration.device | Where-Object { $_.id -eq $d.Name }).name
            $comp = Invoke-RestMethod -Uri ('http://localhost:8384/rest/db/completion?folder=minecraft-data&device=' + $d.Name) -Headers $hd -TimeoutSec 5
            Write-Host ("  - {0} ({1}...): {2}% em dia com este PC" -f $nome, $d.Name.Substring(0,7), [math]::Floor($comp.completion))
        }
    } catch {
        Write-Host 'Syncthing nao respondeu (container parado?).'
    }
} else {
    Write-Host 'config.xml do Syncthing nao encontrado (Syncthing ainda nao rodou aqui).'
}

Write-Host ''
Write-Host '=== SYNC AUTOMATICO E BACKUP DIARIO ===' -ForegroundColor Cyan
foreach ($t in @('MinecraftP2P-Sync', 'MinecraftP2P-Backup')) {
    $task = Get-ScheduledTask -TaskName $t
    if ($task) { Write-Host ("{0}: {1} | proxima execucao {2:dd/MM HH:mm}" -f $t, $task.State, ($task | Get-ScheduledTaskInfo).NextRunTime) }
    else { Write-Host "${t}: NAO agendada (opcao A do menu)" -ForegroundColor Yellow }
}
foreach ($l in @('sync.log', 'backup.log')) {
    $p = Join-Path $root "logs\$l"
    if (Test-Path $p) { Write-Host ("Ultimo registro em logs\${l}: " + (Get-Content $p -Tail 1)) }
}
$diarios = @(Get-ChildItem (Join-Path $root 'backups') -Filter 'world_diario_*.zip' -File | Sort-Object Name -Descending)
Write-Host ("Backups diarios guardados: " + $diarios.Count)
foreach ($b in $diarios) { Write-Host ("  - {0} ({1:N2} GB)" -f $b.Name, ($b.Length / 1GB)) }
