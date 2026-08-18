@echo off
setlocal
cd /d "%~dp0\..\.."
if not exist backups mkdir backups
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%i
powershell -NoProfile -Command "Compress-Archive -Path data -DestinationPath 'backups\workfollow-data-%STAMP%.zip' -Force"
echo Backup completed: backups\workfollow-data-%STAMP%.zip
