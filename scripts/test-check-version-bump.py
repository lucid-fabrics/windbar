#!/usr/bin/env python3
"""Tests for scripts/check-version-bump.sh. Run from repo root:
   python3 scripts/test-check-version-bump.py
or via make:  make test

Each case builds a throwaway git repo, creates a project.yml in the
initial commit, tags it (or skips the tag for the initial-release
case), then makes a real change to the project.yml in a second commit
(forcing the change with a trailing newline if values are unchanged so
the commit is not empty). The script under test is run and its exit
code is checked against the expected outcome.

The script is a regular POSIX shell script and the test driver is
Python because the test framework's shell-function approach was flaky
in environments where the Bash tool's PostToolUse hook interferes with
stdout. Python is unaffected."""

import os
import shutil
import subprocess
import sys
import tempfile


SCRIPT = os.path.join(os.path.dirname(__file__), "check-version-bump.sh")


def setup(tmp, ver, build, tag):
    """Create a fresh git repo with project.yml + an optional tag."""
    subprocess.run(["git", "init", "-q"], cwd=tmp, check=True)
    subprocess.run(["git", "config", "user.email", "ci@example.com"], cwd=tmp, check=True)
    subprocess.run(["git", "config", "user.name", "ci"], cwd=tmp, check=True)
    with open(os.path.join(tmp, "project.yml"), "w") as f:
        f.write(
            "name: Test\n"
            "settings:\n"
            "  base:\n"
            f"    MARKETING_VERSION: \"{ver}\"\n"
            f"    CURRENT_PROJECT_VERSION: \"{build}\"\n"
        )
    subprocess.run(["git", "add", "project.yml"], cwd=tmp, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=tmp, check=True)
    if tag:
        subprocess.run(["git", "tag", tag], cwd=tmp, check=True)


def bump(tmp, new_ver, new_build):
    """Bump project.yml in a second commit. Force a real change if values
    are unchanged (append a trailing newline)."""
    path = os.path.join(tmp, "project.yml")
    with open(path) as f:
        content = f.read()
    cur_ver_m = __import__("re").search(r'MARKETING_VERSION: *"([^"]*)"', content)
    cur_build_m = __import__("re").search(r'CURRENT_PROJECT_VERSION: *"([^"]*)"', content)
    cur_ver = cur_ver_m.group(1) if cur_ver_m else ""
    cur_build = cur_build_m.group(1) if cur_build_m else ""
    if new_ver == cur_ver and new_build == cur_build:
        with open(path, "a") as f:
            f.write("\n")
    else:
        content = __import__("re").sub(
            r'(MARKETING_VERSION: *")[^"]*(")',
            rf'\g<1>{new_ver}\g<2>',
            content,
            count=1,
        )
        content = __import__("re").sub(
            r'(CURRENT_PROJECT_VERSION: *")[^"]*(")',
            rf'\g<1>{new_build}\g<2>',
            content,
            count=1,
        )
        with open(path, "w") as f:
            f.write(content)
    subprocess.run(["git", "add", "project.yml"], cwd=tmp, check=True)
    # Empty commit is OK; the test's expected outcome decides whether
    # the bump was a real change.
    subprocess.run(["git", "commit", "-q", "-m", "bump"], cwd=tmp)


# (label, expected, prior_tag, new_ver, new_build)
CASES = [
    ("same version+build",                 "fail", "v1.0.0",   "1.0.0",  "1"),
    ("same version, higher build",         "pass", "v1.0.0",   "1.0.0",  "2"),
    ("same version, lower build",          "fail", "v1.0.0",   "1.0.0",  "0"),
    ("downgrade 1.0.0 -> 0.9.9",          "fail", "v1.0.0",   "0.9.9",  "1"),
    ("patch 1.0.0 -> 1.0.1",              "pass", "v1.0.0",   "1.0.1",  "1"),
    ("minor 1.0.0 -> 1.1.0",              "pass", "v1.0.0",   "1.1.0",  "1"),
    ("major 1.0.0 -> 2.0.0",              "pass", "v1.0.0",   "2.0.0",  "1"),
    ("minor 1.9.0 -> 1.10.0 (semver)",    "pass", "v1.9.0",   "1.10.0", "1"),
    ("downgrade 1.10.0 -> 1.9.0 (semver)","fail", "v1.10.0",  "1.9.0",  "1"),
    ("0.99.99 -> 1.0.0",                  "pass", "v0.99.99", "1.0.0",  "1"),
    ("1.2.10 -> 1.2.9",                   "fail", "v1.2.10",  "1.2.9",  "1"),
    # No prior tag: initial release on a brand-new repo.
    ("no prior tag, initial release",      "pass", "",        "1.0.0",  "1"),
]


def main() -> int:
    if not os.access(SCRIPT, os.X_OK):
        print(f"missing {SCRIPT}")
        return 1

    passed = 0
    failed = 0
    for label, expected, prior, new_ver, new_build in CASES:
        prior_ver = prior[1:] if prior else "1.0.0"
        prior_build = "1"
        with tempfile.TemporaryDirectory() as tmp:
            setup(tmp, prior_ver, prior_build, prior or None)
            if prior:
                bump(tmp, new_ver, new_build)
            # If no prior tag, leave project.yml at the initial values
            # so the script sees the actual "first commit".

            result = subprocess.run([SCRIPT], cwd=tmp, capture_output=True, text=True, timeout=15,
                                       env={**os.environ, "GITHUB_EVENT_NAME": "pull_request"})
            actual = "pass" if result.returncode == 0 else "fail"
            if actual == expected:
                passed += 1
                print(f"  ok   {label}")
            else:
                failed += 1
                print(f"  FAIL {label} (expected {expected}, got {actual})")
                if result.stdout or result.stderr:
                    out = (result.stdout + result.stderr).strip().splitlines()
                    out = [l for l in out if '🔍' not in l and '✅' not in l
                           and 'On branch' not in l
                           and 'nothing to commit' not in l]
                    if out:
                        print(f"        output: {out[:2]}")

    print()
    print(f"passed: {passed}, failed: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
