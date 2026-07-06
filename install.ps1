#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SetupScript = Join-Path $PSScriptRoot "setup.ps1"

if (-not (Test-Path $SetupScript)) {
    Write-Host "[FAIL] setup.ps1 tidak ditemukan di folder ini." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "CIRS Public Installer" -ForegroundColor Cyan
Write-Host "Menjalankan setup utama..." -ForegroundColor DarkCyan
Write-Host ""

& powershell -NoProfile -ExecutionPolicy Bypass -File $SetupScript
exit $LASTEXITCODE
