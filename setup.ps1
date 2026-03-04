#Requires -Version 5.1
<#
.SYNOPSIS
    Install chap on Windows.

.DESCRIPTION
    Installs chap and its dependencies to a user-accessible location.
    Creates a chap.cmd wrapper in a directory that's added to PATH.

.PARAMETER InstallDir
    Installation directory. Defaults to %LOCALAPPDATA%\chap

.EXAMPLE
    .\setup.ps1
    
.EXAMPLE
    .\setup.ps1 -InstallDir "C:\Tools\chap"
#>

[CmdletBinding()]
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\chap"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------

function Write-Header {
    $title = @"

  +-----------------------------+
  |       chap  installer       |
  +-----------------------------+

"@
    Write-Host $title -ForegroundColor Magenta
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host $Title -ForegroundColor White
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-LogOk {
    param([string]$Message)
    Write-Host "[ OK ] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-LogWarn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-LogFail {
    param([string]$Message)
    Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
    Write-Host $Message
    exit 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Header

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------

Write-Section "Checking dependencies"

# Check for ffmpeg
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpeg) {
    $ffmpegVersion = (ffmpeg -version 2>&1 | Select-Object -First 1) -replace 'ffmpeg version\s+', ''
    Write-LogOk "ffmpeg found  ($ffmpegVersion)"
} else {
    Write-LogWarn "ffmpeg is not installed or not in PATH."
    Write-Host ""
    Write-Host "  Install ffmpeg using one of these methods:" -ForegroundColor Yellow
    Write-Host "    winget install ffmpeg" -ForegroundColor Cyan
    Write-Host "    choco install ffmpeg" -ForegroundColor Cyan
    Write-Host "    scoop install ffmpeg" -ForegroundColor Cyan
    Write-Host "    https://ffmpeg.org/download.html" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  After installing, reopen your terminal and run this setup again." -ForegroundColor Yellow
    Write-Host ""
    $continue = Read-Host "Continue anyway? (y/N)"
    if ($continue -notmatch '^[Yy]') {
        exit 1
    }
}

# Check for Python
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}

if ($python) {
    $pythonVersion = & $python.Source --version 2>&1
    Write-LogOk "Python found  ($pythonVersion)"
} else {
    Write-LogFail "Python is not installed or not in PATH.`n  Install from: https://www.python.org/downloads/"
}

# ---------------------------------------------------------------------------
# Check source files
# ---------------------------------------------------------------------------

Write-Section "Checking source files"

$chapPs1 = Join-Path $ScriptDir "chap.ps1"
$helperPy = Join-Path $ScriptDir "helper.py"
$usageKdl = Join-Path $ScriptDir "chap.usage.kdl"

if (Test-Path $chapPs1) {
    Write-LogOk "chap.ps1        found in '$ScriptDir'"
} else {
    Write-LogFail "chap.ps1 not found in '$ScriptDir'.`n  Make sure you run setup.ps1 from the project directory."
}

if (Test-Path $helperPy) {
    Write-LogOk "helper.py       found in '$ScriptDir'"
} else {
    Write-LogFail "helper.py not found in '$ScriptDir'.`n  Make sure you run setup.ps1 from the project directory."
}

if (Test-Path $usageKdl) {
    Write-LogOk "chap.usage.kdl  found in '$ScriptDir'"
} else {
    Write-LogWarn "chap.usage.kdl not found — shell completions will not be available."
}

# ---------------------------------------------------------------------------
# Create installation directory
# ---------------------------------------------------------------------------

Write-Section "Installing"

if (-not (Test-Path $InstallDir)) {
    try {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Write-LogOk "Created directory: '$InstallDir'"
    } catch {
        Write-LogFail "Cannot create directory '$InstallDir': $_"
    }
} else {
    Write-LogOk "Directory exists: '$InstallDir'"
}

# ---------------------------------------------------------------------------
# Copy files
# ---------------------------------------------------------------------------

try {
    Copy-Item $chapPs1 -Destination (Join-Path $InstallDir "chap.ps1") -Force
    Write-LogOk "Installed chap.ps1      -> $(Join-Path $InstallDir 'chap.ps1')"
} catch {
    Write-LogFail "Cannot copy chap.ps1: $_"
}

try {
    Copy-Item $helperPy -Destination (Join-Path $InstallDir "helper.py") -Force
    Write-LogOk "Installed helper.py     -> $(Join-Path $InstallDir 'helper.py')"
} catch {
    Write-LogFail "Cannot copy helper.py: $_"
}

if (Test-Path $usageKdl) {
    try {
        Copy-Item $usageKdl -Destination (Join-Path $InstallDir "chap.usage.kdl") -Force
        Write-LogOk "Installed chap.usage.kdl -> $(Join-Path $InstallDir 'chap.usage.kdl')"
    } catch {
        Write-LogWarn "Cannot copy chap.usage.kdl: $_"
    }
}

# ---------------------------------------------------------------------------
# Create wrapper script (chap.cmd)
# ---------------------------------------------------------------------------

$wrapperPath = Join-Path $InstallDir "chap.cmd"
$wrapperContent = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$InstallDir\chap.ps1" %*
"@

try {
    Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding ASCII
    Write-LogOk "Created wrapper         -> $wrapperPath"
} catch {
    Write-LogFail "Cannot create wrapper script: $_"
}

# ---------------------------------------------------------------------------
# Add to PATH
# ---------------------------------------------------------------------------

Write-Section "Configuring PATH"

$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$pathEntries = $userPath -split ";"

if ($pathEntries -contains $InstallDir) {
    Write-LogOk "Installation directory already in PATH"
} else {
    try {
        $newPath = $userPath + ";" + $InstallDir
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-LogOk "Added '$InstallDir' to user PATH"
        Write-LogInfo "Restart your terminal for PATH changes to take effect."
    } catch {
        Write-LogWarn "Could not add to PATH automatically.`n  Please add '$InstallDir' to your PATH manually."
    }
}

# ---------------------------------------------------------------------------
# PowerShell alias (optional)
# ---------------------------------------------------------------------------

Write-Section "PowerShell profile"

$profileDir = Split-Path $PROFILE -Parent
$profilePath = $PROFILE

# Check if we should add to PowerShell profile
$addToProfile = $false
if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -notmatch "chap") {
        $addToProfile = $true
    } else {
        Write-LogOk "chap alias already exists in PowerShell profile"
    }
} else {
    $addToProfile = $true
}

if ($addToProfile) {
    $aliasLine = "`n# chap - Add chapters to videos`nfunction chap { & `"$InstallDir\chap.ps1`" @args }`n"
    
    try {
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        Add-Content -Path $profilePath -Value $aliasLine
        Write-LogOk "Added chap function to PowerShell profile"
        Write-LogInfo "Run '. `$PROFILE' or restart PowerShell to use it."
    } catch {
        Write-LogWarn "Could not update PowerShell profile: $_"
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Installation complete." -ForegroundColor Green
Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Try it:" -ForegroundColor White
Write-Host '  chap video.mp4 "00:00 Intro" "01:30 Main Content" "05:00 Outro"' -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note: Restart your terminal for PATH changes to take effect." -ForegroundColor Yellow
Write-Host ""
