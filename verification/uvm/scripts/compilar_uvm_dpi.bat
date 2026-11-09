@echo off
REM =============================================================================
REM compilar_uvm_dpi.bat
REM Recompila uvm\sim\uvm_dpi.dll (biblioteca C da UVM 1.2 usada via DPI).
REM So e necessario se a DLL fornecida nao carregar na sua instalacao.
REM
REM Usa o GCC 4.2.1 que vem com o ModelSim Intel FPGA Starter Edition 2021.1.
REM uvm_dpi_stub.c fornece m__uvm_report_dpi, que o ModelSim Starter nao
REM exporta (a implementacao real e resolvida pelo simulador em tempo de execucao).
REM =============================================================================

if not defined MODELSIM_DIR set MODELSIM_DIR=D:\modelsim_ase
set UVM_DPI=%MODELSIM_DIR%\verilog_src\uvm-1.2\src\dpi
set PATH=%MODELSIM_DIR%\gcc-4.2.1-mingw32vc12\bin;%MODELSIM_DIR%\win32aloem;C:\WINDOWS\system32;C:\WINDOWS

cd /d "%~dp0..\sim"
g++ -c -DQUESTA -I"%MODELSIM_DIR%\include" -I"%UVM_DPI%" "%UVM_DPI%\uvm_dpi.cc" -o uvm_dpi.o || exit /b 1
gcc -c uvm_dpi_stub.c -o uvm_dpi_stub.o || exit /b 1
g++ -shared -o uvm_dpi.dll uvm_dpi.o uvm_dpi_stub.o -L"%MODELSIM_DIR%\win32aloem" -lmtipli || exit /b 1
del /q uvm_dpi.o uvm_dpi_stub.o
echo uvm_dpi.dll gerada em %CD%
