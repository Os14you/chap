# chap

Add chapters to MP4 and MKV videos — no re-encoding, no quality loss.

## Why

Video chapters let viewers jump to specific sections directly from the player's timeline (YouTube, VLC, mpv, etc.). `chap` embeds chapter metadata into any existing MP4 or MKV file using `ffmpeg`'s stream copy mode, meaning the video and audio are never touched — it's fast and lossless.

## Requirements

- `ffmpeg`
- `python3` (Python 3.6+)

## Install

### Linux / macOS

```bash
git clone https://github.com/Os14you/chap
cd chap
sudo ./setup.sh
```

`setup.sh` will check for `ffmpeg` and `python3`, then install the `chap` command to `/usr/local/bin/`.

### Windows

#### Option 1: PowerShell installer (recommended)

```powershell
git clone https://github.com/Os14you/chap
cd chap
.\setup.ps1
```

The installer will:
- Install chap to `%LOCALAPPDATA%\chap`
- Add the directory to your user PATH
- Create a PowerShell function for easy access

> **Note:** Restart your terminal after installation for PATH changes to take effect.

#### Option 2: Run directly (no installation)

```powershell
git clone https://github.com/Os14you/chap
cd chap
.\chap.ps1 video.mp4 "00:00 Intro" "01:30 Main"
```

#### Installing ffmpeg on Windows

If you don't have ffmpeg installed, use one of these methods:

```powershell
# Using winget (Windows Package Manager)
winget install ffmpeg

# Using Chocolatey
choco install ffmpeg

# Using Scoop
scoop install ffmpeg
```

Or download manually from [ffmpeg.org](https://ffmpeg.org/download.html).

## Usage

```
chap <input_video> ["MM:SS Title" ...] [-f chapters.txt] [-o output] [-w]
```

### Inline chapters

Pass chapter timestamps and titles directly as quoted arguments:

```bash
chap video.mp4 "00:00 Intro" "01:30 The Main Part" "05:00 Outro"
```

Output: `video_chap.mp4` (created alongside the original).

### From a file

```bash
chap video.mp4 -f chapters.txt
```

### Mix both

File chapters come first, inline args are appended after:

```bash
chap video.mp4 -f chapters.txt "45:00 Bonus"
```

### Custom output path

```bash
chap video.mp4 "00:00 Intro" "02:00 Demo" -o final/output.mp4
```

### Overwrite the original

```bash
chap video.mp4 "00:00 Intro" "02:00 Demo" -w
```

## Chapter file format

Plain `.txt` file, one chapter per line. Blank lines and lines starting with `#` are ignored.

```
# My video chapters
00:00 Intro
01:30 The Main Part
05:00 Q&A
48:00 Outro
```

Timestamps accept both `MM:SS` and `HH:MM:SS`.

## Supported formats

| Format | Input | Output |
|--------|-------|--------|
| MP4    | yes   | yes    |
| MKV    | yes   | yes    |

## Platform support

| Platform | Status | Install command |
|----------|--------|-----------------|
| Linux    | ✅     | `sudo ./setup.sh` |
| macOS    | ✅     | `sudo ./setup.sh` |
| Windows  | ✅     | `.\setup.ps1` |

## Options

| Flag | Description |
|------|-------------|
| `-f <file>` | Read chapters from a `.txt` file |
| `-o <path>` | Set the output file path/name |
| `-w` | Overwrite the input file in place |
| `-h` | Show help |

`-o` and `-w` cannot be used together.
