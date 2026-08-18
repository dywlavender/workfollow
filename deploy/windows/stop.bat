@echo off
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":8123" ^| findstr "LISTENING"') do taskkill /PID %%p /T /F
echo WorkFollow stopped on port 8123.
