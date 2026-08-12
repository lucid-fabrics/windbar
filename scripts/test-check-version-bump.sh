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
# run <label> <expected> <new_ver> <new_build> [pretend_tag]
# If pretend_tag is empty, the run uses a fresh repo with no prior tag,
# exercising the "initial release" path. Otherwise a vX.Y.Z tag is set
# on the initial commit and HEAD contains the new project.yml.
run() {
    label="$1"; expected="$2"; cur_ver="$3"; cur_build="$4"
    pretend_tag="${5:-v1.0.0}"
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
    if [ -n "$pretend_tag" ]; then
        git tag "$pretend_tag"
    fi

    if [ -n "$pretend_tag" ]; then
        # Bump project.yml to the test case
        sed -i '' "s/MARKETING_VERSION: \"1.0.0\"/MARKETING_VERSION: \"$cur_ver\"/" project.yml
        sed -i '' "s/CURRENT_PROJECT_VERSION: \"1\"/CURRENT_PROJECT_VERSION: \"$cur_build\"/" project.yml
        git add project.yml
        git commit -q -m "test"
    fi
    # If no pretend_tag, leave project.yml at the initial values - this
    # exercises the "no prior tag" path in the script under test.

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

# Run cases: a label, the expected outcome, current version, current build,
# and an optional prior tag (empty = no prior tag).
run "same version+build"        "fail"  "1.0.0"  "1"
run "same version, higher build"  "pass" "1.0.0"  "2"
run "same version, lower build"  "fail"  "1.0.0"  "0"
run "downgrade 1.0.0 -> 0.9.9"   "fail"  "0.9.9"  "1"
run "patch 1.0.0 -> 1.0.1"      "pass"  "1.0.1"  "1"
run "minor 1.0.0 -> 1.1.0"      "pass"  "1.1.0"  "1"
run "major 1.0.0 -> 2.0.0"      "pass"  "2.0.0"  "1"
run "minor 1.9.0 -> 1.10.0 (semver)"  "pass"  "1.10.0" "1"
run "downgrade 1.10.0 -> 1.9.0 (semver)"  "fail"  "1.9.0"  "1"
run "0.99.99 -> 1.0.0"          "pass"  "1.0.0"  "1"
run "1.2.10 -> 1.2.9"            "fail"  "1.2.9"  "1"
# No prior tag: any version/build is accepted (initial release on a
# brand-new repo).
run "no prior tag, initial release"  "pass"  "1.0.0"  "1"  ""

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" = 0 ]
