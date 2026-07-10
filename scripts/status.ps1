# Status do ambiente Minecraft P2P (chamado pelo menu.bat opcao 2)
# Portavel: descobre a raiz do projeto a partir da propria localizacao do script.
$ErrorActionPreference = 'SilentlyContinue'
$root    = Split-Path $PSScriptRoot -Parent
$compose = Join-Path $root 'compose.yaml'
$cfgPath = Join-Path $root 'syncthing_config\config.xml'

Write-Host '=== CONTEINERES ===' -ForegroundColor Cyan
docker compose -f $compose ps

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
        foreach ($d in $devs) { Write-Host ("  - " + $d.Name.Substring(0,7) + '...') }
    } catch {
        Write-Host 'Syncthing nao respondeu (container parado?).'
    }
} else {
    Write-Host 'config.xml do Syncthing nao encontrado (Syncthing ainda nao rodou aqui).'
}
