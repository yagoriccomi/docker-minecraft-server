# Grava a trava do host (data\host-ativo.json) e pede ao Syncthing para envia-la.
# Chamado pelo menu.bat: "ligado" depois do [1] Jogar; "desligado" ao parar pelas opcoes 2, K e !.
param(
    [Parameter(Mandatory = $true)][ValidateSet('ligado', 'desligado')][string]$Estado,
    [string]$Motivo = ''
)
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
. (Join-Path $PSScriptRoot 'lib-lease.ps1')   # inclui o lib-hosts.ps1

if ($Estado -eq 'desligado') {
    # Parada de proposito: o vigia de rede nao deve religar um servidor que ele tinha pausado.
    Remove-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\net-guard.json') -ErrorAction SilentlyContinue
    # Parar o container DESTE PC nunca libera a trava de outro host.
    if (Test-LeaseOther (Get-HostLease)) { exit 0 }
}
Set-HostLease $Estado $Motivo
exit 0
