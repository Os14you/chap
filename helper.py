#!/usr/bin/env python3
"""
helper.py - Generates an ffmetadata file from chapter definitions.

Called by chap.sh (Linux/macOS) or chap.ps1 (Windows), not directly by the user.

Usage:
  helper.py [-f chapters.txt] ["MM:SS Title" ...] ["HH:MM:SS Title" ...]

Chapters from -f file come first, then inline args are appended.
Prints the path to the generated temp ffmetadata file on stdout.
Exits non-zero on any error.
"""

import sys
import os
import re
import tempfile
import argparse


def _supports_color() -> bool:
    """Return True if stderr is a TTY and color is not disabled."""
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stderr.isatty()


def log_info(msg: str) -> None:
    if _supports_color():
        print(f"\033[0;36m[INFO]\033[0m {msg}", file=sys.stderr)
    else:
        print(f"[INFO] {msg}", file=sys.stderr)


def log_warn(msg: str) -> None:
    if _supports_color():
        print(f"\033[0;33m[WARN]\033[0m {msg}", file=sys.stderr)
    else:
        print(f"[WARN] {msg}", file=sys.stderr)


def log_fail(msg: str) -> None:
    """Print a red [FAIL] message to stderr and exit 1."""
    if _supports_color():
        print(f"\033[1;31m[FAIL]\033[0m {msg}", file=sys.stderr)
    else:
        print(f"[FAIL] {msg}", file=sys.stderr)
    sys.exit(1)


def parse_timestamp(ts: str) -> int:
    """
    Parse a timestamp string (MM:SS or HH:MM:SS) and return milliseconds.
    Raises ValueError on invalid format.
    """
    ts = ts.strip()

    match_hms = re.fullmatch(r"(\d+):([0-5]\d):([0-5]\d)", ts)
    match_ms = re.fullmatch(r"(\d+):([0-5]\d)", ts)

    if match_hms:
        h, m, s = (
            int(match_hms.group(1)),
            int(match_hms.group(2)),
            int(match_hms.group(3)),
        )
        return (h * 3600 + m * 60 + s) * 1000
    elif match_ms:
        m, s = int(match_ms.group(1)), int(match_ms.group(2))
        return (m * 60 + s) * 1000
    else:
        raise ValueError(
            f"Invalid timestamp format: '{ts}' (expected MM:SS or HH:MM:SS)"
        )


def parse_chapter_line(line: str) -> tuple:
    """
    Parse a single chapter line: 'TIMESTAMP Title text here'
    Returns (timestamp_str, title).
    Raises ValueError on malformed lines.
    """
    parts = line.strip().split(None, 1)
    if len(parts) < 2:
        raise ValueError(f"Missing title in chapter line: '{line.strip()}'")
    return parts[0], parts[1].strip()


def load_chapters_from_file(path: str) -> list:
    """
    Read a .txt chapters file.
    Blank lines and lines starting with '#' are ignored.
    Returns a list of (start_ms, title) tuples in file order.
    """
    if not os.path.isfile(path):
        log_fail(f"Chapters file not found: '{path}'")

    chapters = []
    with open(path, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                ts_str, title = parse_chapter_line(line)
                ms = parse_timestamp(ts_str)
            except ValueError as e:
                log_fail(f"In '{path}' line {lineno}: {e}")
                continue 
            chapters.append((ms, title))
    return chapters


def load_chapters_from_args(args: list) -> list:
    """
    Parse inline chapter arguments like '01:30 Main Content'.
    Returns a list of (start_ms, title) tuples.
    """
    chapters = []
    for arg in args:
        try:
            ts_str, title = parse_chapter_line(arg)
            ms = parse_timestamp(ts_str)
        except ValueError as e:
            log_fail(f"Invalid chapter argument '{arg}': {e}")
            continue
        chapters.append((ms, title))
    return chapters


def validate_chapters(chapters: list) -> None:
    """
    Validate that:
    - There is at least one chapter.
    - The first chapter starts at 00:00 (0 ms).
    - Timestamps are in strictly ascending order.
    """
    if not chapters:
        log_fail("No chapters provided.")

    if chapters[0][0] != 0:
        log_fail(
            f"The first chapter must start at 00:00, "
            f"but got timestamp for '{chapters[0][1]}'."
        )

    for i in range(1, len(chapters)):
        if chapters[i][0] <= chapters[i - 1][0]:
            log_fail(
                f"Timestamps must be in ascending order. "
                f"'{chapters[i][1]}' is not after '{chapters[i - 1][1]}'."
            )


def write_ffmetadata(chapters: list) -> str:
    """
    Write an ffmetadata file to a temporary location.
    Each chapter's end time is the start of the next chapter.
    The last chapter gets end = start + 1ms (ffmpeg clamps to video duration).
    Returns the path to the temp file.
    """
    fd, path = tempfile.mkstemp(suffix=".txt", prefix="chap_ffmeta_")

    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(";FFMETADATA1\n\n")

        for i, (start_ms, title) in enumerate(chapters):
            end_ms = chapters[i + 1][0] if i + 1 < len(chapters) else start_ms + 1

            f.write("[CHAPTER]\n")
            f.write("TIMEBASE=1/1000\n")
            f.write(f"START={start_ms}\n")
            f.write(f"END={end_ms}\n")
            f.write(f"title={title}\n")
            f.write("\n")

    return path


def main():
    parser = argparse.ArgumentParser(
        description="Generate an ffmetadata file from chapter definitions.",
    )
    parser.add_argument(
        "-f",
        "--file",
        metavar="CHAPTERS_FILE",
        help="Path to a .txt file with one chapter per line (TIMESTAMP Title)",
    )
    parser.add_argument(
        "chapters",
        nargs="*",
        metavar="CHAPTER",
        help='Inline chapter definitions, e.g. "00:00 Intro" "01:30 Main"',
    )

    args = parser.parse_args()

    chapters = []

    if args.file:
        chapters.extend(load_chapters_from_file(args.file))

    if args.chapters:
        chapters.extend(load_chapters_from_args(args.chapters))

    validate_chapters(chapters)

    meta_path = write_ffmetadata(chapters)

    log_info(f"Parsed {len(chapters)} chapter(s) successfully.")

    # Print the temp file path — chap.sh captures this with $(...)
    print(meta_path)


if __name__ == "__main__":
    main()
