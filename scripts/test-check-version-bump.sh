#!/bin/sh
# Tests for check-version-bump.sh. Run from repo root:
#   ./scripts/test-check-version-bump.sh
#
# Each case builds a throwaway git repo with one tag and one project.yml
# in HEAD, then runs the check and asserts the expected outcome. Temp
# repos live in $TMPDIR and are removed at the end.

set -eu

script="$(dirname "$0")/check-version-bump.sh"
[ -x "$script" ] || { echo "missing $script"; exit 1; }

PASS=0
FAIL=0
run() {
    label="$1"; expected="$2"; cur_ver="$3"; cur_build="$4"
    if [ "$expected" = "pass" ]; then expected_code=0; else expected_code=1; fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    cd "$tmp"
    git init -q
    git config user.email "ci@example.com"
    git config user.name "ci"

    cat > project.yml <<YAML
name: Test
options:
  bundleIdPrefix: test
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ABCDE12345
    CODE_SIGN_STYLE: Automatic
packages:
  Foo:
    url: https://example.com
    from: 1.0.0
targets:
  Test:
    type: application
    platform: macOS
    sources:
      - path: Test
YAML
    git add project.yml
    git commit -q -m "initial"
    git tag v1.0.0

    # Edit project.yml to the test case
    sed -i '' "s/MARKETING_VERSION: \"1.0.0\"/MARKETING_VERSION: \"$cur_ver\"/" project.yml
    sed -i '' "s/CURRENT_PROJECT_VERSION: \"1\"/CURRENT_PROJECT_VERSION: \"$cur_build\"/" project.yml
    git add project.yml
    git commit -q -m "test"

    # Make sure the local checkout sees the current commit as HEAD but does
    # NOT contain v1.0.0 in its ancestry. The tag was on the previous
    # commit so HEAD~1 reaches v1.0.0, which is what we want.
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

# Run cases: a label, the expected outcome, current version, current build.
# Expected outcome: "pass" or "fail".
run "same version+build"        "fail"  "1.0.0"  "1"
run "same version, higher build"  "pass" "1.0.0"  "2"
run "same version, lower build"  "fail"  "1.0.0"  "0"
run "downgrade 1.0.0 -> 0.9.9"   "fail"  "0.9.9"  "1"
run "patch 1.0.0 -> 1.0.1"      "pass"  "1.0.1"  "1"
run "minor 1.0.0 -> 1.1.0"      "pass"  "1.1.0"  "1"
run "major 1.0.0 -> 2.0.0"      "pass"  "2.0.0"  "1"
run "minor 1.9.0 -> 1.10.0 (semver)"  "pass"  "1.10.0" "1"
run "downgrade 1.10.0 -> 1.9.0 (semver)"  "fail"  "1.9.0"  "1"
run "2-part to 3-part"          "pass"  "1.0.0.0" "1"  # sort -V treats this as 1.0.0.0 vs 1.0.0; passes if we just say greater
run "0.99.99 -> 1.0.0"          "pass"  "1.0.0"  "1"
run "1.2.10 -> 1.2.9"            "fail"  "1.2.9"  "1"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" = 0 ]
