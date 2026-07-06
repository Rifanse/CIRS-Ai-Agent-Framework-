#Requires -Version 5.1
param(
    [switch]$NoAutoLaunch,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRawBase = "https://raw.githubusercontent.com/Rifanse/CIRS-Ai-Agent-Framework-/main"
$RepoCdnBase = "https://cdn.jsdelivr.net/gh/Rifanse/CIRS-Ai-Agent-Framework-@main"
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

function Show-Banner {
    Write-Host ""
    Write-Host "   ____ ___ ____  ____" -ForegroundColor Green
    Write-Host "  / ___|_ _|  _ \/ ___|" -ForegroundColor Green
    Write-Host " | |    | || |_) \___ \" -ForegroundColor Cyan
    Write-Host " | |___ | ||  _ < ___) |" -ForegroundColor Cyan
    Write-Host "  \____|___|_| \_\____/" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  Critical Innovation Reasoning System" -ForegroundColor White
    Write-Host "  Bootstrap installer untuk local file atau GitHub raw" -ForegroundColor DarkCyan
    Write-Host ""
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

function Download-FileWithFallback {
    param(
        [string]$Label,
        [string[]]$Urls,
        [string]$OutFile
    )

    $headers = @{
        "User-Agent" = "CIRS-Installer/1.0"
        "Accept" = "*/*"
        "Cache-Control" = "no-cache"
    }

    foreach ($url in $Urls) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Info ("Mengunduh {0} ({1}/3) dari: {2}" -f $Label, $attempt, $url)
                Invoke-WebRequest -Uri $url -OutFile $OutFile -Headers $headers -UseBasicParsing

                if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
                    Write-Ok "$Label berhasil diunduh"
                    return
                }
            } catch {
                $statusCode = $null
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                } catch {
                    $statusCode = $null
                }

                if ($statusCode -eq 429) {
                    Write-Info "$Label kena rate limit (429). Mencoba mirror/fallback..."
                } else {
                    Write-Info ("Download {0} gagal: {1}" -f $Label, $_.Exception.Message)
                }
            }

            Start-Sleep -Seconds $attempt
        }
    }

    Fail "Gagal mengunduh $Label dari semua sumber yang tersedia."
}

function Download-InstallerFiles([string]$DestinationDir) {
    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $setupPath = Join-Path $DestinationDir "setup.ps1"
    $repackPath = Join-Path $DestinationDir "core.repack"
    $setupUrls = @(
        "$RepoRawBase/setup.ps1",
        "$RepoCdnBase/setup.ps1"
    )
    $repackUrls = @(
        "$RepoRawBase/core.repack",
        "$RepoCdnBase/core.repack"
    )

    Download-FileWithFallback -Label "setup.ps1" -Urls $setupUrls -OutFile $setupPath
    Download-FileWithFallback -Label "core.repack" -Urls $repackUrls -OutFile $repackPath

    if (-not (Test-Path $setupPath)) {
        Fail "Gagal mengunduh setup.ps1"
    }
    if (-not (Test-Path $repackPath)) {
        Fail "Gagal mengunduh core.repack"
    }

    Write-Ok "File installer berhasil diunduh"
    return $setupPath
}

Show-Banner

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
$ShouldAutoLaunch = -not $NoAutoLaunch
$ShouldPause = -not $NoPause
& $SetupScript -AutoLaunch:$ShouldAutoLaunch -PauseOnExit:$ShouldPause
exit $LASTEXITCODE
