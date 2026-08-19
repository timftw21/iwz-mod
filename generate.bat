@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\validate_ui_script_lifecycle.ps1"
if errorlevel 1 exit /b 1
git submodule update --init --recursive
tools\premake5 %* vs2022
