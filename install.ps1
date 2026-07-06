#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRawBase = "https://raw.githubusercontent.com/Rifanse/CIRS-Ai-Agent-Framework-/main"
$TempBootstrapDir = Join-Path $env:TEMP "cirs_bootstrap"

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Get-LocalScriptRoot {
    if (($PSScriptRoot -is [string]) -and (-not [string]::IsNullOrWhiteSpace($PSScriptRoot))) {
        return $PSScriptRoot
    }

    if (($PSCommandPath -is [string]) -and (-not [string]::IsNullOrWhiteSpace($PSCommandPath))) {
        return (Split-Path -Parent $PSCommandPath)
    }

    if ($MyInvocation -and $MyInvocation.MyCommand) {
        $commandPath = $null

        try {
            $commandPath = $MyInvocation.MyCommand.Path
        } catch {
            $commandPath = $null
        }

        if (($commandPath -is [string]) -and (-not [string]::IsNullOrWhiteSpace($commandPath))) {
            return (Split-Path -Parent $commandPath)
        }
    }

    return $null
}

function Download-InstallerFiles([string]$DestinationDir) {
    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $setupUrl = "$RepoRawBase/setup.ps1"
    $repackUrl = "$RepoRawBase/core.repack"
    $setupPath = Join-Path $DestinationDir "setup.ps1"
    $repackPath = Join-Path $DestinationDir "core.repack"

    Write-Info "Mengunduh setup.ps1 dari GitHub..."
    Invoke-WebRequest -Uri $setupUrl -OutFile $setupPath

    Write-Info "Mengunduh core.repack dari GitHub..."
    Invoke-WebRequest -Uri $repackUrl -OutFile $repackPath

    if (-not (Test-Path $setupPath)) {
        Fail "Gagal mengunduh setup.ps1"
    }
    if (-not (Test-Path $repackPath)) {
        Fail "Gagal mengunduh core.repack"
    }

    Write-Ok "File installer berhasil diunduh"
    return $setupPath
}

Write-Host ""
Write-Host "CIRS Public Installer" -ForegroundColor Cyan
Write-Host "Bootstrap installer untuk local file atau GitHub raw" -ForegroundColor DarkCyan
Write-Host ""

$ScriptRoot = Get-LocalScriptRoot
$SetupScript = $null

if ($ScriptRoot) {
    $Candidate = Join-Path $ScriptRoot "setup.ps1"
    $CandidateRepack = Join-Path $ScriptRoot "core.repack"
    if ((Test-Path $Candidate) -and (Test-Path $CandidateRepack)) {
        Write-Info "Mode lokal terdeteksi"
        $SetupScript = $Candidate
    }
}

if (-not $SetupScript) {
    Write-Info "Mode remote/raw terdeteksi, menyiapkan file bootstrap..."
    $SetupScript = Download-InstallerFiles -DestinationDir $TempBootstrapDir
}

if (-not (Test-Path $SetupScript)) {
    Fail "setup.ps1 tidak ditemukan."
}

Write-Info "Menjalankan setup utama..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $SetupScript
exit $LASTEXITCODE
