# Troca a distancia de visao e a de simulacao do servidor (opcao [R] do menu).
#
# Os valores ficam em .env (MC_VIEW_DISTANCE / MC_SIMULATION_DISTANCE), lidos pelo compose.yaml.
# O .env e LOCAL e nao vai pro git: cada PC escolhe o quanto aguenta quando for o host.
#
#   - Distancia de VISAO: quantos chunks o servidor ENVIA para cada jogador (o que ele enxerga).
#     Mais = mais rede e RAM. Nao muda o que roda no mundo.
#   - Distancia de SIMULACAO: quantos chunks em volta de cada jogador (e do bot AFK) RODAM:
#     mobs, plantas, redstone, farms. Mais = mais CPU (tempo por tick). As areas com /forceload
#     rodam sempre, independente disto.
#
# Uso: set-distance.ps1                    -> tela de escolha
#      set-distance.ps1 -Visao 12 -Simulacao 10   -> troca direto, sem perguntas
param([ValidateRange(0, 32)][int]$Visao = 0, [ValidateRange(0, 32)][int]$Simulacao = 0)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\distance.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$envPath = Join-Path $root '.env'
$MIN_V = 3; $MIN_S = 5; $MAX = 32
$PADRAO = 10                      # padrao do compose.yaml quando o .env nao tem o valor
$direto = ($Visao -gt 0 -or $Simulacao -gt 0)
function Pausa { if (-not $direto) { Write-Host ''; Write-Host '  Pressione ENTER para voltar ao menu...' -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null } }

# ---------------- valores em uso ----------------
$envTxt = if (Test-Path $envPath) { [System.IO.File]::ReadAllText($envPath) } else { '' }
function Ler-Env([string]$chave) {
    $m = [regex]::Match($envTxt, "(?m)^$chave=(\d+)[ \t]*\r?$")
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $PADRAO
}
$vAtual = Ler-Env 'MC_VIEW_DISTANCE'
$sAtual = Ler-Env 'MC_SIMULATION_DISTANCE'

# Tempo por tick agora (so se o servidor estiver no ar aqui): ajuda a decidir a simulacao.
$mspt = $null
if ((Get-ContainerState $mcName) -eq 'running') {
    try { $t = Invoke-Rcon 'tick query'; if ($t -match 'Average time per tick: ([0-9.]+)ms') { $mspt = [double]$Matches[1] } } catch { }
}

# ---------------- escolha ----------------
$vNovo = $Visao; $sNovo = $Simulacao
if (-not $direto) {
    Write-Host ''
    Write-Host '  === DISTANCIAS DO SERVIDOR ===' -ForegroundColor White
    Write-Host ''
    Write-Host '  Visao (chunks enviados ao jogador):     ' -NoNewline -ForegroundColor Gray
    Write-Host ('{0}' -f $vAtual) -ForegroundColor Green
    Write-Host '  Simulacao (chunks que rodam em volta):  ' -NoNewline -ForegroundColor Gray
    Write-Host ('{0}' -f $sAtual) -ForegroundColor Green
    if ($mspt) {
        $cor = if ($mspt -lt 30) { 'Green' } elseif ($mspt -lt 40) { 'Yellow' } else { 'Red' }
        Write-Host '  Tempo por tick agora:                   ' -NoNewline -ForegroundColor Gray
        Write-Host ('{0} ms de 50 ms' -f $mspt) -ForegroundColor $cor
    }
    Write-Host ''
    Write-Host '  Recomendado:' -ForegroundColor Yellow
    Write-Host '    Visao 10 a 12      so muda o que se enxerga; mais = mais rede e RAM.' -ForegroundColor Gray
    Write-Host '    Simulacao 8 a 10   e o que pesa na CPU: mobs, plantas e farms em volta' -ForegroundColor Gray
    Write-Host '                       de cada jogador e do bot. Mantenha <= visao.' -ForegroundColor Gray
    Write-Host '    Se o tempo por tick passar de ~40 ms, baixe a simulacao primeiro.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('   Visao: de {0} a {1}. Simulacao: de {2} a {1}.' -f $MIN_V, $MAX, $MIN_S) -ForegroundColor DarkGray
    Write-Host '   [ENTER] mantem o valor atual' -ForegroundColor DarkGray
    Write-Host ''
    $e = (Read-Host ('  Nova visao      [{0}]' -f $vAtual)).Trim()
    $vNovo = if ($e -eq '') { $vAtual } elseif ($e -match '^\d+$') { [int]$e } else { -1 }
    $e = (Read-Host ('  Nova simulacao  [{0}]' -f $sAtual)).Trim()
    $sNovo = if ($e -eq '') { $sAtual } elseif ($e -match '^\d+$') { [int]$e } else { -1 }
} else {
    if ($vNovo -eq 0) { $vNovo = $vAtual }
    if ($sNovo -eq 0) { $sNovo = $sAtual }
}
if ($vNovo -lt $MIN_V -or $vNovo -gt $MAX -or $sNovo -lt $MIN_S -or $sNovo -gt $MAX) {
    Write-Host ('  Valor invalido: visao de {0} a {1}, simulacao de {2} a {1}.' -f $MIN_V, $MAX, $MIN_S) -ForegroundColor Red
    Write-Log ("distancia ERRO | recusado visao={0} simulacao={1}" -f $vNovo, $sNovo) 'Red' | Out-Null
    Pausa; exit 1
}
if ($vNovo -eq $vAtual -and $sNovo -eq $sAtual) {
    Write-Host '  Nada mudou.' -ForegroundColor Green
    Pausa; exit 0
}
if ($sNovo -gt $vNovo) { Write-Host '  Aviso: simulacao maior que a visao gasta CPU em chunks que ninguem enxerga.' -ForegroundColor Yellow }

# ---------------- grava o .env ----------------
function Gravar-Env([string]$chave, [int]$valor) {
    $m = [regex]::Match($script:envTxt, "(?m)^$chave=\d+[ \t]*\r?$")
    if ($m.Success) { $script:envTxt = $script:envTxt.Remove($m.Index, $m.Length).Insert($m.Index, "$chave=$valor") }
    else { $script:envTxt = ($script:envTxt.TrimEnd("`r", "`n") + "`n$chave=$valor`n").TrimStart("`n") }
}
Gravar-Env 'MC_VIEW_DISTANCE' $vNovo
Gravar-Env 'MC_SIMULATION_DISTANCE' $sNovo
[System.IO.File]::WriteAllText($envPath, $envTxt)
Write-Log ("distancia OK | .env: visao {0} -> {1}, simulacao {2} -> {3}" -f $vAtual, $vNovo, $sAtual, $sNovo) 'Green'

# ---------------- aplicar ----------------
# O servidor so le esses valores ao nascer, e 'docker restart' NAO rele o .env: precisa recriar.
Write-Host ''
if ((Get-ContainerState $mcName) -eq 'running') {
    $jog = '?'
    try { $jog = (Invoke-Rcon 'list') } catch { }
    Write-Host ('  O servidor esta no ar ({0}).' -f $jog) -ForegroundColor Gray
    if ($direto) {
        Write-Host '  Vale no proximo inicio: [2] Parar e depois [1] Jogar.' -ForegroundColor Gray
    } else {
        $r = Read-Host '  Reiniciar AGORA para aplicar? O mundo e salvo antes (S/N)'
        if ($r -match '^[sSyY]') {
            Write-Host '  Reiniciando (ate 60 s para salvar e fechar)...' -ForegroundColor Gray
            Push-Location $root
            try {
                # So o servidor: o bot AFK (se ligado) reconecta sozinho quando ele voltar.
                docker compose -f compose.yaml up -d --force-recreate --no-deps --timeout 60 mc | Out-Null
                Write-Log ("distancia | servidor recriado (visao {0}, simulacao {1}, exit {2})" -f $vNovo, $sNovo, $LASTEXITCODE) 'Green'
                Write-Host '  Servidor reiniciando. Acompanhe pelos logs [6].' -ForegroundColor Green
            } finally { Pop-Location }
        } else {
            Write-Host '  Ok. Vale no proximo inicio: [2] Parar e depois [1] Jogar.' -ForegroundColor Yellow
            Write-Host '  (A opcao [9] Reiniciar NAO aplica: ela nao rele o .env.)' -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host '  O servidor esta desligado. Os valores novos valem no proximo [1] Jogar.' -ForegroundColor Gray
}
Pausa
exit 0
