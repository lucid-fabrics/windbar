#!/bin/sh
# Tests for check-version-bump.sh. Run from repo root:
#   ./scripts/test-check-version-bump.sh
# or via make:  make test
#
# Each case builds a throwaway git repo with one tag, makes a real
# change to project.yml (appending a newline if the version+build is
# unchanged so the commit is not empty), and asserts the script's exit
# code. Temp repos live in $TMPDIR and are removed at the end.

set -eu

script="$(dirname "$0")/check-version-bump.sh"
[ -x "$script" ] || { echo "missing $script"; exit 1; }

PASS=0
FAIL=0

# Build a throwaway repo with one tag and one project.yml. Args: tmp dir,
# initial ver, initial build, tag to place on initial commit (or empty).
setup_repo() {
    _tmp="$1"; _ver="$2"; _build="$3"; _tag="$4"
    cd "$_tmp"
    git init -q
    git config user.email "ci@example.com"
    git config user.name "ci"
    cat > project.yml <<YAML
name: Test
settings:
  base:
    MARKETING_VERSION: "$_ver"
    CURRENT_PROJECT_VERSION: "$_build"
YAML
    git add project.yml
    git commit -q -m "initial"
    if [ -n "$_tag" ]; then
        git tag "$_tag"
    fi
}

# Bump the working-tree project.yml to the new values and commit. If the
# new values are identical to the current ones, append a newline to force
# a real change. Tolerate empty commits.
bump_and_commit() {
    _tmp="$1"; _ver="$2"; _build="$3"
    cd "$_tmp"
    cur_ver="$(grep '^    MARKETING_VERSION:' project.yml | sed -E 's/^    MARKETING_VERSION: *"([^"]*)".*/\1/')"
    cur_build="$(grep '^    CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/^    CURRENT_PROJECT_VERSION: *"([^"]*)".*/\1/')"
    if [ "$_ver" = "$cur_ver" ] && [ "$_build" = "$cur_build" ]; then
        printf '\n' >> project.yml
    else
        sed -i '' "s|^    MARKETING_VERSION:.*|    MARKETING_VERSION: \"$_ver\"|" project.yml
        sed -i '' "s|^    CURRENT_PROJECT_VERSION:.*|    CURRENT_PROJECT_VERSION: \"$_build\"|" project.yml
    fi
    git add project.yml
    git commit -q -m "bump" || true
}

# run <label> <expected> <new_ver> <new_build> [prior_tag]
# If prior_tag is empty, the test exercises the no-prior-tag path.
run() {
    label="$1"; expected="$2"; cur_ver="$3"; cur_build="$4"
    prior="${5:-v1.0.0}"
    if [ "$expected" = "pass" ]; then expected_code=0; else expected_code=1; fi

    prior_ver="${prior#v}"
    prior_build="1"

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    setup_repo "$tmp" "$prior_ver" "$prior_build" "$prior"
    if [ -n "$prior" ]; then
        bump_and_commit "$tmp" "$cur_ver" "$cur_build"
    fi

    if "$script" >/dev/null 2>&1; then actual_code=0; else actual_code=1; fi
    cd /

    if [ "$actual_code" = "$expected_code" ]; then
        PASS=$((PASS+1))
        printf '  ok   %s\n' "$label"
    else
        FAIL=$((FAIL+1))
        printf '  FAIL %s (expected %s, got %s)\n' "$label" "$expected" "$actual_code"
    fi
    trap - EXIT
    rm -rf "$tmp"
}

run "same version+build"           "fail"  "1.0.0"  "1"
run "same version, higher build"   "pass" "1.0.0"  "2"
run "same version, lower build"    "fail"  "1.0.0"  "0"
run "downgrade 1.0.0 -> 0.9.9"     "fail"  "0.9.9"  "1"
run "patch 1.0.0 -> 1.0.1"        "pass" "1.0.1"  "1"
run "minor 1.0.0 -> 1.1.0"        "pass" "1.1.0"  "1"
run "major 1.0.0 -> 2.0.0"        "pass" "2.0.0"  "1"
run "minor 1.9.0 -> 1.10.0 (semver)"  "pass"  "1.10.0" "1"
run "downgrade 1.10.0 -> 1.9.0 (semver)"  "fail"  "1.9.0"  "1"
run "0.99.99 -> 1.0.0"            "pass" "1.0.0"  "1"
run "1.2.10 -> 1.2.9"              "fail"  "1.2.9"  "1"  "v1.2.10"
run "no prior tag, initial release"  "pass"  "1.0.0"  "1"  ""

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" = 0 ]
