# Instala/verifica as dependencias do projeto (Docker Desktop, Git, Tailscale) via winget
# e configura o salvamento automatico do mundo (tarefa agendada de 30 min).
$ErrorActionPreference = 'Continue'

Write-Host '===================================================' -ForegroundColor Cyan
Write-Host '     INSTALAR / VERIFICAR DEPENDENCIAS DO PROJETO'   -ForegroundColor Cyan
Write-Host '===================================================' -ForegroundColor Cyan

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '[ERRO] winget nao encontrado.' -ForegroundColor Red
    Write-Host 'Atualize o "Instalador de Aplicativo" pela Microsoft Store e tente de novo.' -ForegroundColor Red
    return
}

$pacotes = @(
    [pscustomobject]@{ Nome = 'Docker Desktop'; Id = 'Docker.DockerDesktop' },
    [pscustomobject]@{ Nome = 'Git';            Id = 'Git.Git' },
    [pscustomobject]@{ Nome = 'Tailscale';      Id = 'tailscale.tailscale' }
)

foreach ($p in $pacotes) {
    Write-Host ''
    Write-Host ("--> {0}  ({1})" -f $p.Nome, $p.Id) -ForegroundColor Cyan
    winget install -e --id $p.Id --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -eq 0) { Write-Host ("    [OK] {0} instalado/atualizado." -f $p.Nome) -ForegroundColor Green }
    else { Write-Host ("    [INFO] {0}: winget retornou {1} (pode ja estar na versao mais recente)." -f $p.Nome, $LASTEXITCODE) -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '=== Configurando salvamento automatico do mundo (a cada 30 min) ===' -ForegroundColor Cyan
try {
    # Usa o lancador run-hidden.vbs (wscript) para rodar SEM piscar janela de console.
    $vbs     = Join-Path $PSScriptRoot 'run-hidden.vbs'
    $action  = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}"' -f $vbs)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                   -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName 'MinecraftP2P-AutoSave' -Action $action -Trigger $trigger -Force `
        -Description 'Salva o mundo do Minecraft (save-all flush) a cada 30 min, de forma silenciosa (sem janela).' | Out-Null
    Write-Host '[OK] Tarefa "MinecraftP2P-AutoSave" registrada (roda a cada 30 min).' -ForegroundColor Green
} catch {
    Write-Host ("[AVISO] Nao foi possivel registrar a tarefa de autosave: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Concluido!' -ForegroundColor Green
Write-Host 'Obs.: se o Docker Desktop ou o Tailscale foram instalados agora, reinicie o PC e' -ForegroundColor Green
Write-Host 'faca login no Tailscale antes de usar o servidor.' -ForegroundColor Green
