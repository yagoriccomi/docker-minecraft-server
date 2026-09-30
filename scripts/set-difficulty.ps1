# Troca a dificuldade do mundo (opcao [D] do menu).
#
# A dificuldade fica em data\server.properties, que o Syncthing ja sincroniza entre os PCs:
# trocar aqui vale para quem hospedar depois, sem git. O compose.yaml NAO define DIFFICULTY
# de proposito - a imagem itzg so mexe numa propriedade quando a variavel existe.
# O servidor aplica o server.properties toda vez que liga, passando por cima da trava de
# dificuldade do mundo (o level.dat veio do single-player com a dificuldade travada).
#
# Uso: set-difficulty.ps1              -> tela de escolha
#      set-difficulty.ps1 -Nivel hard  -> troca direto, sem perguntas (peaceful|easy|normal|hard)
param([ValidateSet('', 'peaceful', 'easy', 'normal', 'hard')][string]$Nivel = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\difficulty.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$propsPath = Join-Path $root 'data\server.properties'
# ISO-8859-1 le e grava cada byte como ele e: o server.properties do Java nao e UTF-8.
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$niveis = [ordered]@{
    peaceful = @{ Nome = 'Pacifico'; Desc = 'sem monstros. A farm de pigman PARA.' }
    easy     = @{ Nome = 'Facil';    Desc = 'monstros fracos. Portal gera 1x piglins.' }
    normal   = @{ Nome = 'Normal';   Desc = 'Portal gera 2x piglins.' }
    hard     = @{ Nome = 'Dificil';  Desc = 'Portal gera 3x piglins. Fome pode matar, zumbis quebram portas.' }
}
function Pausa { if (-not $Nivel) { Write-Host ''; Write-Host '  Pressione ENTER para voltar ao menu...' -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null } }

if (-not (Test-Path $propsPath)) {
    Write-Log "dificuldade ERRO | $propsPath nao existe (o servidor ainda nao rodou neste PC?)" 'Red'
    Pausa; exit 1
}
$props = [System.IO.File]::ReadAllText($propsPath, $latin1)
$m = [regex]::Match($props, '(?m)^difficulty=([^\r\n]*)')
$atual = if ($m.Success) { $m.Groups[1].Value.Trim() } else { 'easy' }
if (-not $niveis.Contains($atual)) { $niveis[$atual] = @{ Nome = $atual; Desc = '' } }   # valor estranho no arquivo: mostra como esta

# ---------------- escolha ----------------
$novo = $Nivel
if (-not $novo) {
    Write-Host ''
    Write-Host '  === DIFICULDADE DO MUNDO ===' -ForegroundColor White
    Write-Host ''
    Write-Host '  Dificuldade agora: ' -NoNewline -ForegroundColor Gray
    Write-Host ('{0} ({1})' -f $niveis[$atual].Nome, $atual) -ForegroundColor Green
    Write-Host ''
    $i = 0
    foreach ($k in $niveis.Keys) {
        $i++
        $cor = if ($k -eq $atual) { 'Green' } else { 'Gray' }
        Write-Host ('   [{0}] ' -f $i) -NoNewline -ForegroundColor White
        Write-Host ('{0,-9}' -f $niveis[$k].Nome) -NoNewline -ForegroundColor $cor
        Write-Host (' ' + $niveis[$k].Desc) -NoNewline -ForegroundColor DarkGray
        if ($k -eq $atual) { Write-Host '  <- EM USO' -ForegroundColor Green } else { Write-Host '' }
    }
    Write-Host ''
    Write-Host '   O mundo era Dificil no single-player, antes de virar servidor.' -ForegroundColor DarkGray
    Write-Host '   [ENTER] Cancelar e voltar ao menu' -ForegroundColor DarkGray
    Write-Host ''
    $esc = Read-Host '  Escolha'
    if ([string]::IsNullOrWhiteSpace($esc)) { Write-Host '  Cancelado.' -ForegroundColor DarkGray; exit 0 }
    if ($esc -notmatch '^[1-4]$') { Write-Host '  Opcao invalida.' -ForegroundColor Red; Pausa; exit 1 }
    $novo = @($niveis.Keys)[[int]$esc - 1]
}
if ($novo -eq $atual) {
    Write-Host ('  A dificuldade JA e {0}. Nada a fazer.' -f $niveis[$novo].Nome) -ForegroundColor Green
    Pausa; exit 0
}

# ---------------- grava o server.properties e manda para os outros PCs ----------------
if ($m.Success) { $props = $props.Remove($m.Index, $m.Length).Insert($m.Index, "difficulty=$novo") }
else            { $props = $props.TrimEnd("`r", "`n") + "`ndifficulty=$novo`n" }
[System.IO.File]::WriteAllText($propsPath, $props, $latin1)
Write-Log ("dificuldade OK | server.properties: {0} -> {1}" -f $atual, $novo) 'Green'
# Com o watcher do Syncthing desligado (modo agendado) so um scan envia o arquivo.
try { Connect-Syncthing; Invoke-Syncthing "/db/scan?folder=$folderId&sub=server.properties" 'Post' | Out-Null } catch { }

# ---------------- aplicar agora ----------------
Write-Host ''
if ((Get-ContainerState $mcName) -eq 'running') {
    # Ao vivo, sem derrubar ninguem. Se o comando for recusado, o proximo inicio aplica.
    try {
        $r = Invoke-Rcon "difficulty $novo"
        Write-Log ("dificuldade | aplicada ao vivo neste PC: {0}" -f $r) 'Green'
    } catch {
        Write-Log ("dificuldade AVISO | o servidor recusou ao vivo ({0}); vale no proximo inicio (opcoes 2 e 1)." -f $_.Exception.Message) 'Yellow'
    }
} else {
    . (Join-Path $PSScriptRoot 'lib-lease.ps1')
    $lease = Get-HostLease
    if (Test-LeaseOther $lease) {
        Write-Host ('  O servidor esta no PC de {0}. O arquivo novo ja foi para la pelo Syncthing;' -f $lease.nome) -ForegroundColor Yellow
        Write-Host ('  para valer AGORA, la no console (opcao 7) digite:  difficulty {0}' -f $novo) -ForegroundColor Yellow
        Write-Host '  Se ninguem digitar, vale no proximo inicio do servidor.' -ForegroundColor Yellow
    } else {
        Write-Host '  O servidor esta desligado. A dificuldade nova vale no proximo [1] Jogar.' -ForegroundColor Gray
    }
}
Pausa
exit 0
