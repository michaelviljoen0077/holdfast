@echo off
rem Launch Holdfast with the local Godot 4.7.2 install.
set "GODOT=%USERPROFILE%\Desktop\Godot\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
