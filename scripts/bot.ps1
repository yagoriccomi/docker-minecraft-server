# Controle do bot AFK (opcao [B] do menu; tambem chamado pelo [1] Jogar e pelas paradas).
#
# Regras do dono do servidor:
#   - o bot so roda no PC que esta hospedando: so liga se o Minecraft estiver no ar AQUI;
#   - so loga se o verificador (check-bot.ps1) aprovou o par (versao do servidor, versao da
#     biblioteca). Sem aprovacao, avisa e NAO sobe;
#   - nome com prefixo AFK_: nos relatorios, quem comeca com AFK_ conta como bot, nao jogador.
#
# Uso: bot.ps1                 -> tela do bot (status + opcoes)
#      bot.ps1 -Acao subir     -> liga se aprovado (com -Auto: so avisa, sem pausa; usado no [1])
#      bot.ps1 -Acao parar     -> desliga (usado pelas opcoes 2 e K e pelo vigia de rede)
#      bot.ps1 -Acao status    -> so mostra o estado
param([ValidateSet('menu', 'subir', 'parar', 'status')][string]$Acao = 'menu', [switch]$Auto)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\bot.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$botName = 'minecraft-bot'
$cache   = Join-Path $root 'logs\bot-compat.json'
$compose = Join-Path $root 'compose.yaml'

function Versao-Servidor {
    $l = Select-String -LiteralPath $compose -Pattern '^\s*VERSION:\s*"?([^"#\s]+)' | Select-Object -First 1
    if ($l) { return $l.Matches[0].Groups[1].Value }
    return '?'
}
function Versao-Lib {
    try { return (Get-Content (Join-Path $root 'bot\node_modules\mineflayer\package.json') -Raw | ConvertFrom-Json).version } catch { return $null }
}
# Veredito valido para o par ATUAL, ou $null (nunca testado / par mudou).
function Veredito {
    if (-not (Test-Path $cache)) { return $null }
    try { $c = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json } catch { return $null }
    if ($c.servidor -ne (Versao-Servidor) -or $c.mineflayer -ne (Versao-Lib)) { return $null }
    return $c
}
function Bots-Config { try { return @(Get-Content (Join-Path $root 'bot\bots.json') -Raw | ConvertFrom-Json) } catch { return @() } }

function Mostrar-Status {
    $v = Veredito
    Write-Host ''
    Write-Host '  === BOT AFK ===' -ForegroundColor White
    Write-Host ('  Servidor: {0}   |   biblioteca: {1}' -f (Versao-Servidor), ($(if (Versao-Lib) { 'mineflayer ' + (Versao-Lib) } else { 'nao instalada (rode o teste)' }))) -ForegroundColor Gray
    Write-Host '  Compatibilidade: ' -NoNewline -ForegroundColor Gray
    if (-not $v) { Write-Host 'NAO TESTADA para esta versao (opcao 1)' -ForegroundColor Yellow }
    elseif ($v.resultado -eq 'compativel') { Write-Host ('OK  ({0})' -f $v.modo) -ForegroundColor Green }
    else { Write-Host ('{0}: {1}' -f $v.resultado.ToUpper(), $v.detalhe) -ForegroundColor Yellow }
    $st = Get-ContainerState $botName
    Write-Host '  Container do bot: ' -NoNewline -ForegroundColor Gray
    if ($st -eq 'running') { Write-Host 'LIGADO' -ForegroundColor Green } elseif ($st) { Write-Host $st -ForegroundColor Gray } else { Write-Host 'nao existe' -ForegroundColor Gray }
    Write-Host '  Pontos configurados (bot\bots.json):' -ForegroundColor Gray
    foreach ($b in (Bots-Config)) { Write-Host ('    {0,-14} {1} {2} {3}  {4}' -f $b.nome, $b.x, $b.y, $b.z, $b.descricao) -ForegroundColor Gray }
    if ((Get-ContainerState $mcName) -eq 'running') {
        try {
            $lst = Invoke-Rcon 'list'
            $nomes = @(); if ($lst -match ':\s*(.+)$') { $nomes = @($Matches[1] -split ',\s*' | Where-Object { $_ }) }
            $bots = @($nomes | Where-Object { $_ -like 'AFK_*' }); $jog = @($nomes | Where-Object { $_ -notlike 'AFK_*' })
            Write-Host ('  Online agora: {0} jogador(es), {1} bot(s){2}' -f $jog.Count, $bots.Count, $(if ($bots) { ' -> ' + ($bots -join ', ') } else { '' })) -ForegroundColor Gray
        } catch { }
    }
}

function Subir {
    if ((Get-ContainerState $mcName) -ne 'running') {
        Write-Host '  Bot: o servidor nao esta no ar NESTE PC; o bot so roda no PC que hospeda.' -ForegroundColor Yellow
        return 1
    }
    $v = Veredito
    if (-not $v -or $v.resultado -ne 'compativel') {
        $porque = if (-not $v) { ('a compatibilidade com a {0} ainda nao foi testada' -f (Versao-Servidor)) } else { $v.detalhe }
        Write-Host ('  Bot NAO ligado: {0}.' -f $porque) -ForegroundColor Yellow
        Write-Host '  Teste pela opcao [B] -> 1. O servidor segue normal, so sem bot.' -ForegroundColor DarkGray
        Write-Log ("bot | nao ligado: {0}" -f $porque) 'DarkGray' | Out-Null
        return 2
    }
    # --no-deps: nunca recria/mexe no container do Minecraft ao ligar o bot.
    $r = Invoke-Docker ('compose -f "{0}" --profile bot up -d --no-deps bot' -f $compose) 300
    if ($r.Code -ne 0) { Write-Log ("bot ERRO | nao subiu: {0}" -f $r.Err) 'Red'; return 1 }
    Write-Log ("bot | ligado ({0})" -f $v.modo) 'Green'
    return 0
}

function Parar {
    if (-not (Get-ContainerState $botName)) { return 0 }
    Invoke-Docker "stop -t 10 $botName" 60 | Out-Null
    Write-Log 'bot | desligado' 'Gray' | Out-Null
    return 0
}

switch ($Acao) {
    'status' { Mostrar-Status; exit 0 }
    'parar'  { exit (Parar) }
    'subir'  { $c = Subir; exit $c }
    'menu' {
        while ($true) {
            Clear-Host
            Mostrar-Status
            Write-Host ''
            Write-Host '   [1] Testar compatibilidade de novo (servidor descartavel, ~3 min)' -ForegroundColor White
            Write-Host '   [2] Ligar o bot' -ForegroundColor White
            Write-Host '   [3] Desligar o bot' -ForegroundColor White
            Write-Host '   [4] Ver o log do bot (ultimas linhas)' -ForegroundColor White
            Write-Host '   [ENTER] Voltar ao menu' -ForegroundColor DarkGray
            $o = Read-Host '  Escolha'
            switch ($o) {
                '1' { & (Join-Path $PSScriptRoot 'check-bot.ps1') -Forcar | Out-Host }
                '2' { Subir | Out-Null }
                '3' { Parar | Out-Null; Write-Host '  Bot desligado.' -ForegroundColor Gray }
                '4' { Invoke-Docker "logs --tail 30 $botName" 30 | ForEach-Object { $_.Out; $_.Err } | Out-Host }
                ''  { exit 0 }
                default { Write-Host '  Opcao invalida.' -ForegroundColor Red }
            }
            Write-Host ''; Write-Host '  Pressione ENTER para continuar...' -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null
        }
    }
}
