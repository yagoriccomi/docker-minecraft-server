@echo off
setlocal EnableDelayedExpansion
title Painel REMOTO - Servidor Minecraft P2P

:: ===================================================================
::  PORTABILIDADE (local)
::  ROOT = pasta onde este .bat esta (funciona em QUALQUER PC/pasta).
::  Usado apenas para gravar o log local deste painel.
:: ===================================================================
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "LOGDIR=%ROOT%\logs"
set "LOGFILE=%LOGDIR%\menu-remoto.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
cd /d "%ROOT%"

:: ===================================================================
::  CONFIGURACAO DO HOST REMOTO  (edite aqui OU crie menu-remoto.config.bat)
:: -------------------------------------------------------------------
::  A conexao usa o IP do TAILSCALE do outro jogador (rede 100.64.0.0/10,
::  sempre no formato 100.x.y.z). O SSH e o painel do Syncthing sao TODOS
::  derivados desse mesmo IP.
::
::  REMOTE_IP    = IP Tailscale do host remoto (ex.: 100.101.102.103).
::                 Descubra com 'tailscale ip -4' NA MAQUINA DELE, ou em
::                 'tailscale status' aqui, ou no admin console do Tailscale.
::  REMOTE_USER  = usuario Windows do host remoto usado no SSH.
::  RROOT        = pasta do projeto NA MAQUINA DELE (onde esta o compose.yaml).
::  MC_NAME      = nome do container do Minecraft (compose.yaml -> container_name).
::
::  DICA: em vez de editar este arquivo, crie um "menu-remoto.config.bat" na
::  mesma pasta com as linhas 'set ...' abaixo. Ele sobrepoe estes padroes
::  e NAO e sobrescrito quando voce atualiza o projeto (git pull).
:: ===================================================================
set "REMOTE_IP=100.x.y.z"
set "REMOTE_USER=SEU_USUARIO"
set "RROOT=C:\Users\SEU_USUARIO\Server"
set "MC_NAME=minecraft"

if exist "%ROOT%\menu-remoto.config.bat" call "%ROOT%\menu-remoto.config.bat"

:: Derivados do IP Tailscale (nao edite abaixo).
set "REMOTE=%REMOTE_USER%@%REMOTE_IP%"
set "REMOTE_PANEL=http://%REMOTE_IP%:8384"
:: Caminhos no host remoto (formato Windows/backslash).
set "RCOMPOSE=%RROOT%\compose.yaml"
set "RSCRIPTS=%RROOT%\scripts"

:: Aviso se o IP Tailscale ainda nao foi configurado.
if not "%REMOTE_IP%"=="100.x.y.z" goto menu
cls
echo ===================================================
echo   CONFIGURACAO NECESSARIA - IP DO TAILSCALE
echo ===================================================
echo.
echo Antes de usar este painel, defina o IP Tailscale do host remoto.
echo.
echo Opcao recomendada: crie um arquivo "menu-remoto.config.bat" nesta
echo pasta com o conteudo:
echo.
echo     set "REMOTE_IP=100.101.102.103"
echo     set "REMOTE_USER=usuario_do_windows_dele"
echo     set "RROOT=C:\Users\usuario_do_windows_dele\Server"
echo.
echo Descubra o IP com:  tailscale ip -4   na maquina dele.
echo.
pause
goto sair

:menu
cls
echo ===================================================
echo    PAINEL *REMOTO* - MINECRAFT P2P
echo    Host remoto : %REMOTE%
echo    Pasta remota: %RROOT%
echo ===================================================
echo   Os comandos abaixo agem NA MAQUINA REMOTA via SSH.
echo ===================================================
echo.
echo   --- OPERACAO ---
echo   [1] Iniciar servidor remoto (limpa conflitos do Syncthing)
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
echo   [8] Backup do mapa (.zip com data/hora) na maquina remota
echo   [9] Abrir painel do Syncthing remoto no navegador
echo.
echo   --- SETUP ---
echo   [X] Instalar/verificar dependencias na maquina remota
echo   [U] Sincronizar projeto remoto com o GitHub (git pull)
echo   [I] Importar mundo + dados de jogadores (SUBSTITUI o mundo remoto)
echo   [T] Testar conexao SSH com a maquina remota
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
if /i "%opcao%"=="T" goto testar
if "%opcao%"=="0" goto sair
echo.
echo Opcao invalida! Tente novamente.
timeout /t 2 >nul 2>&1
goto menu

:iniciar
cls
echo === INICIANDO SERVIDOR REMOTO ===
echo.
call :check_ssh
if errorlevel 1 ( pause & goto menu )
echo Verificando se o SEU Minecraft LOCAL esta rodando (anti split-brain)...
set "LOCALRUN="
for /f "usebackq delims=" %%i in (`docker inspect -f "{{.State.Running}}" %MC_NAME% 2^>nul`) do set "LOCALRUN=%%i"
if /i "%LOCALRUN%"=="true" (
    echo.
    echo  ##################################################################
    echo  #  ABORTADO: seu Minecraft LOCAL esta ATIVO nesta maquina.        #
    echo  #  Rodar o servidor remoto junto corromperia o mapa ^(split-brain^).#
    echo  #  Pare o local pelo menu.bat ^(opcao 6/7^) antes de iniciar o remoto.#
    echo  ##################################################################
    echo.
    call :log "ABORTADO iniciar remoto: local %MC_NAME% ativo"
    pause
    goto menu
)
echo Local ok ^(parado^). Limpando conflitos do Syncthing na maquina remota...
ssh %REMOTE% powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%RROOT%\data' -Recurse -Filter '*.sync-conflict-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue"
echo Subindo os conteineres na maquina remota...
ssh %REMOTE% docker compose -f "%RCOMPOSE%" up -d
if errorlevel 1 (
    echo [ERRO] Falha ao iniciar no host remoto. Log: "%LOGFILE%"
    call :log "ERRO: 'up -d' remoto falhou"
) else (
    echo Servidor remoto iniciado!  Minecraft: 25565  ^|  Syncthing: 8384
    call :log "OK: 'up -d' remoto"
)
echo.
pause
goto menu

:status
cls
echo === STATUS DO AMBIENTE (host remoto: %REMOTE%) ===
echo.
call :check_ssh
if errorlevel 1 ( pause & goto menu )
ssh %REMOTE% powershell -NoProfile -ExecutionPolicy Bypass -File "%RSCRIPTS%\status.ps1"
if errorlevel 1 call :log "ERRO: status.ps1 remoto falhou"
echo.
echo --- Referencia: estado do SEU Minecraft LOCAL ---
docker inspect -f "Local: {{.State.Status}}" %MC_NAME% 2>nul || echo Local: container nao encontrado / parado
echo.
pause
goto menu

:logs
cls
echo === ULTIMOS LOGS DO MINECRAFT REMOTO (80 linhas) ===
echo.
ssh %REMOTE% docker compose -f "%RCOMPOSE%" logs mc --tail 80
if errorlevel 1 call :log "ERRO: 'logs mc' remoto falhou"
echo.
pause
goto menu

:console
cls
echo === CONSOLE DO SERVIDOR REMOTO (RCON) ===
echo.
echo Digite comandos do Minecraft (ex: list, seed, time set day).
echo Para sair do console e voltar ao menu, digite: exit
echo.
ssh -t %REMOTE% docker compose -f "%RCOMPOSE%" exec mc rcon-cli
if errorlevel 1 (
    echo [ERRO] Nao foi possivel abrir o console. O Minecraft remoto esta rodando?
    call :log "ERRO: 'exec rcon-cli' remoto falhou"
)
echo.
pause
goto menu

:reiniciar
cls
echo === REINICIANDO O MINECRAFT REMOTO ===
echo.
ssh %REMOTE% docker compose -f "%RCOMPOSE%" restart mc
if errorlevel 1 (
    echo [ERRO] Falha ao reiniciar. Log: "%LOGFILE%"
    call :log "ERRO: 'restart mc' remoto falhou"
) else (
    echo Minecraft remoto reiniciado.
    call :log "OK: 'restart mc' remoto"
)
echo.
pause
goto menu

:parar_mc
cls
echo === PARANDO APENAS O MINECRAFT REMOTO ===
echo.
ssh %REMOTE% docker compose -f "%RCOMPOSE%" stop mc
if errorlevel 1 (
    echo [ERRO] Falha ao parar o Minecraft remoto. Log: "%LOGFILE%"
    call :log "ERRO: 'stop mc' remoto falhou"
) else (
    call :log "OK: 'stop mc' remoto"
)
echo.
echo ATENCAO: O Syncthing remoto continua ATIVO para enviar o save.
echo Aguarde a sincronizacao concluir (status "Up to Date") antes de
echo alguem desligar o computador ou iniciar o servidor em outra maquina.
echo.
pause
goto menu

:parar_tudo
cls
echo === PARANDO TODA A INFRAESTRUTURA REMOTA ===
echo.
ssh %REMOTE% docker compose -f "%RCOMPOSE%" down
if errorlevel 1 (
    echo [ERRO] Falha ao encerrar no host remoto. Log: "%LOGFILE%"
    call :log "ERRO: 'down' remoto falhou"
) else (
    echo Infraestrutura remota encerrada ^(Minecraft + Syncthing^).
    call :log "OK: 'down' remoto"
)
echo.
pause
goto menu

:backup
cls
echo === BACKUP DO MAPA (na maquina remota) ===
echo.
echo Dica: pare o Minecraft remoto (opcao 6) antes, para um backup consistente.
echo Compactando o mapa na maquina remota, aguarde...
ssh %REMOTE% powershell -NoProfile -Command "if(-not(Test-Path '%RROOT%\backups')){New-Item -ItemType Directory -Path '%RROOT%\backups' | Out-Null}; $ts=Get-Date -Format 'yyyyMMdd_HHmmss'; $dst=Join-Path '%RROOT%\backups' ('world_backup_'+$ts+'.zip'); Compress-Archive -Path '%RROOT%\data\world\*' -DestinationPath $dst -Force; Write-Host ('Backup criado em: '+$dst)"
if errorlevel 1 (
    echo [ERRO] Falha no backup remoto. Log: "%LOGFILE%"
    call :log "ERRO: backup remoto falhou"
) else (
    call :log "OK: backup remoto do mapa"
)
echo.
pause
goto menu

:syncthing
cls
echo === ABRINDO O PAINEL DO SYNCTHING REMOTO ===
echo.
echo Abrindo %REMOTE_PANEL% no navegador (via Tailscale)...
start "" "%REMOTE_PANEL%"
echo.
echo Se nao abrir, confira o REMOTE_IP (Tailscale) no menu-remoto.config.bat
echo e verifique se o Tailscale esta conectado nas duas maquinas.
echo.
pause
goto menu

:diagnostico
cls
echo === DETECTOR DE ERROS (host remoto: %REMOTE%) ===
echo.
call :check_ssh
if errorlevel 1 ( pause & goto menu )
ssh %REMOTE% powershell -NoProfile -ExecutionPolicy Bypass -File "%RSCRIPTS%\detect-errors.ps1"
call :log "Diagnostico remoto executado"
echo.
pause
goto menu

:instalar
cls
echo === INSTALAR / VERIFICAR DEPENDENCIAS (host remoto) ===
echo.
echo Roda o install-deps.ps1 na maquina remota (Docker, Git, Tailscale).
echo OBS: instalacoes que pedem UAC/Administrador podem NAO funcionar por SSH.
echo Nesse caso, peca ao dono da maquina remota para rodar o menu.bat opcao [X].
echo.
pause
ssh %REMOTE% powershell -NoProfile -ExecutionPolicy Bypass -File "%RSCRIPTS%\install-deps.ps1"
call :log "Instalacao de dependencias remota executada"
echo.
pause
goto menu

:atualizar
cls
echo === SINCRONIZAR PROJETO REMOTO COM O GITHUB (git pull) ===
echo.
call :check_ssh
if errorlevel 1 ( pause & goto menu )
ssh %REMOTE% git -C "%RROOT%" pull --ff-only
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao atualizar o projeto remoto. Veja a mensagem acima.
    call :log "ERRO: git pull remoto falhou"
) else (
    echo.
    echo Projeto remoto atualizado com a versao mais recente do GitHub!
    call :log "OK: git pull remoto"
)
echo.
pause
goto menu

:importar
cls
echo === IMPORTAR MUNDO + DADOS DE JOGADORES (host remoto) ===
echo.
echo Esta opcao SUBSTITUI o mundo REMOTO por um mundo de pasta externa dele.
echo Um backup .zip do mundo remoto e criado ANTES de qualquer alteracao.
echo O Minecraft remoto sera parado para liberar os arquivos.
echo.
call :check_ssh
if errorlevel 1 ( pause & goto menu )
ssh %REMOTE% docker compose -f "%RCOMPOSE%" stop mc
ssh -t %REMOTE% powershell -NoProfile -ExecutionPolicy Bypass -File "%RSCRIPTS%\import-world.ps1"
if errorlevel 1 (
    echo.
    echo [AVISO] Importacao remota nao concluida ^(cancelada ou com erro^).
    call :log "AVISO: import-world remoto nao concluido"
) else (
    call :log "OK: importacao de mundo remoto concluida"
)
echo.
pause
goto menu

:testar
cls
echo === TESTANDO CONEXAO SSH COM O HOST REMOTO (%REMOTE%) ===
echo.
ssh %REMOTE% "Write-Host 'Conexao OK'; hostname; docker --version"
if errorlevel 1 (
    echo.
    echo [ERRO] Nao foi possivel conectar em '%REMOTE%'.
    echo Verifique o REMOTE_IP/Tailscale, a chave SSH e o servico sshd remoto.
    call :log "ERRO: teste SSH falhou"
) else (
    echo.
    echo Conexao SSH funcionando. Se pediu senha, configure a chave SSH.
    call :log "OK: teste SSH"
)
echo.
pause
goto menu

:: ================== SUB-ROTINAS ==================
:check_ssh
where ssh >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Cliente SSH ^(OpenSSH^) nao encontrado nesta maquina.
    echo Instale o "OpenSSH Client" em Configuracoes ^> Aplicativos ^> Recursos opcionais.
    call :log "ERRO: cliente ssh ausente"
    exit /b 1
)
exit /b 0

:log
echo [%DATE% %TIME%] %~1>> "%LOGFILE%"
exit /b 0

:sair
endlocal
exit /b 0
