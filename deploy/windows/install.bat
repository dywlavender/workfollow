@echo off
setlocal
cd /d "%~dp0\..\.."

py -3.12 -c "import sys; assert sys.maxsize > 2**32" >nul 2>&1
if errorlevel 1 (
  echo Error: Python 3.12 x64 is required. Install it offline first.
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
if not exist data\files mkdir data\files
if not exist data\uploads mkdir data\uploads
if not exist logs mkdir logs
if not exist run mkdir run
.venv\Scripts\alembic.exe -c backend\alembic.ini upgrade head
if errorlevel 1 exit /b 1
echo Installation completed. Run deploy\windows\start.bat.
