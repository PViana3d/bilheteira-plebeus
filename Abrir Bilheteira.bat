@echo off
rem Abre a Bilheteira Uniao Academica de Avintes no Chrome com impressao direta (sem janela de impressao).
set "URL=https://pviana3d.github.io/bilheteira-plebeus/"
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%LocalAppData%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" (
  echo Nao encontrei o Google Chrome. Instale-o e volte a abrir este atalho.
  pause
  exit /b 1
)
start "" "%CHROME%" --kiosk-printing --user-data-dir="%LocalAppData%\BilheteiraPlebeus" --app="%URL%"
