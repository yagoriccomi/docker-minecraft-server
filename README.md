# 🎮 Servidor de Minecraft Descentralizado (P2P)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](compose.yaml)
[![Minecraft](https://img.shields.io/badge/Minecraft-1.21.11-62B47A?logo=minecraft&logoColor=white)](#-o-que-alterar--e-para-quê)
[![Syncthing](https://img.shields.io/badge/Sync-Syncthing-0891D1?logo=syncthing&logoColor=white)](https://syncthing.net/)
[![Tailscale](https://img.shields.io/badge/VPN-Tailscale-242424?logo=tailscale&logoColor=white)](https://tailscale.com/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#)

Servidor de Minecraft **Java** rodando em **Docker**, com o mapa sincronizado entre
amigos via **Syncthing** sobre uma rede **Tailscale** (VPN mesh). Sem hospedagem paga,
sem abrir portas no roteador: cada um hospeda na sua vez, e o mundo "viaja" junto.

> **Ideia central:** só **uma** pessoa roda o servidor por vez. Ao terminar, o Syncthing
> envia o mapa atualizado para o outro jogador, que assume na próxima sessão.

---

## 📑 Índice

- [✨ Recursos](#-recursos)
- [🧩 Como funciona](#-como-funciona)
- [✅ Pré-requisitos](#-pré-requisitos)
- [🚀 Instalação (em qualquer PC)](#-instalação-em-qualquer-pc)
  - [🥇 Fluxo A — Primeiro PC](#-fluxo-a--primeiro-pc)
  - [🤝 Fluxo B — PC adicional](#-fluxo-b--pc-adicional)
- [🕹️ Como usar — o painel menu.bat](#-como-usar--o-painel-menubat)
  - [📥 Importar um mundo existente](#-importar-um-mundo-existente)
  - [🔗 Sincronizar com um amigo](#-sincronizar-com-um-amigo-syncthing)
  - [🔄 Ciclo de revezamento](#-ciclo-de-revezamento-importante)
  - [🛟 Salvamento automático e recuperação](#-salvamento-automático-e-recuperação-de-energia)
  - [🧱 Resiliência: dois stacks Docker](#-resiliência-por-que-são-dois-stacks-docker)
- [🔧 O que alterar — e para quê](#-o-que-alterar--e-para-quê)
- [🧾 Captura de erros / diagnóstico](#-captura-de-erros--diagnóstico)
- [📂 Estrutura do projeto](#-estrutura-do-projeto)
- [📜 Licença](#-licença)

---

## ✨ Recursos

- 🐳 **Docker Compose** — sobe Minecraft + Syncthing com um comando.
- 🔁 **Sincronização P2P** do mundo via Syncthing (só a pasta de dados é compartilhada).
- 🖥️ **Painel `menu.bat`** — interface de console para iniciar, parar, status, logs, console RCON e backup.
- 💾 **Backup em `.zip`** com carimbo de data/hora, em um clique.
- 🧾 **Captura de erros** — cada ação registra sucesso/falha em `logs/menu.log`.
- 📦 **Portável** — os scripts detectam a própria pasta; funciona em **qualquer PC / qualquer letra de disco**.

---

## 🧩 Como funciona

```
   PC do Jogador 1  <──────── Tailscale (VPN) ────────>  PC do Jogador 2
   ┌───────────────┐                                     ┌───────────────┐
   │  Docker        │      Syncthing sincroniza          │  Docker        │
   │  ├─ Minecraft  │  <=====  a pasta ./data  =====>     │  ├─ Minecraft  │
   │  └─ Syncthing  │                                     │  └─ Syncthing  │
   └───────────────┘                                     └───────────────┘
     (ATIVO jogando)                                       (STANDBY recebendo)
```

Regra de ouro (anti "split-brain"/corrupção): **apenas um host roda o Minecraft por vez.**

---

## ✅ Pré-requisitos

| Ferramenta | Para quê | Link |
|-----------|----------|------|
| **Docker Desktop** | Rodar os contêineres | https://www.docker.com/products/docker-desktop/ |
| **Tailscale** | Rede P2P entre os PCs | https://tailscale.com/ |
| **Git** | Clonar o repo e baixar atualizações (opção `U`) | https://git-scm.com/ |

> 💡 **Atalho:** já tem o projeto na mão? A opção **`X`** do menu baixa e instala **Docker,
> Git e Tailscale** automaticamente (via `winget`) e ainda configura o salvamento automático.

> Windows: o Docker Desktop usa o backend **WSL 2** (o instalador cuida disso).

---

## 🚀 Instalação (em qualquer PC)

1. **Instale** o Docker Desktop e o Tailscale, e faça login no Tailscale.
2. **Clone** este repositório na pasta que quiser (ex.: `D:\Server-Minecraft`):
   ```bash
   git clone https://github.com/yagoriccomi/docker-minecraft-server.git
   ```
   > Não usa Git? Baixe o ZIP pelo GitHub e extraia.
3. **Aceite o EULA da Minecraft:** já está definido em `compose.yaml` (`EULA: "TRUE"`).
   Ao usar, você concorda com o https://www.minecraft.net/eula.
4. **Inicie:** dê um duplo clique em **`menu.bat`** e escolha a opção **[1] Iniciar**.
   - Na 1ª vez o Docker baixa as imagens e o servidor (~alguns minutos).
   - A pasta `data/` (mapa/config) é criada automaticamente.

Pronto! O servidor sobe em `localhost:25565` e o painel do Syncthing em `http://localhost:8384`.

> 💡 **Portabilidade:** o `menu.bat` descobre sozinho a pasta onde está (`%~dp0`).
> Você **não** precisa editar caminhos ao mudar de PC ou de disco.

---

### 🥇 Fluxo A — Primeiro PC
Você tem o mundo e vai hospedar. **Todo o roteiro está no menu: opção `P` → `[1]`**, que confere
cada pré-requisito e mostra o que falta.

1. **Dependências** — duplo clique em `menu.bat` → opção **`X`**. Instala Docker, Git e Tailscale
   e configura o salvamento automático de 30 min.
2. **Entre no Tailscale** (app ou `tailscale up`). É a rede por onde os amigos vão conectar.
3. **Abra o assistente** — opção **`P`** → **`[1] Este é o PRIMEIRO PC`**. Ele valida tudo acima.
4. **Traga seu mundo** — opção **`!`** (Importar mundo). Aponte a pasta do save (a que contém
   `level.dat`). Ele faz backup do que existir, copia e migra os UUIDs para modo offline.
5. **Compartilhe sua identidade** — assistente **`P`** → **`[3]`** mostra seu **Device ID** do
   Syncthing e seu **IP Tailscale**. Envie os dois para os amigos.
6. **Pareie** — assistente **`P`** → **`[4]`** e cole o Device ID de cada amigo.
7. **Suba o servidor** — opção **`1`**. Os amigos entram em `SEU-IP-TAILSCALE:25565`.
8. **Ao terminar** — opção **`2`** e aguarde o sync ficar `Up to Date` antes de desligar o PC.

### 🤝 Fluxo B — PC adicional
Alguém já tem o mundo e você vai se conectar. **Roteiro no menu: opção `P` → `[2]`.**

1. **Instale o Tailscale** e entre na **mesma rede** do primeiro PC.
2. **Clone o projeto** e rode `menu.bat` → opção **`X`** (dependências).
3. **Abra o assistente** — opção **`P`** → **`[2] Este é um PC ADICIONAL`**.
4. **Troque os Device IDs** — assistente **`P`** → **`[4]`**, cole o ID do dono do mundo; ele faz o
   mesmo com o seu (que aparece em **`P`** → **`[3]`**).
5. **Aguarde o mapa chegar a 100%.** O assistente mostra o progresso e quanto falta. Pode demorar —
   o mundo tem vários GB.
6. ⛔ **Não use a opção `1` antes de 100%.** Subir o servidor com o mapa incompleto cria uma versão
   paralela do mundo e gera **conflito (split-brain)**. Enquanto sincroniza, **entre no servidor do
   outro jogador** pelo IP Tailscale dele.
7. **Quando for sua vez de hospedar:** o outro roda a opção **`2`** e espera o sync terminar; só
   então você roda a opção **`1`**. Nunca os dois ao mesmo tempo.

---

## 🕹️ Como usar — o painel `menu.bat`

| Opção | O que faz |
|-------|-----------|
| **1 · Jogar** | Garante o Syncthing no ar, limpa conflitos e sobe o servidor. |
| **2 · Parar / passar a vez** | Encerramento limpo do Minecraft (use **antes do handoff**). O Syncthing segue enviando o save. |
| **3 · Status** | Contêineres dos **dois stacks**, saúde do Minecraft e **% de sincronização** + dispositivos conectados. |
| **4 · Diagnóstico de erros** | Daemon, estado/saúde dos contêineres, erros nos logs e no Syncthing, **e detecta se o servidor já está ativo em outro host do Tailscale** (com IP). |
| **5 · Backup** | Compacta o mapa em `backups/world_backup_AAAAMMDD_HHmmss.zip`. |
| **6 · Logs** | Últimas 80 linhas do log do Minecraft. |
| **7 · Console (RCON)** | Console para digitar comandos no servidor (`list`, `seed`, `op`, etc). |
| **8 · Painel Syncthing** | Abre `http://localhost:8384` no navegador. |
| **9 · Reiniciar** | Reinicia só o Minecraft. |
| **X · Instalar dependências** | Baixa e instala **Docker, Git e Tailscale** (via `winget`) e configura o salvamento automático de 30 min. |
| **U · Atualizar projeto** | `git pull` — baixa a versão mais recente do projeto no GitHub. |
| **P · Primeiros passos** | **Assistente guiado**: instalar do zero (1º PC) ou conectar um PC adicional, ver seu Device ID e parear com um amigo. |
| **! · Importar mundo** | ⚠️ Importa um mundo externo (**substitui** o atual, com backup) e migra os UUIDs dos jogadores. |
| **K · Remover container** | ⚠️ `down` do stack do jogo. **O Syncthing não é afetado** — é um stack separado. |
| **0 · Sair** | Fecha o painel. |

> 🎨 O painel mostra um **cabeçalho ao vivo** (servidor · sync · amigo conectado) e separa as ações
> em *Dia a dia*, *Ferramentas*, *Manutenção* e **Zona de risco**. As duas ações destrutivas usam
> as teclas **`!`** e **`K`** de propósito — ficam longe dos números do dia a dia, para não
> serem acionadas sem querer.

### 📥 Importar um mundo existente
Traga um mundo de outra instalação (ex.: seu single-player do MultiMC/`.minecraft`) para o servidor:

1. No painel, escolha **`!`**. O Minecraft é parado automaticamente.
2. Cole o **caminho da pasta do mundo** (a que contém o `level.dat`), ex.:
   `C:\Users\voce\AppData\Roaming\.minecraft\saves\MeuMundo`.
3. Confirme. O script:
   - 💾 faz um **backup `.zip`** do mundo atual em `backups/` (`world_antes_import_*.zip`);
   - 📦 copia o mundo novo para `data/world` (com verificação de integridade);
   - 👤 pergunta se quer **migrar os jogadores de UUID online→offline** — necessário quando
     `ONLINE_MODE=FALSE`, senão os jogadores entram com **inventário vazio**.
4. Para a migração de jogadores, o script busca o `usercache.json` (fonte dos apelidos) na raiz
   da instalação de origem; se não achar, ele pede o caminho.

> **Por que a migração de UUID?** Com o servidor em modo offline, o UUID de cada jogador passa a ser
> derivado do apelido (`MD5("OfflinePlayer:"+nick)`). Os arquivos do mundo antigo estão nos UUIDs
> antigos (online), então precisam ser renomeados para os novos (offline) — é isso que a opção faz.

### 🔗 Sincronizar com um amigo (Syncthing)
1. Abra o painel do Syncthing (opção **8**) — ou use o assistente **`P`** → **`[4]`**, que faz o pareamento para você.
2. **Add Remote Device** → cole o **Device ID** do seu amigo (e ele adiciona o seu).
3. Compartilhe **apenas** a pasta `minecraft-data` (a pasta `./data`).
4. Garanta que **ambos estejam online no Tailscale**. Dica: em *Advanced → Addresses*,
   fixe o endereço do outro como `tcp://<IP-Tailscale-dele>:22000` para conexão direta.

### 🔄 Ciclo de revezamento (IMPORTANTE)
- **Host ativo termina de jogar:** opção **2 (Parar / passar a vez)** e aguarde o Syncthing
  ficar `Up to Date` (opção **3** mostra o %) **antes de desligar**.
- **O outro só então** dá **[1] Jogar** no PC dele. Nunca dois rodando o Minecraft ao mesmo tempo.

### 🛟 Salvamento automático e recuperação de energia
- **Autosave a cada 30 min** — a opção **`X`** cria uma tarefa agendada do Windows
  (`MinecraftP2P-AutoSave`) que, enquanto o servidor está no ar, executa `save-all flush` de 30 em
  30 minutos. Assim o Syncthing sempre tem uma cópia recente em disco e, num desligamento abrupto
  (queda de energia), você perde **no máximo ~30 min** de progresso.
- **Auto-restart após queda de energia** — o serviço `mc` usa `restart: unless-stopped`. Se o PC
  reiniciar (pico de energia) **com o servidor rodando**, o Docker sobe o Minecraft sozinho no boot.
  Se você parar de propósito pela opção **2** (handoff), ele **fica parado** — sem risco de split-brain.
  (Requer o Docker Desktop iniciando com o Windows, o que já é o padrão configurado.)

### 🧱 Resiliência: por que são dois stacks Docker
O projeto roda **dois projetos Docker independentes**:

| Stack | Arquivo (projeto) | Papel | Quando desligar |
|-------|-------------------|-------|-----------------|
| **Jogo** | `compose.yaml` (`minecraft-p2p`) | Servidor Minecraft | Sempre que não estiver jogando |
| **Replicação** | `compose.sync.yaml` (`minecraft-p2p-sync`) | Syncthing | **Nunca** |

**Por quê?** Antes os dois ficavam no mesmo compose, e um `docker compose down` derrubava
**os dois** — o PC parava de receber o mapa sem ninguém perceber. Se o outro jogador jogasse e
depois desligasse a máquina (queda de energia, por exemplo), o mapa ficava **ilhado** num único
PC, sem réplica. Com os projetos separados, qualquer `down` do jogo **não encosta** na replicação,
que usa `restart: always` e volta sozinha após reboot ou queda de energia.

> 🗂️ **Versionamento de arquivos:** a pasta usa *staggered file versioning* (retenção de **30
> dias**). Se um sync sobrescrever algo indevidamente, as versões antigas ficam em `.stversions/`
> dentro de `data/` — o Syncthing **não replica** essa pasta. É a rede de segurança contra
> conflito destrutivo.

> 💡 **A prova real de resiliência é ter uma 3ª cópia sempre online** (um Raspberry Pi, NAS ou
> VPS rodando só o Syncthing em *Receive Only*). Com 2 nós que se revezam, existe uma janela em
> que o mapa vive numa máquina só.

---

## 🔧 O que alterar — e para quê

Quase tudo é configurado em **`compose.yaml`**, na seção `environment` do serviço `mc`:

| Variável | Padrão | Para que serve / quando mudar |
|----------|--------|-------------------------------|
| `VERSION` | `"1.21.11"` | Versão do Minecraft. **Deve casar com a versão do seu cliente.** Evite `LATEST` num mundo compartilhado (atualiza o mapa e pode quebrar compatibilidade). |
| `MEMORY` | `"4G"` | RAM da JVM. Ajuste ao seu hardware (deixe folga para SO/Docker). |
| `ONLINE_MODE` | `"FALSE"` | `FALSE` = permite login offline (contas não-premium/MultiMC). `TRUE` = exige conta Mojang. |
| `TYPE` | `"VANILLA"` | Tipo do servidor. Troque para `FABRIC`/`PAPER` se for usar mods/plugins. |
| `USE_AIKAR_FLAGS` | `"TRUE"` | Flags de GC otimizadas — melhora a performance. Deixe ligado. |
| `TZ` | `"America/Sao_Paulo"` | Fuso horário dos logs. |
| `EULA` | `"TRUE"` | Obrigatório para o servidor iniciar. |
| Porta `25565` | — | Porta do Minecraft. Mude o lado esquerdo (`"NOVA:25565"`) para usar outra porta no host. |

> ⚠️ **Não sincronize a pasta `syncthing_config/`** — ela guarda as **chaves privadas** de cada
> máquina. Só a pasta `data/` deve ser compartilhada no Syncthing (já é o padrão).

---

## 🧾 Captura de erros / diagnóstico

- **Opção `4` (Detector de erros)** — diagnóstico completo que aponta problemas: daemon do Docker
  parado, contêiner `exited`/`unhealthy`/em *crash loop*, códigos de saída (ex.: `137` = falta de
  memória), erros recentes nos logs do Minecraft e do Syncthing, e histórico de erros do menu.
  Termina com um resumo de quantos pontos de atenção foram encontrados.
- **Guardião do revezamento (Tailscale)** — o detector varre os hosts da sua rede Tailscale e, se
  encontrar o Minecraft **já ativo em outro host** (porta 25565), avisa **em qual host e com qual IP**
  conectar, alertando que subir o seu próprio servidor causaria *split-brain* (perda do progresso de
  um dos mapas). É só um aviso — você decide. E quando outro host está ativo, o seu Minecraft parado
  passa a ser reconhecido como **"STANDBY"** (não como erro).
- **Healthcheck no Docker** — tanto o Minecraft (imagem `itzg`) quanto o Syncthing têm *healthcheck*;
  o Docker marca o contêiner como `unhealthy` automaticamente quando ele para de responder.
- Toda ação do menu registra **sucesso ou falha** com data/hora em **`logs/menu.log`**.
- Antes de iniciar, o menu **verifica se o Docker está rodando** e avisa se não estiver.
- A opção **3 (Status)** é o diagnóstico rápido: estado dos contêineres, saúde e % de sync.
- Log ao vivo do servidor: opção **6**, ou no terminal:
  ```bash
  docker compose logs -f mc
  ```

---

## 📂 Estrutura do projeto

```
Server-Minecraft/
├── compose.yaml         # Stack do JOGO (Minecraft) — projeto `minecraft-p2p`
├── compose.sync.yaml    # Stack de REPLICAÇÃO (Syncthing) — projeto separado, sempre no ar
├── menu.bat             # Painel de controle (portável, com log de erros)
├── README.md            # Este arquivo
├── LICENSE              # Licença GNU GPL v3.0
├── .gitignore           # Ignora dados, segredos, backups e logs
├── scripts/
│   ├── render-menu.ps1  # Desenha o painel (cabeçalho ao vivo + duas colunas)
│   ├── setup-wizard.ps1 # Assistente de primeiros passos e pareamento (opção P)
│   ├── status.ps1       # Relatório de status (opção 3)
│   ├── detect-errors.ps1# Detector de erros / diagnóstico (opção 4)
│   ├── install-deps.ps1 # Instala Docker/Git/Tailscale + autosave (opção X)
│   ├── autosave.ps1     # save-all flush periódico (tarefa agendada de 30 min)
│   ├── run-hidden.vbs   # lançador silencioso do autosave (sem janela de console)
│   ├── import-world.ps1 # Importa um mundo externo (opção !)
│   └── migrate-uuids.ps1# Migra jogadores de UUID online→offline (usado pelo import)
│
│  --- gerados localmente, NÃO versionados (.gitignore) ---
├── data/                # Mundo + config do servidor (o mapa NÃO vai pro GitHub)
├── syncthing_config/    # Chaves/config do Syncthing (privado, por máquina)
├── backups/             # Backups .zip do mapa
└── logs/                # Logs do menu.bat
```

---

## 📜 Licença

Distribuído sob a **GNU General Public License v3.0 (GPL-3.0)** — veja [LICENSE](LICENSE).
É uma licença *copyleft*: você pode usar, estudar, modificar e redistribuir, mas
trabalhos derivados devem permanecer abertos sob a mesma licença.

Minecraft® é marca da Mojang/Microsoft; este projeto é só infraestrutura e não
distribui o jogo. O servidor é baixado pela imagem `itzg/minecraft-server`,
sujeito ao [EULA da Minecraft](https://www.minecraft.net/eula).
