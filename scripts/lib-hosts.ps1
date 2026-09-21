# Funcoes compartilhadas: descobrir QUAL host da rede Tailscale esta com o servidor
# de Minecraft no ar e consultar quantos jogadores estao conectados.
# Uso: . "$PSScriptRoot\lib-hosts.ps1"   (dot-source)

function Get-TsExe {
    $p = @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $p) { $p = (Get-Command tailscale -ErrorAction SilentlyContinue).Source }
    return $p
}

# Varre, EM PARALELO, a porta 25565 de todos os hosts online do Tailscale.
# Retorna um objeto { Ok; SelfName; SelfIP; Hosts = @({Nome;IP}) }.
# Ok = $false quando o Tailscale nao esta disponivel (resultado desconhecido).
function Find-MinecraftHosts([int]$deadlineMs = 500) {
    $r = [pscustomobject]@{ Ok = $false; SelfName = ''; SelfIP = ''; Hosts = @() }
    $ts = Get-TsExe
    if (-not $ts) { return $r }
    $st = & $ts status --json 2>$null | ConvertFrom-Json
    if (-not $st -or $st.BackendState -ne 'Running') { return $r }
    $r.Ok       = $true
    $r.SelfName = $st.Self.HostName
    $r.SelfIP   = @($st.Self.TailscaleIPs | Where-Object { $_ -notmatch ':' })[0]

    # dispara todas as conexoes de uma vez...
    $probes = @()
    foreach ($p in @($st.Peer.PSObject.Properties.Value)) {
        if (-not $p.Online) { continue }
        $ip = @($p.TailscaleIPs | Where-Object { $_ -notmatch ':' })[0]
        if (-not $ip) { continue }
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $a = $c.BeginConnect($ip, 25565, $null, $null)
            $probes += [pscustomobject]@{ Nome = $p.HostName; IP = $ip; C = $c; A = $a }
        } catch { $c.Close() }
    }
    # ...e espera todas contra UM prazo so (host mudo nao trava o menu)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $found = @()
    foreach ($pr in $probes) {
        $left = [int][math]::Max(0, $deadlineMs - $sw.ElapsedMilliseconds)
        $ok = $false
        try { $ok = $pr.A.AsyncWaitHandle.WaitOne($left) -and $pr.C.Connected } catch { }
        if ($ok) { $found += [pscustomobject]@{ Nome = $pr.Nome; IP = $pr.IP } }
        try { $pr.C.Close() } catch { }
    }
    $r.Hosts = $found
    return $r
}

# Server List Ping do Minecraft: pergunta ao servidor quantos jogadores estao on.
# Retorna { Online; Max; Nomes } ou $null se nao responder.
function Get-McPlayers([string]$ip, [int]$port = 25565, [int]$timeoutMs = 800) {
    function VarInt([int]$v) {
        $b = New-Object System.Collections.Generic.List[byte]
        do {
            $t = $v -band 0x7F
            $v = [int]([uint32]$v -shr 7)
            if ($v -ne 0) { $t = $t -bor 0x80 }
            $b.Add([byte]$t)
        } while ($v -ne 0)
        return ,$b.ToArray()
    }
    function ReadVarInt($s) {
        $n = 0; $shift = 0
        while ($true) {
            $x = $s.ReadByte()
            if ($x -lt 0) { throw 'eof' }
            $n = $n -bor (($x -band 0x7F) -shl $shift)
            if (($x -band 0x80) -eq 0) { break }
            $shift += 7
            if ($shift -gt 35) { throw 'varint' }
        }
        return $n
    }
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $a = $c.BeginConnect($ip, $port, $null, $null)
        if (-not $a.AsyncWaitHandle.WaitOne($timeoutMs) -or -not $c.Connected) { return $null }
        $c.EndConnect($a)
        $s = $c.GetStream(); $s.ReadTimeout = $timeoutMs; $s.WriteTimeout = $timeoutMs

        $hostB = [System.Text.Encoding]::UTF8.GetBytes($ip)
        $payload = New-Object System.Collections.Generic.List[byte]
        $payload.AddRange([byte[]](VarInt 0))            # id do pacote: handshake
        $payload.AddRange([byte[]](VarInt 767))          # versao do protocolo (qualquer vale p/ status)
        $payload.AddRange([byte[]](VarInt $hostB.Length))
        $payload.AddRange($hostB)
        $payload.Add([byte](($port -shr 8) -band 0xFF))  # porta, big-endian
        $payload.Add([byte]($port -band 0xFF))
        $payload.AddRange([byte[]](VarInt 1))            # proximo estado: status
        $pkt = New-Object System.Collections.Generic.List[byte]
        $pkt.AddRange([byte[]](VarInt $payload.Count))
        $pkt.AddRange($payload)
        $pkt.AddRange([byte[]]@(1, 0))                   # status request
        $arr = $pkt.ToArray(); $s.Write($arr, 0, $arr.Length)

        $null = ReadVarInt $s                            # tamanho do pacote
        $null = ReadVarInt $s                            # id do pacote
        $len  = ReadVarInt $s                            # tamanho do JSON
        $buf = New-Object byte[] $len; $off = 0
        while ($off -lt $len) {
            $n = $s.Read($buf, $off, $len - $off)
            if ($n -le 0) { throw 'eof' }
            $off += $n
        }
        $j = [System.Text.Encoding]::UTF8.GetString($buf) | ConvertFrom-Json
        return [pscustomobject]@{
            Online = [int]$j.players.online
            Max    = [int]$j.players.max
            Nomes  = @($j.players.sample | Where-Object { $_ -and $_.name } | ForEach-Object { $_.name })
        }
    } catch { return $null } finally { $c.Close() }
}
