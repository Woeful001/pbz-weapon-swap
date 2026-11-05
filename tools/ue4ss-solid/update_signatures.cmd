@echo off
chcp 65001 >nul
cd /d "%~dp0"
python "%~dp0update_signatures.py" %*
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" (echo Done. Start the game and check ue4ss\UE4SS.log.) else (echo Failed, nothing written. Old signatures are untouched.)
pause
exit /b %RC%
