@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0\..\.."

py -3.12 -c "import sys; assert sys.maxsize > 2**32" >nul 2>&1
if errorlevel 1 (
  echo Error: Python 3.12 x64 is required. Install it offline first.
  exit /b 1
)
set "NODE_EXE=runtime\node\node.exe"
if not exist "%NODE_EXE%" (
  echo Error: bundled Node.js runtime is missing: runtime\node\node.exe. Get the complete release package.
  exit /b 1
)
set "NODE_MAJOR="
for /f "tokens=1 delims=." %%v in ('%NODE_EXE% -p "process.versions.node"') do set NODE_MAJOR=%%v
if not defined NODE_MAJOR (
  echo Error: bundled Node.js runtime could not be executed.
  exit /b 1
)
if !NODE_MAJOR! LSS 22 (
  echo Error: bundled Node.js 22+ is required for the collaboration service.
  exit /b 1
)
if exist collaboration\node_modules\@hocuspocus\server\package.json if exist collaboration\node_modules\@hocuspocus\transformer\package.json if exist collaboration\node_modules\yjs\package.json (
  echo Prepackaged collaboration dependencies found.
) else (
  echo Error: bundled collaboration dependencies are incomplete. The target does not need npm; get the complete release package.
  exit /b 1
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
