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

## 🕹️ Como usar — o painel `menu.bat`

| Opção | O que faz |
|-------|-----------|
| **1 · Iniciar** | Limpa conflitos do Syncthing e sobe os contêineres (`docker compose up -d`). |
| **2 · Status** | Mostra contêineres, saúde do Minecraft e **% de sincronização** + dispositivos conectados. |
| **3 · Logs** | Últimas 80 linhas do log do Minecraft. |
| **4 · Console (RCON)** | Abre um console para digitar comandos no servidor (`list`, `seed`, `op`, etc). |
| **D · Detector de erros** | Diagnóstico completo: daemon, estado/saúde dos contêineres, erros nos logs e no Syncthing, **e detecta se o servidor já está ativo em outro host do Tailscale** (com IP). |
| **5 · Reiniciar** | Reinicia só o Minecraft. |
| **6 · Parar Minecraft** | Para **só** o Minecraft e **mantém o Syncthing** enviando o save. |
| **7 · Parar Tudo** | Encerra Minecraft + Syncthing. |
| **8 · Backup** | Compacta o mapa em `backups/world_backup_AAAAMMDD_HHmmss.zip`. |
| **9 · Painel Syncthing** | Abre `http://localhost:8384` no navegador. |
| **X · Instalar dependências** | Baixa e instala **Docker, Git e Tailscale** (via `winget`) e configura o salvamento automático de 30 min. |
| **U · Atualizar projeto** | `git pull` — baixa a versão mais recente do projeto no GitHub. |
| **I · Importar mundo** | Importa um mundo externo (**substitui** o atual, com backup automático) e migra os dados dos jogadores de UUID online→offline. |
| **0 · Sair** | Fecha o painel. |

### 📥 Importar um mundo existente (opção `I`)
Traga um mundo de outra instalação (ex.: seu single-player do MultiMC/`.minecraft`) para o servidor:

1. No painel, escolha **`I`**. O Minecraft é parado automaticamente.
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
1. Abra o painel do Syncthing (opção **9**).
2. **Add Remote Device** → cole o **Device ID** do seu amigo (e ele adiciona o seu).
3. Compartilhe **apenas** a pasta `minecraft-data` (a pasta `./data`).
4. Garanta que **ambos estejam online no Tailscale**. Dica: em *Advanced → Addresses*,
   fixe o endereço do outro como `tcp://<IP-Tailscale-dele>:22000` para conexão direta.

### 🔄 Ciclo de revezamento (IMPORTANTE)
- **Host ativo termina de jogar:** opção **6 (Parar Minecraft)** e aguarde o Syncthing
  ficar `Up to Date` (opção **2** mostra o %) **antes de desligar**.
- **O outro só então** dá **[1] Iniciar** no PC dele. Nunca dois rodando o Minecraft ao mesmo tempo.

### 🛟 Salvamento automático e recuperação de energia
- **Autosave a cada 30 min** — a opção **`X`** cria uma tarefa agendada do Windows
  (`MinecraftP2P-AutoSave`) que, enquanto o servidor está no ar, executa `save-all flush` de 30 em
  30 minutos. Assim o Syncthing sempre tem uma cópia recente em disco e, num desligamento abrupto
  (queda de energia), você perde **no máximo ~30 min** de progresso.
- **Auto-restart após queda de energia** — o serviço `mc` usa `restart: unless-stopped`. Se o PC
  reiniciar (pico de energia) **com o servidor rodando**, o Docker sobe o Minecraft sozinho no boot.
  Se você parar de propósito pela opção **6** (handoff), ele **fica parado** — sem risco de split-brain.
  (Requer o Docker Desktop iniciando com o Windows, o que já é o padrão configurado.)

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

- **Opção `D` (Detector de erros)** — diagnóstico completo que aponta problemas: daemon do Docker
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
- A opção **2 (Status)** é o diagnóstico rápido: estado dos contêineres, saúde e % de sync.
- Log ao vivo do servidor: opção **3**, ou no terminal:
  ```bash
  docker compose logs -f mc
  ```

---

## 📂 Estrutura do projeto

```
Server-Minecraft/
├── compose.yaml         # Orquestração Docker (Minecraft + Syncthing)
├── menu.bat             # Painel de controle (portável, com log de erros)
├── README.md            # Este arquivo
├── LICENSE              # Licença GNU GPL v3.0
├── .gitignore           # Ignora dados, segredos, backups e logs
├── scripts/
│   ├── status.ps1       # Relatório de status (usado pela opção 2)
│   ├── detect-errors.ps1# Detector de erros / diagnóstico (opção D)
│   ├── install-deps.ps1 # Instala Docker/Git/Tailscale + autosave (opção X)
│   ├── autosave.ps1     # save-all flush periódico (tarefa agendada de 30 min)
│   ├── import-world.ps1 # Importa um mundo externo (opção I)
│   ├── migrate-uuids.ps1# Migra jogadores de UUID online→offline (usado pelo import)
│   └── uuid_*.py        # Utilitários de migração de UUID (uso pontual, referência)
├── docs/
│   └── RELATORIO-HARDWARE.md
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
