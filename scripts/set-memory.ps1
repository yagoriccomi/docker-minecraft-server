# Troca a memoria (heap da JVM) do servidor Minecraft (opcao [M] do menu).
#
# A memoria fica em .env (MC_MEMORY=8G), lido pelo compose.yaml. O .env e LOCAL e nao vai
# pro git: cada PC tem a sua RAM, entao cada um guarda o seu valor.
#
# RECOMENDADO = 25% da RAM fisica, com piso de 2 GB e teto de 32 GB
#   (PC de 8 GB -> 2 GB | PC de 64 GB -> 16 GB | PC de 128 GB ou mais -> 32 GB).
# Acima de 50% da RAM o script recusa: sobraria pouco para Windows, Docker e Syncthing.
#
# Uso: set-memory.ps1              -> tela de escolha (digite o valor em GB, ou R = recomendado)
#      set-memory.ps1 -Gb 8        -> troca direto, sem perguntas
param([ValidateRange(0, 32)][int]$Gb = 0)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\memory.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$envPath = Join-Path $root '.env'
$MIN = 2; $MAX = 32
function Pausa { if (-not $Gb) { Write-Host ''; Write-Host '  Pressione ENTER para voltar ao menu...' -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null } }

# ---------------- detecta o PC ----------------
$ramGb  = [int][math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)   # 63,7 -> 64
$rec    = [int][math]::Min($MAX, [math]::Max($MIN, [math]::Floor($ramGb * 0.25)))
$limite = [int][math]::Max($MIN, [math]::Min($MAX, [math]::Floor($ramGb * 0.5)))                 # recusa acima disso
$perfil = if ($ramGb -le 8) { 'basico' } elseif ($ramGb -le 16) { 'intermediario' }
          elseif ($ramGb -le 32) { 'bom' } elseif ($ramGb -le 64) { 'potente' } else { 'estacao de trabalho' }

# ---------------- valor em uso ----------------
$envTxt = if (Test-Path $envPath) { [System.IO.File]::ReadAllText($envPath) } else { '' }
$m = [regex]::Match($envTxt, '(?m)^MC_MEMORY=(\d+)G[ \t]*\r?$')
$atual = if ($m.Success) { [int]$m.Groups[1].Value } else { 4 }   # 4 = padrao do compose.yaml

# ---------------- escolha ----------------
$novo = $Gb
if ($novo -eq 0) {
    Write-Host ''
    Write-Host '  === MEMORIA DO SERVIDOR ===' -ForegroundColor White
    Write-Host ''
    Write-Host ('  Este PC:          {0} GB de RAM ({1})' -f $ramGb, $perfil) -ForegroundColor Gray
    Write-Host '  Memoria agora:    ' -NoNewline -ForegroundColor Gray
    Write-Host ('{0} GB' -f $atual) -ForegroundColor Green
    Write-Host '  Recomendada:      ' -NoNewline -ForegroundColor Gray
    Write-Host ('{0} GB' -f $rec) -NoNewline -ForegroundColor Yellow
    Write-Host '  (25% da RAM, entre 2 e 32 GB)' -ForegroundColor DarkGray
    Write-Host ('  Maximo aceito:    {0} GB (50% da RAM)' -f $limite) -ForegroundColor Gray
    Write-Host ''
    $opcoes = @($MIN, 4, 6, 8, 12, 16, 24, 32, $rec, $atual) | Where-Object { $_ -ge $MIN -and $_ -le $limite } | Sort-Object -Unique
    foreach ($o in $opcoes) {
        $tag = ''; $cor = 'Gray'
        if ($o -eq $rec)   { $tag = '  <- RECOMENDADO'; $cor = 'Yellow' }
        if ($o -eq $atual) { $tag += '  <- EM USO'; $cor = 'Green' }
        Write-Host ('   {0,2} GB{1}' -f $o, $tag) -ForegroundColor $cor
    }
    Write-Host ''
    Write-Host ('   Digite o valor em GB ({0} a {1}) ou [R] para o recomendado.' -f $MIN, $limite) -ForegroundColor DarkGray
    Write-Host '   [ENTER] Cancelar e voltar ao menu' -ForegroundColor DarkGray
    Write-Host ''
    $esc = (Read-Host '  Escolha').Trim()
    if ($esc -eq '') { Write-Host '  Cancelado.' -ForegroundColor DarkGray; exit 0 }
    if ($esc -match '^[rR]$') { $novo = $rec }
    elseif ($esc -match '^(\d+)\s*[gG]?[bB]?$') { $novo = [int]$Matches[1] }
    else { Write-Host '  Opcao invalida.' -ForegroundColor Red; Pausa; exit 1 }
}
if ($novo -lt $MIN -or $novo -gt $limite) {
    Write-Host ('  Valor fora do aceito: use de {0} a {1} GB neste PC.' -f $MIN, $limite) -ForegroundColor Red
    Write-Log ("memoria ERRO | {0} GB recusado (aceito {1}-{2} GB, RAM {3} GB)" -f $novo, $MIN, $limite, $ramGb) 'Red'
    Pausa; exit 1
}
if ($novo -eq $atual -and $m.Success) {
    Write-Host ('  A memoria JA e {0} GB. Nada a fazer.' -f $novo) -ForegroundColor Green
    Pausa; exit 0
}

# ---------------- grava o .env ----------------
if ($m.Success) { $envTxt = $envTxt.Remove($m.Index, $m.Length).Insert($m.Index, "MC_MEMORY=${novo}G") }
else { $envTxt = $envTxt.TrimEnd("`r", "`n"); $envTxt = ($envTxt + "`nMC_MEMORY=${novo}G`n").TrimStart("`n") }
[System.IO.File]::WriteAllText($envPath, $envTxt)
Write-Log ("memoria OK | .env: {0} GB -> {1} GB (RAM {2} GB, recomendado {3} GB)" -f $atual, $novo, $ramGb, $rec) 'Green'
if ($novo -gt $rec) { Write-Host ('  Aviso: acima do recomendado ({0} GB). Funciona, mas sobra menos RAM para o resto.' -f $rec) -ForegroundColor Yellow }

# ---------------- aplicar ----------------
# A JVM so le a memoria ao nascer, e 'docker restart' NAO rele o .env: precisa recriar (up -d).
Write-Host ''
if ((Get-ContainerState $mcName) -eq 'running') {
    $jog = '?'
    try { $jog = (Invoke-Rcon 'list') } catch { }
    Write-Host ('  O servidor esta no ar ({0}).' -f $jog) -ForegroundColor Gray
    if ($Gb) {
        Write-Host '  Vale no proximo inicio: [2] Parar e depois [1] Jogar.' -ForegroundColor Gray
    } else {
        $r = Read-Host '  Reiniciar AGORA para aplicar? O mundo e salvo antes (S/N)'
        if ($r -match '^[sSyY]') {
            Write-Host '  Reiniciando (ate 60 s para salvar e fechar)...' -ForegroundColor Gray
            Push-Location $root
            try {
                docker compose -f compose.yaml up -d --force-recreate --timeout 60 | Out-Null
                Write-Log ("memoria | servidor recriado com {0} GB (exit {1})" -f $novo, $LASTEXITCODE) 'Green'
                Write-Host ('  Servidor reiniciando com {0} GB. Acompanhe pelos logs [6].' -f $novo) -ForegroundColor Green
            } finally { Pop-Location }
        } else {
            Write-Host '  Ok. Vale no proximo inicio: [2] Parar e depois [1] Jogar.' -ForegroundColor Yellow
            Write-Host '  (A opcao [9] Reiniciar NAO aplica a memoria nova.)' -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host '  O servidor esta desligado. A memoria nova vale no proximo [1] Jogar.' -ForegroundColor Gray
}
Pausa
exit 0
