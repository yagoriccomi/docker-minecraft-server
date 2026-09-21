# Logs do servidor, onde quer que ele esteja rodando (opcao 6 do menu).
#   - Servidor NESTE PC       -> logs do container (docker logs)
#   - Servidor em OUTRO PC    -> data/logs/latest.log, que chega pelo Syncthing
#   - Ninguem hospedando      -> ultimas linhas da ultima sessao registrada
# -Once: mostra uma vez e sai (sem o loop de atualizacao).
param([switch]$Once, [int]$Tail = 60)
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib-hosts.ps1')
$logFile = Join-Path $root 'data\logs\latest.log'

function Cor($l) {
    if     ($l -match '/(ERROR|FATAL)\]|Exception') { 'Red' }
    elseif ($l -match '/WARN\]')                     { 'Yellow' }
    elseif ($l -match 'joined the game|left the game') { 'Green' }
    elseif ($l -match '\]: <[^>]+> ')                { 'Cyan' }      # chat
    else                                             { 'Gray' }
}
function Mostrar($linhas) { foreach ($l in $linhas) { Write-Host $l -ForegroundColor (Cor $l) } }
function Idade($t) {
    $s = [int]((Get-Date) - $t).TotalSeconds
    if ($s -lt 90)   { return "$s s" }
    if ($s -lt 5400) { return "$([int]($s/60)) min" }
    return "$([math]::Round($s/3600,1)) h"
}

# Estado da copia local: 'em dia' | 'sincronizando' | 'desconectado' | 'indisponivel'
function Get-SyncState {
    $cfgPath = Join-Path $root 'syncthing_config\config.xml'
    if (-not (Test-Path $cfgPath)) { return 'indisponivel' }
    try {
        [xml]$cfg = Get-Content $cfgPath
        $hdr  = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
        $conn = Invoke-RestMethod 'http://localhost:8384/rest/system/connections' -Headers $hdr -TimeoutSec 3
        $n = @($conn.connections.PSObject.Properties | Where-Object { $_.Value.connected }).Count
        if ($n -eq 0) { return 'desconectado' }
        $st = Invoke-RestMethod 'http://localhost:8384/rest/db/status?folder=minecraft-data' -Headers $hdr -TimeoutSec 3
        if ($st.state -eq 'idle' -and [double]$st.needBytes -eq 0) { return 'em dia' }
        return 'sincronizando'
    } catch { return 'indisponivel' }
}

# De onde vem o log? (decidido uma vez por abertura da tela)
$origem = 'nenhum'; $host1 = $null
if ((docker inspect -f '{{.State.Status}}' minecraft 2>$null) -eq 'running') { $origem = 'local' }
else {
    $scan = Find-MinecraftHosts 700
    $h = @($scan.Hosts)
    if ($h.Count) { $origem = 'remoto'; $host1 = $h[0] }
}

while ($true) {
    if (-not $Once) { Clear-Host }
    Write-Host ''
    switch ($origem) {
        'local' {
            Write-Host "  LOGS - servidor rodando NESTE PC (ultimas $Tail linhas)" -ForegroundColor White
            Write-Host ''
            Mostrar @(docker logs --tail $Tail minecraft 2>&1 | ForEach-Object { "$_" })
        }
        'remoto' {
            Write-Host "  LOGS - servidor em " -NoNewline -ForegroundColor White
            Write-Host $host1.Nome -NoNewline -ForegroundColor Green
            Write-Host "  (copia recebida pelo Syncthing)" -ForegroundColor DarkGray
            if (Test-Path $logFile) {
                $idade = Idade (Get-Item $logFile).LastWriteTime
                # A idade do arquivo NAO indica atraso: sem jogadores o servidor passa
                # ate 30 min sem escrever. O que indica atraso e o estado do Syncthing.
                $sync = Get-SyncState
                if ($sync -eq 'desconectado') {
                    Write-Host "  [AVISO] O Syncthing nao esta conectado ao outro PC - este log pode estar desatualizado." -ForegroundColor Yellow
                    Write-Host "          Ultima linha recebida ha $idade." -ForegroundColor Yellow
                } elseif ($sync -eq 'sincronizando') {
                    Write-Host "  Sincronizando agora - o log pode estar alguns segundos atras. Ultima linha ha $idade." -ForegroundColor DarkYellow
                } elseif ($sync -eq 'em dia') {
                    Write-Host "  Copia em dia com o Syncthing. Ultima linha escrita pelo servidor ha $idade." -ForegroundColor DarkGray
                } else {
                    Write-Host "  Ultima linha ha $idade (estado do Syncthing indisponivel)." -ForegroundColor DarkGray
                }
                Write-Host ''
                Mostrar @(Get-Content $logFile -Tail $Tail -Encoding UTF8)
            } else {
                Write-Host '  Ainda nao ha log sincronizado deste servidor.' -ForegroundColor Yellow
            }
        }
        default {
            Write-Host '  Ninguem esta hospedando agora - ultimas linhas da ULTIMA sessao registrada' -ForegroundColor White
            if (Test-Path $logFile) {
                Write-Host ("  Log de {0:dd/MM/yyyy HH:mm}" -f (Get-Item $logFile).LastWriteTime) -ForegroundColor DarkGray
                Write-Host ''
                Mostrar @(Get-Content $logFile -Tail $Tail -Encoding UTF8)
            } else {
                Write-Host '  Nenhum log encontrado.' -ForegroundColor Yellow
            }
        }
    }
    if ($Once) { break }
    Write-Host ''
    $k = Read-Host '  ENTER = atualizar  |  0 = voltar ao menu'
    if ($null -eq $k -or $k.Trim() -eq '0') { break }   # $null = entrada encerrada
}
