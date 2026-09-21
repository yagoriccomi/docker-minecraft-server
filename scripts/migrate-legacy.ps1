# Migra containers da estrutura antiga (v1.0.0: tudo num compose so) para a nova
# (v1.1.0: stacks separados 'minecraft-p2p' e 'minecraft-p2p-sync').
# Sem isso, apos atualizar, o menu nao acharia o servidor antigo e o 'up'
# falharia com "nome de container ja em uso".
#
# Regras de seguranca:
#   - Syncthing: migrado sempre (config e pareamentos ficam em syncthing_config/).
#   - Minecraft: so e tocado se estiver PARADO. Rodando, apenas avisa.
# Codigo de saida 3 = algo foi feito/avisado (o menu pausa para o usuario ler).
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$root        = Split-Path $PSScriptRoot -Parent
$composeSync = Join-Path $root 'compose.sync.yaml'

function Info($name) {
    $j = docker inspect $name 2>$null | ConvertFrom-Json
    if (-not $j) { return $null }
    return [pscustomobject]@{
        Projeto = $j[0].Config.Labels.'com.docker.compose.project'
        Estado  = $j[0].State.Status
    }
}

$acao = $false

$s = Info 'syncthing'
if ($s -and $s.Projeto -ne 'minecraft-p2p-sync') {
    Write-Host '  Migrando o Syncthing para o stack separado (nova versao)...' -ForegroundColor Yellow
    docker stop syncthing 2>&1 | Out-Null
    docker rm syncthing 2>&1 | Out-Null
    docker compose -f $composeSync up -d 2>&1 | Out-Null
    if ((Info 'syncthing').Estado -eq 'running') {
        Write-Host '  [OK] Syncthing migrado - config e pareamentos preservados.' -ForegroundColor Green
    } else {
        Write-Host '  [ERRO] Syncthing nao subiu apos a migracao. Rode a opcao 4 (diagnostico).' -ForegroundColor Red
    }
    $acao = $true
}

$m = Info 'minecraft'
if ($m -and $m.Projeto -ne 'minecraft-p2p') {
    if ($m.Estado -eq 'running') {
        Write-Host '  [AVISO] Seu servidor ainda roda na estrutura ANTIGA. Tudo continua funcionando;' -ForegroundColor Yellow
        Write-Host '          ele sera migrado sozinho depois que voce o parar (opcao 2).' -ForegroundColor Yellow
    } else {
        docker rm minecraft 2>&1 | Out-Null
        Write-Host '  [OK] Container antigo do Minecraft removido - o mundo em data/ esta intacto.' -ForegroundColor Green
    }
    $acao = $true
}

if ($acao) { exit 3 } else { exit 0 }
