@echo off
:: ===================================================================
::  EXEMPLO de configuracao do painel remoto (menu-remoto.bat)
:: -------------------------------------------------------------------
::  COMO USAR:
::   1) Copie este arquivo para "menu-remoto.config.bat" (mesma pasta).
::   2) Preencha os 3 valores abaixo com os dados do host remoto.
::   3) Rode o menu-remoto.bat normalmente.
::
::  O menu-remoto.config.bat NAO e versionado (fica so na sua maquina),
::  entao o IP/usuario do seu amigo nao vao parar no GitHub.
:: ===================================================================

:: IP do Tailscale do host remoto (formato 100.x.y.z).
:: Descubra na maquina DELE com:  tailscale ip -4
set "REMOTE_IP=100.101.102.103"

:: Usuario Windows do host remoto (usado no SSH: usuario@ip).
set "REMOTE_USER=amigo"

:: Pasta do projeto NA MAQUINA DELE (onde esta o compose.yaml).
set "RROOT=C:\Users\amigo\Server"
