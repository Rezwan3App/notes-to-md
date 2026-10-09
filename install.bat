@echo off
setlocal enabledelayedexpansion
title notes-to-md installer

echo.
echo  ============================================
echo   notes-to-md installer for Windows
echo  ============================================
echo.

REM ── 1. Python ────────────────────────────────────────────────────────────────
set "PY="
for %%P in (python.exe) do set "PY=%%~$PATH:P"
if not defined PY (
    for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
        if exist "%%D\python.exe" set "PY=%%D\python.exe"
    )
)

if not defined PY (
    echo  [1/3] Python not found. Installing via winget...
    winget install -e --id Python.Python.3.12 ^
        --accept-package-agreements --accept-source-agreements --silent
    if !errorlevel! neq 0 (
        echo.
        echo  Could not install Python automatically.
        echo  Please install it from https://www.python.org/downloads/
        echo  Make sure to check "Add Python to PATH" during install,
        echo  then run this installer again.
        goto :fail
    )
    REM Find it in the new default location after install
    for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
        if exist "%%D\python.exe" set "PY=%%D\python.exe"
    )
    if not defined PY set "PY=python.exe"
    echo  [1/3] Python installed.
) else (
    echo  [1/3] Python found.
)

REM ── 2. Tesseract ─────────────────────────────────────────────────────────────
set "TESS=C:\Program Files\Tesseract-OCR\tesseract.exe"
where tesseract.exe >nul 2>&1 && set "TESS=tesseract.exe"

if not exist "%TESS%" (
    where tesseract.exe >nul 2>&1
    if !errorlevel! neq 0 (
        echo  [2/3] Tesseract not found. Installing via winget...
        winget install -e --id UB-Mannheim.TesseractOCR ^
            --accept-package-agreements --accept-source-agreements --silent
        if !errorlevel! neq 0 (
            echo.
            echo  Could not install Tesseract automatically.
            echo  Please install it from:
            echo  https://github.com/UB-Mannheim/tesseract/wiki
            echo  Then run this installer again.
            goto :fail
        )
        echo  [2/3] Tesseract installed.
    )
) else (
    echo  [2/3] Tesseract found.
)

REM ── 3. Python packages ────────────────────────────────────────────────────────
echo  [3/3] Installing Python packages (pytesseract, pymupdf, Pillow)...
"%PY%" -m pip install --quiet --upgrade pytesseract pymupdf Pillow
if !errorlevel! neq 0 (
    echo.
    echo  pip install failed. Check your internet connection and try again.
    goto :fail
)

REM ── 4. Copy skill to Claude skills folder ────────────────────────────────────
set "DEST=%USERPROFILE%\.claude\skills\notes-to-md"
if not exist "%USERPROFILE%\.claude\skills" mkdir "%USERPROFILE%\.claude\skills"

echo.
if exist "%DEST%" (
    echo  Updating existing skill at %DEST%...
    rd /s /q "%DEST%"
)
mkdir "%DEST%"

set "SRC=%~dp0"
for %%F in (SKILL.md README.md LICENSE) do (
    if exist "%SRC%%%F" copy /y /q "%SRC%%%F" "%DEST%\%%F" >nul
)
if exist "%SRC%assets"   xcopy /e /y /q "%SRC%assets"   "%DEST%\assets\"   >nul
if exist "%SRC%scripts"  xcopy /e /y /q "%SRC%scripts"  "%DEST%\scripts\"  >nul

echo.
echo  ============================================
echo   Done! notes-to-md is installed.
echo  ============================================
echo.
echo  Restart Claude Code, then try asking:
echo.
echo    "turn my handwritten notes in Downloads\my-notes into markdown"
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
