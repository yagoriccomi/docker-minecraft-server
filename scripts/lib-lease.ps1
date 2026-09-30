# Trava do host: data\host-ativo.json diz QUAL PC esta com o servidor.
# Fica separada do lib-hosts.ps1 de proposito: o antivirus (Kaspersky) bloqueia um .ps1 que
# junte o Server List Ping (socket com bytes crus) com a leitura da API key + POST desta trava.
# Precisa do lib-hosts.ps1 (Get-TsExe). Uso: . "$PSScriptRoot\lib-lease.ps1"   (dot-source)
. (Join-Path $PSScriptRoot 'lib-hosts.ps1')

$script:mcLeasePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'data\host-ativo.json'

# Viaja pelo Syncthing junto com o mapa. Quem sobe o servidor grava "ligado"; quem para limpo
# grava "desligado"; o vigia de rede grava "pausado" quando para o servidor por falta de rede.
# Se o host cai da rede com o servidor ligado, a trava continua "ligado" nos outros PCs: a
# varredura da porta 25565 nao o enxerga mais, mas a trava impede subir um 2o servidor.
function Get-HostLease {
    if (-not (Test-Path $script:mcLeasePath)) { return $null }
    try { return (Get-Content $script:mcLeasePath -Raw | ConvertFrom-Json) } catch { return $null }
}

function Test-LeaseMine($lease) { return [bool]($lease -and $lease.computador -eq $env:COMPUTERNAME) }

# "ligado" ou "pausado" de OUTRO PC = aquele PC ainda e o dono do mapa.
function Test-LeaseOther($lease) {
    return [bool]($lease -and -not (Test-LeaseMine $lease) -and $lease.estado -in @('ligado', 'pausado'))
}

function Set-HostLease([string]$Estado, [string]$Motivo = '') {
    $ErrorActionPreference = 'SilentlyContinue'
    $nome = $env:COMPUTERNAME
    $ts = Get-TsExe
    if ($ts) { try { $n = (& $ts status --json 2>$null | ConvertFrom-Json).Self.HostName; if ($n) { $nome = $n } } catch { } }
    $obj = [ordered]@{
        estado     = $Estado
        nome       = $nome
        computador = $env:COMPUTERNAME
        desde      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        motivo     = $Motivo
    }
    [System.IO.File]::WriteAllText($script:mcLeasePath, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
    # Com o watcher desligado (modo agendado) so um scan envia o arquivo: pede o scan so dele.
    # Sem Syncthing/rede agora, o proximo sync (30 min) leva junto com o mapa.
    try {
        [xml]$cfg = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'syncthing_config\config.xml')
        Invoke-RestMethod 'http://localhost:8384/rest/db/scan?folder=minecraft-data&sub=host-ativo.json' -Method Post `
            -Headers @{ 'X-API-Key' = $cfg.configuration.gui.apikey } -TimeoutSec 15 | Out-Null
    } catch { }
}

# Texto "Beatriz (ligado desde 29/09 11:31)" para as mensagens.
function Format-Lease($lease) {
    $quando = ''
    try { $quando = ' desde ' + ([datetime]$lease.desde).ToString('dd/MM HH:mm') } catch { }
    return ('{0} ({1}{2})' -f $lease.nome, $lease.estado, $quando)
}
