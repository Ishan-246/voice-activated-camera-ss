@echo off
cd /d "%~dp0"
py -3 -c "import numpy, matplotlib, sounddevice" 2>nul || py -3 -m pip install -r requirements.txt
py -3 voice_camera_app.py
if errorlevel 1 pause
