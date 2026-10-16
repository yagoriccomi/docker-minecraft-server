# Garante o Docker no ar antes de subir o servidor (opcao 1 do menu).
# Com o Syncthing como servico do Windows (opcao N), o Docker Desktop so precisa estar aberto
# no PC que hospeda: este script o abre na hora de jogar e espera o engine responder.
# Saida: 0 = Docker pronto | 1 = nao instalado ou nao respondeu a tempo.
param([int]$TimeoutSec = 240)
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$ddExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'

function Test-Engine { $null = docker info --format '{{.ServerVersion}}' 2>$null; return ($LASTEXITCODE -eq 0) }

if (Test-Engine) { exit 0 }

if (-not (Get-Process -Name 'Docker Desktop')) {
    if (-not (Test-Path $ddExe)) {
        Write-Host '[ERRO] Docker Desktop nao encontrado. Use a opcao [X] para instalar.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Abrindo o Docker Desktop (so e preciso no PC que hospeda)...' -ForegroundColor Cyan
    Start-Process $ddExe
}

Write-Host -NoNewline 'Esperando o Docker ficar pronto'
$limite = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $limite) {
    Start-Sleep -Seconds 3
    if (Test-Engine) { Write-Host ' pronto!' -ForegroundColor Green; exit 0 }
    Write-Host -NoNewline '.'
}
Write-Host ''
Write-Host "[ERRO] O Docker nao respondeu em $TimeoutSec s. Confira o Docker Desktop e tente de novo." -ForegroundColor Red
exit 1
