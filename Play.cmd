@echo off
setlocal
cd /d "%~dp0"
if defined SHU_GODOT (call "%SHU_GODOT%" --path "%~dp0") else (call godot --path "%~dp0")
