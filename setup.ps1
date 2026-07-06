#Requires -Version 5.1
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$INSTALL_DIR  = "$env:USERPROFILE\.cirs"
$WORKSPACE    = "$env:USERPROFILE\CIRS_Workspace"
$CONFIG_DIR   = "$env:USERPROFILE\.cirs"
$REPACK_FILE  = Join-Path $PSScriptRoot "core.repack"

$REQUIRED_PACKAGES = "textual","fastapi","uvicorn","httpx","psutil","litellm","rich","pydantic"

function Msg([string]$t,[string]$m){
    $col = switch($t){
        "STEP" {"Yellow"} "OK" {"Green"} "FAIL" {"Red"}
        "INFO" {"Gray"} "HEAD" {"Cyan"} default {"White"}
    }
    Write-Host "  [$t] $m" -ForegroundColor $col
}

Write-Host ""
Write-Host "  CIRS Innovation Engine v2.0 - Setup" -ForegroundColor Cyan
Write-Host "  Critical Innovation and Research System" -ForegroundColor DarkCyan
Write-Host ""

# Step 1: Verify core.repack
Msg "STEP" "Verifying core.repack..."
if (-not (Test-Path $REPACK_FILE)) {
    Msg "FAIL" "core.repack not found. Place core.repack next to setup.ps1"
    exit 1
}
$sz = [math]::Round((Get-Item $REPACK_FILE).Length / 1024, 1)
Msg "OK" "core.repack found - $sz KB"

# Step 2: Find or install Python
Msg "STEP" "Checking Python 3.10+..."
$pythonCmd = $null
$pythonPaths = @("python","python3","py",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python310\python.exe",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python311\python.exe",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python312\python.exe",
    "C:\Python310\python.exe","C:\Python311\python.exe","C:\Python312\python.exe"
)
foreach ($cmd in $pythonPaths) {
    try {
        $raw = & $cmd --version 2>&1
        if ("$raw" -match "Python (\d+)\.(\d+)") {
            $maj = [int]$Matches[1]; $min = [int]$Matches[2]
            if ($maj -ge 3 -and $min -ge 10) {
                $pythonCmd = $cmd
                Msg "OK" "Python $maj.$min detected"
                break
            }
        }
    } catch {}
}
if (-not $pythonCmd) {
    Msg "STEP" "Python 3.11+ not found. Attempting winget install..."
    try {
        winget install --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        Msg "OK" "Python installed via winget."
        $pythonCmd = "python"
    } catch {
        Msg "FAIL" "Could not auto-install Python. Install Python 3.11+ from https://python.org and re-run setup.ps1"
        exit 1
    }
}

# Step 3: Install packages
Msg "STEP" "Checking Python packages..."
& $pythonCmd -m pip install --upgrade pip --quiet 2>&1 | Out-Null
$toInstall = @()
foreach ($pkg in $REQUIRED_PACKAGES) {
    $check = & $pythonCmd -c "import importlib.util; spec=importlib.util.find_spec('$pkg'); exit(0 if spec else 1)" 2>&1
    if ($LASTEXITCODE -ne 0) { $toInstall += $pkg }
}
if ($toInstall.Count -eq 0) {
    Msg "OK" "All packages already installed."
} else {
    Msg "STEP" "Installing $($toInstall.Count) package(s)..."
    foreach ($pkg in $toInstall) {
        Msg "INFO" "pip install $pkg"
        & $pythonCmd -m pip install $pkg --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Msg "FAIL" "Failed: $pkg"; exit 1 }
    }
    Msg "OK" "All packages installed."
}

# Step 4: Create dirs
Msg "STEP" "Creating workspace and config directories..."
foreach ($d in @($INSTALL_DIR,"$WORKSPACE","$WORKSPACE\output","$WORKSPACE\sessions")) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}
$cfgFile = Join-Path $CONFIG_DIR "config.json"
if (-not (Test-Path $cfgFile)) {
    $cfg = '{"default_provider":null,"default_model":null,"api_keys":{},"timeout":60,"max_retries":3,"debug":false,"output_language":"en"}'
    Set-Content -Path $cfgFile -Value $cfg -Encoding UTF8
}
Msg "OK" "Directories ready."

# Step 5: Copy core files
Msg "STEP" "Installing core files to $INSTALL_DIR..."
Copy-Item -Path $REPACK_FILE -Destination $INSTALL_DIR -Force

# Write the inline loader to install dir
$loaderDst = Join-Path $INSTALL_DIR "_cirs_loader.py"
$wksp_escaped = $WORKSPACE -replace '\\', '\\\\'
$cfg_escaped  = $CONFIG_DIR -replace '\\', '\\\\'

$loader = @"
import sys, os, struct, hashlib, zlib, zipfile, io, importlib, types
from pathlib import Path
_MAGIC = b'CIRS\x1a\x01'
_PACK  = Path(r'$INSTALL_DIR') / 'core.repack'
_WKSP  = Path(r'$WORKSPACE')
_CFG   = Path(r'$CONFIG_DIR')
os.environ.setdefault('CIRS_WORKSPACE', str(_WKSP))
os.environ.setdefault('CIRS_CONFIG', str(_CFG))
sys.path.insert(0, str(_WKSP / 'sessions'))

def _xor(data, key):
    ks, seed = b'', key
    while len(ks) < len(data):
        seed = hashlib.sha256(seed).digest(); ks += seed
    return bytes(a^b for a,b in zip(data, ks))

def _load(pw):
    raw = _PACK.read_bytes()
    if raw[:6] != _MAGIC: raise RuntimeError('Invalid core.repack')
    salt = raw[7:23]; hmac_in = raw[31:63]; enc = raw[63:]
    key  = hashlib.pbkdf2_hmac('sha256', pw.encode(), salt, 200_000, dklen=32)
    if hashlib.sha256(salt + enc + key).digest() != hmac_in:
        raise RuntimeError('Authentication failed')
    return zlib.decompress(_xor(enc, key))

def _inject(zip_data):
    vfs = zipfile.ZipFile(io.BytesIO(zip_data))
    def mk(name, code, pkg=False):
        m = types.ModuleType(name); m.__package__ = name if pkg else name.rpartition('.')[0]
        m.__path__ = [] if pkg else None; m.__file__ = '<repack>'; m.__spec__ = None
        sys.modules[name] = m; exec(compile(code, f'<repack:{name}>', 'exec'), m.__dict__); return m
    deferred = {}
    for f in sorted(vfs.namelist()):
        if not f.endswith('.py') or f in ('tui.py','server/main.py'): continue
        parts = f[:-3].split('/'); dotname = '.'.join(parts); code = vfs.read(f).decode()
        if parts[-1] == '__init__': mk('.'.join(parts[:-1]), code, pkg=True)
        else: deferred[dotname] = code
    for n,c in deferred.items():
        if n not in sys.modules: mk(n, c)
    return vfs.read('tui.py').decode() if 'tui.py' in vfs.namelist() else None

if __name__ == '__main__':
    try:
        tui = _inject(_load('MYTZ_DEV_CZ'))
        if not tui: print('ERROR: tui.py missing from repack'); sys.exit(1)
        exec(compile(tui, '<tui>', 'exec'), {'__name__': '__main__'})
    except RuntimeError as e:
        print(f'CIRS: {e}'); sys.exit(1)
"@
Set-Content -Path $loaderDst -Value $loader -Encoding UTF8
Msg "OK" "Core installed to $INSTALL_DIR"

# Step 6: Register 'cirs' command
Msg "STEP" "Registering 'cirs' command..."

$cmdBatch = Join-Path $INSTALL_DIR "cirs.cmd"
$batchTxt = "@echo off`r`n`"$pythonCmd`" `"$loaderDst`" %*"
Set-Content -Path $cmdBatch -Value $batchTxt -Encoding ASCII

$curPath = [System.Environment]::GetEnvironmentVariable("PATH","User")
if ($curPath -notlike "*$INSTALL_DIR*") {
    [System.Environment]::SetEnvironmentVariable("PATH","$curPath;$INSTALL_DIR","User")
    Msg "INFO" "Added $INSTALL_DIR to PATH"
}

# Also refresh current session
$env:PATH = "$env:PATH;$INSTALL_DIR"

Msg "OK" "'cirs' command registered."

# Summary
Write-Host ""
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  HOW TO START" -ForegroundColor White
Write-Host "    Open a new terminal and type:  cirs" -ForegroundColor Yellow
Write-Host ""
Write-Host "  OUTPUT LOCATION" -ForegroundColor White
Write-Host "    $WORKSPACE\output\" -ForegroundColor Gray
Write-Host ""
Write-Host "  CONFIG FILE (API Keys)" -ForegroundColor White
Write-Host "    $CONFIG_DIR\config.json" -ForegroundColor Gray
Write-Host ""
Write-Host "  SESSION CACHE (for /continue)" -ForegroundColor White
Write-Host "    $WORKSPACE\sessions\" -ForegroundColor Gray
Write-Host ""
