# Liga/desliga as areas forcadas (/forceload) do servidor (opcao [F] do menu).
#
# CADASTRAR area continua sendo no console do jogo (opcao [7] ou dentro do jogo):
#     forceload add <x1> <z1> <x2> <z2>            (Overworld)
#     execute in minecraft:the_end run forceload add ...   (outras dimensoes)
# Este script so LIGA e DESLIGA o conjunto inteiro, sem perder o cadastro:
#   - desligar: guarda a lista atual em data\forceload-cadastro.json e tira tudo;
#   - ligar:    junta o que esta ativo com o cadastro, regrava o cadastro e recoloca tudo.
# O cadastro fica em data\ (o Syncthing leva aos outros PCs); o estado desejado de cada PC fica
# no .env (MC_FORCELOAD=ligado|desligado, padrao ligado), aplicado pelo [1] Jogar.
#
# Uso: forceload.ps1                    -> tela (status + ligar/desligar)
#      forceload.ps1 -Acao aplicar [-Esperar]   -> aplica o estado do .env (usado pelo [1])
#      forceload.ps1 -Acao ligar|desligar|status
param([ValidateSet('menu', 'aplicar', 'ligar', 'desligar', 'status')][string]$Acao = 'menu', [switch]$Esperar)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$script:LogFile = Join-Path $root 'logs\forceload.log'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$envPath  = Join-Path $root '.env'
$cadastro = Join-Path $root 'data\forceload-cadastro.json'
$DIMS     = @('minecraft:overworld', 'minecraft:the_nether', 'minecraft:the_end')

function Estado-Env {
    $t = if (Test-Path $envPath) { [System.IO.File]::ReadAllText($envPath) } else { '' }
    $m = [regex]::Match($t, '(?m)^MC_FORCELOAD=(\w+)')
    if ($m.Success -and $m.Groups[1].Value -match '^(desligado|off|false|0)$') { return 'desligado' }
    return 'ligado'
}
function Gravar-Env([string]$valor) {
    $t = if (Test-Path $envPath) { [System.IO.File]::ReadAllText($envPath) } else { '' }
    $m = [regex]::Match($t, '(?m)^MC_FORCELOAD=\w*[ \t]*\r?$')
    if ($m.Success) { $t = $t.Remove($m.Index, $m.Length).Insert($m.Index, "MC_FORCELOAD=$valor") }
    else { $t = ($t.TrimEnd("`r", "`n") + "`nMC_FORCELOAD=$valor`n").TrimStart("`n") }
    [System.IO.File]::WriteAllText($envPath, $t)
}

# Chunks forcados agora, por dimensao: hashtable dim -> lista de "x,z".
function Ativos {
    $r = @{}
    foreach ($d in $DIMS) {
        $out = Invoke-Rcon ("execute in {0} run forceload query" -f $d) 60
        $r[$d] = @([regex]::Matches($out, '\[(-?\d+), (-?\d+)\]') | ForEach-Object { '{0},{1}' -f $_.Groups[1].Value, $_.Groups[2].Value })
    }
    return $r
}
function Ler-Cadastro {
    $r = @{}; foreach ($d in $DIMS) { $r[$d] = @() }
    if (Test-Path $cadastro) {
        try {
            $j = Get-Content -LiteralPath $cadastro -Raw | ConvertFrom-Json
            foreach ($d in $DIMS) { if ($j.dimensoes.$d) { $r[$d] = @($j.dimensoes.$d) } }
        } catch { Write-Log "forceload AVISO | cadastro ilegivel: $($_.Exception.Message)" 'Yellow' }
    }
    return $r
}
# ATENCAO: variaveis do PowerShell nao diferenciam maiusculas; o parametro NAO pode se chamar
# $dims (seria a mesma variavel que a lista $DIMS e o cadastro sairia vazio).
function Gravar-Cadastro($mapa) {
    # JSON montado a mao: o ConvertTo-Json do PowerShell 5.1 nao serializa dicionario aninhado.
    $partes = foreach ($d in $DIMS) {
        $lista = @($mapa[$d] | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { '"{0}"' -f $_ })
        '    "{0}": [{1}]' -f $d, ($lista -join ', ')
    }
    $json = "{`n  `"atualizado`": `"$((Get-Date).ToString('yyyy-MM-dd HH:mm'))`",`n  `"dimensoes`": {`n" + ($partes -join ",`n") + "`n  }`n}`n"
    [System.IO.File]::WriteAllText($cadastro, $json)
}

function Servidor-Pronto([int]$limiteS) {
    $fim = (Get-Date).AddSeconds($limiteS)
    while ($true) {
        if ((Get-ContainerState $mcName) -eq 'running') {
            $h = (Invoke-Docker "inspect -f {{.State.Health.Status}} $mcName" 30).Out
            if ($h -eq 'healthy') { return $true }
        }
        if ((Get-Date) -ge $fim) { return $false }
        Start-Sleep -Seconds 5
    }
}

function Ligar {
    $at = Ativos; $cad = Ler-Cadastro; $total = 0
    foreach ($d in $DIMS) {
        $todos = @(@($cad[$d]) + @($at[$d]) | Where-Object { $_ } | Sort-Object -Unique)
        $cad[$d] = $todos; $total += $todos.Count
        # Agrupa em faixas continuas por linha (mesmo z) para usar poucos comandos.
        $porZ = @{}
        foreach ($c in $todos) { $x, $z = $c -split ','; if (-not $porZ.ContainsKey([int]$z)) { $porZ[[int]$z] = @() }; $porZ[[int]$z] += [int]$x }
        foreach ($z in $porZ.Keys) {
            $xs = @($porZ[$z] | Sort-Object); $ini = $xs[0]; $ant = $xs[0]
            foreach ($x in @($xs[1..($xs.Count)] | Where-Object { $_ -ne $null }) + @([int]::MaxValue)) {
                if ($x -eq $ant + 1) { $ant = $x; continue }
                Invoke-Rcon ("execute in {0} run forceload add {1} {2} {3} {2}" -f $d, ($ini * 16), ($z * 16), ($ant * 16)) 60 | Out-Null
                $ini = $x; $ant = $x
            }
        }
    }
    Gravar-Cadastro $cad
    Write-Log ("forceload | ligado: {0} chunks (cadastro atualizado)" -f $total) 'Green'
}

function Desligar {
    $at = Ativos; $cad = Ler-Cadastro; $n = 0
    foreach ($d in $DIMS) { $n += @($at[$d]).Count; $cad[$d] = @(@($cad[$d]) + @($at[$d]) | Where-Object { $_ } | Sort-Object -Unique) }
    Gravar-Cadastro $cad   # guarda ANTES de tirar: o cadastro nunca se perde
    # Trava: rele o arquivo e confere que cada chunk ativo esta la. Se faltar algo, NAO tira nada.
    $relido = Ler-Cadastro
    foreach ($d in $DIMS) {
        $falta = @($at[$d] | Where-Object { $_ -and (@($relido[$d]) -notcontains $_) })
        if ($falta.Count) { throw ('cadastro incompleto em {0} ({1} chunks faltando); nada foi desligado' -f $d, $falta.Count) }
    }
    foreach ($d in $DIMS) { if (@($at[$d]).Count) { Invoke-Rcon ("execute in {0} run forceload remove all" -f $d) 60 | Out-Null } }
    Write-Log ("forceload | desligado: {0} chunks tirados (guardados no cadastro)" -f $n) 'Yellow'
}

function Mostrar {
    Write-Host ''
    Write-Host '  === AREAS FORCADAS (/forceload) ===' -ForegroundColor White
    $e = Estado-Env
    Write-Host '  Neste PC (.env): ' -NoNewline -ForegroundColor Gray
    Write-Host $e.ToUpper() -ForegroundColor $(if ($e -eq 'ligado') { 'Green' } else { 'Yellow' })
    $cad = Ler-Cadastro
    $online = (Get-ContainerState $mcName) -eq 'running'
    $at = $null; if ($online) { try { $at = Ativos } catch { } }
    foreach ($d in $DIMS) {
        $nome = $d -replace 'minecraft:', ''
        $a = if ($at) { @($at[$d]).Count } else { '?' }
        Write-Host ('    {0,-10} ativos agora: {1,4}   no cadastro: {2,4}' -f $nome, $a, @($cad[$d]).Count) -ForegroundColor Gray
    }
    if (-not $online) { Write-Host '  (servidor desligado neste PC: "ativos agora" so aparece com ele no ar)' -ForegroundColor DarkGray }
    Write-Host '  Cadastrar area: no console [7] -> forceload add x1 z1 x2 z2' -ForegroundColor DarkGray
}

$online = (Get-ContainerState $mcName) -eq 'running'
switch ($Acao) {
    'status' { Mostrar; exit 0 }
    'aplicar' {
        if ($Esperar) { Write-Host '  Areas forcadas: esperando o servidor ficar pronto...' -ForegroundColor DarkGray }
        if (-not (Servidor-Pronto $(if ($Esperar) { 300 } else { 5 }))) { Write-Log 'forceload AVISO | servidor nao ficou pronto; estado nao aplicado' 'Yellow'; exit 1 }
        if ((Estado-Env) -eq 'ligado') { Ligar } else { Desligar }
        exit 0
    }
    'ligar'    { Gravar-Env 'ligado';    if ($online) { Ligar } else { Write-Host '  Vale no proximo [1] Jogar.' -ForegroundColor Gray }; exit 0 }
    'desligar' { Gravar-Env 'desligado'; if ($online) { Desligar } else { Write-Host '  Vale no proximo [1] Jogar.' -ForegroundColor Gray }; exit 0 }
    'menu' {
        Mostrar
        Write-Host ''
        Write-Host '   [1] Ligar as areas forcadas' -ForegroundColor White
        Write-Host '   [2] Desligar as areas forcadas (o cadastro fica guardado)' -ForegroundColor White
        Write-Host '   [ENTER] Voltar ao menu' -ForegroundColor DarkGray
        $o = Read-Host '  Escolha'
        switch ($o) {
            '1' { Gravar-Env 'ligado';    if ($online) { Ligar } else { Write-Host '  Gravado. Vale no proximo [1] Jogar.' -ForegroundColor Gray } }
            '2' { Gravar-Env 'desligado'; if ($online) { Desligar } else { Write-Host '  Gravado. Vale no proximo [1] Jogar.' -ForegroundColor Gray } }
            default { exit 0 }
        }
        Write-Host ''; Write-Host '  Pressione ENTER para voltar ao menu...' -NoNewline -ForegroundColor DarkGray; Read-Host | Out-Null
    }
}
