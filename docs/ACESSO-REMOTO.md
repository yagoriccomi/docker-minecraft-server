# 🎛️ Acesso Remoto — Controlar o servidor da Beatriz pela sua máquina

Este guia configura o **`menu-remoto.bat`**: um painel que roda na **sua máquina (Maquina3)**
e executa os comandos (iniciar, parar, logs, RCON, backup) na **máquina da Beatriz**, por SSH,
através da rede **Tailscale**.

> **Regra de ouro (não esqueça):** continua valendo o *single-host* do `CLAUDE.md` —
> apenas **UMA** máquina roda o container `mc` por vez. O `menu-remoto.bat` já tem uma
> trava: ele **recusa** iniciar o servidor da Beatriz se o seu Minecraft local estiver ligado.

---

## Visão geral

```
  SUA MÁQUINA (Maquina3)                 MÁQUINA DA BEATRIZ
  ┌────────────────────┐   Tailscale    ┌────────────────────┐
  │  menu-remoto.bat   │ ─── SSH ─────▶ │  OpenSSH Server     │
  │  (cliente SSH)     │   (porta 22)   │  Docker + compose   │
  └────────────────────┘                └────────────────────┘
```

Você precisa fazer 3 blocos: **A)** na máquina da Beatriz, **B)** na sua, **C)** testar e usar.

---

## A) Na máquina da Beatriz (feito 1 vez)

### A1. Instalar e logar no Tailscale
1. Baixar em https://tailscale.com/download/windows e instalar.
2. Logar com a conta da rede de vocês (a mesma tailnet que você usa).
3. Anotar o **IP Tailscale** dela (começa com `100.`) — veja em:
   ```powershell
   & "C:\Program Files\Tailscale\tailscale.exe" ip -4
   ```

### A2. Ligar o servidor SSH do Windows (OpenSSH Server)
Abrir o **PowerShell como Administrador** na máquina dela e rodar:
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
# Liberar no firewall (normalmente já vem, mas garante):
New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

### A3. Autorizar a SUA chave pública (login sem senha)
A sua chave pública (da Maquina3) é:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEYq/cW1dIx0mWGEfMDqvpv6YMLc2NZw9mYsbx3zlwJV yago.riccomi.s@gmail.com
```
Na máquina da Beatriz, no PowerShell **da conta de usuário dela** (não admin), rodar
(troque o conteúdo entre aspas pela linha acima, exatamente):
```powershell
$pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEYq/cW1dIx0mWGEfMDqvpv6YMLc2NZw9mYsbx3zlwJV yago.riccomi.s@gmail.com'
$dir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
Add-Content -Path "$dir\authorized_keys" -Value $pub -Encoding ascii
```
> ⚠️ Se a conta dela for **Administrador**, o OpenSSH do Windows ignora o `authorized_keys`
> pessoal e exige o arquivo `C:\ProgramData\ssh\administrators_authorized_keys`.
> Nesse caso, rode isto (PowerShell **Admin**) em vez do de cima:
> ```powershell
> $pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEYq/cW1dIx0mWGEfMDqvpv6YMLc2NZw9mYsbx3zlwJV yago.riccomi.s@gmail.com'
> Add-Content -Path 'C:\ProgramData\ssh\administrators_authorized_keys' -Value $pub -Encoding ascii
> icacls 'C:\ProgramData\ssh\administrators_authorized_keys' /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'
> ```

### A4. Confirmar que o projeto está em `D:\Server-Minecraft`
O menu remoto chama caminhos fixos na máquina dela:
- `D:\Server-Minecraft\compose.yaml`
- `D:\Server-Minecraft\scripts\status.ps1`
- `D:\Server-Minecraft\scripts\iniciar-limpo.ps1`
- `D:\Server-Minecraft\scripts\backup-mapa.ps1`

Como o Syncthing sincroniza **apenas a pasta `data`**, os arquivos de `scripts\` **não**
chegam sozinhos na máquina dela. Copie a pasta `scripts\` atualizada (com os dois `.ps1`
novos) e o `compose.yaml` para `D:\Server-Minecraft` na máquina da Beatriz.
Anote também o **nome de usuário Windows** dela (`whoami`) — você vai usar no passo B2.

---

## B) Na sua máquina (Maquina3) — feito 1 vez

### B1. Instalar e logar no Tailscale
Mesma coisa: https://tailscale.com/download/windows → instalar → logar na **mesma** tailnet.
Confirme que as duas aparecem:
```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
```

### B2. Criar o atalho `beatriz` no seu `~/.ssh/config`
Você já tem a chave `id_ed25519`. Adicione este bloco no fim de
`C:\Users\USER\.ssh\config` (troque `USUARIO_DELA` e o IP `100.x.y.z`
pelos dados do passo A1/A4):
```
Host beatriz
    HostName 100.x.y.z
    User USUARIO_DELA
    IdentityFile C:\Users\USER\.ssh\id_ed25519
    IdentitiesOnly yes
```
> Dica: se o Tailscale MagicDNS estiver ligado, dá pra usar o nome da máquina dela
> no lugar do IP em `HostName` (ex.: `HostName maquina-da-beatriz`).

---

## C) Testar e usar

1. Dê um duplo-clique em **`menu-remoto.bat`** (ou rode no terminal).
2. Escolha a opção **[T] Testar conexão SSH**.
   - Deve aparecer `Conexao OK`, o nome da máquina dela e a versão do Docker.
   - Se **pedir senha**, a chave não foi autorizada — revise o passo **A3**.
   - Se der **timeout / conexão recusada**, revise Tailscale (A1/B1) e o SSH (A2).
3. Com o teste ok, use o menu normalmente. As opções agem **na máquina da Beatriz**:

| Opção | O que faz na máquina dela |
|------|----------------------------|
| 1 | Limpa conflitos do Syncthing e **sobe** o servidor (com trava anti split-brain) |
| 2 | Status dos containers, saúde e sincronização + estado do SEU local |
| 3 | Últimos 80 logs do Minecraft |
| 4 | Console RCON interativo (`list`, `time set day`, …; `exit` p/ voltar) |
| 5 | Reinicia só o Minecraft |
| 6 | Para só o Minecraft (Syncthing segue enviando o save) |
| 7 | Para tudo (`docker compose down`) |
| 8 | Backup `.zip` do mapa, salvo na máquina dela |
| 9 | Abre o painel Syncthing dela no navegador (`http://beatriz:8384`) |

---

## 🔒 Fluxo seguro do revezamento (com controle remoto)

O controle remoto facilita a vida, mas **aumenta o risco de split-brain** se usado sem cuidado.
Regra prática:

1. **Antes de iniciar o servidor da Beatriz remotamente**, garanta que o SEU local está parado
   (o menu já bloqueia, mas confirme).
2. Ao terminar de jogar, **pare o `mc`** (opção 6) e **espere o Syncthing ficar `Up to Date`**
   (opção 2) antes que qualquer outra máquina suba o servidor.
3. Nunca tenha **duas máquinas** com o container `mc` ligado ao mesmo tempo.

---

## 🩹 Problemas comuns

- **`ssh: Could not resolve hostname beatriz`** → falta o bloco `Host beatriz` no `~/.ssh/config` (B2).
- **Pede senha toda vez** → chave não autorizada (A3) ou conta admin sem
  `administrators_authorized_keys` (nota do A3).
- **`Connection timed out`** → Tailscale caído em alguma ponta (`tailscale status`) ou firewall/sshd parado (A2).
- **`docker: command not found` no SSH** → o Docker Desktop dela não está aberto/rodando.
- **Menu abre e fecha sozinho** → rode pelo terminal pra ver o erro, ou confira se o `%REMOTE%`
  no topo do `.bat` bate com o `Host` do config.
