# 📌 Diretrizes do Projeto: Servidor de Minecraft Descentralizado (Docker + Syncthing)

## 🤖 Papel do Assistente (Claude)
Você atuará como o executor técnico deste projeto. O gerenciamento de alto nível e as revisões de arquitetura continuarão sob a responsabilidade do Gemini. Sua função principal é codificar, aplicar as configurações, debugar problemas no Docker/Syncthing e garantir a integridade dos dados, respeitando **rigorosamente** os limites de hardware e os caminhos locais definidos abaixo.

## 💻 Especificações do Ambiente Local (Host 1)
- **Diretório Raiz do Projeto:** `D:\\Server-Minecraft` (Mandatório o uso do disco D: devido à limitação crítica de espaço no disco C:).
- **Origem do Mapa:** O mapa atual (Tamanho: ~1,90 GB) deve ser migrado de `D:\\Games\\MultiMC\\instances\\1.211\\.minecraft\\saves\\world` para dentro de `D:\\Server-Minecraft\\data\\world`.
- **Rede P2P:** A conexão entre os nós para sincronização e jogatina ocorre através do **Tailscale** (Mesh VPN).
- **Limite de Memória:** O sistema local possui 16 GB de RAM no total. O contêiner do Minecraft **DEVE** ser restrito a no máximo **4 GB** (`MEMORY: "4G"`) para evitar esgotamento de memória no host.
- **Autenticação:** O servidor deve rodar com `ONLINE_MODE: "FALSE"` para permitir o acesso em modo offline das contas via MultiMC.

## 📂 Estrutura de Diretórios Esperada
- `compose.yaml`: Arquivo principal de orquestração na raiz (`D:\\Server-Minecraft`).
- `./data/`: Volume de dados do servidor de Minecraft (contém o `world`, `server.properties`, etc). **ATENÇÃO: Apenas esta pasta deve ser mapeada no Syncthing para sincronização.**
- `./syncthing_config/`: Volume de configurações e chaves locais do Syncthing. (Estritamente local, NÃO sincronizar).

## 🚀 Comandos Principais
- **Iniciar o ambiente:** `docker compose up -d`
- **Parar o ambiente:** `docker compose down` (Obrigatório após o fim da sessão de jogo).
- **Acompanhar logs:** `docker compose logs -f mc`
- **Painel do Syncthing:** Acessível localmente via `http://localhost:8384`

## 🔄 Protocolo de Sincronização e Prevenção de Split-Brain (Regras Estritas)
Para evitar a corrupção do mapa pesado durante o revezamento de hosts, as seguintes regras são absolutas:
1. **Regra de Exclusividade (Single Host):** Apenas UMA máquina deve executar o container do Minecraft ativamente de cada vez.
2. **Ciclo de Vida (Host Ativo):** 
   - Início: Rodar `docker compose up -d`.
   - Fim: Rodar obrigatoriamente `docker compose down`. O desligamento adequado do container libera os arquivos em uso e permite que o Syncthing finalize o envio da versão mais recente sem conflitos.
3. **Ciclo de Vida (Host Passivo / Standby):**
   - O Docker do outro jogador pode permanecer ligado apenas para o Syncthing receber os pacotes em segundo plano, mas ele **nunca** deve tentar subir o serviço `mc` (Minecraft) simultaneamente.
"""