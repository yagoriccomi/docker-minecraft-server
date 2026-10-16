# Instala o Syncthing como SERVICO DO WINDOWS (MinecraftP2P-Syncthing), sem Docker.
# Chamado pela opcao [N] do menu (-Menu), que pede admin sozinho.
#
# Por que: com o Syncthing no container, os PCs que NAO hospedam precisam deixar o Docker
# Desktop (e a VM do WSL) ligado so para receber o mapa. Como servico, o Docker so abre no PC
# que vai hospedar (opcao 1) e pode ser fechado no fim (opcao 2).
#
# O que faz (pode rodar de novo: reinstala/atualiza):
#   1. baixa o Syncthing e o shawl (wrapper de servico) para bin\ e confere o SHA256;
#   2. congela o mundo se o Minecraft estiver rodando AQUI (o primeiro scan nao pode pegar
#      arquivo pela metade);
#   3. remove o container 'syncthing' (mesmo Device ID: os dois juntos dariam conflito);
#   4. backup do syncthing_config\ e ajuste do config.xml (pasta /data -> <raiz>\data,
#      painel so em 127.0.0.1:8384);
#   5. cria o servico com a conta virtual NT SERVICE\MinecraftP2P-Syncthing (sem senha, sem
#      admin), da permissao so nas pastas necessarias, libera ligar/desligar para os usuarios
#      (menu, guardiao e SSH sem admin) e abre o firewall so para Tailscale e rede local;
#   6. sobe, confere saude, Device ID e scan da pasta. Qualquer falha -> volta ao container.
#
# Uso:  install-sync-service.ps1              -> instala/migra (pede admin)
#       install-sync-service.ps1 -Desinstalar -> volta ao container do compose.sync.yaml
#       install-sync-service.ps1 -Verificar   -> so baixa e confere os binarios (sem admin)
#       install-sync-service.ps1 -Menu        -> tela da opcao N (mostra o estado e pergunta)
# Registro em logs\sync-service.log.
param([switch]$Desinstalar, [switch]$Verificar, [switch]$Menu, [switch]$Elevado)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # a barra de progresso deixa o download 10x mais lento
. (Join-Path $PSScriptRoot 'common.ps1')      # $root, Write-Log, docker, RCON, trava do mundo, API e lib-sync
$script:LogFile = Join-Path $root 'logs\sync-service.log'

# Versoes fixas: a mesma do container (banco index-v2) e dos outros PCs. Para atualizar, troque
# versao + URL + hash (Syncthing: sha256sum.txt.asc da release; shawl nao publica hash, entao o
# valor abaixo foi calculado no download de 2026-10-16).
$SYNCTHING_VERSAO = 'v2.1.1'
$SYNCTHING_URL    = "https://github.com/syncthing/syncthing/releases/download/$SYNCTHING_VERSAO/syncthing-windows-amd64-$SYNCTHING_VERSAO.zip"
$SYNCTHING_SHA256 = 'dd4cba5222a0b7e170203c4422e27b7908584ace035272bcf483bc63138f54ae'
$SHAWL_VERSAO     = 'v1.9.0'
$SHAWL_URL        = "https://github.com/mtkennerly/shawl/releases/download/$SHAWL_VERSAO/shawl-$SHAWL_VERSAO-win64.zip"
$SHAWL_SHA256     = 'f883c5d09c9beae2efaeabd8513e7d3f57cd1d0864cec3df4f4a7b6ee904351c'

$servico   = $script:SyncServiceName
$conta     = "NT SERVICE\$servico"
$binDir    = Join-Path $root 'bin'
$stExe     = Join-Path $binDir 'syncthing.exe'
$shawlExe  = Join-Path $binDir 'shawl.exe'
$cfgDir    = Join-Path $root 'syncthing_config'
$cfgXml    = Join-Path $cfgDir 'config.xml'
$dataDir   = Join-Path $root 'data'
$stLogDir  = Join-Path $root 'logs\syncthing'
$GUI_SERVICO = '127.0.0.1:8384'    # o menu remoto entra por SSH e usa localhost
$GUI_DOCKER  = '0.0.0.0:8384'      # dentro do container precisa ouvir em todas as interfaces
$PASTA_DOCKER = '/data'
$FW_GRUPO  = 'Minecraft P2P - Syncthing'
$FW_ORIGEM = @('100.64.0.0/10', 'LocalSubnet')   # Tailscale + rede local
# Usuarios (BU) podem consultar, ligar e desligar o servico; o resto do SDDL fica como o Windows criou.
$ACE_USUARIOS = '(A;;CCLCSWRPWPDTLOCRRC;;;BU)'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Roda este script de novo como admin (nova janela, que pausa no fim) e devolve o codigo dele.
function Invoke-Elevado([string[]]$Extra) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Elevado') + $Extra
    Write-Host 'Pedindo permissao de administrador (o Windows vai perguntar)...' -ForegroundColor Cyan
    try { $p = Start-Process powershell.exe -ArgumentList $a -Verb RunAs -Wait -PassThru }
    catch { Write-Host '[CANCELADO] Sem permissao de administrador nada foi alterado.' -ForegroundColor Yellow; return 1 }
    return $p.ExitCode
}

# Chamada nativa (sc.exe, icacls, shawl) que falha alto: codigo != 0 vira excecao.
function Invoke-Nativo([string]$Exe, [string[]]$Argumentos) {
    $saida = & $Exe @Argumentos 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw ('{0} {1} falhou ({2}): {3}' -f $Exe, ($Argumentos -join ' '), $LASTEXITCODE, $saida.Trim()) }
    return $saida
}

# ---------------- binarios ----------------
function Get-Verificado([string]$Url, [string]$Sha256, [string]$Destino) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing
    $hash = (Get-FileHash -Path $Destino -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $Sha256) { throw "hash diferente do esperado para $Url (veio $hash). Download descartado." }
}

function Test-Binarios {
    if (-not (Test-Path $stExe) -or -not (Test-Path $shawlExe)) { return $false }
    $v = & $stExe --version 2>$null | Out-String
    return ($v -match [regex]::Escape("syncthing $SYNCTHING_VERSAO "))
}

function Install-Binarios {
    if (Test-Binarios) { Write-Log "binarios ja na versao $SYNCTHING_VERSAO (bin\)."; return }
    $tmp = Join-Path $env:TEMP ('mcp2p-sync-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Log "baixando Syncthing $SYNCTHING_VERSAO e shawl $SHAWL_VERSAO (conferindo SHA256)..."
        Get-Verificado $SYNCTHING_URL $SYNCTHING_SHA256 (Join-Path $tmp 'st.zip')
        Get-Verificado $SHAWL_URL $SHAWL_SHA256 (Join-Path $tmp 'shawl.zip')
        Expand-Archive (Join-Path $tmp 'st.zip') (Join-Path $tmp 'st') -Force
        Expand-Archive (Join-Path $tmp 'shawl.zip') (Join-Path $tmp 'shawl') -Force
        if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }
        Copy-Item (Get-ChildItem (Join-Path $tmp 'st') -Recurse -Filter 'syncthing.exe' | Select-Object -First 1).FullName $stExe -Force
        Copy-Item (Get-ChildItem (Join-Path $tmp 'shawl') -Recurse -Filter 'shawl.exe' | Select-Object -First 1).FullName $shawlExe -Force
        Write-Log 'binarios conferidos e copiados para bin\.' 'Green'
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------- config.xml ----------------
# Edita como texto (nao como XML) para nao mexer em mais nada do arquivo do Syncthing.
function Set-ConfigSync([string]$PastaDados, [string]$Gui) {
    if (-not (Test-Path $cfgXml)) { return }
    $t = [IO.File]::ReadAllText($cfgXml)
    $t = [regex]::Replace($t, '(<folder id="minecraft-data"[^>]*?\spath=")[^"]*(")', { param($m) $m.Groups[1].Value + $PastaDados + $m.Groups[2].Value })
    $t = [regex]::Replace($t, '(<gui\b[^>]*>\s*<address>)[^<]*(</address>)', { param($m) $m.Groups[1].Value + $Gui + $m.Groups[2].Value })
    [IO.File]::WriteAllText($cfgXml, $t, (New-Object Text.UTF8Encoding $false))
}

function Get-PastaConfigurada {
    if (-not (Test-Path $cfgXml)) { return $null }
    $m = [regex]::Match([IO.File]::ReadAllText($cfgXml), '<folder id="minecraft-data"[^>]*?\spath="([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}

# ---------------- API ----------------
function Wait-Saude([int]$TimeoutSec = 120) {
    $limite = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $limite) {
        try { if ((Invoke-RestMethod 'http://localhost:8384/rest/noauth/health' -TimeoutSec 5).status -eq 'OK') { return $true } } catch { }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Get-MeuId {
    try { Connect-Syncthing; return (Invoke-Syncthing '/system/status').myID } catch { return $null }
}

# Instalacao do zero: cria a pasta do mundo (o assistente P so pareia uma pasta que ja existe).
function Add-PastaMundo {
    $pasta = @{ id = $folderId; label = 'Minecraft Data'; path = $dataDir; type = 'sendreceive'
                ignorePerms = $true; fsWatcherEnabled = $true; rescanIntervalS = 3600 }
    Invoke-Syncthing "/config/folders/$folderId" 'Put' $pasta | Out-Null
    Write-Log "pasta '$folderId' criada apontando para $dataDir."
}

# Scan completo (a chamada so volta quando termina) e confere que a pasta ficou sem erro.
function Test-PastaPronta {
    Connect-Syncthing
    Invoke-Syncthing "/db/scan?folder=$folderId" 'Post' -TimeoutSec 3600 | Out-Null
    $st  = Invoke-Syncthing "/db/status?folder=$folderId"
    $err = Invoke-Syncthing "/folder/errors?folder=$folderId"
    $n   = @($err.errors | Where-Object { $_ }).Count
    if ($st.state -eq 'error' -or $n -gt 0) {
        $amostra = (@($err.errors | Select-Object -First 3 | ForEach-Object { "$($_.path): $($_.error)" }) -join ' | ')
        throw "pasta $folderId com erro depois do scan (estado $($st.state), $n erro(s)) $amostra $($st.error)"
    }
    Write-Log ('pasta {0}: estado {1}, {2:N0} arquivos, {3:N2} GB.' -f $folderId, $st.state, $st.localFiles, ($st.localBytes / 1GB)) 'Green'
}

# ---------------- servico ----------------
function New-ServicoSync {
    if (-not (Test-Path $stLogDir)) { New-Item -ItemType Directory -Path $stLogDir | Out-Null }
    if (-not (Get-SyncService)) {
        Invoke-Nativo $shawlExe @('add', '--name', $servico, '--restart', '--restart-delay', '10000',
            '--stop-timeout', '30000', '--no-log-cmd', '--log-dir', $stLogDir, '--cwd', $cfgDir,
            '--env', 'STNODEFAULTFOLDER=1', '--',
            $stExe, 'serve', '--no-browser', '--no-restart', '--no-upgrade', "--home=$cfgDir",
            "--log-file=$stLogDir\syncthing.log", '--log-max-size=5242880', '--log-max-old-files=3') | Out-Null
        Write-Log "servico $servico criado (shawl)."
    }
    Invoke-Nativo 'sc.exe' @('config', $servico, 'start=', 'delayed-auto', 'obj=', $conta, 'DisplayName=', 'Minecraft P2P - Syncthing') | Out-Null
    Invoke-Nativo 'sc.exe' @('description', $servico, 'Minecraft P2P: replica a pasta data com os outros PCs (Syncthing). Instalado pela opcao N do menu.') | Out-Null
    Invoke-Nativo 'sc.exe' @('failure', $servico, 'reset=', '86400', 'actions=', 'restart/60000/restart/60000/restart/300000') | Out-Null
    $sd = (Invoke-Nativo 'sc.exe' @('sdshow', $servico)).Trim()
    if ($sd -notlike "*$ACE_USUARIOS*") {
        Invoke-Nativo 'sc.exe' @('sdset', $servico, ($sd -replace '^D:', ('D:' + $ACE_USUARIOS))) | Out-Null
    }
    # A conta virtual so enxerga o necessario: le os binarios e altera config, mapa e logs dele.
    Invoke-Nativo 'icacls.exe' @($binDir, '/grant', "${conta}:(OI)(CI)RX", '/Q') | Out-Null
    foreach ($d in @($cfgDir, $dataDir, $stLogDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
        Invoke-Nativo 'icacls.exe' @($d, '/grant', "${conta}:(OI)(CI)M", '/Q') | Out-Null
    }
    Get-NetFirewallRule -Group $FW_GRUPO -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    foreach ($r in @(@('TCP', 22000), @('UDP', 22000), @('UDP', 21027))) {
        New-NetFirewallRule -DisplayName ('{0} ({1} {2})' -f $FW_GRUPO, $r[0], $r[1]) -Group $FW_GRUPO -Direction Inbound `
            -Action Allow -Program $stExe -Protocol $r[0] -LocalPort $r[1] -RemoteAddress $FW_ORIGEM -Profile Any | Out-Null
    }
    Write-Log 'conta virtual, permissoes, recuperacao e firewall configurados.'
}

function Remove-ServicoSync {
    $svc = Get-SyncService
    if ($svc) {
        if ($svc.Status -ne 'Stopped') { Stop-Service -Name $servico -Force; $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60)) }
        Invoke-Nativo 'sc.exe' @('delete', $servico) | Out-Null
    }
    Get-NetFirewallRule -Group $FW_GRUPO -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    foreach ($d in @($binDir, $cfgDir, $dataDir, $stLogDir)) {
        if (Test-Path $d) { & icacls.exe $d /remove $conta /Q 2>&1 | Out-Null }
    }
}

# ---------------- container ----------------
function Remove-ContainerSync {
    if (-not (Get-SyncContainerState)) { return }
    $r = Invoke-Docker ('compose -f "{0}" down' -f $script:SyncCompose) 180
    if ($r.Code -ne 0 -or (Get-SyncContainerState)) { throw "nao consegui remover o container syncthing: $($r.Err) $($r.Out)" }
    Write-Log 'container syncthing removido (compose.sync.yaml down).'
}

function Start-ContainerSync {
    Set-ConfigSync $PASTA_DOCKER $GUI_DOCKER
    $r = Invoke-Docker ('compose -f "{0}" up -d' -f $script:SyncCompose) 300
    if ($r.Code -ne 0) { throw "compose.sync.yaml up -d falhou: $($r.Err) $($r.Out)" }
    if (-not (Wait-Saude 180)) { throw 'o container do Syncthing subiu mas nao respondeu em 180 s' }
}

# Docker no ar (abre o Docker Desktop se preciso). Retorna $false se nao tem Docker instalado.
function Confirm-Docker {
    if ((Invoke-Docker 'info --format {{.ServerVersion}}' 20).Code -eq 0) { return $true }
    if (-not (Test-Path (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'))) { return $false }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'ensure-docker.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'o Docker Desktop nao ficou pronto' }
    return $true
}

# ---------------- fluxos ----------------
function Install-Servico {
    $modoAntes = Get-SyncMode
    # Reinstalando com versao nova: o exe em uso nao pode ser trocado (o guardiao religa se falhar).
    if ($modoAntes -eq 'servico' -and -not (Test-Binarios)) { Stop-Service -Name $servico -Force }
    Install-Binarios                                  # falha aqui = nada foi tocado ainda
    $temDocker = Confirm-Docker
    $doContainer = $temDocker -and [bool](Get-SyncContainerState)
    $idAntes = $null
    if ($modoAntes -eq 'servico' -or $doContainer) {
        $idAntes = Get-MeuId
        if (-not $idAntes) { throw 'o Syncthing atual nao responde na API: ligue-o (opcao S) e rode de novo' }
        Write-Log "Device ID atual: $idAntes"
    }
    $doZero = -not (Test-Path $cfgXml)
    $backup = $null

    # Sync/backup agendados esperam a migracao terminar.
    if (-not (Enter-WorldLock -TimeoutMin 15)) { throw 'outro sync/backup do mapa esta rodando ha mais de 15 min' }
    try {
        if (Suspend-WorldSaves) { Write-Log 'Minecraft rodando neste PC: mundo congelado durante a migracao.' 'Yellow' }

        if ($modoAntes -eq 'servico') { Stop-Service -Name $servico -Force; (Get-SyncService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60)) }
        if ($temDocker) { Remove-ContainerSync }

        if (-not $doZero) {
            $backup = '{0}.bak-{1:yyyyMMdd-HHmmss}' -f $cfgDir, (Get-Date)
            Copy-Item $cfgDir $backup -Recurse
            Write-Log "backup da config em $backup"
            Set-ConfigSync $dataDir $GUI_SERVICO
        }

        try {
            New-ServicoSync
            Start-Service -Name $servico
            if (-not (Wait-Saude 120)) { throw 'o servico subiu mas o Syncthing nao respondeu em 120 s (veja logs\syncthing\)' }
            if ($doZero) { Connect-Syncthing; Add-PastaMundo }
            $idDepois = Get-MeuId
            if ($idAntes -and $idDepois -ne $idAntes) { throw "Device ID mudou ($idAntes -> $idDepois): chaves nao reaproveitadas" }
            Write-Log 'servico no ar; escaneando a pasta do mundo (a 1a vez rele ~2 GB, alguns minutos)...' 'Cyan'
            Test-PastaPronta
        } catch {
            Write-Log ('ERRO na migracao: {0} - desfazendo...' -f $_.Exception.Message) 'Red'
            Remove-ServicoSync
            if ($backup) { Copy-Item (Join-Path $backup 'config.xml') $cfgXml -Force }
            # Volta para o container sempre que houver Docker e config (tambem se era uma reinstalacao).
            if ($temDocker -and -not $doZero) { Start-ContainerSync; Write-Log 'de volta ao container do Syncthing.' 'Yellow' }
            else { Write-Log 'sem Docker para voltar: rode a opcao N de novo depois de corrigir o erro acima.' 'Yellow' }
            throw
        }
    } finally {
        Resume-WorldSaves
        Exit-WorldLock
    }

    Write-Log "OK: Syncthing rodando como servico $servico (Device ID $idDepois)." 'Green'
    try {
        $con = (Invoke-Syncthing '/system/connections').connections
        $nomes = @{}; foreach ($d in (Invoke-Syncthing '/config/devices')) { $nomes[$d.deviceID] = $d.name }
        $on = @($con.PSObject.Properties | Where-Object { $_.Value.connected } | ForEach-Object { $nomes[$_.Name] })
        if ($on.Count) { Write-Log ('PCs conectados: ' + ($on -join ', ')) 'Green' }
        else { Write-Host 'Nenhum PC conectado ainda (eles podem levar 1-2 min para reconectar).' -ForegroundColor Yellow }
    } catch { }
    Write-Host ''
    Write-Host 'Para o Docker nao abrir sozinho ao ligar o PC: Docker Desktop > Settings > General >' -ForegroundColor Cyan
    Write-Host 'desmarque "Start Docker Desktop when you sign in". A opcao 1 do menu abre o Docker na hora de jogar.' -ForegroundColor Cyan
    Write-Host 'Para voltar ao container: opcao N do menu > desinstalar.' -ForegroundColor DarkGray
}

function Uninstall-Servico {
    if (-not (Get-SyncService)) { Write-Log 'o servico nao esta instalado - nada a fazer.'; return }
    if (-not (Confirm-Docker)) { throw 'sem Docker instalado nao ha container para onde voltar; o servico foi mantido' }
    if (-not (Enter-WorldLock -TimeoutMin 15)) { throw 'outro sync/backup do mapa esta rodando ha mais de 15 min' }
    try {
        if (Suspend-WorldSaves) { Write-Log 'Minecraft rodando neste PC: mundo congelado durante a volta ao container.' 'Yellow' }
        Remove-ServicoSync
        Write-Log 'servico removido; subindo o container do Syncthing...'
        Start-ContainerSync
        Test-PastaPronta
    } finally {
        Resume-WorldSaves
        Exit-WorldLock
    }
    Write-Log 'OK: Syncthing de volta ao container (compose.sync.yaml). Os binarios em bin\ podem ser apagados.' 'Green'
}

function Show-Menu {
    Write-Host '=== SYNCTHING COMO SERVICO DO WINDOWS (SEM DOCKER) ===' -ForegroundColor Cyan
    Write-Host ''
    if ((Get-SyncMode) -eq 'servico') {
        Write-Host ("Instalado: servico $servico ({0})." -f (Get-SyncService).Status) -ForegroundColor Green
        Write-Host ''
        Write-Host '  [R] Reinstalar / atualizar'
        Write-Host '  [D] Desinstalar (voltar ao container do Docker)'
        $op = (Read-Host '  Opcao (ENTER cancela)').Trim()
        if ($op -match '^[rR]$') { return Invoke-Elevado @() }
        if ($op -match '^[dD]$') { return Invoke-Elevado @('-Desinstalar') }
        return 0
    }
    Write-Host 'Hoje o Syncthing roda no Docker: o Docker Desktop (e a VM do WSL) precisa ficar'
    Write-Host 'ligado o tempo todo so para receber o mapa.'
    Write-Host ''
    Write-Host 'Como servico do Windows ele roda sozinho (~100 MB de RAM), com o mesmo Device ID e a'
    Write-Host 'mesma configuracao. O Docker so abre quando voce for hospedar (opcao 1).'
    Write-Host ''
    Write-Host 'Durante a instalacao (alguns minutos) o sync pausa e, se o servidor estiver rodando'
    Write-Host 'aqui, o mundo fica congelado (os jogadores continuam jogando normalmente).'
    Write-Host ''
    $c = (Read-Host '  Digite INSTALAR para continuar (ENTER cancela)').Trim()
    if ($c -ne 'INSTALAR') { Write-Host '  Cancelado.' -ForegroundColor Gray; return 0 }
    return Invoke-Elevado @()
}

# ---------------- principal ----------------
if ($Verificar) {
    Install-Binarios
    & $stExe --version
    exit 0
}
if ($Menu) { exit (Show-Menu) }

if (-not (Test-Admin)) {
    $extra = @(); if ($Desinstalar) { $extra += '-Desinstalar' }
    exit (Invoke-Elevado $extra)
}

$codigo = 0
try {
    if ($Desinstalar) { Uninstall-Servico } else { Install-Servico }
} catch {
    $codigo = 1
    Write-Log ('ERRO: ' + $_.Exception.Message) 'Red'
}
if ($Elevado) { Write-Host ''; Read-Host 'Pressione ENTER para fechar esta janela' | Out-Null }
exit $codigo
