# Troca a VERSION do compose.yaml por uma release OFICIAL do Minecraft (opcao [V] do menu).
#
# So oferece versoes do tipo "release" do manifest oficial da Mojang - snapshots, betas e
# versoes antigas de teste ficam de fora de proposito: um mundo compartilhado nao deve rodar
# em build instavel.
#
# O manifest e cacheado em %TEMP%\mcp2p-versions.json (6 h) para que a tela abra rapido e
# continue funcionando sem internet.
#
# IMPORTANTE (por que existem tantas confirmacoes aqui):
#   - SUBIR de versao converte o mapa para o formato novo. Isso e IRREVERSIVEL.
#   - DESCER de versao nao e suportado pelo Minecraft: o mundo ja convertido simplesmente
#     nao abre numa versao anterior. So da para voltar restaurando um backup.
#   - A versao do servidor tem que casar com a do cliente (MultiMC), senao ninguem entra.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\version.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$composePath = Join-Path $root 'compose.yaml'
$cachePath   = Join-Path $env:TEMP 'mcp2p-versions.json'
$MANIFEST    = 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json'
$MOSTRAR     = 12    # quantas releases recentes listar na tela

function Pausa { Write-Host ''; Write-Host '  Pressione ENTER para voltar ao menu...' -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null }

# ---------------- 1) versao configurada hoje ----------------
if (-not (Test-Path $composePath)) {
    Write-Log "set-version ERRO | compose.yaml nao encontrado em $composePath" 'Red'
    Pausa; exit 1
}
# Leitura com UTF-8 EXPLICITO. O 'Get-Content -Raw' do PowerShell 5.1 assume a codepage
# ANSI do Windows em arquivos sem BOM, e os acentos do compose.yaml voltariam duplamente
# codificados na hora de gravar (memória -> memÃ³ria).
$composeTxt = [System.IO.File]::ReadAllText($composePath, [System.Text.Encoding]::UTF8)
$mAtual = [regex]::Match($composeTxt, '(?m)^([ \t]*)VERSION:[ \t]*"?([^"#\r\n]+?)"?[ \t]*(#.*)?$')
if (-not $mAtual.Success) {
    Write-Log 'set-version ERRO | nao achei a linha VERSION: no compose.yaml' 'Red'
    Pausa; exit 1
}
$indent    = $mAtual.Groups[1].Value
$verAtual  = $mAtual.Groups[2].Value.Trim()
$comentario= $mAtual.Groups[3].Value

Write-Host ''
Write-Host '  === VERSAO DO MINECRAFT ===' -ForegroundColor White
Write-Host ''
Write-Host '  Versao configurada agora: ' -NoNewline -ForegroundColor Gray
Write-Host $verAtual -ForegroundColor Green
Write-Host ''

# ---------------- 2) releases oficiais (manifest da Mojang, com cache) ----------------
$releases = $null
$origem   = ''
if (Test-Path $cachePath) {
    try {
        $c = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        if (((Get-Date) - [datetime]$c.At).TotalHours -lt 6) {
            $releases = @($c.Releases); $origem = 'cache local'
        }
    } catch { }
}
if (-not $releases) {
    Write-Host '  Consultando a lista oficial de versoes da Mojang...' -ForegroundColor DarkGray
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
        $mf = Invoke-RestMethod -Uri $MANIFEST -TimeoutSec 20
        # SO releases oficiais. O manifest ja vem da mais nova para a mais antiga.
        $releases = @($mf.versions | Where-Object { $_.type -eq 'release' } |
                      ForEach-Object { [pscustomobject]@{ Id = $_.id; Data = ([datetime]$_.releaseTime).ToString('dd/MM/yyyy') } })
        $origem = 'site da Mojang'
        try {
            [pscustomobject]@{ At = (Get-Date).ToString('o'); Releases = $releases } |
                ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cachePath -Encoding UTF8
        } catch { }
    } catch {
        # Sem internet: tenta o cache mesmo vencido, senao cai no modo manual.
        if (Test-Path $cachePath) {
            try {
                $c = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
                $releases = @($c.Releases); $origem = 'cache VENCIDO (sem internet agora)'
            } catch { }
        }
    }
}
if (-not $releases -or $releases.Count -eq 0) {
    Write-Log 'set-version ERRO | sem internet e sem cache: nao da para listar as versoes oficiais.' 'Red'
    Write-Host '  Conecte a internet e tente de novo.' -ForegroundColor Yellow
    Pausa; exit 1
}

# Posicao na lista = ordem de lancamento (0 = mais nova). Comparar por indice evita
# interpretar numeros de versao (o Minecraft mudou de 1.21.x para 26.x em 2026).
$idxAtual = -1
for ($i = 0; $i -lt $releases.Count; $i++) { if ($releases[$i].Id -eq $verAtual) { $idxAtual = $i; break } }

Write-Host ('  Releases oficiais mais recentes (fonte: {0}):' -f $origem) -ForegroundColor Gray
Write-Host ''
$topo = [math]::Min($MOSTRAR, $releases.Count)
for ($i = 0; $i -lt $topo; $i++) {
    $r   = $releases[$i]
    $tag = ''
    $cor = 'Gray'
    if ($i -eq 0)            { $tag = '  <- mais recente'; $cor = 'Cyan' }
    if ($r.Id -eq $verAtual) {
        $cor = 'Green'
        if ($i -eq 0) { $tag = '  <- EM USO (e a mais recente)' } else { $tag = '  <- EM USO AGORA' }
    }
    Write-Host ('   [{0,2}] ' -f ($i + 1)) -NoNewline -ForegroundColor White
    Write-Host ('{0,-10}' -f $r.Id) -NoNewline -ForegroundColor $cor
    Write-Host (' {0}' -f $r.Data) -NoNewline -ForegroundColor DarkGray
    Write-Host $tag -ForegroundColor $cor
}
Write-Host ''
Write-Host '   [O] Outra versao oficial (digitar o numero, ex: 1.20.4)' -ForegroundColor Gray
Write-Host '   [ENTER] Cancelar e voltar ao menu' -ForegroundColor DarkGray
Write-Host ''

# ---------------- 3) escolha ----------------
$esc = Read-Host '  Escolha'
if ([string]::IsNullOrWhiteSpace($esc)) { Write-Host '  Cancelado.' -ForegroundColor DarkGray; exit 0 }

$novo = $null
if ($esc -match '^[Oo]$') {
    $digitada = (Read-Host '  Numero da versao (so releases oficiais)').Trim()
    if ([string]::IsNullOrWhiteSpace($digitada)) { Write-Host '  Cancelado.' -ForegroundColor DarkGray; exit 0 }
    $achada = @($releases | Where-Object { $_.Id -eq $digitada })
    if ($achada.Count -eq 0) {
        Write-Host ''
        Write-Host ('  [ERRO] "{0}" nao e uma release oficial do Minecraft.' -f $digitada) -ForegroundColor Red
        Write-Host '  Snapshots e pre-releases nao sao aceitos aqui de proposito.' -ForegroundColor Yellow
        Pausa; exit 1
    }
    $novo = $achada[0].Id
} elseif ($esc -match '^\d+$' -and [int]$esc -ge 1 -and [int]$esc -le $topo) {
    $novo = $releases[[int]$esc - 1].Id
} else {
    Write-Host '  Opcao invalida.' -ForegroundColor Red
    Pausa; exit 1
}

if ($novo -eq $verAtual) {
    Write-Host ''
    Write-Host ('  O servidor JA esta configurado na {0}. Nada a fazer.' -f $novo) -ForegroundColor Green
    Pausa; exit 0
}

# ---------------- 4) avisos conforme a direcao da troca ----------------
$idxNovo = -1
for ($i = 0; $i -lt $releases.Count; $i++) { if ($releases[$i].Id -eq $novo) { $idxNovo = $i; break } }
$descendo = ($idxAtual -ge 0 -and $idxNovo -gt $idxAtual)

Write-Host ''
Write-Host ('  {0}  ->  {1}' -f $verAtual, $novo) -ForegroundColor White
Write-Host ''
if ($descendo) {
    Write-Host '  !! ATENCAO: isto e VOLTAR para uma versao ANTERIOR.' -ForegroundColor Red
    Write-Host '     O Minecraft NAO sabe desconverter um mundo. Se o mapa ja foi aberto na' -ForegroundColor Red
    Write-Host ('     {0}, ele provavelmente NAO vai abrir na {1}.' -f $verAtual, $novo) -ForegroundColor Red
    Write-Host '     A forma segura de voltar e restaurar um backup daquela epoca (opcao [!]).' -ForegroundColor Yellow
} else {
    Write-Host '  !! ATENCAO: subir de versao CONVERTE o mapa para o formato novo.' -ForegroundColor Yellow
    Write-Host '     Isso e IRREVERSIVEL: depois o mundo nao abre mais na versao antiga.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host ('     Todos os jogadores precisam ter a {0} no MultiMC, senao ninguem entra.' -f $novo) -ForegroundColor Yellow
Write-Host '     Avise os outros hosts: eles tambem precisam dar [U] para pegar a troca.' -ForegroundColor Yellow
Write-Host ('     Bot AFK: ele NAO loga na {0} ate passar no teste da opcao [B] -> 1.' -f $novo) -ForegroundColor Yellow
Write-Host ''

$conf = Read-Host '  Digite SIM para continuar (ENTER cancela)'
if ($conf -ne 'SIM') { Write-Host '  Cancelado. Nada foi alterado.' -ForegroundColor DarkGray; exit 0 }

# ---------------- 5) backup antes de mexer ----------------
Write-Host ''
$bk = Read-Host '  Fazer um backup do mapa agora? (S/n)'
if ($bk -notmatch '^[Nn]') {
    Write-Host ''
    & (Join-Path $PSScriptRoot 'backup-world.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host '  [ERRO] O backup falhou. A versao NAO foi alterada.' -ForegroundColor Red
        Write-Log ("set-version ABORTADO | backup falhou antes de trocar {0} -> {1}" -f $verAtual, $novo) 'Red'
        Pausa; exit 1
    }
}

# ---------------- 6) grava o compose.yaml ----------------
# Mantem a indentacao e o comentario que ja existiam na linha; o alinhamento em 25
# colunas e o mesmo usado nas outras variaveis do arquivo.
$valor = 'VERSION: "' + $novo + '"'
if ($comentario) { $linhaNova = $indent + $valor.PadRight(25) + $comentario }
else             { $linhaNova = $indent + $valor }

$backupCompose = $composePath + '.bak'
Copy-Item -LiteralPath $composePath -Destination $backupCompose -Force
$composeNovo = $composeTxt.Remove($mAtual.Index, $mAtual.Length).Insert($mAtual.Index, $linhaNova)
# UTF8Encoding($false) = SEM BOM. O 'Set-Content -Encoding UTF8' do PowerShell 5.1
# escreveria um BOM que o compose.yaml nao tem, sujando o diff do git sem motivo.
[System.IO.File]::WriteAllText($composePath, $composeNovo, (New-Object System.Text.UTF8Encoding $false))

Write-Log ("set-version OK | compose.yaml: {0} -> {1}" -f $verAtual, $novo) 'Green'
Write-Host ('  (copia do compose anterior em {0})' -f (Split-Path $backupCompose -Leaf)) -ForegroundColor DarkGray

# ---------------- 7) aplicar agora? ----------------
$estado = Get-ContainerState $mcName
Write-Host ''
if ($estado -eq 'running') {
    Write-Host '  O servidor esta NO AR nesta maquina com a versao antiga.' -ForegroundColor Yellow
    Write-Host '  Para aplicar, ele precisa ser recriado (quem estiver jogando cai).' -ForegroundColor Yellow
    Write-Host ''
    $ap = Read-Host '  Recriar o servidor na versao nova agora? (s/N)'
} else {
    Write-Host '  O servidor esta parado. A versao nova entra no proximo [1] Jogar.' -ForegroundColor Gray
    $ap = 'n'
}

if ($ap -match '^[Ss]') {
    Write-Host ''
    Write-Host '  Avisando quem esta no servidor e salvando o mundo...' -ForegroundColor Gray
    try { Invoke-Rcon ('say [SERVIDOR] Trocando para a versao {0} - reconecte em instantes' -f $novo) | Out-Null } catch { }
    try { Invoke-Rcon 'save-all' 60 | Out-Null } catch { }
    Write-Host '  Baixando a imagem e recriando o container...' -ForegroundColor Gray
    docker compose -f $composePath pull
    docker compose -f $composePath up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Log 'set-version ERRO | falha ao recriar o container na versao nova' 'Red'
        Write-Host '  Veja o erro acima. Para voltar atras: renomeie compose.yaml.bak.' -ForegroundColor Yellow
        Pausa; exit 1
    }
    Write-Log ("set-version OK | servidor recriado na {0}" -f $novo) 'Green'
    Write-Host ''
    Write-Host ('  Servidor subindo na {0}. A conversao do mapa pode levar alguns minutos:' -f $novo) -ForegroundColor Green
    Write-Host '  acompanhe pela opcao [6] Ver logs e espere o "Done".' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host ('  Versao gravada como {0}. Use [1] Jogar quando quiser subir.' -f $novo) -ForegroundColor Green
}
Pausa
exit 0
