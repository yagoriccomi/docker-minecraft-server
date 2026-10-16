# ENTREGA — syncthing-servico

| Campo | Valor |
|---|---|
| **Tarefa** | `syncthing-servico` |
| **Plano** | [`PLANO-syncthing-servico.md`](PLANO-syncthing-servico.md) |
| **Modo** | 🔁 Loop |
| **Data** | 2026-10-16 |
| **Branch / Commits** | `feat/syncthing-servico` — `2ffa279`, `97e612e`, `fc2030a`, `375761f`, `3f4ccbf`, `24def79` |
| **Status** | ⚠️ Entregue com pendências — código pronto e testado no modo docker; a migração real de cada PC espera confirmação |

---

## 1. O que foi feito

O Syncthing pode rodar como **serviço do Windows** (opção **[N]** do menu), sem Docker. Assim, quem não está hospedando pode fechar o Docker Desktop e devolver a RAM da VM do WSL. O Device ID e a configuração continuam os mesmos, e os PCs podem migrar um de cada vez. O menu passou a abrir o Docker na hora de jogar (**[1]**) e a oferecer fechá-lo ao parar (**[2]**).

## 2. Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `scripts/lib-sync.ps1` | criado: modo/estado/ligar/desligar do Syncthing (serviço ou container) |
| `scripts/install-sync-service.ps1` | criado: instalar/migrar, reinstalar, `-Desinstalar`, `-Verificar`, `-Menu` |
| `scripts/ensure-docker.ps1` | criado: abre o Docker Desktop e espera o engine |
| `scripts/free-docker.ps1` | criado: pergunta se fecha o Docker após a opção 2 (só no modo serviço) |
| `scripts/ensure-sync.ps1` | guardião nos dois modos; remove container intruso no modo serviço |
| `scripts/common.ps1` | carrega a `lib-sync.ps1` |
| `scripts/sync-world.ps1`, `render-menu.ps1`, `status.ps1`, `detect-errors.ps1`, `setup-wizard.ps1`, `migrate-legacy.ps1` | estado do Syncthing pela lib; Docker fechado deixa de ser erro no modo serviço |
| `menu.bat` | [1] usa `ensure-docker`, [2] chama `free-docker`, nova opção [N], texto da [K]; removida a sub-rotina `check_docker` (sem uso) |
| `.gitignore` | `/bin/`, `/syncthing_config.bak-*/` |
| `README.md` | seção "Syncthing sem Docker", opções 1/2/N/K, guardião, estrutura |
| `CLAUDE.md` (local) | dois modos do Syncthing e regra do host passivo |

## 3. Como validar (num PC, após migrar)

1. Menu → **[N]** → digitar `INSTALAR` → aceitar o pedido de admin. A janela mostra cada etapa e termina com `OK: Syncthing rodando como servico`.
2. Feche o Docker Desktop. O cabeçalho do menu deve mostrar `Sync: no ar` e os amigos conectados.
3. **[3] Status** → `MinecraftP2P-Syncthing: Running` e pasta `idle`/100%.
4. **[1] Jogar** → o Docker abre sozinho e o servidor sobe. **[2] Parar** → pergunta se fecha o Docker.
5. Rollback: **[N]** → **[D]** volta ao container.

## 4. Verificações executadas

- [x] Parser do PowerShell 5.1: os 28 `.ps1` sem erro.
- [x] Modo docker (este PC, sem migrar): cabeçalho do menu, status, guardião (não alterou nada nem registrou log), `ensure-docker`/`free-docker` (exit 0) e um **sync real** com o mundo congelado por 17 s (`sync OK | em dia: MONSTRO`).
- [x] `install-sync-service.ps1 -Verificar`: baixou Syncthing v2.1.1 + shawl 1.9.0 com SHA256 conferido para `bin\`.
- [x] Edição do `config.xml` testada numa cópia: muda só as 2 linhas (pasta e painel), e a volta reproduz o arquivo original byte a byte.
- [ ] **Migração real (serviço instalado, Docker fechado): NÃO executada.** Ela altera o ambiente (para o container, cria serviço, mexe no firewall) e por isso espera a sua confirmação.

## 5. ⚠️ Premissas assumidas (revisar)

| # | Premissa | Por quê | Como mudar se estiver errada |
|---|---|---|---|
| P1 | Wrapper shawl v1.9.0 com hash fixado por mim (o projeto não publica checksum) | [#7] simples e mantido | constantes no topo do instalador |
| P2 | Syncthing v2.1.1, sem auto-update | [#81] mesma versão em todos os PCs | constantes no topo do instalador |
| P3 | Conta virtual + ACL mínima | [#55] | `sc config obj=` |
| P4 | Grupo Usuários pode ligar/desligar o serviço | menu, guardião e SSH sem admin | `$ACE_USUARIOS` |
| P5 | Painel só em `127.0.0.1:8384` | [#55]; o remoto usa SSH | `$GUI_SERVICO` |
| P6 | Firewall só para Tailscale + rede local | [#55] | `$FW_ORIGEM` |
| P7 | Fechar o Docker é perguntado e nem é oferecido com outros containers rodando | este PC roda outros projetos | `free-docker.ps1` |
| P8 | Autostart do Docker: só orientação | editar o JSON do Docker é frágil [#7] | — |
| P9 | Sem `profiles` no `compose.sync.yaml` | PCs não migrados usam o `up -d` simples [#7] | — |
| P10 | Mundo congelado durante a migração se o Minecraft roda no PC | primeiro scan consistente [#6] | — |

## 6. Decisão visual

- **Mockup:** não, porque é só uma linha nova no menu de console, no padrão existente.
- **`design-de-interface-projeto`:** não aplicável (ajuste pontual).

## 7. Pendências e fora de escopo

- **Migrar cada PC** (beatriz, MONSTRO, amigo) pela opção [N], com confirmação.
- **Neste PC (beatriz) o ganho de RAM é pequeno:** o Docker continua aberto por causa de outros projetos (supabase, ponto, radar…). O ganho real está nos PCs que ficam em standby.
- O detector de erros marca avisos (`WRN`) do Syncthing que contêm `error=` (comportamento anterior, fora do escopo).
- O instalador não foi testado com caminho contendo espaços (`D:\Server-Minecraft` e `C:\Users\USER\Server` não têm).

## 8. Próximo passo natural

Migrar um PC pela opção [N], observar 1–2 ciclos do sync de 30 min e um revezamento, e depois os demais. Em seguida, abrir o PR de `feat/syncthing-servico` (a revisão de arquitetura do Gemini, conforme o CLAUDE.md).

## 9. Rastreabilidade

- **Jira:** sem integração neste projeto.
- **`CLAUDE.md`:** atualizado (dois modos do Syncthing, regra do host passivo).
