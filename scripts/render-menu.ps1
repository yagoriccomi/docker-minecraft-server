# Renderiza o painel (Modelo B - duas colunas) com status ao vivo no cabecalho.
# Chamado pelo menu.bat a cada redesenho. Usa Write-Host -ForegroundColor
# (API do console), que funciona tanto no Windows Terminal quanto no conhost.
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib-hosts.ps1')

# --- caracteres de caixa por codigo (evita problema de encoding no .ps1) ---
# NOTA: prefixo "b" de proposito - $H colidiria com o $h de outras variaveis.
$bTL=[char]0x2554; $bTR=[char]0x2557; $bBL=[char]0x255A; $bBR=[char]0x255D
$bH =[char]0x2550; $bV =[char]0x2551; $bLN=[char]0x2500
$BOXW = 72   # largura INTERNA da caixa
$COL  = 31   # largura da 1a coluna do corpo

function P($t,$c) { if ($c) { Write-Host $t -NoNewline -ForegroundColor $c } else { Write-Host $t -NoNewline } }
function NL { Write-Host '' }
function Fit($s,$n) { if ($s.Length -gt $n) { $s.Substring(0,$n) } else { $s.PadRight($n) } }
function S($t,$c) { [pscustomobject]@{ T = [string]$t; C = $c } }
# Linha da caixa: segmentos coloridos, cortados/completados ate $BOXW
function BoxLine($segs) {
    P ('  ' + $bV) 'Cyan'
    $len = 0
    foreach ($s in $segs) {
        $t = $s.T
        if ($len + $t.Length -gt $BOXW) { $t = $t.Substring(0, [math]::Max(0, $BOXW - $len)) }
        P $t $s.C; $len += $t.Length
    }
    if ($len -lt $BOXW) { P (' ' * ($BOXW - $len)) }
    P $bV 'Cyan'; NL
}

# ---------------- 1) CONTAINERS LOCAIS (sempre frescos) ----------------
$docker = $true; $local = 'ausente'; $sync = 'AUSENTE'
$rows = docker ps -a --format '{{.Names}}|{{.State}}' 2>$null
if ($LASTEXITCODE -ne 0) { $docker = $false }
foreach ($r in @($rows)) {
    $p = "$r" -split '\|'
    if ($p[0] -eq 'minecraft') { $local = $p[1] }
    if ($p[0] -eq 'syncthing') { if ($p[1] -eq 'running') { $sync = 'no ar' } else { $sync = 'PARADO!' } }
}

# ---------------- 2) REDE TAILSCALE (cache de 15 s) ----------------
# A varredura custa ate ~0,7 s; o cache deixa os redesenhos seguidos instantaneos.
$cache = Join-Path $env:TEMP 'mcp2p-hosts.json'
$net = $null
if (Test-Path $cache) {
    try {
        $c = Get-Content $cache -Raw | ConvertFrom-Json
        if (((Get-Date) - [datetime]$c.At).TotalSeconds -lt 15) { $net = $c }
    } catch { }
}
if (-not $net) {
    $scan = Find-MinecraftHosts 500
    $remote = @($scan.Hosts | Select-Object -First 1)
    $players = $null
    if ($remote.Count -gt 0) { $players = Get-McPlayers $remote[0].IP }
    $net = [pscustomobject]@{
        At = (Get-Date).ToString('o'); Ok = $scan.Ok; SelfIP = $scan.SelfIP
        Hosts = @($scan.Hosts); Players = $players
    }
    try { $net | ConvertTo-Json -Depth 5 | Set-Content $cache -Encoding UTF8 } catch { }
}
$remoteHosts = @($net.Hosts)

# ---------------- 3) AMIGOS CONECTADOS NO SYNCTHING (por nome) ----------------
$friends = '-'
$cfgPath = Join-Path $root 'syncthing_config\config.xml'
if ($sync -eq 'no ar' -and (Test-Path $cfgPath)) {
    try {
        [xml]$cfg = Get-Content $cfgPath
        $hdr = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
        $conn = Invoke-RestMethod 'http://localhost:8384/rest/system/connections' -Headers $hdr -TimeoutSec 3
        $ids = @($conn.connections.PSObject.Properties | Where-Object { $_.Value.connected } | ForEach-Object { $_.Name })
        if ($ids.Count -eq 0) { $friends = 'nenhum online' }
        else {
            $names = foreach ($id in $ids) {
                $d = $cfg.configuration.device | Where-Object { $_.id -eq $id } | Select-Object -First 1
                if ($d -and $d.name) { $d.name } else { $id.Substring(0,7) }
            }
            $friends = ($names -join ', ')
        }
    } catch { $friends = 'sem API' }
}

# ---------------- 4) QUEM ESTA HOSPEDANDO ----------------
function PlayersTxt($pl) {
    if (-not $pl) { return '' }
    $n = @($pl.Nomes | Where-Object { $_ })
    if ($n.Count) { return "  $($pl.Online)/$($pl.Max): " + ($n -join ', ') }
    return "  $($pl.Online)/$($pl.Max) jogando"
}
$line1 = @( (S '  Servidor: ' 'Gray') )
if (-not $docker) {
    $line1 += S 'Docker nao esta rodando (abra o Docker Desktop)' 'Red'
} elseif ($local -eq 'running' -and $remoteHosts.Count -gt 0) {
    $line1 += S "CONFLITO! rodando AQUI e em $($remoteHosts[0].Nome)" 'Red'
} elseif ($remoteHosts.Count -gt 0) {
    $line1 += S 'NO AR em ' 'Green'
    $line1 += S $remoteHosts[0].Nome 'White'
    $line1 += S "  $($remoteHosts[0].IP):25565" 'Cyan'
    $line1 += S (PlayersTxt $net.Players) 'DarkGray'
} elseif ($local -eq 'running') {
    $line1 += S 'NO AR neste PC' 'Green'
    if ($net.SelfIP) { $line1 += S "  $($net.SelfIP):25565" 'Cyan' }
} elseif ($local -eq 'restarting') {
    $line1 += S 'CRASH neste PC - veja a opcao 4' 'Red'
} elseif (-not $net.Ok) {
    $line1 += S 'desligado neste PC' 'DarkGray'
    $line1 += S '  (Tailscale offline: rede nao verificada)' 'Yellow'
} else {
    $line1 += S 'desligado - ninguem esta hospedando' 'DarkGray'
}

$cSync = if ($sync -eq 'no ar') { 'Green' } else { 'Red' }
$cFr   = if ($friends -match '^(-|nenhum online|sem API)$') { 'Yellow' } else { 'Green' }
if ($friends -eq '-') { $cFr = 'DarkGray' }
$line2 = @( (S '  Sync:     ' 'Gray'), (S (Fit $sync 12) $cSync),
            (S 'Amigos no sync: ' 'Gray'), (S $friends $cFr) )

# ---------------- CABECALHO ----------------
# Titulo embutido na borda superior:  ╔══ MINECRAFT P2P ═════...═╗
$title = ' MINECRAFT P2P '
NL
P ('  ' + $bTL + ($bH.ToString() * 2)) 'Cyan'
P $title 'White'
P (($bH.ToString() * ($BOXW - 2 - $title.Length)) + $bTR) 'Cyan'; NL
BoxLine $line1
BoxLine $line2
P ('  ' + $bBL + ($bH.ToString() * $BOXW) + $bBR) 'Cyan'; NL
if ($local -eq 'running' -and $remoteHosts.Count -gt 0) {
    P '  !! Dois hosts com o servidor no ar: o progresso de UM dos mapas sera perdido.' 'Red'; NL
    P '     Pare um deles (opcao 2) e deixe o sync terminar.' 'Red'; NL
}
NL

# ---------------- CORPO: DUAS COLUNAS ----------------
function Row($k1,$t1,$c1,$k2,$t2,$c2) {
    P '  ' ; P $k1 $c1 ; P ' '
    if ($k2) {
        P (Fit $t1 $COL) 'Gray'
        P $k2 $c2 ; P ' ' ; P $t2 'Gray'
    } else {
        P $t1 'Gray'
    }
    NL
}

P '  DIA A DIA                          FERRAMENTAS' 'White'; NL
Row '[1]' 'Jogar (subir o servidor)'     'Green' '[6]' 'Ver logs do servidor' 'Cyan'
Row '[2]' 'Parar / passar a vez'         'Green' '[7]' 'Console de comandos'  'Cyan'
Row '[3]' 'Status do ambiente'           'Green' '[8]' 'Painel do Syncthing'  'Cyan'
Row '[4]' 'Diagnostico de erros'         'Green' '[9]' 'Reiniciar o servidor' 'Cyan'
Row '[5]' 'Backup do mapa'               'Green' ''    ''                     ''
NL
P '  MANUTENCAO                         ZONA DE RISCO' 'White'; NL
Row '[X]' 'Instalar dependencias'        'Cyan'  '[!]' 'Importar mundo (SUBSTITUI)' 'Red'
Row '[U]' 'Atualizar projeto (git pull)' 'Cyan'  '[K]' 'Remover container do jogo'  'Red'
Row '[A]' 'Agendar sync + backup'      'Cyan'  ''    ''                           ''
NL
P '  ' ; P '[P]' 'Yellow' ; P ' PRIMEIROS PASSOS' 'White' ; P '  (instalar do zero / conectar outro PC)' 'DarkGray'; NL
P '  ' ; P '[0]' 'DarkGray'; P ' Sair' 'DarkGray'; NL
P ('  ' + ($bLN.ToString() * ($BOXW + 2))) 'DarkGray'; NL
