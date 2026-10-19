# PLANO DE EXECUÇÃO — syncthing-servico

| Campo | Valor |
|---|---|
| **Tarefa** | `syncthing-servico` |
| **Origem** | descrição livre (conversa de 2026-10-16) |
| **Tipo** | Melhoria (arquitetura de infraestrutura local) |
| **Modo de execução** | 🔁 Loop (sem confirmação do plano) |
| **Data** | 2026-10-16 |
| **Branch** | `feat/syncthing-servico` (a partir de `feat/distancias`) |

---

## 1. Enunciado Canônico

- **Problema:** nos PCs que não estão hospedando, o Docker Desktop (e a VM do WSL) fica ligado só para o container do Syncthing receber o mapa, ocupando GBs de RAM à toa.
- **Resultado esperado:** o Syncthing roda como **serviço do Windows** (`MinecraftP2P-Syncthing`), sem Docker; o Docker só precisa estar aberto no PC que hospeda o Minecraft. Mesmo Device ID, mesma config, mesmos scripts.
- **Como validar:** num PC migrado, com o Docker Desktop fechado, o painel `http://localhost:8384` abre, a pasta *Minecraft Data* fica "Em dia", os outros PCs aparecem conectados e a opção 3 do menu mostra o sync funcionando. A opção 1 (Jogar) abre o Docker sozinha e sobe o servidor.

## 2. Escopo

**Vou fazer:**
- Instalador `scripts/install-sync-service.ps1` (migra do container, ou instala do zero; `-Desinstalar` volta ao container).
- Biblioteca `scripts/lib-sync.ps1`: estado/ligar/desligar do Syncthing, valendo para **os dois modos** (serviço ou container), porque os PCs vão migrar um de cada vez.
- Trocar todas as checagens `docker inspect syncthing` pela biblioteca.
- Guardião (`ensure-sync.ps1`) ciente do serviço; no modo serviço remove qualquer container `syncthing` que reapareça.
- Menu: Jogar abre o Docker Desktop se estiver fechado (`ensure-docker.ps1`); Parar oferece fechar o Docker; nova opção **[N]** para instalar o serviço.
- README e CLAUDE.md atualizados.

**NÃO vou fazer (escopo negativo)** [#8]:
- Rodar a migração no ambiente real sem confirmação (é ação que altera o ambiente — exceção da Regra de Ouro nº 5).
- Mexer no Minecraft, bot, ViaProxy ou no `compose.yaml` do jogo.
- Editar automaticamente as configurações do Docker Desktop (autostart): o instalador só orienta.
- Atualização automática do Syncthing.
- Apagar o `compose.sync.yaml` (continua sendo o modo dos PCs não migrados e o caminho de rollback).

## 3. Premissas Assumidas

| # | Premissa | Por quê | Se estiver errada… |
|---|---|---|---|
| P1 | Wrapper **shawl v1.9.0**, hash fixado (`f883c5d0…351c`, calculado no download de 2026-10-16; o projeto não publica checksums) | Mantido, 1 exe, para o Syncthing com Ctrl-C (encerramento limpo) [#7] | Trocar URL/hash no topo do instalador |
| P2 | Syncthing **v2.1.1** (mesma versão do container), hash oficial do `sha256sum.txt.asc` | Mesma versão do banco `index-v2` e dos outros PCs [#81] | Atualizar as 2 constantes |
| P3 | Conta **virtual** `NT SERVICE\MinecraftP2P-Syncthing` + ACLs só nas pastas necessárias | Menor privilégio; sem senha guardada [#55] | Trocar `obj=` no `sc config` |
| P4 | Ligar/desligar o serviço liberado ao grupo **Usuários** (BU) via SDDL | Menu, guardião e SSH remoto rodam sem admin | Restringir ao SID de um usuário |
| P5 | GUI passa a `127.0.0.1:8384` | Menu remoto usa SSH + localhost; menos superfície [#55] | Voltar o `<address>` no config.xml |
| P6 | Firewall: entrada 22000 TCP/UDP e 21027 UDP só de `100.64.0.0/10` (Tailscale) e `LocalSubnet`, presa ao `syncthing.exe` | Os PCs conversam via Tailscale; relays são saída | Ampliar `RemoteAddress` |
| P7 | Fechar o Docker no fim da opção 2 é **perguntado**, e nem é oferecido se houver outros containers rodando | Este PC roda outros projetos em Docker | — |
| P8 | Autostart do Docker Desktop: só orientação na tela | Editar o JSON interno do Docker é frágil [#7] | Implementar depois |
| P9 | Sem `profiles` no `compose.sync.yaml`; a proteção contra "duas instâncias" fica no instalador (`down`) + guardião (remove container que reapareça) | Os PCs não migrados continuam precisando do `up -d` simples [#7] | Adicionar profile |
| P10 | Com o Minecraft rodando, a migração **congela o mundo** (save-off) durante o primeiro scan e devolve no fim | Primeiro scan não pode pegar arquivo pela metade; reaproveita `Suspend-WorldSaves` [#6] | — |

## 4. Decisão Visual

- **Tem superfície visual?** Sim, mínima: texto do menu de console (nova linha `[N]`, mensagens).
- **Precisa de mockup?** Não — **porquê:** segue o padrão existente de linhas/cores do `render-menu.ps1`; nenhum layout novo.
- **`design-de-interface-projeto` acionada?** Não — ajuste pontual dentro do padrão já existente (critério de dispensa da etapa 5).

## 5. Terreno (o que já existe)

| Arquivo | Papel hoje | O que muda |
|---|---|---|
| `scripts/lib-sync.ps1` | — | **criar**: `Get-SyncMode`, `Get-SyncState`, `Start-Sync`, `Stop-Sync` |
| `scripts/install-sync-service.ps1` | — | **criar**: instalador/desinstalador |
| `scripts/ensure-docker.ps1` | — | **criar**: abre o Docker Desktop e espera o engine |
| `scripts/free-docker.ps1` | — | **criar**: oferece fechar o Docker após a opção 2 |
| `scripts/common.ps1` | helpers do sync/backup | dot-source do `lib-sync.ps1` |
| `scripts/ensure-sync.ps1` | guardião (só Docker) | dois modos |
| `scripts/sync-world.ps1` | sync agendado | estado via `Get-SyncState` |
| `scripts/render-menu.ps1` | cabeçalho + opções | estado via lib; linha `[N]` |
| `scripts/status.ps1`, `detect-errors.ps1`, `setup-wizard.ps1`, `migrate-legacy.ps1` | checam o container | cientes do serviço |
| `menu.bat` | menu | Jogar/Parar/[N]/[K] |
| `.gitignore` | — | `/bin/`, `/syncthing_config.bak-*/` |
| `README.md`, `CLAUDE.md` | docs | nova arquitetura |

**Reaproveitamento** [#6]: `Suspend/Resume-WorldSaves`, `Enter/Exit-WorldLock`, `Connect-Syncthing`/`Invoke-Syncthing`, `run-hidden.vbs`, padrão `Log` e marca `syncthing-desligado.flag`.
**Convenções locais** [#5][#13]: PowerShell 5.1, comentários em português sem acento nos .ps1, `$root` a partir de `$PSScriptRoot`, docker sempre com tempo-limite, logs só quando faz algo.

## 6. Passos Atômicos

| # | Arquivo alvo | O que muda (1 frase) | Prática | Como verificar |
|---|---|---|---|---|
| 1 | `lib-sync.ps1`, `common.ps1` | Biblioteca única de estado do Syncthing (serviço ou container) | [#6][#13] | Dot-source e `Get-SyncState` devolve `running` aqui (modo docker) |
| 2 | `sync-world.ps1`, `render-menu.ps1`, `status.ps1`, `detect-errors.ps1`, `setup-wizard.ps1`, `migrate-legacy.ps1` | Trocam `docker inspect syncthing` pela lib | [#6] | Parser OK + menu/status rodam iguais no modo docker |
| 3 | `ensure-sync.ps1` | Guardião nos dois modos; modo serviço remove container intruso e nunca abre o Docker | [#2][#9] | Parser OK; rodar a checagem no modo docker não altera nada |
| 4 | `ensure-docker.ps1`, `free-docker.ps1`, `menu.bat` | Docker sob demanda: Jogar abre, Parar oferece fechar | [#98] | Parser OK; `ensure-docker` retorna 0 com Docker já aberto |
| 5 | `install-sync-service.ps1`, `.gitignore`, `menu.bat`, `render-menu.ps1` | Instalador com verificação de hash, ACL, SDDL, firewall, validação e rollback automático; opção [N] | [#55][#84][#37] | Parser OK; `-Verificar` (sem admin) baixa e confere os hashes |
| 6 | `README.md`, `CLAUDE.md` | Documenta a nova arquitetura e o rollback | [#96] | Leitura |

## 7. Impacto em Dados e Contratos

- **Banco de dados:** o `index-v2` do Syncthing é reaproveitado; a troca de caminho `/data` → `<root>\data` faz um rescan completo (~1,9 GB) na primeira subida.
- **Contrato de API:** nenhum — mesma API REST em `localhost:8384`, mesma API key.
- **Configuração:** `config.xml` (path da pasta e endereço da GUI) editado pelo instalador, com backup antes. Nenhum segredo novo; nada vai para o git [#37].
- **Dados pessoais (LGPD):** nenhum.

## 8. Plano de Testes

O projeto não tem suíte automatizada para os scripts PowerShell; a verificação é por parser + execução real.

| Nível | O que cobre | Caminho de falha coberto |
|---|---|---|
| Sintaxe | Todos os .ps1 tocados passam no parser do PowerShell 5.1 | — |
| Integração (modo docker, sem migrar) | `lib-sync`, `render-menu`, `status`, `ensure-sync`, `sync-world` continuam funcionando com o container | Serviço ausente → cai no container |
| Download | `install-sync-service.ps1 -Verificar` baixa e confere SHA256 | Hash divergente aborta antes de instalar |
| Migração real (com confirmação do usuário) | Device ID igual, pasta idle, peers conectados, Docker fechado | Falha de saúde/ID → rollback automático para o container |

## 9. Riscos e Rollback

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Container e serviço rodando juntos (mesmo Device ID) | Média | Conflitos/loops de sync | Instalador faz `down`; guardião remove container que reapareça; Docker mode recusa subir se o serviço existir |
| Serviço sem permissão em algum arquivo do `data` | Baixa | Pasta em erro | ACL com herança + checagem de `folder/errors` na validação → rollback |
| Primeiro scan com o mundo rodando | Média | Arquivo pela metade nos outros PCs | Mundo congelado durante a validação (P10) |
| Usuário comum sem direito de ligar/desligar | Baixa | Guardião/menu falham | SDDL para BU + teste no fim do instalador |

**Rollback** [#84]: `install-sync-service.ps1 -Desinstalar` (ou opção [N] → desinstalar): remove o serviço e as regras de firewall, devolve o `config.xml` para `/data`/`0.0.0.0:8384` e sobe o container de novo. Backup integral da config em `syncthing_config.bak-<data>`.

## 10. Definição de Pronto

- [ ] Passos 1–6 executados
- [ ] Todos os .ps1 tocados passam no parser
- [ ] Menu/status/guardião/sync funcionam no modo docker (este PC, antes da migração)
- [ ] `-Verificar` confere os hashes
- [ ] Migração real feita e conferida (**depende da confirmação do usuário**)
- [ ] Sem segredo em código [#37]
- [ ] Commits atômicos com Conventional Commits [#31][#32]
- [ ] `docs/planos/ENTREGA-syncthing-servico.md` escrito
- [ ] `CLAUDE.md` atualizado
