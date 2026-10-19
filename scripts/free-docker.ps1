# Depois de parar o servidor (opcao 2), oferece fechar o Docker Desktop para devolver a RAM
# da VM do WSL. So faz sentido com o Syncthing como servico do Windows (opcao N): no modo
# docker o Syncthing depende do Docker e o guardiao o reabriria.
# Nunca fecha sozinho e nem oferece se houver OUTROS containers rodando neste PC.
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
. (Join-Path $PSScriptRoot 'lib-sync.ps1')

if ((Get-SyncMode) -ne 'servico') { exit 0 }
$nomes = @(docker ps --format '{{.Names}}' 2>$null | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { exit 0 }                     # Docker ja fechado

Write-Host ''
if ($nomes.Count -gt 0) {
    Write-Host ('O Docker continua aberto: ha outros containers rodando ({0}).' -f ($nomes -join ', ')) -ForegroundColor DarkGray
    exit 0
}
Write-Host 'O Syncthing roda como servico: o Docker nao e mais necessario neste PC agora.' -ForegroundColor Cyan
$r = (Read-Host '  Fechar o Docker Desktop para liberar a memoria? (S/N)').Trim()
if ($r -notmatch '^[sS]') { Write-Host '  Docker mantido aberto.' -ForegroundColor Gray; exit 0 }

# 'docker desktop stop' desliga a VM com calma; versoes antigas nao tem o comando.
docker desktop stop 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Get-Process -Name 'Docker Desktop' | Stop-Process -Force
    wsl.exe --terminate docker-desktop 2>$null | Out-Null
}
Write-Host '  [OK] Docker Desktop fechado. A opcao 1 abre de novo quando for jogar.' -ForegroundColor Green
exit 0
