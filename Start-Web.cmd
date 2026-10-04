@echo off
setlocal
cd /d "%~dp0"
if defined SHU_PYTHON (call "%SHU_PYTHON%" tools\serve_preview.py --open) else (call python tools\serve_preview.py --open)
