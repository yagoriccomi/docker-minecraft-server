@echo off
setlocal
title Painel de Controle - Servidor Minecraft P2P

:: ================== PORTABILIDADE ==================
:: ROOT = pasta onde este .bat esta (funciona em QUALQUER PC/pasta)
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "COMPOSE=%ROOT%\compose.yaml"
set "LOGDIR=%ROOT%\logs"
set "LOGFILE=%LOGDIR%\menu.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
cd /d "%ROOT%"

:menu
cls
echo ===================================================
echo         PAINEL DE CONTROLE - MINECRAFT P2P
echo         Pasta: %ROOT%
echo ===================================================
echo.
echo   --- OPERACAO ---
echo   [1] Iniciar servidor (limpa conflitos do Syncthing)
echo   [2] STATUS (conteineres, saude e sincronizacao)
echo.
echo   --- MONITORAR ---
echo   [3] Ver ultimos logs do Minecraft
echo   [4] Console / Comandos do servidor (RCON)
echo   [D] Detector de erros (diagnostico completo)
echo.
echo   --- CONTROLE ---
echo   [5] Reiniciar apenas o Minecraft
echo   [6] Parar apenas o Minecraft (mantem Syncthing)
echo   [7] Parar TUDO (Minecraft + Syncthing)
echo.
echo   --- EXTRAS ---
echo   [8] Backup do mapa (.zip com data/hora)
echo   [9] Abrir painel do Syncthing no navegador
echo.
echo   --- SETUP ---
echo   [X] Instalar/verificar dependencias (Docker, Git, Tailscale)
echo   [U] Sincronizar projeto com o GitHub (git pull)
echo   [I] Importar mundo + dados de jogadores (SUBSTITUI o mundo atual)
echo.
echo   [0] Sair
echo.
echo ===================================================
set /p "opcao=Digite a opcao e tecle ENTER: "

if "%opcao%"=="1" goto iniciar
if "%opcao%"=="2" goto status
if "%opcao%"=="3" goto logs
if "%opcao%"=="4" goto console
if "%opcao%"=="5" goto reiniciar
if "%opcao%"=="6" goto parar_mc
if "%opcao%"=="7" goto parar_tudo
if "%opcao%"=="8" goto backup
if "%opcao%"=="9" goto syncthing
if /i "%opcao%"=="D" goto diagnostico
if /i "%opcao%"=="X" goto instalar
if /i "%opcao%"=="U" goto atualizar
if /i "%opcao%"=="I" goto importar
if "%opcao%"=="0" goto sair
echo.
echo Opcao invalida! Tente novamente.
timeout /t 2 >nul 2>&1
goto menu

:iniciar
cls
echo === INICIANDO SERVIDOR ===
echo.
call :check_docker
if errorlevel 1 ( pause & goto menu )
echo Limpando arquivos de conflito do Syncthing (.sync-conflict-*)...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%ROOT%\data' -Recurse -Filter '*.sync-conflict-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue"
echo.
echo Subindo os conteineres (Minecraft + Syncthing)...
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

:status
cls
echo === STATUS DO AMBIENTE ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\status.ps1"
echo.
pause
goto menu

:logs
cls
echo === ULTIMOS LOGS DO MINECRAFT (80 linhas) ===
echo.
docker compose -f "%COMPOSE%" logs mc --tail 80
if errorlevel 1 call :log "ERRO: 'logs mc' falhou"
echo.
pause
goto menu

:console
cls
echo === CONSOLE DO SERVIDOR (RCON) ===
echo.
echo Digite comandos do Minecraft (ex: list, seed, time set day).
echo Para sair do console e voltar ao menu, digite: exit
echo.
docker compose -f "%COMPOSE%" exec mc rcon-cli
if errorlevel 1 (
    echo [ERRO] Nao foi possivel abrir o console. O Minecraft esta rodando?
    call :log "ERRO: 'exec rcon-cli' falhou"
)
echo.
pause
goto menu

:reiniciar
cls
echo === REINICIANDO O MINECRAFT ===
echo.
docker compose -f "%COMPOSE%" restart mc
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

:parar_mc
cls
echo === PARANDO APENAS O MINECRAFT ===
echo.
docker compose -f "%COMPOSE%" stop mc
if errorlevel 1 (
    echo [ERRO] Falha ao parar o Minecraft. Log: "%LOGFILE%"
    call :log "ERRO: 'stop mc' falhou"
) else (
    call :log "OK: 'stop mc'"
)
echo.
echo ATENCAO: O Syncthing continua ATIVO para enviar o save ao seu amigo.
echo Aguarde a sincronizacao concluir no painel http://localhost:8384
echo (status "Up to Date") ANTES de desligar o computador.
echo.
pause
goto menu

:parar_tudo
cls
echo === PARANDO TODA A INFRAESTRUTURA ===
echo.
docker compose -f "%COMPOSE%" down
if errorlevel 1 (
    echo [ERRO] Falha ao encerrar. Log: "%LOGFILE%"
    call :log "ERRO: 'down' falhou"
) else (
    echo Infraestrutura encerrada (Minecraft + Syncthing).
    call :log "OK: 'down'"
)
echo.
pause
goto menu

:backup
cls
echo === BACKUP DO MAPA ===
echo.
echo Dica: pare o Minecraft (opcao 6) antes, para um backup 100%% consistente.
echo Compactando o mapa, aguarde...
powershell -NoProfile -ExecutionPolicy Bypass -Command "if(-not(Test-Path '%ROOT%\backups')){New-Item -ItemType Directory -Path '%ROOT%\backups' | Out-Null}; $ts=Get-Date -Format 'yyyyMMdd_HHmmss'; $dst=Join-Path '%ROOT%\backups' ('world_backup_'+$ts+'.zip'); Compress-Archive -Path '%ROOT%\data\world\*' -DestinationPath $dst -Force; Write-Host ('Backup criado em: '+$dst)"
if errorlevel 1 (
    echo [ERRO] Falha no backup. Log: "%LOGFILE%"
    call :log "ERRO: backup falhou"
) else (
    call :log "OK: backup do mapa criado"
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

:instalar
cls
echo === INSTALAR / VERIFICAR DEPENDENCIAS ===
echo.
echo Isto vai baixar/instalar Docker Desktop, Git e Tailscale (via winget)
echo e configurar o salvamento automatico do mundo (a cada 30 min).
echo O Windows pode pedir permissao de administrador durante a instalacao.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\install-deps.ps1"
call :log "Instalacao/verificacao de dependencias executada"
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

:diagnostico
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\detect-errors.ps1"
call :log "Diagnostico (detector de erros) executado"
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
docker compose -f "%COMPOSE%" stop mc >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\import-world.ps1"
if errorlevel 1 (
    echo.
    echo [AVISO] Importacao nao concluida (cancelada ou com erro). Log: "%LOGFILE%"
    call :log "AVISO: import-world nao concluido"
) else (
    call :log "OK: importacao de mundo/dados concluida"
)
echo.
pause
goto menu

:: ================== SUB-ROTINAS ==================
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
