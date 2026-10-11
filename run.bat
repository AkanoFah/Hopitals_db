@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
    py app.py
    goto :done
)
where python >nul 2>nul
if %errorlevel%==0 (
    python app.py
    goto :done
)
echo Python was not found.
echo Install it from https://www.python.org/downloads/ and tick "Add python.exe to PATH",
echo then double-click run.bat again.
:done
pause
