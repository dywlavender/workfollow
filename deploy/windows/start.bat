@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0\..\.."
where node >nul 2>&1
if errorlevel 1 (
  echo Error: Node.js 22+ is required.
  exit /b 1
)
for /f "tokens=1 delims=." %%v in ('node -p "process.versions.node"') do set NODE_MAJOR=%%v
if !NODE_MAJOR! LSS 22 (
  echo Error: Node.js 22+ is required.
  exit /b 1
)
where curl.exe >nul 2>&1
if errorlevel 1 (
  echo Error: curl.exe is required for health checks.
  exit /b 1
)
if not exist .venv\Scripts\uvicorn.exe (
  echo Error: backend environment is missing. Run deploy\windows\install.bat first.
  exit /b 1
)
if not exist collaboration\node_modules\@hocuspocus\server\package.json (
  echo Error: collaboration dependencies are incomplete. Reinstall the full offline package.
  exit /b 1
)
if not exist logs mkdir logs
if not exist run mkdir run
if "%WORKFOLLOW_HOST%"=="" set WORKFOLLOW_HOST=0.0.0.0
if "%WORKFOLLOW_PORT%"=="" set WORKFOLLOW_PORT=8123
if "%WORKFOLLOW_COLLABORATION_PORT%"=="" set WORKFOLLOW_COLLABORATION_PORT=8124
if "%WORKFOLLOW_COLLABORATION_BIND%"=="" set WORKFOLLOW_COLLABORATION_BIND=%WORKFOLLOW_HOST%
if "%WORKFOLLOW_BACKEND_URL%"=="" set WORKFOLLOW_BACKEND_URL=http://127.0.0.1:%WORKFOLLOW_PORT%
if "%WORKFOLLOW_COLLABORATION_HTTP_URL%"=="" set WORKFOLLOW_COLLABORATION_HTTP_URL=http://127.0.0.1:%WORKFOLLOW_COLLABORATION_PORT%
if "%WORKFOLLOW_COLLABORATION_DATA_DIR%"=="" set WORKFOLLOW_COLLABORATION_DATA_DIR=%CD%\data\collaboration
if "!WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN!"=="" (
  if exist run\workfollow-collaboration-token set /p WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN=<run\workfollow-collaboration-token
  if "!WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN!"=="" (
    for /f "delims=" %%t in ('.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(32))"') do set "WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN=%%t"
    >run\workfollow-collaboration-token <nul set /p "=!WORKFOLLOW_COLLABORATION_INTERNAL_TOKEN!"
  )
)

set BACKEND_OK=0
set COLLABORATION_OK=0
curl.exe -fsS "http://127.0.0.1:%WORKFOLLOW_PORT%/api/health" >nul 2>&1 && set BACKEND_OK=1
curl.exe -fsS "http://127.0.0.1:%WORKFOLLOW_COLLABORATION_PORT%/health" >nul 2>&1 && set COLLABORATION_OK=1
if "%BACKEND_OK%"=="1" if "%COLLABORATION_OK%"=="1" (
  echo WorkFollow backend and collaboration service are already running.
  exit /b 0
)

if "%BACKEND_OK%"=="0" (
  .venv\Scripts\alembic.exe -c backend\alembic.ini upgrade head
  if errorlevel 1 exit /b 1
)
if "%BACKEND_OK%"=="0" start "WorkFollow" /min cmd /c ".venv\Scripts\uvicorn.exe app.main:app --app-dir backend --host %WORKFOLLOW_HOST% --port %WORKFOLLOW_PORT% >> logs\workfollow-http.log 2>&1"
if "%COLLABORATION_OK%"=="0" start "WorkFollow Collaboration" /min cmd /c "cd /d collaboration && node server.mjs >> ..\logs\workfollow-collaboration.log 2>&1"
timeout /t 2 /nobreak >nul
curl.exe -fsS "http://127.0.0.1:%WORKFOLLOW_PORT%/api/health" >nul 2>&1
if errorlevel 1 (
  echo Backend service failed to start. Check logs\workfollow-http.log.
  exit /b 1
)
curl.exe -fsS "http://127.0.0.1:%WORKFOLLOW_COLLABORATION_PORT%/health" >nul 2>&1
if errorlevel 1 (
  echo Collaboration service failed to start. Check logs\workfollow-collaboration.log.
  exit /b 1
)
echo WorkFollow is starting at http://localhost:%WORKFOLLOW_PORT%
echo Collaboration service is listening on port %WORKFOLLOW_COLLABORATION_PORT%.
echo Use deploy\windows\stop.bat to stop it.
