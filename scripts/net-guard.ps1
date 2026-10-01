# Vigia de rede do HOST (tarefa MinecraftP2P-NetGuard, a cada 1 min, sem janela).
#
# Impede dois servidores ao mesmo tempo (split-brain) quando o host perde a rede:
#   1. Servidor rodando AQUI e a rede caiu (sem internet ou sem Tailscale) em 3 checagens
#      seguidas -> avisa no chat, para o Minecraft (o 'stop' salva tudo) e marca a trava do host
#      como "pausado". Ninguem de fora conseguia entrar mesmo, e o mapa para de mudar.
#   2. Foi ESTE vigia que parou e a rede voltou (2 checagens seguidas) -> espera o Syncthing
#      trocar as novidades e sobe o servidor de novo, SE ninguem assumiu nesse meio tempo.
#   3. Servidor rodando AQUI mas a trava diz que o host e OUTRO PC (ele assumiu enquanto este
#      estava fora e o Docker religou este no boot, por exemplo) -> para o daqui.
#   4. Servidor rodando AQUI sem trava (ou com a trava deste PC como parada) -> grava "ligado".
# Parar pelo menu (opcoes 2, K, !) cancela a volta automatica do item 2.
# Estado entre execucoes em logs\net-guard.json. So registra quando FAZ algo: logs\net-guard.log.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'lib-lease.ps1')   # inclui o lib-hosts.ps1
$script:LogFile = Join-Path $root 'logs\net-guard.log'
$statePath = Join-Path $root 'logs\net-guard.json'

$FALHAS_PARA_PARAR = 3    # checagens seguidas sem rede (1 por minuto) antes de parar
$OKS_PARA_VOLTAR   = 2    # checagens seguidas com rede antes de pensar em religar
$SEM_PEER_MIN      = 10   # rede de volta mas nenhum PC do sync conectado: decide sozinho apos N min

$s = [pscustomobject]@{ falhas = 0; oks = 0; parado = $false; paradoEm = ''; voltouEm = '' }
if (Test-Path $statePath) {
    try {
        $lido = Get-Content $statePath -Raw | ConvertFrom-Json
        foreach ($p in $s.PSObject.Properties.Name) { if ($null -ne $lido.$p) { $s.$p = $lido.$p } }
    } catch { }
}

# Avisa no chat, espera o sync/backup em andamento soltar o mapa e para com encerramento limpo.
function Stop-Local([string]$Aviso) {
    try { Invoke-Rcon "say [VIGIA] $Aviso" 15 | Out-Null } catch { }
    Start-Sleep -Seconds 10
    $null = Enter-WorldLock -TimeoutMin 5
    try {
        # O bot AFK sai junto: ele so pode existir no PC que hospeda (sem erro se nao existir).
        Invoke-Docker 'stop -t 10 minecraft-bot' 60 | Out-Null
        $r = Invoke-Docker "stop -t 60 $mcName" 120
        if ($r.Code -ne 0) { throw ('docker stop falhou: {0} {1}' -f $r.Err, $r.Out) }
    } finally { Exit-WorldLock }
}

# A rede voltou: o Syncthing ja trocou as novidades com os outros PCs? Sem isso a trava
# lida aqui pode estar velha (alguem pode ter assumido o servidor enquanto este estava fora).
function Test-SyncPronto {
    try {
        Connect-Syncthing
        $fs = Invoke-Syncthing "/db/status?folder=$folderId"
        if ($fs.state -ne 'idle' -or ([int64]$fs.needFiles + [int64]$fs.needDeletes) -gt 0) { return $false }
        $con = (Invoke-Syncthing '/system/connections').connections
        foreach ($p in $con.PSObject.Properties) {
            if (-not $p.Value.connected) { continue }
            if (((Get-Date) - [datetime]$p.Value.startedAt).TotalSeconds -ge 60) { return $true }
        }
        # Nenhum PC do sync por perto: nao da para perguntar a ninguem. Espera um pouco e segue.
        return (((Get-Date) - [datetime]$s.voltouEm).TotalMinutes -ge $SEM_PEER_MIN)
    } catch { return $false }
}

$estado = Get-ContainerState $mcName
$online = Test-NetOnline
if ($online) {
    if ($s.oks -eq 0) { $s.voltouEm = (Get-Date).ToString('o') }
    $s.oks++; $s.falhas = 0
} else {
    $s.falhas++; $s.oks = 0
}

try {
    if ($estado -eq 'running') {
        $s.parado = $false                            # rodando = ninguem precisa religar
        if (-not $online) {
            if ($s.falhas -ge $FALHAS_PARA_PARAR) {
                Write-Log ('vigia | sem rede ha {0} checagens seguidas: parando o servidor.' -f $s.falhas) 'Yellow'
                Stop-Local 'Este PC ficou sem internet. O servidor desliga em 10 s e volta sozinho quando a rede voltar.'
                Set-HostLease 'pausado' 'vigia: sem rede'
                $s.parado = $true; $s.paradoEm = (Get-Date).ToString('o')
                Write-Log 'vigia | servidor PARADO por falta de rede (trava: pausado). Volta quando a rede voltar.' 'Yellow'
            }
        } else {
            $lease = Get-HostLease
            if (Test-LeaseOther $lease) {
                Write-Log ('vigia | servidor rodando aqui, mas a trava diz que o host e {0}: parando o daqui.' -f (Format-Lease $lease)) 'Yellow'
                Stop-Local ('O servidor esta com {0}. Entre no servidor de la.' -f $lease.nome)
                Write-Log 'vigia | servidor deste PC PARADO (outro PC e o host).' 'Yellow'
            } elseif (-not (Test-LeaseMine $lease) -or $lease.estado -ne 'ligado') {
                Set-HostLease 'ligado' 'vigia: servidor ja estava no ar'
                Write-Log 'vigia | trava do host gravada: servidor ligado neste PC.'
            }
        }
    } elseif ($s.parado -and $online -and $s.oks -ge $OKS_PARA_VOLTAR -and $estado -in @('exited', 'created')) {
        if (Test-SyncPronto) {
            $lease = Get-HostLease
            if (Test-LeaseOther $lease) {
                $s.parado = $false
                Write-Log ('vigia | rede de volta, mas {0} assumiu o servidor: este fica parado.' -f (Format-Lease $lease)) 'Yellow'
            } else {
                $outros = @((Find-MinecraftHosts 900).Hosts)
                if ($outros.Count -gt 0) {
                    $s.parado = $false
                    Set-HostLease 'desligado' 'vigia: outro PC ja estava no ar'
                    Write-Log ('vigia | rede de volta, mas o servidor ja esta no ar em {0}: este fica parado.' -f $outros[0].Nome) 'Yellow'
                } else {
                    Set-HostLease 'ligado' 'vigia: rede voltou'   # antes do start: fecha a janela para outro PC subir junto
                    $r = Invoke-Docker "start $mcName" 120
                    if ($r.Code -ne 0) { throw ('docker start falhou: {0} {1}' -f $r.Err, $r.Out) }
                    $s.parado = $false
                    Write-Log 'vigia | rede de volta: servidor RELIGADO neste PC.' 'Green'
                }
            }
        }
    }
} catch {
    Write-Log ('vigia ERRO | ' + $_.Exception.Message) 'Red'
} finally {
    $s | ConvertTo-Json | Set-Content $statePath -Encoding ASCII
}
