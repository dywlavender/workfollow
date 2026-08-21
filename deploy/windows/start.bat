@echo off
setlocal
cd /d "%~dp0\..\.."
if not exist logs mkdir logs
if not exist run mkdir run
if "%WORKFOLLOW_HOST%"=="" set WORKFOLLOW_HOST=0.0.0.0
if "%WORKFOLLOW_PORT%"=="" set WORKFOLLOW_PORT=8123

.venv\Scripts\alembic.exe -c backend\alembic.ini upgrade head
if errorlevel 1 exit /b 1
start "WorkFollow" /min cmd /c ".venv\Scripts\uvicorn.exe app.main:app --app-dir backend --host %WORKFOLLOW_HOST% --port %WORKFOLLOW_PORT% >> logs\workfollow-http.log 2>&1"
echo WorkFollow is starting at http://localhost:%WORKFOLLOW_PORT%
echo Use deploy\windows\stop.bat to stop it.
