# Checagem ANTES de subir o servidor (opcao 1 do menu).
# Sai com codigo 2 se o Minecraft ja estiver no ar em OUTRO host do Tailscale,
# para o menu.bat pedir confirmacao. Codigo 0 = livre para subir.
$ErrorActionPreference = 'SilentlyContinue'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
. (Join-Path $PSScriptRoot 'lib-hosts.ps1')

Write-Host 'Verificando se alguem ja esta hospedando na rede Tailscale...' -ForegroundColor DarkGray
$scan = Find-MinecraftHosts 900      # prazo maior: aqui a precisao importa mais que a velocidade
Remove-Item (Join-Path $env:TEMP 'mcp2p-hosts.json') -ErrorAction SilentlyContinue   # invalida o cache do menu

if (-not $scan.Ok) {
    Write-Host '[AVISO] Tailscale indisponivel: nao da para saber se outro PC esta hospedando.' -ForegroundColor Yellow
    exit 0
}
$outros = @($scan.Hosts)
if ($outros.Count -eq 0) {
    Write-Host 'Ninguem hospedando. Livre para subir.' -ForegroundColor Green
    exit 0
}

$h  = $outros[0]
$pl = Get-McPlayers $h.IP
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Red
Write-Host "   O SERVIDOR JA ESTA NO AR EM: $($h.Nome)" -ForegroundColor Red
Write-Host "   Para jogar, entre em:  $($h.IP):25565" -ForegroundColor Cyan
if ($pl) {
    $quem = if ($pl.Nomes.Count) { ' - ' + ($pl.Nomes -join ', ') } else { '' }
    Write-Host "   Jogadores agora: $($pl.Online)/$($pl.Max)$quem" -ForegroundColor Gray
}
Write-Host '  ------------------------------------------------------------' -ForegroundColor Red
Write-Host '   Subir o SEU servidor agora cria dois mapas divergentes e o' -ForegroundColor Gray
Write-Host '   progresso de UM deles sera PERDIDO (split-brain).' -ForegroundColor Gray
Write-Host '  ============================================================' -ForegroundColor Red
Write-Host ''
exit 2
