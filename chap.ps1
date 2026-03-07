#Requires -Version 5.1
<#
.SYNOPSIS
    Add chapters to an MP4 or MKV video using ffmpeg.

.DESCRIPTION
    chap embeds chapter metadata into any existing MP4 or MKV file using
    ffmpeg's stream copy mode — no re-encoding, no quality loss.

.PARAMETER InputVideo
    Path to the source MP4 or MKV file (required).

.PARAMETER Chapters
    One or more inline chapter definitions, e.g. "00:00 Intro" "01:30 Main".

.PARAMETER File
    Read chapters from a .txt file (one "TIMESTAMP Title" per line).

.PARAMETER Output
    Set the output file path/name.

.PARAMETER Overwrite
    Overwrite the input file in place.

.PARAMETER Help
    Show help message.

.PARAMETER UsageSpec
    Print the KDL spec for shell completion generation (internal use).

.EXAMPLE
    chap video.mp4 "00:00 Intro" "01:30 Main Content" "05:00 Outro"

.EXAMPLE
    chap video.mp4 -f chapters.txt

.EXAMPLE
    chap video.mp4 -f chapters.txt "45:00 Bonus"

.EXAMPLE
    chap video.mp4 "00:00 Intro" "02:00 Demo" -o final/output.mp4

.EXAMPLE
    chap video.mp4 "00:00 Intro" "02:00 Demo" -w
#>

[CmdletBinding(DefaultParameterSetName = "Default")]
param(
    [Parameter(Position = 0, ParameterSetName = "Default")]
    [string]$InputVideo,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true, ParameterSetName = "Default")]
    [string[]]$Chapters,

    [Parameter(ParameterSetName = "Default")]
    [Alias("f")]
    [string]$File,

    [Parameter(ParameterSetName = "Default")]
    [Alias("o")]
    [string]$Output,

    [Parameter(ParameterSetName = "Default")]
    [Alias("w")]
    [switch]$Overwrite,

    [Parameter(ParameterSetName = "Default")]
    [Parameter(ParameterSetName = "Help")]
    [Alias("h")]
    [switch]$Help,

    [Parameter(ParameterSetName = "UsageSpec")]
    [switch]$UsageSpec
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Determine script/install location for helper.py
# ---------------------------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Check multiple locations for helper.py
$HelperLocations = @(
    (Join-Path $ScriptDir "helper.py"),                          # Same directory as script
    (Join-Path $env:LOCALAPPDATA "chap\helper.py"),              # Windows install location
    "/usr/local/lib/chap/helper.py"                               # Linux/macOS install location
)

$Helper = $null
foreach ($loc in $HelperLocations) {
    if (Test-Path $loc) {
        $Helper = $loc
        break
    }
}

$SpecLocations = @(
    (Join-Path $ScriptDir "chap.usage.kdl"),
    (Join-Path $env:LOCALAPPDATA "chap\chap.usage.kdl"),
    "/usr/local/lib/chap/chap.usage.kdl"
)

$Spec = $null
foreach ($loc in $SpecLocations) {
    if (Test-Path $loc) {
        $Spec = $loc
        break
    }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Test-TtyColors {
    if ($env:NO_COLOR) { return $false }
    return $Host.UI.SupportsVirtualTerminal -or ($Host.Name -eq "ConsoleHost")
}

function Write-LogInfo {
    param([string]$Message)
    if (Test-TtyColors) {
        Write-Host "`e[0;36m[INFO]`e[0m $Message" -NoNewline
        Write-Host ""
    } else {
        Write-Host "[INFO] $Message"
    }
}

function Write-LogOk {
    param([string]$Message)
    if (Test-TtyColors) {
        Write-Host "`e[0;32m[ OK ]`e[0m $Message" -NoNewline
        Write-Host ""
    } else {
        Write-Host "[ OK ] $Message"
    }
}

function Write-LogWarn {
    param([string]$Message)
    if (Test-TtyColors) {
        Write-Host "`e[0;33m[WARN]`e[0m $Message" -NoNewline
        Write-Host ""
    } else {
        Write-Host "[WARN] $Message"
    }
}

function Write-LogFail {
    param([string]$Message)
    if (Test-TtyColors) {
        Write-Host "`e[1;31m[FAIL]`e[0m $Message" -NoNewline
        Write-Host ""
    } else {
        Write-Host "[FAIL] $Message"
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

function Show-Usage {
    $usage = @"
Usage: chap <input_video> ["MM:SS Title" ...] [-f chapters.txt] [-o output] [-w]

Arguments:
  <input_video>       Path to the source MP4 or MKV file (required)
  "MM:SS Title"       One or more inline chapter definitions (optional)

Options:
  -f <file>           Read chapters from a .txt file
  -o <path>           Output file path/name (default: <name>_chap.<ext>)
  -w                  Overwrite the input file in place
  -h, -Help           Show this help message

Notes:
  - At least one chapter source (-f or inline args) is required.
  - -o and -w are mutually exclusive.
  - When using -f and inline args together, file chapters come first.
  - Supported formats: MP4, MKV.

Chapter file format (.txt):
  # This is a comment
  00:00 Intro
  01:30 Main Content
  05:00 Outro
"@
    Write-Host $usage
    exit 0
}

function Show-UsageSpec {
    if ($Spec -and (Test-Path $Spec)) {
        Get-Content $Spec -Raw
    } else {
        # Fallback: emit the spec inline so completions work even before install
        @'
name chap
bin chap
about "Add chapters to MP4 and MKV videos — no re-encoding, no quality loss."

arg <input_video> help="Path to the source MP4 or MKV file"

arg "[CHAPTERS]…" help="Inline chapter definitions, e.g. \"00:00 Intro\" \"01:30 Main Content\"" required=#false var=#true

flag "-f --file" help="Read chapters from a .txt file (one 'TIMESTAMP Title' per line)" {
    arg <FILE>
}

flag "-o --output" help="Output file path/name (default: <name>_chap.<ext> in the same directory)" {
    arg <PATH>
}

flag "-w --overwrite" help="Overwrite the input file in place (mutually exclusive with -o)"

flag "-h --help" help="Print help"
'@
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Handle special flags first
if ($UsageSpec) {
    Show-UsageSpec
}

if ($Help -or (-not $InputVideo -and -not $File -and -not $Chapters)) {
    Show-Usage
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

if (-not $InputVideo) {
    Write-LogFail "No input file specified. Run 'chap -Help' for usage."
}

if (-not (Test-Path $InputVideo)) {
    Write-LogFail "Input file not found: '$InputVideo'"
}

$Extension = [System.IO.Path]::GetExtension($InputVideo).ToLower()
if ($Extension -notin @(".mp4", ".mkv")) {
    Write-LogFail "Unsupported file format: '$Extension'. Only MP4 and MKV are supported."
}

if (-not $File -and (-not $Chapters -or $Chapters.Count -eq 0)) {
    Write-LogFail "No chapters provided. Use -f <file> and/or inline 'MM:SS Title' arguments."
}

if ($Overwrite -and $Output) {
    Write-LogFail "-o and -w are mutually exclusive. Use one or the other."
}

if (-not $Helper) {
    Write-LogFail "helper.py not found. Please run setup.ps1 to install chap."
}

# Find Python
$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) {
    $Python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $Python) {
    Write-LogFail "Python is not installed or not in PATH.`n  Install from: https://www.python.org/downloads/"
}
$PythonExe = $Python.Source

# Find ffmpeg
$FFmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $FFmpeg) {
    Write-LogFail "ffmpeg is not installed or not in PATH.`n  Install using: winget install ffmpeg"
}

# ---------------------------------------------------------------------------
# Determine output path
# ---------------------------------------------------------------------------

$InputPath = Resolve-Path $InputVideo
$InputDir = Split-Path $InputPath -Parent
$InputBase = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)

if ($Overwrite) {
    $TmpOutput = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', $Extension
    $FinalOutput = $InputPath
} elseif ($Output) {
    $TmpOutput = $Output
    $FinalOutput = $Output
} else {
    $TmpOutput = Join-Path $InputDir "$($InputBase)_chap$Extension"
    $FinalOutput = $TmpOutput
}

# ---------------------------------------------------------------------------
# Build helper.py arguments
# ---------------------------------------------------------------------------

$HelperArgs = @()
if ($File) {
    $HelperArgs += "-f"
    $HelperArgs += $File
}
if ($Chapters) {
    $HelperArgs += $Chapters
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

$MetaFile = $null

try {
    Write-LogInfo "Generating chapter metadata..."
    
    $MetaFile = & $PythonExe $Helper @HelperArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        exit 1
    }
    $MetaFile = $MetaFile | Select-Object -Last 1  # Get the last line (the path)

    Write-LogInfo "Embedding chapters into video..."

    $ffmpegArgs = @(
        "-loglevel", "error",
        "-i", $InputPath,
        "-i", $MetaFile,
        "-map_metadata", "1",
        "-map_chapters", "1",
        "-codec", "copy",
        "-y",
        $TmpOutput
    )

    & ffmpeg @ffmpegArgs 2>&1 | ForEach-Object { Write-Host $_ }
    
    if ($LASTEXITCODE -ne 0) {
        Write-LogFail "ffmpeg failed. Check the error message above."
    }

    if ($Overwrite) {
        Move-Item -Path $TmpOutput -Destination $FinalOutput -Force
    }

    Write-LogOk "Done: '$FinalOutput'"

} finally {
    # Cleanup
    if ($MetaFile -and (Test-Path $MetaFile -ErrorAction SilentlyContinue)) {
        Remove-Item $MetaFile -Force -ErrorAction SilentlyContinue
    }
    if ($Overwrite -and $TmpOutput -ne $FinalOutput -and (Test-Path $TmpOutput -ErrorAction SilentlyContinue)) {
        Remove-Item $TmpOutput -Force -ErrorAction SilentlyContinue
    }
}
