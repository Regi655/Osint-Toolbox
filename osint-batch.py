#!/usr/bin/env python3
"""
osint-batch.py — run the bundled OSINT tools against a LIST of targets
(usernames/emails) and save one Markdown report, organized by target and tool.

Why it exists: running the same tools by hand over many targets is slow and
error-prone. Give it a list file and collect a single report when it finishes.

Runs inside the osint-toolbox container. Typical use:
    python3 osint-batch.py --targets targets.txt --outdir out

Target file format: one target per line. A line containing '@' is treated as an
email, otherwise as a username. Blank lines and lines starting with '#' are
ignored (so you can add comments).

Only non-interactive tools are used, so the batch never blocks waiting for input.
"""

import argparse
import datetime
import os
import re
import subprocess
import sys

# Tools print ANSI color codes and use spinners that emit control sequences.
# Those are garbage in a .md file, so strip them before writing.
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


def tools_for(kind):
    """Return the (label, command-builder) pairs to run for a given target type."""
    if kind == "email":
        return [
            ("mosint",       lambda t: ["mosint", t]),
            ("user-scanner", lambda t: ["user-scanner", "-e", t]),
        ]
    # username
    return [
        ("gosearch",     lambda t: ["gosearch", "-u", t, "--no-false-positives"]),
        ("user-scanner", lambda t: ["user-scanner", "-u", t]),
    ]


def clean(text):
    """Remove ANSI/control noise and normalize carriage returns for Markdown."""
    return ANSI.sub("", text).replace("\r", "\n")


def run(cmd, timeout):
    """Run a command, capture stdout+stderr, never block longer than `timeout`."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (p.stdout or "") + (p.stderr or ""), p.returncode
    except subprocess.TimeoutExpired as e:
        partial = ""
        for stream in (e.stdout, e.stderr):
            if stream:
                partial += stream if isinstance(stream, str) else stream.decode(errors="replace")
        return partial + f"\n[ABORTED: exceeded the {timeout}s timeout]", None
    except FileNotFoundError:
        return f"[command not found: {cmd[0]}]", None


def read_targets(path):
    """Read the list file into (target, kind) pairs, skipping blanks/comments."""
    targets = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            kind = "email" if "@" in line else "username"
            targets.append((line, kind))
    return targets


def main():
    ap = argparse.ArgumentParser(description="Batch OSINT search over a list of targets.")
    ap.add_argument("--targets", required=True, help="file with one target per line")
    ap.add_argument("--outdir", default="out", help="directory to write the report into")
    ap.add_argument("--timeout", type=int, default=300, help="max seconds per tool (default 300)")
    args = ap.parse_args()

    if not os.path.isfile(args.targets):
        print(f"File not found: {args.targets}", file=sys.stderr)
        sys.exit(1)

    targets = read_targets(args.targets)
    if not targets:
        print("No valid targets in the file (blank lines and '#' are ignored).", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.outdir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    outpath = os.path.join(args.outdir, f"report-{stamp}.md")

    n_user = sum(1 for _, k in targets if k == "username")
    n_mail = sum(1 for _, k in targets if k == "email")

    with open(outpath, "w", encoding="utf-8") as md:
        md.write("# OSINT batch report\n\n")
        md.write(f"_Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}_\n\n")
        md.write(f"_Targets: {len(targets)} ({n_user} username, {n_mail} email)._\n\n")
        md.write("---\n\n")

        for idx, (target, kind) in enumerate(targets, 1):
            print(f"[{idx}/{len(targets)}] {target} ({kind})", file=sys.stderr)
            md.write(f"## #{idx} — {target}  _({kind})_\n\n")

            for tool_name, build in tools_for(kind):
                print(f"    -> {tool_name} ...", file=sys.stderr)
                raw, code = run(build(target), args.timeout)
                body = clean(raw).strip()
                exit_note = "" if code in (0, None) else f" (exit {code})"
                md.write(f"### {tool_name}{exit_note}\n\n")
                md.write("```\n")
                md.write(body if body else "(no output)")
                md.write("\n```\n\n")
            md.flush()

    print(f"\nReport saved to: {outpath}", file=sys.stderr)


if __name__ == "__main__":
    main()
