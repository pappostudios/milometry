@echo off
REM Double-click this to build the latest code and install it on your phone.
REM It builds in C:\psycho_build (a copy VS Code does NOT watch), so the
REM "Unable to delete directory" Gradle lock error can never happen.
REM You can keep VS Code open while this runs.
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\My games\Mobile\psycho_app\build_debug_install.ps1"
echo.
pause
