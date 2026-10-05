@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
set "_GA_PYTHON="
set "_GA_PREFIX="

if defined GAME_ART_PYTHON goto configured

rem Machine-local interpreter cache is ignored by Git; never commit host paths.
if exist "%~dp0.local\game-art-python.txt" for /f "usebackq delims=" %%P in ("%~dp0.local\game-art-python.txt") do call :probe "%%P"
if defined _GA_PYTHON goto run

rem Reuse the existing Windows GameDev runtime even outside the Codex PATH.
if exist "%LOCALAPPDATA%\GameDevCenter\bin\python.cmd" call :probe "%LOCALAPPDATA%\GameDevCenter\bin\python.cmd"
if exist "%USERPROFILE%\.local\bin\python3.12.exe" call :probe "%USERPROFILE%\.local\bin\python3.12.exe"
for /f "delims=" %%P in ('where.exe py 2^>nul') do call :probe "%%P" -3.12
for /f "delims=" %%P in ('where.exe python 2^>nul') do call :probe "%%P"
if defined _GA_PYTHON goto run

rem uv-managed installations need not be on PATH. Probe before selecting one.
for /d %%D in ("%APPDATA%\uv\python\cpython-3.12*-windows-*-none") do if exist "%%D\python.exe" call :probe "%%D\python.exe"
if defined _GA_PYTHON goto run
echo [ERROR] No working Python 3.12+ was found.
echo Set GAME_ART_PYTHON to a real Python executable, then run this launcher again.
set "_GA_EXIT=1"
goto finish

:configured
call :probe "%GAME_ART_PYTHON%"
if defined _GA_PYTHON goto run
echo [ERROR] GAME_ART_PYTHON does not run a working Python 3.12+ interpreter.
set "_GA_EXIT=1"
goto finish

:run
call "%_GA_PYTHON%" %_GA_PREFIX% -I "%~dp0tools\setup_game_art.py" %*
set "_GA_EXIT=%errorlevel%"
goto finish

:probe
if defined _GA_PYTHON exit /b 0
rem Skip the Microsoft Store alias rather than launching it.
if /i "%~1"=="%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe" exit /b 0
call "%~1" %~2 -I -c "import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)" >nul 2>nul
if errorlevel 1 exit /b 0
set "_GA_PYTHON=%~1"
set "_GA_PREFIX=%~2"
exit /b 0

:finish
pause
exit /b %_GA_EXIT%
