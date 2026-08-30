@echo off
setlocal
cd /d "%~dp0\..\.."

py -3.12 -c "import sys; assert sys.maxsize > 2**32" >nul 2>&1
if errorlevel 1 (
  echo Error: Python 3.12 x64 is required. Install it offline first.
  exit /b 1
)
node -p "process.versions.node" >nul 2>&1
if errorlevel 1 (
  echo Error: Node.js 22+ is required for the collaboration service.
  exit /b 1
)
for /f "tokens=1 delims=." %%v in ('node -p "process.versions.node"') do set NODE_MAJOR=%%v
if %NODE_MAJOR% LSS 22 (
  echo Error: Node.js 22+ is required for the collaboration service.
  exit /b 1
)
if exist collaboration\node_modules\@hocuspocus\server\package.json if exist collaboration\node_modules\@hocuspocus\transformer\package.json if exist collaboration\node_modules\yjs\package.json (
  echo Prepackaged collaboration dependencies found; skipping npm install.
) else (
  where npm >nul 2>&1
  if errorlevel 1 (
    echo Error: collaboration dependencies are missing and npm was not found. Use a release package with bundled dependencies.
    exit /b 1
  )
  npm --prefix collaboration ci --omit=dev --no-audit --no-fund
  if errorlevel 1 exit /b 1
)

py -3.12 -m venv .venv
if errorlevel 1 exit /b 1
if exist wheelhouse\*.whl (
  echo Local wheelhouse found. Installing without network.
  .venv\Scripts\python.exe -m pip install --no-index --find-links wheelhouse -r deploy\requirements-offline.txt
) else (
  echo No wheelhouse found. Downloading Python dependencies.
  .venv\Scripts\python.exe -m pip install -r deploy\requirements-offline.txt
)
if errorlevel 1 exit /b 1
.venv\Scripts\python.exe -c "import fastapi, httpx, mcp, sqlalchemy"
if errorlevel 1 (
  echo Error: Python dependency verification failed. Check that wheelhouse contains all Windows x64 Python 3.12 wheels.
  exit /b 1
)
if not exist data\files mkdir data\files
if not exist data\uploads mkdir data\uploads
if not exist logs mkdir logs
if not exist run mkdir run
if not exist data\collaboration mkdir data\collaboration
.venv\Scripts\alembic.exe -c backend\alembic.ini upgrade head
if errorlevel 1 exit /b 1
echo Installation completed. Run deploy\windows\start.bat.
