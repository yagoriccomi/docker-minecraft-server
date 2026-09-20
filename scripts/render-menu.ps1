# Renderiza o painel (Modelo B - duas colunas) com status ao vivo no cabecalho.
# Chamado pelo menu.bat a cada redesenho. Usa Write-Host -ForegroundColor
# (API do console), que funciona tanto no Windows Terminal quanto no conhost.
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$root = Split-Path $PSScriptRoot -Parent

# --- caracteres de caixa por codigo (evita problema de encoding no .ps1) ---
# NOTA: prefixo "b" de proposito - $H colidiria com o $h dos headers da API.
$bTL=[char]0x2554; $bTR=[char]0x2557; $bBL=[char]0x255A; $bBR=[char]0x255D
$bH =[char]0x2550; $bV =[char]0x2551; $bLN=[char]0x2500
$BOXW = 72   # largura INTERNA da caixa (tem que bater com o cabecalho montado)
$COL  = 31   # largura da 1a coluna do corpo

function P($t,$c) { if ($c) { Write-Host $t -NoNewline -ForegroundColor $c } else { Write-Host $t -NoNewline } }
function NL { Write-Host '' }
function Fit($s,$n) { if ($s.Length -gt $n) { $s.Substring(0,$n) } else { $s.PadRight($n) } }

# ---------------- STATUS AO VIVO ----------------
$srv = 'ausente'; $sync = 'AUSENTE'; $peer = 'sem dados'
$rows = docker ps -a --format '{{.Names}}|{{.State}}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $rows) {
    $srv = 'sem Docker'; $sync = 'sem Docker'
} else {
    foreach ($r in $rows) {
        $p = $r -split '\|'
        if ($p[0] -eq 'minecraft') {
            switch ($p[1]) {
                'running'    { $srv = 'NO AR' }
                'exited'     { $srv = 'parado' }
                'restarting' { $srv = 'CRASH!' }
                default      { $srv = $p[1] }
            }
        }
        if ($p[0] -eq 'syncthing') {
            if ($p[1] -eq 'running') { $sync = 'no ar' } else { $sync = 'PARADO!' }
        }
    }
}

# Amigo(s) conectado(s) - so consulta se o Syncthing estiver de pe
$cfgPath = Join-Path $root 'syncthing_config\config.xml'
if ($sync -eq 'no ar' -and (Test-Path $cfgPath)) {
    try {
        [xml]$cfg = Get-Content $cfgPath
        $hdr = @{ 'X-API-Key' = $cfg.configuration.gui.apikey }
        $conn = Invoke-RestMethod 'http://localhost:8384/rest/system/connections' -Headers $hdr -TimeoutSec 3
        $n = @($conn.connections.PSObject.Properties | Where-Object { $_.Value.connected }).Count
        if ($n -gt 0) { $peer = "$n online" } else { $peer = 'offline' }
    } catch { $peer = 'sem API' }
} elseif ($sync -ne 'no ar') { $peer = '-' }

$cSrv  = if ($srv  -eq 'NO AR') { 'Green' } elseif ($srv -match 'CRASH|sem Docker') { 'Red' } else { 'DarkGray' }
$cSync = if ($sync -eq 'no ar') { 'Green' } else { 'Red' }
$cPeer = if ($peer -match 'online') { 'Green' } elseif ($peer -eq 'offline') { 'Yellow' } else { 'DarkGray' }

# ---------------- CABECALHO ----------------
# Soma do miolo: 15 + 13 + 10 + 6 + 10 + 7 + 11 = 72 = $BOXW
NL
P ('  ' + $bTL + ($bH.ToString() * $BOXW) + $bTR) 'Cyan'; NL
P ('  ' + $bV) 'Cyan'
P '  MINECRAFT P2P' 'White'
P '   Servidor: ' 'Gray'; P (Fit $srv 10)  $cSrv
P 'Sync: '        'Gray'; P (Fit $sync 10) $cSync
P 'Amigo: '       'Gray'; P (Fit $peer 11) $cPeer
P $bV 'Cyan'; NL
P ('  ' + $bBL + ($bH.ToString() * $BOXW) + $bBR) 'Cyan'; NL
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
NL
P '  ' ; P '[P]' 'Yellow' ; P ' PRIMEIROS PASSOS' 'White' ; P '  (instalar do zero / conectar outro PC)' 'DarkGray'; NL
P '  ' ; P '[0]' 'DarkGray'; P ' Sair' 'DarkGray'; NL
P ('  ' + ($bLN.ToString() * ($BOXW + 2))) 'DarkGray'; NL
