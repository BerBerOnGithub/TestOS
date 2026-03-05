@echo off
REM ===========================================================================
REM build.bat - ClaudeOS Build Script for Windows
REM
REM Requirements (see README.md for download links):
REM   nasm.exe  - assembler, must be in PATH or same folder as this script
REM   QEMU      - optional, only needed for "build.bat run"
REM
REM Usage:
REM   build.bat          build claudeos.img
REM   build.bat run      build then launch in QEMU
REM   build.bat clean    delete build output
REM ===========================================================================

setlocal

REM ---------------------------------------------------------------------------
REM Handle "clean" early before anything else
REM ---------------------------------------------------------------------------
if /i "%~1"=="clean" goto :clean

REM ---------------------------------------------------------------------------
REM Locate NASM
REM ---------------------------------------------------------------------------
set "NASM=nasm"
where nasm >nul 2>&1
if errorlevel 1 (
    if exist "%~dp0nasm.exe" (
        set "NASM=%~dp0nasm.exe"
    ) else (
        echo.
        echo  ERROR: nasm.exe not found in PATH.
        echo.
        echo  Download the win64 installer from:
        echo    https://nasm.us
        echo  Install it and tick "Add to PATH", then open a new Command Prompt.
        echo.
        echo  Alternatively, copy nasm.exe into this folder next to build.bat.
        echo.
        pause
        exit /b 1
    )
)

REM ---------------------------------------------------------------------------
REM Create build directory
REM ---------------------------------------------------------------------------
if not exist build md build

REM ---------------------------------------------------------------------------
REM Step 1: Assemble bootloader
REM ---------------------------------------------------------------------------
echo [1/3] Assembling bootloader...
"%NASM%" -f bin -o build\boot.bin boot.asm
if errorlevel 1 (
    echo  FAILED: boot.asm had assembly errors.
    exit /b 1
)

for %%F in (build\boot.bin) do set "BOOTSIZE=%%~zF"
if not "%BOOTSIZE%"=="512" (
    echo  ERROR: boot.bin is %BOOTSIZE% bytes, must be exactly 512.
    exit /b 1
)
echo  OK  boot.bin  [512 bytes]

REM ---------------------------------------------------------------------------
REM Step 2: Assemble kernel
REM ---------------------------------------------------------------------------
echo [2/3] Assembling kernel...
"%NASM%" -f bin -o build\kernel.bin kernel.asm
if errorlevel 1 (
    echo  FAILED: kernel.asm had assembly errors.
    exit /b 1
)
for %%F in (build\kernel.bin) do set "KERNSIZE=%%~zF"
echo  OK  kernel.bin  [%KERNSIZE% bytes]

REM ---------------------------------------------------------------------------
REM Step 3: Build disk image via a temporary PowerShell script
REM         (Writing PS inline in bat causes $ expansion conflicts, so we
REM          write a .ps1 file first then run it.)
REM ---------------------------------------------------------------------------
echo [3/3] Building claudeos.img...

set "PS1=%TEMP%\claudeos_build.ps1"

(
    echo $img  = New-Object byte[] ^(2880 * 512^)
    echo $boot = [IO.File]::ReadAllBytes^('build\boot.bin'^)
    echo $kern = [IO.File]::ReadAllBytes^('build\kernel.bin'^)
    echo [Array]::Copy^($boot, 0, $img, 0,   $boot.Length^)
    echo [Array]::Copy^($kern, 0, $img, 512, $kern.Length^)
    echo [IO.File]::WriteAllBytes^('claudeos.img', $img^)
    echo Write-Host ' OK  claudeos.img  [1.44 MB floppy image]'
) > "%PS1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
del "%PS1%" >nul 2>&1

if errorlevel 1 (
    echo  FAILED: Could not create claudeos.img
    exit /b 1
)

echo.
echo ==================================================
echo   claudeos.img built successfully!
echo.
echo   Test in QEMU:   build.bat run
echo   Flash to USB:   see README.md
echo ==================================================
echo.

if /i "%~1"=="run" goto :run
exit /b 0

REM ---------------------------------------------------------------------------
REM Launch in QEMU
REM ---------------------------------------------------------------------------
:run
where qemu-system-x86_64 >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: qemu-system-x86_64.exe not found in PATH.
    echo.
    echo  Download QEMU for Windows from:
    echo    https://www.qemu.org/download/#windows
    echo  Install it, add the install folder to PATH, then re-run:
    echo    build.bat run
    echo.
    pause
    exit /b 1
)

echo Launching ClaudeOS in QEMU...
echo Close the QEMU window to stop.
echo.
qemu-system-x86_64 -drive file=claudeos.img,format=raw,if=floppy -m 4M -display sdl -no-reboot
exit /b 0

REM ---------------------------------------------------------------------------
REM Clean
REM ---------------------------------------------------------------------------
:clean
echo Cleaning...
if exist build\boot.bin   del /q build\boot.bin
if exist build\kernel.bin del /q build\kernel.bin
if exist claudeos.img     del /q claudeos.img
if exist build            rd build
echo Done.
exit /b 0
