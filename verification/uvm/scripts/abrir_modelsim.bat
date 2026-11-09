@echo off
REM =============================================================================
REM abrir_modelsim.bat
REM Abre o ModelSim com o GCC correto no PATH (necessario para a DPI da UVM).
REM Depois, no console do ModelSim:
REM     cd <repositorio>/uvm/sim
REM     do ../scripts/run_uvm_gui.do
REM =============================================================================

if not defined MODELSIM_DIR set MODELSIM_DIR=D:\modelsim_ase

set PATH=%MODELSIM_DIR%\gcc-4.2.1-mingw32vc12\bin;%MODELSIM_DIR%\win32aloem;C:\WINDOWS\system32;C:\WINDOWS
set MODEL_TECH=%MODELSIM_DIR%\win32aloem

REM Primeira execucao (ou repositorio sem a DLL): compila a DLL da UVM
if not exist "%~dp0..\sim\uvm_dpi.dll" call "%~dp0compilar_uvm_dpi.bat" || exit /b 1

cd /d "%~dp0..\sim"
start "" "%MODELSIM_DIR%\win32aloem\modelsim.exe"
