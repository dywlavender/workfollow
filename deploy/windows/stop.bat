@echo off
if "%WORKFOLLOW_PORT%"=="" set WORKFOLLOW_PORT=8123
if "%WORKFOLLOW_COLLABORATION_PORT%"=="" set WORKFOLLOW_COLLABORATION_PORT=8124
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%WORKFOLLOW_COLLABORATION_PORT%" ^| findstr "LISTENING"') do taskkill /PID %%p /T /F
echo WorkFollow collaboration stopped on port %WORKFOLLOW_COLLABORATION_PORT%.
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%WORKFOLLOW_PORT%" ^| findstr "LISTENING"') do taskkill /PID %%p /T /F
echo WorkFollow stopped on port %WORKFOLLOW_PORT%.
