@echo off
REM ===========================================================================
REM build.bat - ClaudeOS Build Script
REM ===========================================================================
setlocal

if /i "%~1"=="clean" goto :clean

set "NASM=nasm"
where nasm >nul 2>&1
if errorlevel 1 (
    if exist "%~dp0nasm.exe" ( set "NASM=%~dp0nasm.exe" ) else (
        echo ERROR: nasm not found. & pause & exit /b 1
    )
)

if not exist build md build

echo [1/5] Assembling stage 1...
"%NASM%" -f bin -o build\boot.bin boot.asm
if errorlevel 1 ( echo FAILED: boot.asm & exit /b 1 )
for %%F in (build\boot.bin) do set S=%%~zF
if not "%S%"=="512" ( echo ERROR: boot.bin must be 512 bytes & exit /b 1 )
echo  OK  boot.bin [512 bytes]

echo [2/5] Assembling stage 2...
"%NASM%" -f bin -o build\stage2.bin stage2.asm
if errorlevel 1 ( echo FAILED: stage2.asm & exit /b 1 )
for %%F in (build\stage2.bin) do echo  OK  stage2.bin [%%~zF bytes]

echo [3/5] Assembling kernel...
"%NASM%" -f bin -o build\kernel.bin kernel.asm
if errorlevel 1 ( echo FAILED: kernel.asm & exit /b 1 )
for %%F in (build\kernel.bin) do echo  OK  kernel.bin [%%~zF bytes]

echo [4/5] Packing filesystem...
python mkfs.py
if errorlevel 1 ( echo FAILED: mkfs.py & exit /b 1 )

echo [5/5] Building disk image...

REM Layout (all LBA-based, 512 bytes/sector):
REM   LBA 0       = boot.bin   (byte 0)
REM   LBA 1-2     = stage2.bin (byte 512)
REM   LBA 3..202  = kernel.bin (byte 1536)
REM   LBA 203+    = fs.bin     (byte 103936)
set "PS1=%TEMP%\claudeos_build.ps1"
(
    echo $img    = New-Object byte[] ^(2880 * 512^)
    echo $boot   = [IO.File]::ReadAllBytes^('build\boot.bin'^)
    echo $stage2 = [IO.File]::ReadAllBytes^('build\stage2.bin'^)
    echo $kern   = [IO.File]::ReadAllBytes^('build\kernel.bin'^)
    echo $fs     = [IO.File]::ReadAllBytes^('build\fs.bin'^)
    echo [Array]::Copy^($boot,   0, $img,      0, $boot.Length^)
    echo [Array]::Copy^($stage2, 0, $img,    512, $stage2.Length^)
    echo [Array]::Copy^($kern,   0, $img,   1536, $kern.Length^)
    echo [Array]::Copy^($fs,     0, $img, 103936, $fs.Length^)
    echo [IO.File]::WriteAllBytes^('claudeos.img', $img^)
    echo Write-Host ' OK  claudeos.img'
) > "%PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
del "%PS1%" >nul 2>&1
if errorlevel 1 ( echo FAILED: image creation & exit /b 1 )

echo.
echo ================================
echo   claudeos.img built!
echo ================================

if /i "%~1"=="run" goto :run
exit /b 0

:run
qemu-system-x86_64 -drive file=claudeos.img,format=raw,if=floppy -m 32M -display sdl -no-reboot -nic user,model=e1000
exit /b 0

:clean
echo Cleaning...
if exist build\boot.bin   del /q build\boot.bin
if exist build\stage2.bin del /q build\stage2.bin
if exist build\kernel.bin del /q build\kernel.bin
if exist build\fs.bin     del /q build\fs.bin
if exist claudeos.img     del /q claudeos.img
if exist build            rd build
echo Done.
exit /b 0