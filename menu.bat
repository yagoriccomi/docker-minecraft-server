@echo off
setlocal
chcp 65001 >nul 2>&1
title Painel de Controle - Minecraft P2P

:: ================== PORTABILIDADE ==================
:: ROOT = pasta onde este .bat esta (funciona em QUALQUER PC/pasta)
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "COMPOSE=%ROOT%\compose.yaml"
set "COMPOSE_SYNC=%ROOT%\compose.sync.yaml"
set "LOGDIR=%ROOT%\logs"
set "LOGFILE=%LOGDIR%\menu.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
cd /d "%ROOT%"

:: Migra containers da estrutura antiga (v1.0.0), se existirem. Nada acontece se ja
:: estiver tudo na estrutura nova. Codigo 3 = mostrou algo: pausa para o usuario ler.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\migrate-legacy.ps1" <nul
if errorlevel 3 ( echo. & pause )

:menu
cls
:: O painel (cabecalho com status ao vivo + duas colunas) e desenhado pelo
:: PowerShell, que cuida de cores e alinhamento.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\render-menu.ps1" <nul
:: Zera antes de ler: sem isso, um ENTER vazio repetiria a ULTIMA opcao escolhida.
set "opcao="
set /p "opcao=  Opcao: "

if "%opcao%"=="1" goto iniciar
if "%opcao%"=="2" goto parar_mc
if "%opcao%"=="3" goto status
if "%opcao%"=="4" goto diagnostico
if "%opcao%"=="5" goto backup
if "%opcao%"=="6" goto logs
if "%opcao%"=="7" goto console
if "%opcao%"=="8" goto syncthing
if "%opcao%"=="9" goto reiniciar
if /i "%opcao%"=="X" goto instalar
if /i "%opcao%"=="A" goto agendar
if /i "%opcao%"=="U" goto atualizar
if /i "%opcao%"=="P" goto primeiros
if /i "%opcao%"=="K" goto parar_tudo
if "%opcao%"=="!" goto importar
if "%opcao%"=="0" goto sair
echo.
echo   Opcao invalida! Tente novamente.
timeout /t 2 >nul 2>&1
goto menu

:iniciar
cls
echo === INICIANDO SERVIDOR ===
echo.
call :check_docker
if errorlevel 1 ( pause & goto menu )
docker inspect -f "{{.State.Status}}" minecraft 2>nul | findstr /x "running" >nul
if not errorlevel 1 (
    echo O servidor ja esta rodando NESTE PC.
    echo.
    pause
    goto menu
)
:: Regra de host unico: se outro PC ja esta com o servidor no ar, avisa e pede confirmacao.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\check-host.ps1" <nul
if errorlevel 2 goto iniciar_confirma
goto iniciar_go
:iniciar_confirma
set "conf="
set /p "conf=  Digite SIM para subir mesmo assim (ENTER cancela): "
if /i not "%conf%"=="SIM" (
    echo   Cancelado. Entre no servidor do outro host pelo IP acima.
    call :log "Jogar cancelado: servidor ja ativo em outro host"
    echo.
    pause
    goto menu
)
call :log "AVISO: servidor iniciado mesmo com outro host ativo (usuario confirmou)"
:iniciar_go
:: Remove container antigo PARADO da v1.0.0 (senao o 'up' falha com nome em uso)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\migrate-legacy.ps1" <nul
echo.
echo Limpando arquivos de conflito do Syncthing (.sync-conflict-*)...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%ROOT%\data' -Recurse -Filter '*.sync-conflict-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue"
echo.
echo Garantindo que a replicacao (Syncthing) esteja no ar...
docker compose -f "%COMPOSE_SYNC%" up -d
echo.
echo Subindo o servidor de Minecraft...
docker compose -f "%COMPOSE%" up -d
if errorlevel 1 (
    echo [ERRO] Falha ao iniciar. Detalhes no log: "%LOGFILE%"
    call :log "ERRO: 'up -d' falhou"
) else (
    echo Servidor iniciado!  Minecraft: porta 25565  ^|  Syncthing: porta 8384
    call :log "OK: 'up -d' concluido"
)
echo.
pause
goto menu

:parar_mc
cls
echo === PARANDO O MINECRAFT (encerramento limpo) ===
echo.
call :has_local_mc
if errorlevel 1 ( echo Nenhum servidor de Minecraft neste PC para parar. & echo. & pause & goto menu )
:: Ate 60 s para o servidor salvar o mundo e fechar limpo.
docker stop -t 60 minecraft
if errorlevel 1 (
    echo [ERRO] Falha ao parar o Minecraft. Log: "%LOGFILE%"
    call :log "ERRO: 'stop mc' falhou"
    echo.
    pause
    goto menu
)
call :log "OK: 'stop mc'"
echo.
echo Enviando o save final para os outros PCs pelo Syncthing...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\sync-world.ps1"
if errorlevel 1 (
    call :log "ERRO: sync do save final falhou"
) else (
    call :log "OK: sync do save final"
)
echo.
echo ATENCAO: o Syncthing continua ATIVO. Se algum PC apareceu acima como
echo offline ou com tempo esgotado, ele so recebe o save quando conectar:
echo deixe este computador ligado ate la (a opcao 3 mostra quanto cada PC ja tem).
echo.
pause
goto menu

:status
cls
echo === STATUS DO AMBIENTE ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\status.ps1"
echo.
pause
goto menu

:diagnostico
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\detect-errors.ps1"
call :log "Diagnostico (detector de erros) executado"
echo.
pause
goto menu

:backup
cls
echo === BACKUP DO MAPA ===
echo.
echo Pode rodar com o servidor ligado: o mundo fica congelado so durante a copia.
echo Backups manuais NAO entram no rodizio dos 3 diarios (nunca sao apagados).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\backup-world.ps1"
if errorlevel 1 (
    echo [ERRO] Falha no backup. Detalhes: "%LOGDIR%\backup.log"
    call :log "ERRO: backup falhou"
) else (
    call :log "OK: backup do mapa criado"
)
echo.
pause
goto menu

:logs
cls
:: Mostra os logs de onde o servidor estiver: deste PC ou, se estiver em outro,
:: a copia do latest.log que chega pelo Syncthing. Tem loop proprio (ENTER atualiza).
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\show-logs.ps1"
goto menu

:console
cls
echo === CONSOLE DO SERVIDOR (RCON) ===
echo.
echo Digite comandos do Minecraft (ex: list, seed, time set day).
echo Para sair do console e voltar ao menu, digite: exit
echo.
call :has_local_mc
if errorlevel 1 ( echo O servidor nao esta rodando NESTE PC. & echo. & pause & goto menu )
docker exec -it minecraft rcon-cli
if errorlevel 1 (
    echo [ERRO] Nao foi possivel abrir o console. O Minecraft esta rodando?
    call :log "ERRO: 'exec rcon-cli' falhou"
)
echo.
pause
goto menu

:syncthing
cls
echo === ABRINDO PAINEL DO SYNCTHING ===
echo.
start "" "http://localhost:8384"
echo Painel aberto no navegador padrao (http://localhost:8384).
echo.
pause
goto menu

:reiniciar
cls
echo === REINICIANDO O MINECRAFT ===
echo.
call :has_local_mc
if errorlevel 1 ( echo O servidor nao esta rodando NESTE PC. & echo. & pause & goto menu )
docker restart -t 60 minecraft
if errorlevel 1 (
    echo [ERRO] Falha ao reiniciar. Log: "%LOGFILE%"
    call :log "ERRO: 'restart mc' falhou"
) else (
    echo Minecraft reiniciado.
    call :log "OK: 'restart mc'"
)
echo.
pause
goto menu

:primeiros
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\setup-wizard.ps1"
call :log "Assistente de primeiros passos aberto"
goto menu

:instalar
cls
echo === INSTALAR / VERIFICAR DEPENDENCIAS ===
echo.
echo Isto vai baixar/instalar Docker Desktop, Git e Tailscale (via winget)
echo e agendar o sync do mapa (a cada 30 min) e o backup diario (22:00).
echo O Windows pode pedir permissao de administrador durante a instalacao.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\install-deps.ps1"
call :log "Instalacao/verificacao de dependencias executada"
echo.
pause
goto menu

:agendar
cls
echo === AGENDAR SYNC DO MAPA + BACKUP DIARIO ===
echo.
echo Cria/atualiza duas tarefas no Agendador de Tarefas do Windows:
echo   MinecraftP2P-Sync   - a cada 30 min congela o mundo e sincroniza o mapa
echo   MinecraftP2P-Backup - todo dia as 22:00 faz backup .zip (mantem os 3 mais recentes)
echo Para desfazer: powershell -ExecutionPolicy Bypass -File scripts\install-tasks.ps1 -Remove
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\install-tasks.ps1"
if errorlevel 1 (
    echo [ERRO] Falha ao agendar as tarefas. Log: "%LOGFILE%"
    call :log "ERRO: agendamento de sync/backup falhou"
) else (
    call :log "OK: sync 30 min + backup diario agendados"
)
echo.
pause
goto menu

:atualizar
cls
echo === SINCRONIZAR PROJETO COM O GITHUB (git pull) ===
echo.
where git >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Git nao encontrado. Use a opcao [X] para instalar as dependencias.
    call :log "ERRO: git ausente na atualizacao"
    echo.
    pause
    goto menu
)
git -C "%ROOT%" pull --ff-only
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao atualizar. Veja a mensagem acima. Log: "%LOGFILE%"
    call :log "ERRO: git pull falhou"
) else (
    echo.
    echo Projeto atualizado com a versao mais recente do GitHub!
    call :log "OK: git pull"
)
echo.
pause
goto menu

:importar
cls
echo === IMPORTAR MUNDO + DADOS DE JOGADORES ===
echo.
echo Esta opcao SUBSTITUI o mundo atual pelo mundo de uma pasta externa.
echo Um backup .zip do mundo atual e criado ANTES de qualquer alteracao.
echo O Minecraft sera parado para liberar os arquivos.
echo.
docker stop -t 60 minecraft >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\import-world.ps1"
if errorlevel 1 (
    echo.
    echo [AVISO] Importacao nao concluida ^(cancelada ou com erro^). Log: "%LOGFILE%"
    call :log "AVISO: import-world nao concluido"
) else (
    call :log "OK: importacao de mundo/dados concluida"
)
echo.
pause
goto menu

:parar_tudo
cls
echo === REMOVENDO O CONTAINER DO MINECRAFT ===
echo.
echo O Syncthing NAO sera afetado: ele roda num stack separado
echo (compose.sync.yaml) e continua replicando o mapa.
echo.
call :has_local_mc
if errorlevel 1 ( echo Nenhum container do Minecraft neste PC. & echo. & pause & goto menu )
docker stop -t 60 minecraft >nul 2>&1
docker rm minecraft
if errorlevel 1 (
    echo [ERRO] Falha ao encerrar. Log: "%LOGFILE%"
    call :log "ERRO: 'down' do stack do jogo falhou"
) else (
    echo Stack do Minecraft encerrado. Syncthing segue no ar.
    call :log "OK: 'down' do stack do jogo"
)
echo.
pause
goto menu

:: ================== SUB-ROTINAS ==================
:has_local_mc
:: 0 = existe um container 'minecraft' neste PC (estrutura nova OU antiga)
docker inspect minecraft >nul 2>&1
exit /b %errorlevel%

:check_docker
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Docker nao encontrado ou nao esta em execucao.
    echo Abra o Docker Desktop e aguarde ficar "running", depois tente de novo.
    call :log "ERRO: Docker daemon indisponivel"
    exit /b 1
)
exit /b 0

:log
echo [%DATE% %TIME%] %~1>> "%LOGFILE%"
exit /b 0

:sair
endlocal
exit /b 0
