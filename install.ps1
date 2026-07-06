$InstallDir = "$env:USERPROFILE\.cirs"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# â”€â”€â”€ ANSI Color Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$ESC = [char]27
function c([string]$t) { "$ESC[${t}m" }
$CYAN    = c "96"; $YELLOW = c "93"; $GREEN = c "92"
$RED     = c "91"; $GRAY   = c "90"; $WHITE  = c "97"
$BOLD    = c "1";  $RESET  = c "0"

function Logo {
    Write-Host ""
    Write-Host "${CYAN}${BOLD}   ______   _____   ______    _____   ${RESET}"
    Write-Host "${CYAN}${BOLD}  / ____/  /  _/  / __ \ \  / ___/   ${RESET}"
    Write-Host "${CYAN}${BOLD} / /       / /   / /_/ /\ \/ /\__ \   ${RESET}"
    Write-Host "${CYAN}${BOLD}/ /___   _/ /   / _, _/  \  /___/ /   ${RESET}"
    Write-Host "${CYAN}${BOLD}\____/  /___/  /_/ |_|    \/ /____/   ${RESET}"
    Write-Host ""
    Write-Host "${YELLOW}${BOLD}  AGENTIC FRAMEWORK  |  v2.0  |  MYTZ_DEV${RESET}"
    Write-Host "${GRAY}  Critical Innovation and Research System  ${RESET}"
    Write-Host ""
}

function Step([string]$m) { Write-Host "${YELLOW}  [ > ] $m${RESET}" }
function OK([string]$m)   { Write-Host "${GREEN}  [ + ] $m${RESET}" }
function Fail([string]$m) { Write-Host "${RED}  [ ! ] $m${RESET}"; exit 1 }
function Info([string]$m) { Write-Host "${GRAY}        $m${RESET}" }

Logo

Write-Host "${BOLD}${WHITE}  Installing CIRS Agentic Framework...${RESET}"
Write-Host ""

$WORKSPACE = "$env:USERPROFILE\CIRS_Workspace"
$REQUIRED  = "textual","fastapi","uvicorn","httpx","psutil","litellm","rich","pydantic"

# â”€â”€â”€ Step 1: Find Python â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Step "Detecting Python 3.10+..."
$py = $null
$candidates = @("python","python3","py",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python312\python.exe",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python311\python.exe",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python310\python.exe",
    "C:\Python312\python.exe","C:\Python311\python.exe","C:\Python310\python.exe")
foreach ($c in $candidates) {
    try {
        $v = & $c --version 2>&1
        if ("$v" -match "Python (\d+)\.(\d+)" -and [int]$Matches[1] -ge 3 -and [int]$Matches[2] -ge 10) {
            $py = $c; OK "Python $($Matches[1]).$($Matches[2]) found"; break
        }
    } catch {}
}
if (-not $py) {
    Step "Python not found. Installing via winget..."
    try {
        winget install --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        $py = "python"; OK "Python installed."
    } catch { Fail "Cannot install Python. Visit https://python.org" }
}

# â”€â”€â”€ Step 2: Packages â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Step "Installing Python packages..."
try { & $py -m pip uninstall -y cirs --quiet 2>&1 | Out-Null } catch {}
& $py -m pip install --upgrade pip --quiet 2>&1 | Out-Null
$miss = @()
foreach ($pkg in $REQUIRED) {
    $r = & $py -c "import importlib.util; exit(0 if importlib.util.find_spec('$pkg') else 1)" 2>&1
    if ($LASTEXITCODE -ne 0) { $miss += $pkg }
}
if ($miss.Count -gt 0) {
    foreach ($pkg in $miss) {
        Info "pip install $pkg"
        & $py -m pip install $pkg --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Failed: $pkg" }
    }
}
OK "All packages ready."

# â”€â”€â”€ Step 3: Directories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Step "Preparing workspace..."
@($InstallDir,"$WORKSPACE","$WORKSPACE\output","$WORKSPACE\sessions") | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}
$cfgFile = "$InstallDir\config.json"
if (-not (Test-Path $cfgFile)) {
    '{"default_provider":null,"default_model":null,"api_keys":{},"timeout":60,"max_retries":3,"debug":false}' | Set-Content $cfgFile -Encoding UTF8
}
OK "Workspace ready: $WORKSPACE"

# â”€â”€â”€ Step 4: Write core.repack from embedded base64 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Step "Decoding and writing core.repack..."
$b64 = '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'
  $raw = [Convert]::FromBase64String($b64)
  [IO.File]::WriteAllBytes("$InstallDir\core.repack", $raw)
  OK "core.repack written."
  # â”€â”€â”€ Done: Print Tutorial â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ""
Write-Host "${CYAN}${BOLD}  ====================================================${RESET}"
Write-Host "${GREEN}${BOLD}  CIRS is ready.${RESET}"
Write-Host "${CYAN}${BOLD}  ====================================================${RESET}"
Write-Host ""
Write-Host "${BOLD}${WHITE}  QUICK START${RESET}"
Write-Host "${YELLOW}  Open a NEW terminal window and type:${RESET}"
Write-Host ""
Write-Host "${BOLD}${CYAN}      cirs${RESET}"
Write-Host ""
Write-Host "${GRAY}  That's all. CIRS will guide you through the rest.${RESET}"
Write-Host ""
Write-Host "${BOLD}${WHITE}  WHAT HAPPENS NEXT${RESET}"
Write-Host "${GRAY}  1. CIRS opens its terminal interface${RESET}"
Write-Host "${GRAY}  2. First launch prompts for your AI provider and API key${RESET}"
Write-Host "${GRAY}  3. Type any problem or topic to start the 12-stage pipeline${RESET}"
Write-Host ""
Write-Host "${BOLD}${WHITE}  COMMANDS (inside CIRS)${RESET}"
Write-Host "${GRAY}  <your problem>      Run full 12-stage innovation pipeline${RESET}"
Write-Host "${GRAY}  /research <topic>   Deep research only${RESET}"
Write-Host "${GRAY}  /continue           Resume an interrupted session${RESET}"
Write-Host "${GRAY}  /config             Change API key or provider${RESET}"
Write-Host "${GRAY}  /help               Show all commands${RESET}"
Write-Host ""
Write-Host "${BOLD}${WHITE}  OUTPUT LOCATION${RESET}"
Write-Host "${GRAY}  $WORKSPACE\output\${RESET}"
Write-Host ""
Write-Host "${YELLOW}  Restart your terminal before running 'cirs'${RESET}"
Write-Host ""







