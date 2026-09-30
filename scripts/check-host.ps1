# Checagem ANTES de subir o servidor (opcao 1 do menu). Codigos de saida:
#   0 = livre para subir
#   2 = BLOQUEADO (outro PC com o servidor no ar, este PC sem rede, ou o mapa ainda chegando)
#   3 = a trava diz que OUTRO PC e o host, mas ele sumiu da rede: o menu so sobe se o
#       usuario digitar ASSUMIR (o que foi jogado la depois do ultimo sync vira conflito)
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib-lease.ps1')   # inclui o lib-hosts.ps1

function Caixa([string[]]$linhas, [string]$cor) {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor $cor
    foreach ($l in $linhas) { Write-Host "   $l" -ForegroundColor $cor }
    Write-Host '  ============================================================' -ForegroundColor $cor
    Write-Host ''
}

# 1) Este PC precisa estar com rede: sem ela ninguem entra e o mapa nao sincroniza.
Write-Host 'Verificando a rede deste PC...' -ForegroundColor DarkGray
if (-not (Test-NetOnline)) {
    Caixa @('ESTE PC ESTA SEM REDE (internet ou Tailscale fora do ar).',
            'O servidor so sobe com a rede no ar: sem ela ninguem consegue',
            'entrar e o mapa nao chega aos outros PCs.') 'Red'
    exit 2
}

# 2) Alguem ja esta com o servidor no ar? Bloqueio sem excecao.
Write-Host 'Verificando se alguem ja esta hospedando na rede Tailscale...' -ForegroundColor DarkGray
$scan = Find-MinecraftHosts 900      # prazo maior: aqui a precisao importa mais que a velocidade
Remove-Item (Join-Path $env:TEMP 'mcp2p-hosts.json') -ErrorAction SilentlyContinue   # invalida o cache do menu
$outros = @($scan.Hosts)
if ($outros.Count -gt 0) {
    $h  = $outros[0]
    $pl = Get-McPlayers $h.IP
    $linhas = @("O SERVIDOR JA ESTA NO AR EM: $($h.Nome)", "Para jogar, entre em:  $($h.IP):25565")
    if ($pl) {
        $quem = if ($pl.Nomes.Count) { ' - ' + ($pl.Nomes -join ', ') } else { '' }
        $linhas += "Jogadores agora: $($pl.Online)/$($pl.Max)$quem"
    }
    $linhas += '', 'Dois servidores ao mesmo tempo criam dois mapas diferentes e o', 'progresso de UM deles se perde. Por isso o seu NAO vai subir.'
    Caixa $linhas 'Red'
    exit 2
}

# 3) A trava do host: outro PC pode ter caido da rede com o servidor ligado.
$lease = Get-HostLease
if (Test-LeaseOther $lease) {
    $visto = ''
    $ts = Get-TsExe
    if ($ts) {
        $st = & $ts status --json 2>$null | ConvertFrom-Json
        $peer = @($st.Peer.PSObject.Properties.Value | Where-Object { $_.HostName -eq $lease.nome }) | Select-Object -First 1
        if ($peer -and -not $peer.Online -and $peer.LastSeen) {
            try { $visto = ' (visto pela ultima vez ' + ([datetime]$peer.LastSeen).ToString('dd/MM HH:mm') + ')' } catch { }
        }
    }
    Caixa @("O SERVIDOR ESTA COM: $(Format-Lease $lease)",
            "mas esse PC nao responde na rede$visto.",
            '',
            'Ele provavelmente caiu (sem internet, desligou ou travou) com o',
            'servidor ligado. O que foi jogado la depois do ultimo sync AINDA',
            'NAO chegou aqui. O certo e esperar ele voltar: o vigia de rede',
            'dele religa o servidor sozinho, ou ele para pela opcao 2.',
            '',
            'Se tiver CERTEZA de que ninguem jogou la (ou aceitar perder isso),',
            'da para assumir o servidor. Quando ele voltar, o mapa dele vira',
            'conflito e o SEU prevalece.') 'Yellow'
    exit 3
}

# 4) O mapa deste PC precisa estar em dia com o que os outros ja enviaram.
$cfgPath = Join-Path $root 'syncthing_config\config.xml'
try {
    [xml]$cfg = Get-Content $cfgPath
    $hd = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
    $fs = Invoke-RestMethod 'http://localhost:8384/rest/db/status?folder=minecraft-data' -Headers $hd -TimeoutSec 5
    $falta = [int64]$fs.needFiles + [int64]$fs.needDeletes
    if ($falta -gt 0) {
        Caixa @(('O MAPA AINDA ESTA CHEGANDO: faltam {0} arquivo(s), {1:N1} MB.' -f $falta, ($fs.needBytes / 1MB)),
                'Subir agora usaria um mapa pela metade. Espere terminar',
                '(a opcao 3 mostra o andamento) e tente de novo.') 'Yellow'
        exit 2
    }
} catch {
    Write-Host '[AVISO] Syncthing sem resposta: nao deu para conferir se o mapa esta em dia.' -ForegroundColor Yellow
}

Write-Host 'Ninguem hospedando e mapa em dia. Livre para subir.' -ForegroundColor Green
exit 0
