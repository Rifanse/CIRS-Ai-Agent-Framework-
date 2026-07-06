#Requires -Version 5.1
param(
    [switch]$Force,
    [switch]$AutoLaunch,
    [switch]$PauseOnExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:USERPROFILE ".cirs"
$WorkspaceDir = Join-Path $env:USERPROFILE "CIRS_Workspace"
$ConfigFile = Join-Path $InstallDir "config.json"
$RepackFile = Join-Path $PSScriptRoot "core.repack"
$RequiredPackages = @("textual", "fastapi", "uvicorn", "httpx", "psutil", "rich", "pydantic")

function Write-Step([string]$Message) {
    Write-Host "[STEP] $Message" -ForegroundColor Yellow
}

function Write-Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Show-Banner {
    Write-Host ""
    Write-Host "   ____ ___ ____  ____" -ForegroundColor Green
    Write-Host "  / ___|_ _|  _ \/ ___|" -ForegroundColor Green
    Write-Host " | |    | || |_) \___ \" -ForegroundColor Cyan
    Write-Host " | |___ | ||  _ < ___) |" -ForegroundColor Cyan
    Write-Host "  \____|___|_| \_\____/" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  Critical Innovation Reasoning System" -ForegroundColor White
    Write-Host "  Installer publik untuk core.repack + runtime loader" -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-QuickGuide {
    Write-Host "Panduan singkat:" -ForegroundColor Yellow
    Write-Host "  1. /config   -> set provider + API key" -ForegroundColor Gray
    Write-Host "  2. /idea ... -> jalankan ide atau problem solving" -ForegroundColor Gray
    Write-Host "  3. /help     -> lihat command utama" -ForegroundColor Gray
    Write-Host "  4. Ctrl+C    -> keluar dari CIRS" -ForegroundColor Gray
    Write-Host ""
}

function Get-PythonCommand {
    $pythonCandidates = @(
        "python",
        "py",
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python312\python.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python311\python.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python310\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe",
        "C:\Python310\python.exe"
    )

    foreach ($candidate in $pythonCandidates) {
        try {
            $versionOutput = & $candidate --version 2>&1
            if ("$versionOutput" -match "Python (\d+)\.(\d+)") {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                if ($major -ge 3 -and $minor -ge 10) {
                    return $candidate
                }
            }
        } catch {}
    }

    return $null
}

Show-Banner

Write-Step "Memeriksa file paket"
if (-not (Test-Path $RepackFile)) {
    Fail "File core.repack tidak ditemukan. Letakkan core.repack di folder yang sama dengan setup.ps1."
}
Write-Ok "core.repack ditemukan"

Write-Step "Mencari Python 3.10+"
$PythonCmd = Get-PythonCommand
if (-not $PythonCmd) {
    Write-Info "Python belum ditemukan. Mencoba install otomatis via winget..."
    try {
        winget install --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent | Out-Null
    } catch {}
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $PythonCmd = Get-PythonCommand
}
if (-not $PythonCmd) {
    Fail "Python 3.10+ tidak ditemukan. Install Python dulu lalu jalankan setup.ps1 lagi."
}
Write-Ok "Python aktif: $PythonCmd"

Write-Step "Menyiapkan folder instalasi"
foreach ($dir in @($InstallDir, $WorkspaceDir, (Join-Path $WorkspaceDir "output"), (Join-Path $WorkspaceDir "sessions"))) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-Ok "Folder instalasi siap"

Write-Step "Menginstal dependency Python"
& $PythonCmd -m pip install --upgrade pip | Out-Null
& $PythonCmd -m pip install @RequiredPackages | Out-Null
Write-Ok "Dependency selesai dipasang"

Write-Step "Menyalin core.repack"
Copy-Item -Path $RepackFile -Destination (Join-Path $InstallDir "core.repack") -Force
Write-Ok "core.repack tersalin ke $InstallDir"

Write-Step "Membuat runtime loader"
$LoaderCode = @'
#!/usr/bin/env python3
"""CIRS encrypted runtime loader."""
from __future__ import annotations

import atexit
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
import zlib
from pathlib import Path

_MAGIC = b"CIRS\x1a\x01"
_PACK = Path(__file__).parent / "core.repack"
_PASSWORD = os.environ.get("CIRS_REPACK_KEY", "MYTZ_DEV_CZ")


def _xor(data: bytes, key: bytes) -> bytes:
    keystream = b""
    seed = key
    while len(keystream) < len(data):
        seed = hashlib.sha256(seed).digest()
        keystream += seed
    return bytes(a ^ b for a, b in zip(data, keystream))


def _decrypt(password: str) -> bytes:
    raw = _PACK.read_bytes()
    if raw[:6] != _MAGIC:
        print("CIRS: Invalid core.repack - file may be corrupted.")
        sys.exit(1)

    salt = raw[7:23]
    hmac_input = raw[31:63]
    encrypted = raw[63:]
    key = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 200_000, 32)
    if hashlib.sha256(salt + encrypted + key).digest() != hmac_input:
        print("CIRS: Authentication failed - wrong key or corrupted repack.")
        sys.exit(1)

    return zlib.decompress(_xor(encrypted, key))


def _unpack(zip_data: bytes) -> Path:
    temp_dir = Path(tempfile.mkdtemp(prefix="cirs_runtime_"))
    atexit.register(shutil.rmtree, temp_dir, ignore_errors=True)
    with zipfile.ZipFile(io.BytesIO(zip_data)) as archive:
        archive.extractall(temp_dir)
    return temp_dir


def main() -> int:
    workspace = Path(os.environ.get("CIRS_WORKSPACE", str(Path.home() / "CIRS_Workspace")))
    config_dir = Path(os.environ.get("CIRS_CONFIG", str(Path.home() / ".cirs")))
    os.environ.setdefault("CIRS_WORKSPACE", str(workspace))
    os.environ.setdefault("CIRS_CONFIG", str(config_dir))
    os.environ.setdefault("PYTHONUTF8", "1")

    zip_data = _decrypt(_PASSWORD)
    runtime_dir = _unpack(zip_data)
    tui_path = runtime_dir / "tui.py"
    if not tui_path.exists():
        print("CIRS: tui.py not found inside core.repack.")
        return 1

    env = os.environ.copy()
    env["PYTHONPATH"] = str(runtime_dir) + os.pathsep + env.get("PYTHONPATH", "")
    result = subprocess.run([sys.executable, str(tui_path), *sys.argv[1:]], env=env)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
'@
Set-Content -Path (Join-Path $InstallDir "_cirs_loader.py") -Value $LoaderCode -Encoding UTF8
Write-Ok "Loader berhasil dibuat"

Write-Step "Membuat config default"
if ($Force -or -not (Test-Path $ConfigFile)) {
    $DefaultConfig = @{
        default_provider = $null
        default_model = $null
        api_keys = @{}
        timeout = 60
        max_retries = 3
        debug = $false
        output_language = "en"
    } | ConvertTo-Json -Depth 4
    Set-Content -Path $ConfigFile -Value $DefaultConfig -Encoding ASCII
    Write-Ok "config.json dibuat"
} else {
    Write-Info "config.json sudah ada, dilewati"
}

Write-Step "Mendaftarkan command cirs"
$CommandPath = Join-Path $InstallDir "cirs.cmd"
$CommandBody = (
    "@echo off",
    "set PYTHONUTF8=1",
    ('"{0}" "{1}\_cirs_loader.py" %*' -f $PythonCmd, $InstallDir)
) -join "`r`n"
Set-Content -Path $CommandPath -Value $CommandBody -Encoding ASCII

$UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ([string]::IsNullOrWhiteSpace($UserPath)) {
    $UserPath = $InstallDir
} elseif ($UserPath -notlike "*$InstallDir*") {
    $UserPath = "$UserPath;$InstallDir"
}
[System.Environment]::SetEnvironmentVariable("PATH", $UserPath, "User")
$env:PATH = "$env:PATH;$InstallDir"
Write-Ok "Command 'cirs' sudah terdaftar"

Write-Host ""
Write-Host "Setup selesai." -ForegroundColor Green
Write-Host "Runtime: $InstallDir" -ForegroundColor Gray
Write-Host "Config API: $ConfigFile" -ForegroundColor Gray
Write-Host "Output: $(Join-Path $WorkspaceDir 'output')" -ForegroundColor Gray
Write-Host ""
Show-QuickGuide

if ($AutoLaunch) {
    Write-Step "Menjalankan CIRS otomatis"
    Write-Info "Backend Python akan dinyalakan otomatis oleh runtime saat TUI dibuka"
    & $PythonCmd (Join-Path $InstallDir "_cirs_loader.py")
    $LaunchExitCode = $LASTEXITCODE
    if ($LaunchExitCode -ne 0) {
        Write-Host ""
        Write-Host "[WARN] CIRS keluar dengan kode $LaunchExitCode" -ForegroundColor Yellow
    }
} else {
    Write-Host "Buka terminal baru lalu jalankan: cirs" -ForegroundColor Yellow
    Write-Host ""
}

if ($PauseOnExit) {
    Read-Host "Tekan Enter untuk menutup jendela PowerShell"
}
