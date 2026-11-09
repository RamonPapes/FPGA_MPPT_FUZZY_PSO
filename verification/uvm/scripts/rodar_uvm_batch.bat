@echo off
REM =============================================================================
REM rodar_uvm_batch.bat
REM Roda a verificacao UVM sem interface grafica. Duplo-clique ou rode no cmd.
REM Resultado: uvm\resultados\transcript.txt
REM
REM Se o ModelSim nao estiver em D:\modelsim_ase, antes de rodar:
REM     set MODELSIM_DIR=C:\caminho\do\modelsim_ase
REM =============================================================================

if not defined MODELSIM_DIR set MODELSIM_DIR=D:\modelsim_ase

REM PATH limpo: so o GCC 4.2.1 do ModelSim. Outro GCC no PATH (ex.: MSYS2)
REM faz a carga da DLL da UVM falhar.
set PATH=%MODELSIM_DIR%\gcc-4.2.1-mingw32vc12\bin;%MODELSIM_DIR%\win32aloem;C:\WINDOWS\system32;C:\WINDOWS
set MODEL_TECH=%MODELSIM_DIR%\win32aloem

REM Primeira execucao (ou repositorio sem a DLL): compila a DLL da UVM
if not exist "%~dp0..\sim\uvm_dpi.dll" call "%~dp0compilar_uvm_dpi.bat" || exit /b 1

if not exist "%~dp0..\resultados" mkdir "%~dp0..\resultados"
cd /d "%~dp0..\sim"
"%MODELSIM_DIR%\win32aloem\vsim.exe" -c -do "do ../scripts/run_uvm_batch.do"
