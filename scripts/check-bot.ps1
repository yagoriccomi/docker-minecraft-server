# Verificador de compatibilidade do bot AFK (opcao [B] do menu).
#
# Responde: "o bot consegue entrar na versao do servidor?" SEM logar no mundo real.
#   1) instala/atualiza a biblioteca do bot (bot\node_modules) num container node;
#   2) le o que a biblioteca conhece da versao do servidor (bot\info.js);
#   3) consulta no npm se saiu versao nova da biblioteca;
#   4) sobe um servidor DESCARTAVEL (mesma VERSION, mundo plano vazio, rede docker propria,
#      sem porta publicada) e testa o bot entrando e ficando 20 s (bot\smoke.js):
#        - exato: a biblioteca tem os dados da versao do servidor;
#        - protocolo forcado: usa os dados da versao vizinha mais nova (ex.: 26.1) anunciando
#          o protocolo do servidor. So passa se os pacotes nao mudaram entre as duas;
#   5) grava o veredito em logs\bot-compat.json e o modo aprovado em bot\runtime.json.
#
# O veredito vale para o par (versao do servidor, versao da biblioteca): mudou um dos dois,
# o bot nao sobe ate testar de novo. O teste so roda de novo com -Forcar ou se o par mudou.
#
# Uso: check-bot.ps1            -> usa o resultado guardado se o par for o mesmo
#      check-bot.ps1 -Forcar    -> refaz o teste
# Codigo de saida: 0 compativel | 2 incompativel | 1 erro ao testar
param([switch]$Forcar)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\bot.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$botDir   = Join-Path $root 'bot'
$cache    = Join-Path $root 'logs\bot-compat.json'
$runtime  = Join-Path $botDir 'runtime.json'
$NODE     = 'node:22-alpine'
$MC_IMG   = 'itzg/minecraft-server:latest'
$TESTE    = 'mcbot-teste'          # nome do container E da rede do servidor descartavel
$vol      = '-v "{0}:/app" -w /app' -f $botDir

function Gravar($obj) {
    $dir = Split-Path $cache -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cache -Encoding UTF8
}
function Codigo([string]$res) { switch ($res) { 'compativel' { 0 } 'incompativel' { 2 } default { 1 } } }
function Mostrar($r) {
    $cor = @{ 'compativel' = 'Green'; 'incompativel' = 'Yellow'; 'erro' = 'Red' }[$r.resultado]
    Write-Host ''
    Write-Host ('  Servidor {0} (protocolo {1})  |  bot: mineflayer {2}' -f $r.servidor, $r.protocolo, $r.mineflayer) -ForegroundColor Gray
    Write-Host ('  Resultado: {0}' -f $r.resultado.ToUpper()) -NoNewline -ForegroundColor $cor
    if ($r.modo) { Write-Host ('  ({0})' -f $r.modo) -ForegroundColor $cor } else { Write-Host '' }
    Write-Host ('  {0}' -f $r.detalhe) -ForegroundColor Gray
    if ($r.atualizacao) { Write-Host ('  Biblioteca nova no npm: mineflayer {0}. O teste ja usou a mais nova.' -f $r.atualizacao) -ForegroundColor Cyan }
    Write-Host ('  Testado em {0}' -f $r.quando) -ForegroundColor DarkGray
}

# ---------------- 1) versao do servidor (compose.yaml) ----------------
$l = Select-String -LiteralPath (Join-Path $root 'compose.yaml') -Pattern '^\s*VERSION:\s*"?([^"#\s]+)' | Select-Object -First 1
if (-not $l) { Write-Log 'bot ERRO | nao achei VERSION no compose.yaml' 'Red'; exit 1 }
$ver = $l.Matches[0].Groups[1].Value

Write-Host ''
Write-Host '  === BOT AFK: TESTE DE COMPATIBILIDADE ===' -ForegroundColor White
Write-Host ('  Versao do servidor: {0}' -f $ver) -ForegroundColor Gray

# ---------------- 2) biblioteca: instala a versao fixada no package.json ----------------
Write-Host '  Preparando a biblioteca do bot (pode levar 1 min na primeira vez)...' -ForegroundColor DarkGray
$r = Invoke-Docker ("run --rm {0} {1} npm install --omit=dev --no-audit --no-fund" -f $vol, $NODE) 600
if ($r.Code -ne 0) { Write-Log ("bot ERRO | npm install falhou: {0}" -f $r.Err) 'Red'; exit 1 }

$r = Invoke-Docker ("run --rm {0} {1} node info.js {2}" -f $vol, $NODE, $ver) 120
if ($r.Code -ne 0) { Write-Log ("bot ERRO | info.js falhou: {0}" -f $r.Err) 'Red'; exit 1 }
$info = ($r.Out -split "`n")[-1] | ConvertFrom-Json

# ---------------- 3) tem biblioteca mais nova no npm? (sem internet, segue sem) ----------------
$ultima = $null
$r = Invoke-Docker ("run --rm {0} npm view mineflayer version" -f $NODE) 90
if ($r.Code -eq 0 -and $r.Out) { $ultima = ($r.Out -split "`n")[-1].Trim() }
$atualizacao = if ($ultima -and $ultima -ne $info.mineflayer) { $ultima } else { $null }

# ---------------- 4) resultado guardado para o mesmo par? ----------------
if (-not $Forcar -and (Test-Path $cache)) {
    try {
        $c = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
        if ($c.servidor -eq $ver -and $c.mineflayer -eq $info.mineflayer -and $c.resultado -ne 'erro') {
            $c | Add-Member -NotePropertyName atualizacao -NotePropertyValue $atualizacao -Force
            Mostrar $c
            Write-Host '  (resultado guardado; use "Testar de novo" para refazer)' -ForegroundColor DarkGray
            exit (Codigo $c.resultado)
        }
    } catch { }
}

# ---------------- 5) tentativas ----------------
$tentativas = @()
if ($info.temDados) { $tentativas += @{ Modo = "exato ($ver)"; Args = $ver; Run = @{ dados = $ver } } }
elseif ($info.vizinha -and $info.protocoloAlvo) {
    $tentativas += @{ Modo = ('protocolo forcado: dados da {0} anunciando {1}' -f $info.vizinha.versao, $info.protocoloAlvo)
                      Args = ('{0} {1}' -f $info.vizinha.versao, $info.protocoloAlvo)
                      Run  = @{ dados = $info.vizinha.versao; protocolo = [int]$info.protocoloAlvo } }
}
$res = [ordered]@{
    servidor = $ver; protocolo = $info.protocoloAlvo; mineflayer = $info.mineflayer; minecraftData = $info.minecraftData
    resultado = 'incompativel'; modo = $null; detalhe = ''; atualizacao = $atualizacao
    quando = (Get-Date).ToString('yyyy-MM-dd HH:mm')
}
if (-not $tentativas) {
    $res.detalhe = "a biblioteca nao conhece a $ver nem outra versao da mesma serie para tentar."
    Gravar $res; Remove-Item -LiteralPath $runtime -ErrorAction SilentlyContinue
    Write-Log ("bot | {0} x mineflayer {1}: incompativel (sem dados)" -f $ver, $info.mineflayer) 'Yellow'
    Mostrar ([pscustomobject]$res); exit 2
}
if (-not $info.temDados) {
    Write-Host ('  A biblioteca nao tem os dados da {0}; vou testar o modo protocolo forcado.' -f $ver) -ForegroundColor Yellow
}

# ---------------- 6) servidor descartavel + teste ----------------
$falhas = @()
try {
    Invoke-Docker "rm -f -v $TESTE" 60 | Out-Null
    Invoke-Docker "network rm $TESTE" 30 | Out-Null
    $r = Invoke-Docker "network create $TESTE" 30
    if ($r.Code -ne 0) { throw ('nao criei a rede de teste: {0}' -f $r.Err) }
    Write-Host '  Subindo um servidor DESCARTAVEL de teste (mundo plano vazio, nada do seu mapa)...' -ForegroundColor DarkGray
    $envs = "-e EULA=TRUE -e TYPE=VANILLA -e VERSION=$ver -e ONLINE_MODE=FALSE -e MEMORY=1G -e LEVEL_TYPE=FLAT -e GENERATE_STRUCTURES=false -e SPAWN_PROTECTION=0"
    $r = Invoke-Docker ("run -d --name {0} --network {0} {1} {2}" -f $TESTE, $envs, $MC_IMG) 600
    if ($r.Code -ne 0) { throw ('nao subi o servidor de teste: {0}' -f $r.Err) }
    $limite = (Get-Date).AddMinutes(8); $saude = ''
    while ((Get-Date) -lt $limite) {
        $saude = (Invoke-Docker "inspect -f {{.State.Health.Status}} $TESTE" 30).Out
        if ($saude -eq 'healthy') { break }
        if ((Get-ContainerState $TESTE) -ne 'running') { break }
        Start-Sleep -Seconds 5
    }
    if ($saude -ne 'healthy') { throw ('o servidor de teste nao ficou pronto (estado: {0})' -f $saude) }

    foreach ($t in $tentativas) {
        Write-Host ('  Testando o bot: {0}...' -f $t.Modo) -ForegroundColor DarkGray
        $r = Invoke-Docker ("run --rm --network {0} {1} {2} node smoke.js {0} 25565 {3}" -f $TESTE, $vol, $NODE, $t.Args) 180
        $ultimaLinha = (($r.Out + "`n" + $r.Err).Trim() -split "`n" | Where-Object { $_ -match '^(OK|FALHOU):' } | Select-Object -Last 1)
        if (-not $ultimaLinha) { $ultimaLinha = ($r.Out + ' ' + $r.Err).Trim() }
        if ($r.Code -eq 0) {
            $res.resultado = 'compativel'; $res.modo = $t.Modo; $res.detalhe = $ultimaLinha
            $t.Run | ConvertTo-Json | Set-Content -LiteralPath $runtime -Encoding ASCII
            break
        }
        $falhas += ('{0}: {1}' -f $t.Modo, $ultimaLinha)
    }
    if ($res.resultado -ne 'compativel') {
        $res.detalhe = ($falhas -join ' | ')
        Remove-Item -LiteralPath $runtime -ErrorAction SilentlyContinue
    }
} catch {
    $res.resultado = 'erro'; $res.detalhe = $_.Exception.Message
} finally {
    Invoke-Docker "rm -f -v $TESTE" 90 | Out-Null
    Invoke-Docker "network rm $TESTE" 30 | Out-Null
}

Gravar $res
Write-Log ("bot | {0} x mineflayer {1}: {2} {3} | {4}" -f $ver, $info.mineflayer, $res.resultado, $res.modo, $res.detalhe) @{ 'compativel' = 'Green'; 'incompativel' = 'Yellow'; 'erro' = 'Red' }[$res.resultado]
Mostrar ([pscustomobject]$res)
exit (Codigo $res.resultado)
