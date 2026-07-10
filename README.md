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
| **Git** (opcional) | Clonar este repositório | https://git-scm.com/ |

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
| **5 · Reiniciar** | Reinicia só o Minecraft. |
| **6 · Parar Minecraft** | Para **só** o Minecraft e **mantém o Syncthing** enviando o save. |
| **7 · Parar Tudo** | Encerra Minecraft + Syncthing. |
| **8 · Backup** | Compacta o mapa em `backups/world_backup_AAAAMMDD_HHmmss.zip`. |
| **9 · Painel Syncthing** | Abre `http://localhost:8384` no navegador. |
| **0 · Sair** | Fecha o painel. |

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
│   └── uuid_*.py        # Utilitários de migração de UUID (uso pontual)
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
