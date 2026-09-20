# Assistente de PRIMEIROS PASSOS: instalar do zero (1o PC) ou conectar um PC
# adicional a quem ja tem o mundo. Chamado pela opcao [P] do menu.bat.
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$root    = Split-Path $PSScriptRoot -Parent
$cfgPath = Join-Path $root 'syncthing_config\config.xml'

function OK  ($m) { Write-Host "   [ OK ]   $m" -ForegroundColor Green }
function FALTA($m){ Write-Host "   [FALTA]  $m" -ForegroundColor Yellow }
function TODO($m) { Write-Host "   [ -- ]   $m" -ForegroundColor Gray }
function Titulo($t) {
    Write-Host ''
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor Cyan
    Write-Host "   $t" -ForegroundColor White
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor Cyan
    Write-Host ''
}

function Get-SyncApi {
    if (-not (Test-Path $cfgPath)) { return $null }
    try {
        [xml]$c = Get-Content $cfgPath
        return @{ 'X-API-Key' = $c.configuration.gui.apikey }
    } catch { return $null }
}
function Get-MyId {
    $h = Get-SyncApi; if (-not $h) { return $null }
    try { return (Invoke-RestMethod 'http://localhost:8384/rest/system/status' -Headers $h -TimeoutSec 4).myID } catch { return $null }
}
function Get-TsExe {
    $p = @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $p) { $p = (Get-Command tailscale -ErrorAction SilentlyContinue).Source }
    return $p
}
function Test-DockerUp { $null = docker info --format '{{.ServerVersion}}' 2>$null; return ($LASTEXITCODE -eq 0) }
function Test-SyncUp   { return ((docker inspect -f '{{.State.Status}}' syncthing 2>$null) -eq 'running') }

function Checklist-Comuns {
    if (Test-DockerUp) { OK 'Docker instalado e rodando' } else { FALTA 'Docker - use a opcao [X] do menu e abra o Docker Desktop' }
    if (Get-Command git -ErrorAction SilentlyContinue) { OK 'Git instalado' } else { FALTA 'Git - use a opcao [X] do menu' }
    $ts = Get-TsExe
    if ($ts) {
        $st = & $ts status --json 2>$null | ConvertFrom-Json
        if ($st.BackendState -eq 'Running') { OK 'Tailscale conectado' }
        else { FALTA 'Tailscale instalado, mas sem login - rode: tailscale up' }
    } else { FALTA 'Tailscale - use a opcao [X] do menu' }
    if (Test-SyncUp) { OK 'Replicacao (Syncthing) no ar' } else { FALTA 'Syncthing parado - use a opcao [1] do menu (ele sobe junto)' }
}

function Mostrar-Identidade {
    $id = Get-MyId
    $ts = Get-TsExe
    Write-Host ''
    if ($id) {
        Write-Host '   Seu Device ID do Syncthing (envie para o outro jogador):' -ForegroundColor White
        Write-Host "   $id" -ForegroundColor Cyan
    } else {
        Write-Host '   Device ID indisponivel (o Syncthing precisa estar no ar).' -ForegroundColor Yellow
    }
    if ($ts) {
        $ip = (& $ts ip -4 2>$null | Select-Object -First 1)
        if ($ip) {
            Write-Host ''
            Write-Host '   Seu IP na rede Tailscale (endereco do servidor no jogo):' -ForegroundColor White
            Write-Host "   $ip`:25565" -ForegroundColor Cyan
        }
    }
}

function Progresso-Mapa {
    $h = Get-SyncApi; if (-not $h) { return }
    try {
        $c = Invoke-RestMethod 'http://localhost:8384/rest/db/completion?folder=minecraft-data' -Headers $h -TimeoutSec 4
        $s = Invoke-RestMethod 'http://localhost:8384/rest/db/status?folder=minecraft-data' -Headers $h -TimeoutSec 4
        $pct = [math]::Round([double]$c.completion, 1)
        $falta = [math]::Round([double]$s.needBytes / 1GB, 2)
        Write-Host ''
        if ($pct -ge 100 -and [double]$s.needBytes -eq 0) {
            Write-Host "   Mapa sincronizado: 100%  (estado: $($s.state))" -ForegroundColor Green
        } else {
            Write-Host "   Mapa sincronizado: $pct%  -  faltam $falta GB  (estado: $($s.state))" -ForegroundColor Yellow
        }
    } catch { }
}

function Parear {
    Titulo 'PAREAR COM OUTRO JOGADOR'
    $h = Get-SyncApi
    if (-not $h -or -not (Test-SyncUp)) {
        Write-Host '   O Syncthing precisa estar no ar. Use a opcao [1] do menu primeiro.' -ForegroundColor Yellow
        return
    }
    Mostrar-Identidade
    Write-Host ''
    Write-Host '   Agora cole o Device ID do OUTRO jogador (ou ENTER para cancelar):' -ForegroundColor White
    $id = (Read-Host '   Device ID').Trim().ToUpper()
    if (-not $id) { Write-Host '   Cancelado.' -ForegroundColor Gray; return }
    if ($id -notmatch '^[A-Z2-7]{7}(-[A-Z2-7]{7}){7}$') {
        Write-Host '   Formato invalido. Deve ter 8 grupos de 7 caracteres separados por hifen.' -ForegroundColor Red
        return
    }
    $nome = (Read-Host '   Um apelido para esse PC (ex: Beatriz)').Trim()
    if (-not $nome) { $nome = 'amigo' }
    try {
        $dev = @{ deviceID = $id; name = $nome } | ConvertTo-Json
        Invoke-RestMethod "http://localhost:8384/rest/config/devices/$id" -Method Put -Headers $h -ContentType 'application/json' -Body $dev -TimeoutSec 15 | Out-Null
        $f = Invoke-RestMethod 'http://localhost:8384/rest/config/folders/minecraft-data' -Headers $h -TimeoutSec 10
        if (@($f.devices.deviceID) -notcontains $id) {
            $f.devices += [pscustomobject]@{ deviceID = $id }
            Invoke-RestMethod 'http://localhost:8384/rest/config/folders/minecraft-data' -Method Put -Headers $h -ContentType 'application/json' -Body ($f | ConvertTo-Json -Depth 10) -TimeoutSec 15 | Out-Null
        }
        Write-Host ''
        Write-Host "   [ OK ] '$nome' adicionado e a pasta do mundo foi compartilhada com ele." -ForegroundColor Green
        Write-Host '   Ele precisa fazer o mesmo do lado dele, com o SEU Device ID acima.' -ForegroundColor Gray
    } catch {
        Write-Host "   [ERRO] Nao foi possivel parear: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Roteiro-Primeiro {
    Titulo 'ROTEIRO - PRIMEIRO PC (voce tem o mundo e vai hospedar)'
    Checklist-Comuns
    Write-Host ''
    TODO 'Traga seu mundo para o servidor  ->  opcao [!] Importar mundo'
    TODO 'Envie seu Device ID aos amigos   ->  opcao [3] deste assistente'
    TODO 'Adicione o Device ID deles       ->  opcao [4] deste assistente'
    TODO 'Suba o servidor                  ->  opcao [1] do menu'
    Mostrar-Identidade
    Write-Host ''
    Write-Host '   Ao terminar de jogar, use a opcao [2] do menu e aguarde o sync' -ForegroundColor Gray
    Write-Host '   chegar a 100% antes de desligar o PC.' -ForegroundColor Gray
}

function Roteiro-Adicional {
    Titulo 'ROTEIRO - PC ADICIONAL (conectar a quem ja tem o mundo)'
    Checklist-Comuns
    Write-Host ''
    TODO 'Troque Device IDs com o dono do mundo  ->  opcao [4] deste assistente'
    TODO 'Aguarde o mapa chegar por completo (pode demorar bastante)'
    Progresso-Mapa
    Mostrar-Identidade
    Write-Host ''
    Write-Host '   IMPORTANTE: NAO use a opcao [1] (Jogar) antes de chegar a 100%.' -ForegroundColor Red
    Write-Host '   Iniciar o servidor com o mapa incompleto cria uma versao paralela' -ForegroundColor Gray
    Write-Host '   do mundo e gera conflito (split-brain). Enquanto isso, entre no' -ForegroundColor Gray
    Write-Host '   servidor do outro jogador pelo IP Tailscale dele.' -ForegroundColor Gray
}

# ---------------- LOOP ----------------
while ($true) {
    Titulo 'PRIMEIROS PASSOS - Minecraft P2P'
    Write-Host '   Qual e o caso deste computador?' -ForegroundColor White
    Write-Host ''
    Write-Host '    [1] Este e o PRIMEIRO PC  (eu tenho o mundo e vou hospedar)'
    Write-Host '    [2] Este e um PC ADICIONAL (vou me conectar a quem ja tem)'
    Write-Host '    [3] Mostrar meu Device ID e meu IP Tailscale'
    Write-Host '    [4] Parear com outro jogador (colar o Device ID dele)'
    Write-Host '    [0] Voltar ao menu' -ForegroundColor DarkGray
    Write-Host ''
    $op = (Read-Host '   Opcao').Trim()
    switch ($op) {
        '1' { Roteiro-Primeiro;  Write-Host ''; Read-Host '   ENTER para continuar' | Out-Null }
        '2' { Roteiro-Adicional; Write-Host ''; Read-Host '   ENTER para continuar' | Out-Null }
        '3' { Titulo 'MINHA IDENTIDADE'; Mostrar-Identidade; Write-Host ''; Read-Host '   ENTER para continuar' | Out-Null }
        '4' { Parear; Write-Host ''; Read-Host '   ENTER para continuar' | Out-Null }
        '0' { return }
        default { }
    }
    Clear-Host
}
