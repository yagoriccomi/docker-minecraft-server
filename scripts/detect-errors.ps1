# Detector de erros do ambiente (Docker + Minecraft + Syncthing).
# Portavel. Chamado pela opcao [D] do menu.bat.
$ErrorActionPreference = 'SilentlyContinue'
$root    = Split-Path $PSScriptRoot -Parent
$logfile = Join-Path $root 'logs\menu.log'
$cfgPath = Join-Path $root 'syncthing_config\config.xml'

$script:problemas = 0
function Falha ($m) { $script:problemas++; Write-Host "  [ERRO]   $m" -ForegroundColor Red }
function Alerta($m) { $script:problemas++; Write-Host "  [ALERTA] $m" -ForegroundColor Yellow }
function Okk   ($m) {                        Write-Host "  [OK]     $m" -ForegroundColor Green }

Write-Host '============================================' -ForegroundColor Cyan
Write-Host '        DETECTOR DE ERROS DO AMBIENTE'        -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

# -------- 1) Docker daemon --------
Write-Host "`n[1] Docker Engine"
$null = docker info --format '{{.ServerVersion}}' 2>$null
if ($LASTEXITCODE -ne 0) {
    Falha 'Docker nao encontrado ou daemon parado. Abra o Docker Desktop e aguarde "running".'
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "RESUMO: $script:problemas problema(s). Sem Docker nao da para checar o resto." -ForegroundColor Red
    return
}
Okk 'daemon respondendo'

# -------- 2) Estado dos containers --------
Write-Host "`n[2] Containers"
foreach ($name in @('minecraft', 'syncthing')) {
    $json = docker inspect $name 2>$null | ConvertFrom-Json
    if (-not $json) { Alerta "$name : nao existe (nunca criado? rode a opcao [1])"; continue }
    $st = $json[0].State
    $status   = $st.Status
    $exit     = $st.ExitCode
    $restarts = $json[0].RestartCount
    $health   = $st.Health.Status

    switch ($status) {
        'running' {
            if     ($health -eq 'unhealthy') { Falha  "$name : running porem UNHEALTHY (healthcheck falhando)" }
            elseif ($health -eq 'starting')  { Okk    "$name : running (healthcheck inicializando)" }
            else {
                $hlabel = if ([string]::IsNullOrEmpty($health)) { 'sem healthcheck' } else { $health }
                Okk "$name : running ($hlabel)"
            }
            if ($restarts -gt 5) { Alerta "$name : $restarts reinicios acumulados (possivel instabilidade)" }
        }
        'restarting' { Falha "$name : REINICIANDO EM LOOP (crash loop) - veja os logs (opcao 3)" }
        'exited' {
            if ($exit -eq 0) { Okk "$name : parado (exit 0) - normal se voce encerrou pela opcao 6/7" }
            elseif ($exit -eq 137) { Falha "$name : saiu com EXIT 137 (SIGKILL / falta de memoria). Considere reduzir MEMORY ou fechar apps." }
            else { Falha "$name : saiu com ERRO (exit $exit). Verifique os logs (opcao 3)." }
        }
        default { Alerta "$name : estado inesperado '$status'" }
    }
}

# -------- 3) Erros recentes nos logs dos containers --------
Write-Host "`n[3] Erros recentes nos logs (ultimas 200 linhas)"
foreach ($name in @('minecraft', 'syncthing')) {
    $exists = docker inspect $name 2>$null
    if (-not $exists) { continue }
    # Ignora linhas INFO (Minecraft "/INFO]" e Syncthing " INF ") e casa apenas erros reais.
    $log = docker logs $name --tail 200 2>&1
    $errLines = @($log | Where-Object {
        ($_ -notmatch '(?i)(/INFO\]|\sINF\s)') -and
        ($_ -match '(?i)(\bERROR\b|\bSEVERE\b|\bFATAL\b|Exception|OutOfMemoryError|panic:|Caused by:)')
    })
    if ($errLines.Count -gt 0) {
        Alerta "$name : $($errLines.Count) linha(s) de erro nos logs recentes. Amostra:"
        $errLines | Select-Object -Last 3 | ForEach-Object { Write-Host ("      " + $_.ToString().Trim()) -ForegroundColor DarkYellow }
    } else {
        Okk "$name : sem erros nos logs recentes"
    }
}

# -------- 4) Syncthing (API) --------
Write-Host "`n[4] Syncthing"
if (Test-Path $cfgPath) {
    [xml]$cfg = Get-Content $cfgPath
    $hd = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
    try {
        $sysErr = Invoke-RestMethod -Uri 'http://localhost:8384/rest/system/error' -Headers $hd -TimeoutSec 5
        if ($sysErr.errors -and $sysErr.errors.Count -gt 0) {
            Falha "Syncthing reportou $($sysErr.errors.Count) erro(s) de sistema."
            $sysErr.errors | Select-Object -Last 2 | ForEach-Object { Write-Host ("      " + $_.message) -ForegroundColor DarkYellow }
        } else { Okk 'sem erros de sistema' }

        $fErr = Invoke-RestMethod -Uri 'http://localhost:8384/rest/folder/errors?folder=minecraft-data' -Headers $hd -TimeoutSec 5
        if ($fErr.errors -and $fErr.errors.Count -gt 0) {
            Falha "Pasta minecraft-data com $($fErr.errors.Count) erro(s) de sincronizacao."
        } else { Okk 'pasta minecraft-data sem erros de sync' }

        $conn = Invoke-RestMethod -Uri 'http://localhost:8384/rest/system/connections' -Headers $hd -TimeoutSec 5
        $nConn = @($conn.connections.PSObject.Properties | Where-Object { $_.Value.connected }).Count
        if ($nConn -eq 0) { Alerta 'nenhum dispositivo conectado (amigo offline ou fora do Tailscale)' }
        else { Okk "$nConn dispositivo(s) conectado(s)" }
    } catch {
        Alerta 'Syncthing nao respondeu na API (container parado?)'
    }
} else {
    Alerta 'config.xml do Syncthing nao encontrado (ainda nao rodou aqui)'
}

# -------- 5) Log do proprio menu --------
Write-Host "`n[5] Historico de erros do menu (logs/menu.log)"
if (Test-Path $logfile) {
    $erros = Get-Content $logfile | Where-Object { $_ -match 'ERRO' } | Select-Object -Last 3
    if ($erros) {
        Alerta 'Ha registros de ERRO no menu.log (mais recentes):'
        $erros | ForEach-Object { Write-Host ("      " + $_) -ForegroundColor DarkYellow }
    } else { Okk 'nenhum ERRO registrado no menu.log' }
} else {
    Okk 'menu.log ainda nao existe (nenhuma acao registrada)'
}

# -------- Resumo --------
Write-Host "`n============================================" -ForegroundColor Cyan
if ($script:problemas -eq 0) {
    Write-Host 'RESUMO: nenhum problema detectado. Tudo certo! ' -ForegroundColor Green
} else {
    Write-Host "RESUMO: $script:problemas ponto(s) de atencao/erro detectado(s) acima." -ForegroundColor Yellow
}
Write-Host '============================================' -ForegroundColor Cyan
